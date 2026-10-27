"""Passo 2: dal grezzo Wikidata al catalogo Marca → Modello → Versione.

Ingresso: out/wikidata_raw.json (+ out/class_labels.json, scaricato qui se manca), curated/*.csv.
Uscita: out/catalog.json (formato dello snapshot, con image.commonsFile al posto di path) e
out/build_report.md.
"""
import csv
import re
import sys
from collections import Counter, defaultdict
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))  # solo i moduli della pipeline
from catalog_common import CURATED, OUT, normalize, read_json, slug, sparql, write_json

CURRENT_YEAR = datetime.now(timezone.utc).year
MIN_YEAR = 1980
CLASSIC_MIN_SITELINKS = 25      # prima del 1980 solo le auto molto note
NO_IMAGE_MIN_SITELINKS = 10     # senza immagine, solo se abbastanza note
NO_DATE_MIN_SITELINKS = 3       # senza anni (spesso voci minori), solo se abbastanza note
MIN_MODELS_PER_MAKE = 2
HOMONYM_GAP_YEARS = 25          # stesso nome a distanza di anni = modelli diversi (Fiat 500)

# Classi da scartare (parole nell'etichetta inglese della classe).
EXCLUDE_WORDS = ("concept", "prototype", "race car", "racing", "racecar", "formula", "rally car",
                 "sports prototype", "truck", "lorry", "bus", "tractor", "armored", "armoured",
                 "military", "fire engine", "ambulance", "kit car", "toy", "model car", "dragster",
                 "land speed", "le mans", "touring car racing", "stock car")
EXCLUDE_RE = re.compile(r"\b(" + "|".join(re.escape(w) for w in EXCLUDE_WORDS) + r")\b")
# Carrozzeria: prima regola che corrisponde vince.
BODY_RULES = (
    ("pickup", ("pickup", "pick-up", "ute")),
    ("furgone", ("van", "light commercial", "panel van", "minibus")),
    ("suv", ("sport utility", "suv", "crossover", "off-road", "off road", "four-wheel drive vehicle",
             "fuoristrada")),
    ("cabrio", ("convertible", "roadster", "cabriolet", "spider", "spyder", "targa")),
    ("monovolume", ("minivan", "mpv", "multi-purpose", "people carrier", "leisure activity vehicle")),
    ("station_wagon", ("station wagon", "estate car", "estate", "shooting brake", "familiare")),
    ("sportiva", ("sports car", "supercar", "hypercar", "grand tourer", "muscle car", "pony car",
                  "vettura sportiva", "auto sportiva", "gran turismo")),
    ("coupe", ("coupé", "coupe")),
    ("utilitaria", ("city car", "a-segment", "b-segment", "supermini", "microcar", "kei car",
                    "subcompact", "utilitaria", "citycar")),
    ("berlina", ("sedan", "saloon", "hatchback", "c-segment", "d-segment", "e-segment", "f-segment",
                 "compact car", "family car", "executive car", "luxury car", "fastback", "liftback")),
)
SERIES_WORDS = ("model series", "car model series", "automobile model series")
GEN_SUFFIX = re.compile(
    r"\s+(\(\s*[^)]*\)|mk\.?\s?[ivx\d]+|mark\s+[ivx\d]+|[ivx]{1,4}|"
    r"(first|second|third|fourth|fifth|sixth|seventh|eighth|ninth|tenth)\s+generation|"
    r"\d+(st|nd|rd|th)\s+generation|generation\s+\d+|[a-z]{1,2}\d{2,3}[a-z]?)$",
    re.IGNORECASE)
COMPANY_SUFFIX = re.compile(
    r"\s+(group|groupe|gruppe|s\.p\.a\.|spa|ag|gmbh|limited|ltd\.?|inc\.?|s\.a\.|sa|plc|"
    r"co\.|holding|automobiles s\.a\.)$", re.IGNORECASE)
COMPANY_PREFIX = re.compile(r"^(ab|aktiebolaget)\s+", re.IGNORECASE)


