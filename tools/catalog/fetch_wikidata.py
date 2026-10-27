"""Passo 1: scarica da Wikidata i modelli di automobile con i dati che servono al catalogo.

Due fasi: elenco degli item (classe "modello di automobile" e sottoclassi, con marca) e dettagli a
blocchi con VALUES, per stare sotto il timeout di 60 s del servizio SPARQL.
Uscita: out/wikidata_raw.json = {qid: {...}}.
"""
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))  # solo i moduli della pipeline
from catalog_common import OUT, qid, read_json, sparql, write_json

LIST_QUERY = """
SELECT DISTINCT ?m WHERE {
  { ?m wdt:P31/wdt:P279* wd:Q3231690 . } UNION { ?m wdt:P31 wd:Q59773381 . }
  { ?m wdt:P1716 [] } UNION { ?m wdt:P176 [] }
}
"""

DETAIL_QUERY = """
SELECT ?m ?enLabel ?itLabel ?brand ?brandLabel ?brandCountry ?maker ?makerLabel ?makerCountry
       ?series ?image ?start ?end ?inst ?sub ?origin ?sitelinks ?itwiki ?dewiki ?frwiki WHERE {
  VALUES ?m { %s }
  OPTIONAL { ?m rdfs:label ?enLabel FILTER(LANG(?enLabel) = "en") }
  OPTIONAL { ?m rdfs:label ?itLabel FILTER(LANG(?itLabel) = "it") }
  OPTIONAL { ?m wdt:P1716 ?brand . ?brand rdfs:label ?brandLabel FILTER(LANG(?brandLabel) = "en")
             OPTIONAL { ?brand wdt:P17/wdt:P297 ?brandCountry } }
  OPTIONAL { ?m wdt:P176 ?maker . ?maker rdfs:label ?makerLabel FILTER(LANG(?makerLabel) = "en")
             OPTIONAL { ?maker wdt:P17/wdt:P297 ?makerCountry } }
  OPTIONAL { ?m wdt:P179 ?series }
  OPTIONAL { ?m wdt:P18 ?image }
  OPTIONAL { ?m wdt:P580|wdt:P571|wdt:P2754|wdt:P5204|wdt:P729|wdt:P2031 ?start }
  OPTIONAL { ?m wdt:P582|wdt:P2669|wdt:P576|wdt:P730|wdt:P2032 ?end }
  OPTIONAL { ?m wdt:P31 ?inst }
  OPTIONAL { ?m wdt:P279 ?sub }
  OPTIONAL { ?m wdt:P495/wdt:P297 ?origin }
  OPTIONAL { ?m wikibase:sitelinks ?sitelinks }
  OPTIONAL { ?itwiki schema:about ?m ; schema:isPartOf <https://it.wikipedia.org/> }
  OPTIONAL { ?dewiki schema:about ?m ; schema:isPartOf <https://de.wikipedia.org/> }
  OPTIONAL { ?frwiki schema:about ?m ; schema:isPartOf <https://fr.wikipedia.org/> }
}
"""


def year(value: str | None) -> int | None:
    if not value or value.startswith("-"):
        return None
    try:
        y = int(value.lstrip("+").split("-")[0])
    except ValueError:
        return None
    return y if y and 1880 <= y <= 2100 else None


def merge_row(items: dict, row: dict) -> None:
    q = qid(row["m"])
    it = items.setdefault(q, {
        "qid": q, "en": None, "it": None, "brand": None, "brandName": None, "brandCountry": None,
        "maker": None, "makerName": None, "makerCountry": None, "series": set(), "images": set(),
        "starts": set(), "ends": set(), "instanceOf": set(), "subclassOf": set(), "origin": set(),
        "sitelinks": 0, "itwiki": False, "dewiki": False, "frwiki": False,
    })
    for key, src in (("en", "enLabel"), ("it", "itLabel"), ("brandName", "brandLabel"),
                     ("makerName", "makerLabel"), ("brandCountry", "brandCountry"),
                     ("makerCountry", "makerCountry")):
        if row.get(src) and not it[key]:
            it[key] = row[src]
    if row.get("brand") and not it["brand"]:
        it["brand"] = qid(row["brand"])
    if row.get("maker") and not it["maker"]:
        it["maker"] = qid(row["maker"])
    if row.get("series"):
        it["series"].add(qid(row["series"]))
    if row.get("image"):
        it["images"].add(row["image"].rsplit("/", 1)[-1])
    if (y := year(row.get("start"))):
        it["starts"].add(y)
    if (y := year(row.get("end"))):
        it["ends"].add(y)
    if row.get("inst"):
        it["instanceOf"].add(qid(row["inst"]))
    if row.get("sub"):
        it["subclassOf"].add(qid(row["sub"]))
    if row.get("origin"):
        it["origin"].add(row["origin"])
    if row.get("sitelinks"):
        it["sitelinks"] = max(it["sitelinks"], int(row["sitelinks"]))
    for wiki in ("itwiki", "dewiki", "frwiki"):
        if row.get(wiki):
            it[wiki] = True


def main() -> None:
    print("elenco item…", flush=True)
    ids = sorted({qid(r["m"]) for r in sparql(LIST_QUERY)})
    print(f"{len(ids)} item", flush=True)
    # Incrementale: tiene gli item già scaricati (cancella out/wikidata_raw.json per rifare tutto).
    path = OUT / "wikidata_raw.json"
    old = read_json(path) if path.exists() else {}
    items: dict = {}
    todo = [q for q in ids if q not in old]
    print(f"{len(todo)} nuovi", flush=True)
    batch = 150
    for i in range(0, len(todo), batch):
        chunk = todo[i:i + batch]
        rows = sparql(DETAIL_QUERY % " ".join("wd:" + q for q in chunk))
        for row in rows:
            merge_row(items, row)
        print(f"  {min(i + batch, len(todo))}/{len(todo)}", flush=True)
        time.sleep(0.5)
    out = {q: it for q, it in old.items() if q in set(ids)}
    for q, it in items.items():
        it = dict(it)
        for key in ("series", "images", "starts", "ends", "instanceOf", "subclassOf", "origin"):
            it[key] = sorted(it[key])
        out[q] = it
    write_json(OUT / "wikidata_raw.json", out)
    print(f"salvati {len(out)} item in out/wikidata_raw.json")


if __name__ == "__main__":
    sys.exit(main())
