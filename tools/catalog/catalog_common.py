"""Utilità condivise della pipeline del catalogo (slug, normalizzazione, HTTP educato)."""
import json
import re
import subprocess
import time
import unicodedata
import urllib.parse
from pathlib import Path

ROOT = Path(__file__).resolve().parent
OUT = ROOT / "out"
CURATED = ROOT / "curated"
USER_AGENT = "CarSpotCatalog/0.1 (car spotting game; trial catalog)"
SPARQL_URL = "https://query.wikidata.org/sparql"
COMMONS_API = "https://commons.wikimedia.org/w/api.php"


def fold(text: str) -> str:
    """Toglie i diacritici (Citroën → Citroen, Doblò → Doblo)."""
    nfkd = unicodedata.normalize("NFKD", text)
    return "".join(c for c in nfkd if not unicodedata.combining(c))


def normalize(text: str) -> str:
    """Minuscole, senza diacritici, trattini/underscore come spazi, spazi compressi."""
    t = fold(text).lower().replace("-", " ").replace("_", " ")
    return " ".join(t.split())


def slug(text: str) -> str:
    t = fold(text).lower().replace("+", " plus ")
    t = re.sub(r"[^a-z0-9]+", "-", t)
    return t.strip("-")


def http_get(url: str, params: dict | None = None, accept: str = "application/json",
             retries: int = 5, timeout: int = 120) -> bytes:
    """GET con curl (il Python di python.org non ha i certificati di sistema), con ritentativi."""
    if params:
        url = url + "?" + urllib.parse.urlencode(params)
    delay = 5
    for attempt in range(retries):
        proc = subprocess.run(
            ["curl", "-sS", "-L", "--max-time", str(timeout), "-A", USER_AGENT, "-H", f"Accept: {accept}",
             "-w", "\n%{http_code}", url], capture_output=True)
        body, _, code = proc.stdout.rpartition(b"\n")
        status = int(code or 0)
        if proc.returncode == 0 and status == 200:
            return body
        if attempt < retries - 1 and (proc.returncode != 0 or status in (429, 500, 502, 503, 504)):
            time.sleep(delay)
            delay *= 2
            continue
        raise RuntimeError(f"HTTP {status} (curl {proc.returncode}) per {url[:200]}")
    raise RuntimeError("unreachable")


def download(url: str, dest: Path, timeout: int = 120) -> int:
    """Scarica un file con curl; restituisce lo status HTTP."""
    dest.parent.mkdir(parents=True, exist_ok=True)
    proc = subprocess.run(["curl", "-sS", "-L", "--max-time", str(timeout), "-A", USER_AGENT,
                           "-o", str(dest), "-w", "%{http_code}", url], capture_output=True, text=True)
    return int(proc.stdout or 0)


def sparql(query: str) -> list[dict]:
    data = http_get(SPARQL_URL, {"query": query, "format": "json"},
                    accept="application/sparql-results+json")
    rows = json.loads(data)["results"]["bindings"]
    return [{k: v["value"] for k, v in row.items()} for row in rows]


def qid(uri: str) -> str:
    return uri.rsplit("/", 1)[-1]


def read_json(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def write_json(path: Path, data) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=1, sort_keys=True), encoding="utf-8")