def load_csv(name: str) -> list[dict]:
    path = CURATED / name
    if not path.exists():
        return []
    with path.open(encoding="utf-8") as f:
        return [row for row in csv.DictReader(f) if not (row.get(next(iter(row)), "") or "").startswith("#")]


def class_labels(raw: dict) -> dict:
    """Etichette inglesi delle classi (P31/P279), in cache su disco."""
    path = OUT / "class_labels.json"
    labels = read_json(path) if path.exists() else {}
    wanted = sorted({c for it in raw.values() for c in it["instanceOf"] + it["subclassOf"]} - set(labels))
    for i in range(0, len(wanted), 300):
        chunk = wanted[i:i + 300]
        rows = sparql("SELECT ?c ?l WHERE { VALUES ?c { %s } ?c rdfs:label ?l FILTER(LANG(?l)='en') }"
                      % " ".join("wd:" + c for c in chunk))
        for r in rows:
            labels[r["c"].rsplit("/", 1)[-1]] = r["l"].lower()
        for c in chunk:
            labels.setdefault(c, "")
    write_json(path, labels)
    return labels


SERIES_QUERY = """
SELECT ?s ?en ?it ?brandLabel ?sitelinks ?image ?itwiki ?dewiki ?frwiki WHERE {
  VALUES ?s { %s }
  OPTIONAL { ?s rdfs:label ?en FILTER(LANG(?en) = "en") }
  OPTIONAL { ?s rdfs:label ?it FILTER(LANG(?it) = "it") }
  OPTIONAL { ?s wdt:P1716 ?b . ?b rdfs:label ?brandLabel FILTER(LANG(?brandLabel) = "en") }
  OPTIONAL { ?s wikibase:sitelinks ?sitelinks }
  OPTIONAL { ?s wdt:P18 ?image }
  OPTIONAL { ?itwiki schema:about ?s ; schema:isPartOf <https://it.wikipedia.org/> }
  OPTIONAL { ?dewiki schema:about ?s ; schema:isPartOf <https://de.wikipedia.org/> }
  OPTIONAL { ?frwiki schema:about ?s ; schema:isPartOf <https://fr.wikipedia.org/> }
}
"""


def series_info(raw: dict) -> dict:
    """Etichette e notorietà delle serie (es. "Volkswagen Golf") che non sono item del grezzo."""
    path = OUT / "series_info.json"
    info = read_json(path) if path.exists() else {}
    wanted = sorted({s for it in raw.values() for s in it["series"] + it["subclassOf"]} - set(raw) - set(info))
    for i in range(0, len(wanted), 200):
        chunk = wanted[i:i + 200]
        for r in sparql(SERIES_QUERY % " ".join("wd:" + c for c in chunk)):
            q = r["s"].rsplit("/", 1)[-1]
            cur = info.setdefault(q, {"en": None, "it": None, "brandName": None, "sitelinks": 0,
                                      "image": None, "european": False})
            cur["en"] = cur["en"] or r.get("en")
            cur["it"] = cur["it"] or r.get("it")
            cur["brandName"] = cur["brandName"] or r.get("brandLabel")
            cur["sitelinks"] = max(cur["sitelinks"], int(r.get("sitelinks", 0)))
            cur["image"] = cur["image"] or (r["image"].rsplit("/", 1)[-1] if r.get("image") else None)
            cur["european"] = cur["european"] or any(r.get(w) for w in ("itwiki", "dewiki", "frwiki"))
        for c in chunk:
            info.setdefault(c, {"en": None, "it": None, "brandName": None, "sitelinks": 0,
                                "image": None, "european": False})
    write_json(path, info)
    return info


NOT_A_VARIANT = re.compile(
    r"\b(generation|generazione|serie|series|facelift|restyling|sedan|saloon|berlina|hatchback|estate|"
    r"wagon|touring|variant|avant|sportback|coupe|coupé|cabrio|cabriolet|convertible|limousine|mk\.?\s?\d|"
    r"\d{4}|phase|lwb|swb)\b", re.IGNORECASE)


def variant_suffix_ok(variant: str, model: str) -> bool:
    """Una versione Wikidata vale se è "Modello + suffisso" e il suffisso non è generazione/carrozzeria."""
    v, m = normalize(variant), normalize(model)
    if not v.startswith(m + " "):
        return False
    rest = variant[len(model):].strip() if variant.lower().startswith(model.lower()) else v[len(m):].strip()
    if re.fullmatch(r"[A-Za-z]{1,2}\d{1,3}", rest):
        return False  # codice di generazione (Passat B5, Serie 3 E46)
    return bool(strip_generation(" x " + rest)[3:].strip()) and not NOT_A_VARIANT.search(rest)


def curated_variant_name(model: str, variant: str) -> str:
    """"=Nome" nel CSV = nome completo; altrimenti "Modello Versione"."""
    return variant[1:].strip() if variant.startswith("=") else f"{model} {variant}"


YEAR = r"(1[89]\d\d|20[0-3]\d)"
DESC_RANGE = re.compile(rf"(?:from|between|dal|tra il)\s+{YEAR}\s+(?:to|and|al|e il)\s+{YEAR}", re.IGNORECASE)
DESC_RANGE_DASH = re.compile(rf"\b{YEAR}\s*[–-]\s*{YEAR}\b")
DESC_SINCE = re.compile(rf"(?:since|dal|from)\s+{YEAR}", re.IGNORECASE)
DESC_SINGLE = re.compile(rf"(?:del|of|in|introduced in)\s+{YEAR}", re.IGNORECASE)


def descriptions(raw: dict) -> dict:
    """Descrizioni en/it degli item (spesso contengono gli anni), in cache su disco."""
    path = OUT / "descriptions.json"
    desc = read_json(path) if path.exists() else {}
    wanted = sorted(set(raw) - set(desc))
    for i in range(0, len(wanted), 300):
        chunk = wanted[i:i + 300]
        rows = sparql("SELECT ?m ?d WHERE { VALUES ?m { %s } ?m schema:description ?d "
                      "FILTER(LANG(?d) IN ('en', 'it')) }" % " ".join("wd:" + c for c in chunk))
        for c in chunk:
            desc.setdefault(c, "")
        for r in rows:
            q = r["m"].rsplit("/", 1)[-1]
            desc[q] = (desc[q] + " | " + r["d"]).strip(" |")
    write_json(path, desc)
    return desc


def years_from_description(text: str) -> tuple[int | None, int | None]:
    """("autovettura del 1996…", "produced from 2000 to 2010") → (inizio, fine)."""
    if (m := DESC_RANGE.search(text)) or (m := DESC_RANGE_DASH.search(text)):
        return int(m.group(1)), int(m.group(2))
    if (m := DESC_SINCE.search(text)) or (m := DESC_SINGLE.search(text)):
        return int(m.group(1)), None
    return None, None


def strip_generation(name: str) -> str:
    prev = None
    while prev != name:
        prev = name
        name = GEN_SUFFIX.sub("", name).strip()
    return name


def clean_company(name: str) -> str:
    prev = None
    while prev != name:
        prev = name
        name = COMPANY_SUFFIX.sub("", name).strip(" ,")
        name = COMPANY_PREFIX.sub("", name)
    return name


def strip_make(label: str, make: str) -> str:
    n = label.strip()
    for prefix in sorted({make, make.replace("-", " "), make.split()[0]}, key=len, reverse=True):
        if normalize(n).startswith(normalize(prefix) + " "):
            return n[len(prefix):].strip(" -")
    return n


def is_excluded(classes: list[str], labels: dict, description: str = "") -> bool:
    text = " | ".join(labels.get(c, "") for c in classes) + " | " + description.lower()
    return bool(EXCLUDE_RE.search(text)) or "manuale" in description.lower()


def translate_name(name: str) -> str:
    """Nomi all'italiana come li dice chi guida: "3 Series" → "Serie 3", "A-Class" → "Classe A"."""
    name = re.sub(r"^(\d) Series\b", r"Serie \1", name)
    name = re.sub(r"^([A-Z]{1,3})[- ]Class\b", r"Classe \1", name)
    return name


def model_name(it: dict, make: str) -> str:
    """Nome del modello senza marca né generazione, dall'etichetta inglese (più coerente su Wikidata)."""
    label = it.get("en") or it.get("it") or ""
    if "/" in label:
        label = re.sub(r"\s*\([^)]*\)", "", label)
        parts = [x.strip() for x in label.split("/")]
        label = next((x for x in parts if normalize(x).startswith(normalize(make) + " ")), parts[0])
    return translate_name(strip_make(strip_generation(label), make))


def body_type(classes: list[str], labels: dict, description: str = "") -> str:
    text = " | ".join(labels.get(c, "") for c in classes) + " | " + description.lower()
    for body, words in BODY_RULES:
        if any(re.search(r"\b" + re.escape(w) + r"\b", text) for w in words):
            return body
    return "berlina"


def merge_generations(members: list[dict]) -> dict:
    """Unisce le generazioni di un modello: anni minimi/massimi, immagine della più recente."""
    starts = [y for m in members for y in m["starts"]]
    ends = [y for m in members for y in m["ends"]]
    open_ended = any(m["starts"] and not m["ends"] for m in members)
    with_image = [m for m in members if m["images"]]
    latest = max(with_image, key=lambda m: max(m["starts"] or [0])) if with_image else None
    return {
        "yearStart": min(starts) if starts else None,
        "yearEnd": None if open_ended or not ends else max(ends),
        "image": latest["images"][0] if latest else None,
        "popularity": max(m["sitelinks"] for m in members),
        "latestStart": max(starts) if starts else None,
        "european": any(m["itwiki"] or m["dewiki"] or m["frwiki"] for m in members),
    }


def split_homonyms(members: list[dict]) -> list[list[dict]]:
    """Stesso nome ma anni lontanissimi (Fiat 500 del 1957 e del 2007) → modelli separati.
    Le generazioni della stessa serie Wikidata restano sempre insieme."""
    parents = {m.get("_series") for m in members}
    if len(parents) == 1 and None not in parents:
        return [members]
    dated = sorted(members, key=lambda m: min(m["starts"] or [9999]))
    clusters: list[list[dict]] = []
    last_year = None
    for m in dated:
        start = min(m["starts"]) if m["starts"] else None
        if clusters and (start is None or last_year is None or start - last_year <= HOMONYM_GAP_YEARS):
            clusters[-1].append(m)
        else:
            clusters.append([m])
        years = m["ends"] or m["starts"]
        if years:
            last_year = max(last_year or 0, max(years))
    return clusters


GENERIC_MAKE_WORDS = {"motor", "motors", "company", "cars", "car", "auto", "automobile", "automobiles",
                      "automobili", "corporation", "marque", "automotive", "group"}


def canonical_makes(names: set[str], merges: dict[str, str]) -> dict[str, str | None]:
    """Nome grezzo → marca canonica: correzioni curate, poi "Hyundai Motor Company" → "Hyundai"."""
    out: dict[str, str | None] = {}
    for n in names:
        if n in merges:
            out[n] = merges[n] or None
            continue
        best = n
        for other in names:
            if other != n and n.startswith(other + " ") and len(other) < len(best):
                rest = set(normalize(n[len(other):]).split())
                if rest and rest <= GENERIC_MAKE_WORDS:
                    best = other
        out[n] = merges.get(best, best) or None
    return out


def main() -> None:
    raw = read_json(OUT / "wikidata_raw.json")
    labels = class_labels(raw)
    desc = descriptions(raw)
    for q, it in raw.items():
        if not it["starts"]:
            start, end = years_from_description(desc.get(q, ""))
            if start:
                it["starts"] = [start]
                if end and not it["ends"]:
                    it["ends"] = [end]
    report = Counter()
    curated_make_alias = defaultdict(list)
    for row in load_csv("make_aliases.csv"):
        curated_make_alias[normalize(row["make"])].append(row["alias"])
    exclude = {row["qid"] for row in load_csv("exclude.csv")}

    sinfo = series_info(raw)

    def info_of(p: str) -> dict | None:
        return raw.get(p) or sinfo.get(p)

    # 1) Marca di ogni item.
    def make_of(it: dict) -> tuple[str | None, str | None]:
        if it.get("brandName"):
            return clean_company(it["brandName"]), it.get("brandCountry")
        if it.get("makerName"):
            return clean_company(it["makerName"]), it.get("makerCountry")
        return None, None

    def parent_of(q: str, it: dict, make: str) -> str | None:
        """Serie dell'item: P179, oppure una classe P279 della stessa marca ("bmw 3 series")."""
        for s_ in it["series"]:
            if s_ != q and info_of(s_):
                return s_
        mk = normalize(make)
        for p_ in it["subclassOf"]:
            target = info_of(p_)
            if p_ != q and target and target.get("en") and normalize(target["en"]).startswith(mk + " "):
                return p_
        return None

    # 2) Raggruppa per (marca, nome di modello senza generazione); le serie raccolgono i membri,
    #    le versioni (Golf GTI ⊂ Golf) si agganciano dopo.
    groups: dict[tuple, list[dict]] = defaultdict(list)
    group_country: dict[str, Counter] = defaultdict(Counter)
    pending_variants: list[tuple[str, str, str, str]] = []  # (qid, serie, nome, marca)
    for q, it in raw.items():
        if q in exclude:
            report["escluso a mano"] += 1
            continue
        classes = it["instanceOf"] + it["subclassOf"]
        if is_excluded(classes, labels) or is_excluded([], labels, desc.get(q, "")):
            report["classe esclusa (concept, corsa, camion…)"] += 1
            continue
        make, country = make_of(it)
        if not make or not (it["en"] or it["it"]):
            report["senza marca o nome"] += 1
            continue
        own = model_name(it, make)
        parent = parent_of(q, it, make)
        name = own
        if parent:
            target = info_of(parent)
            pname = model_name(target, make)
            if pname and own and variant_suffix_ok(own, pname):
                pending_variants.append((q, parent, own, make))
                continue
            name = pname or own
            sl = target.get("sitelinks", 0)
            eu = target.get("european") or target.get("itwiki") or target.get("dewiki") or target.get("frwiki")
            it = dict(it, sitelinks=max(it["sitelinks"], sl), itwiki=bool(it["itwiki"] or eu))
        if not name or normalize(name) == normalize(make):
            report["nome di modello vuoto"] += 1
            continue
        alias = strip_make(strip_generation(it["it"]), make) if it["it"] else ""
        it = dict(it, _series=parent, _body=body_type(classes, labels, desc.get(q, "")), _name=name,
                  _alias=alias if alias and normalize(alias) != normalize(name) else "", _make=make)
        groups[(normalize(make), normalize(name))].append(it)
        if country:
            group_country[normalize(make)][country] += 1

    # 2b) Marche canoniche: unisce i gruppi di "Ford" e "Ford Motor Company".
    merges = {r["from"]: (r.get("to") or "").strip() for r in load_csv("make_merge.csv")}
    canon = canonical_makes({m["_make"] for ms in groups.values() for m in ms}, merges)
    regrouped: dict[tuple, list[dict]] = defaultdict(list)
    for (_, name_key), members in groups.items():
        for m in members:
            make = canon.get(m["_make"])
            if not make:
                report["marca esclusa a mano"] += 1
                continue
            regrouped[(normalize(make), name_key)].append(dict(m, _make=make))
            country = group_country.get(normalize(m["_make"]))
            if country:
                group_country[normalize(make)].update(country)
    groups = regrouped
    known = sorted({k[0] for k in groups}, key=len, reverse=True)
    display_of = {normalize(m["_make"]): m["_make"] for ms in groups.values() for m in ms}
    moved: dict[tuple, list[dict]] = defaultdict(list)
    for (make_key, name_key), members in groups.items():
        other = next((k for k in known if k != make_key and name_key.startswith(k + " ")), None)
        if other:
            new_name = name_key[len(other) + 1:]
            for m in members:
                moved[(other, new_name)].append(dict(m, _make=display_of[other],
                                                     _name=m["_name"][len(display_of[other]) + 1:] or m["_name"]))
            report["modelli spostati alla marca giusta"] += len(members)
        else:
            moved[(make_key, name_key)].extend(members)
    groups = moved

    # 3) Modelli, con filtri europei/anni/notorietà.
    makes: dict[str, dict] = {}
    models: list[dict] = []
    for (make_key, _), members in groups.items():
        for cluster in split_homonyms(members):
            info = merge_generations(cluster)
            ys, ye = info["yearStart"], info["yearEnd"]
            latest = info["latestStart"]
            if ((ye is not None and ye < MIN_YEAR) or (latest is not None and latest < MIN_YEAR - 5)) \
                    and info["popularity"] < CLASSIC_MIN_SITELINKS:
                report["classica poco nota (finita prima del 1980)"] += 1
                continue
            if ys is None and ye is None and info["popularity"] < NO_DATE_MIN_SITELINKS:
                report["senza anni e poco noto"] += 1
                continue
            if not info["european"]:
                report["senza articolo it/de/fr"] += 1
                continue
            if not info["image"] and info["popularity"] < NO_IMAGE_MIN_SITELINKS:
                report["senza immagine e poco noto"] += 1
                continue
            make_name = Counter(m["_make"] for m in cluster).most_common(1)[0][0]
            name = Counter(m["_name"] for m in cluster).most_common(1)[0][0]
            bodies = Counter(m["_body"] for m in cluster)
            aliases = sorted({m["_alias"] for m in cluster if m["_alias"] and normalize(m["_alias"]) != normalize(name)})
            make_id = slug(make_name)
            makes.setdefault(make_id, {"id": make_id, "name": make_name, "aliases": [],
                                       "country": (group_country[make_key].most_common(1) or [(None, 0)])[0][0]})
            models.append({
                "makeId": make_id, "name": name, "bodyType": max(bodies, key=lambda b: (bodies[b], b != "berlina")) if bodies else "berlina",
                "yearStart": ys, "yearEnd": info["yearEnd"], "popularity": info["popularity"],
                "aliases": aliases, "image": info["image"],
                "wikidata": sorted({m["qid"] for m in cluster} | {m["_series"] for m in cluster if m["_series"]}),
            })

    # 4) Id dei modelli; omonimi: il più vecchio prende l'anno nell'id e nel nome.
    by_key = defaultdict(list)
    for m in models:
        by_key[(m["makeId"], normalize(m["name"]))].append(m)
    for same in by_key.values():
        same.sort(key=lambda m: m["yearStart"] or 0)
        for i, m in enumerate(same):
            m["id"] = f"{m['makeId']}-{slug(m['name'])}"
            if len(same) > 1 and i < len(same) - 1 and m["yearStart"]:
                m["id"] += f"-{m['yearStart']}"
                m["aliases"] = sorted(set(m["aliases"]) | {m["name"]})
                m["name"] = f"{m['name']} ({m['yearStart']})"

    # 4b) Ultima difesa contro id uguali (nomi che differiscono solo per simboli).
    used: Counter = Counter()
    for m in sorted(models, key=lambda m: -m["popularity"]):
        used[m["id"]] += 1
        if used[m["id"]] > 1:
            m["id"] = f"{m['id']}-{used[m['id']]}"

    # 5) Marche troppo piccole o senza immagini: fuori.
    per_make = defaultdict(list)
    for m in models:
        per_make[m["makeId"]].append(m)
    keep = {mk for mk, ms in per_make.items()
            if len(ms) >= MIN_MODELS_PER_MAKE and any(m["image"] for m in ms)}
    report["marche scartate (piccole o senza immagini)"] = len(per_make) - len(keep)
    models = [m for m in models if m["makeId"] in keep]
    makes = {k: v for k, v in makes.items() if k in keep}
    for k, v in makes.items():
        v["aliases"] = sorted(set(curated_make_alias.get(normalize(v["name"]), [])))

    # 6) Versioni: base + curate.
    model_by_name = {(m["makeId"], normalize(n)): m for m in models
                     for n in [m["name"]] + m["aliases"]}
    variants = []
    for m in models:
        variants.append({"id": m["id"], "modelId": m["id"], "name": m["name"], "isBase": True,
                         "yearStart": m["yearStart"], "yearEnd": m["yearEnd"], "aliases": list(m["aliases"]),
                         "commonsFile": m["image"]})
    seen = {v["id"] for v in variants}
    model_by_qid = {q: m for m in models for q in m["wikidata"]}
    for q, parent, vname, _ in pending_variants:
        base = model_by_qid.get(parent)
        it = raw[q]
        if not base:
            report["versioni Wikidata senza modello"] += 1
            continue
        if not (it["itwiki"] or it["dewiki"] or it["frwiki"]):
            report["versioni Wikidata non europee"] += 1
            continue
        base_plain = re.sub(r"\s\(\d{4}\)$", "", base["name"])
        suffix = vname[len(base_plain):] if normalize(vname).startswith(normalize(base_plain)) else vname
        vid = f"{base['id']}-{slug(suffix) or slug(vname)}"
        if vid in seen or vid == base["id"]:
            continue
        seen.add(vid)
        alias = strip_make(it["it"], makes[base["makeId"]]["name"]) if it["it"] else ""
        variants.append({"id": vid, "modelId": base["id"], "name": vname, "isBase": False,
                         "yearStart": min(it["starts"]) if it["starts"] else base["yearStart"],
                         "yearEnd": max(it["ends"]) if it["ends"] else None,
                         "aliases": [alias] if alias and normalize(alias) != normalize(vname) else [],
                         "commonsFile": it["images"][0] if it["images"] else None})
    missing_curated = []
    for row in load_csv("variants.csv"):
        mk = slug(row["make"])
        base = model_by_name.get((mk, normalize(row["model"])))
        if not base:
            missing_curated.append(f"{row['make']} {row['model']} {row['variant']}")
            continue
        base_name = re.sub(r"\s\(\d{4}\)$", "", base["name"])
        vid = f"{base['id']}-{slug(row['variant'].lstrip('='))}"
        if vid in seen:
            continue
        seen.add(vid)
        aliases = [a.strip() for a in (row.get("aliases") or "").split("|") if a.strip()]
        variants.append({"id": vid, "modelId": base["id"], "name": curated_variant_name(base_name, row["variant"]),
                         "isBase": False, "yearStart": int(row["year_start"]) if row.get("year_start") else base["yearStart"],
                         "yearEnd": int(row["year_end"]) if row.get("year_end") else None,
                         "aliases": aliases, "commonsFile": None})

    now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    for coll in (makes.values(), models, variants):
        for r in coll:
            r["updatedAt"] = now
    catalog = {"version": 1, "generatedAt": now,
               "makes": sorted(makes.values(), key=lambda r: r["id"]),
               "models": sorted(({k: v for k, v in m.items() if k != "image"} for m in models), key=lambda r: r["id"]),
               "variants": sorted(variants, key=lambda r: r["id"])}
    write_json(OUT / "catalog.json", catalog)

    lines = [f"# Catalogo — {now}", "",
             f"- Marche: {len(makes)}", f"- Modelli: {len(models)}", f"- Versioni: {len(variants)}",
             f"- Modelli con immagine: {sum(1 for m in models if m['image'])}", "", "## Scarti", ""]
    lines += [f"- {k}: {v}" for k, v in report.most_common()]
    lines += ["", "## Versioni curate senza modello", ""] + [f"- {x}" for x in missing_curated]
    lines += ["", "## Modelli per marca", ""]
    lines += [f"- {makes[mk]['name']}: {len(ms)}" for mk, ms in
              sorted(((mk, ms) for mk, ms in per_make.items() if mk in keep), key=lambda x: -len(x[1]))]
    (OUT / "build_report.md").write_text("\n".join(lines), encoding="utf-8")
    print(f"marche {len(makes)} · modelli {len(models)} · versioni {len(variants)}")


if __name__ == "__main__":
    sys.exit(main())
