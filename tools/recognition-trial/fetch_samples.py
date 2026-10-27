#!/usr/bin/env python3
"""Scarica poche foto di esempio da Wikimedia Commons (solo licenze libere) in samples/.

Servono solo per provare la pipeline quando mancano le foto dell'utente: i numeri
ottenuti qui NON sono rappresentativi di foto scattate in strada.
Scrive samples/truth.csv e samples/LICENSES.csv (autore, licenza, URL della pagina).
"""
import csv
import html
import json
import re
import sys
import time
import urllib.parse
import ssl
import urllib.request

import certifi

CTX = ssl.create_default_context(cafile=certifi.where())
from pathlib import Path

HERE = Path(__file__).resolve().parent
OUT = HERE / "samples"
API = "https://commons.wikimedia.org/w/api.php"
UA = "CarSpotRecognitionTrial/0.1 (andrea.balloni@outlook.com; zero-shot evaluation, few images)"
PER_MODEL = 2

# (query di ricerca, marca, modello come in labels.csv, parole obbligatorie nel titolo)
QUERIES = [
    ("Fiat Panda 2012", "Fiat", "Panda", ["panda"]),
    ("Fiat 500 2007", "Fiat", "500", ["500"]),
    ("Fiat Tipo 2016", "Fiat", "Tipo", ["tipo"]),
    ("Fiat Grande Punto", "Fiat", "Grande Punto", ["punto"]),
    ("Alfa Romeo Giulietta", "Alfa Romeo", "Giulietta", ["giulietta"]),
    ("Alfa Romeo Giulia 952", "Alfa Romeo", "Giulia", ["giulia"]),
    ("Alfa Romeo Stelvio", "Alfa Romeo", "Stelvio", ["stelvio"]),
    ("Lancia Ypsilon", "Lancia", "Ypsilon", ["ypsilon"]),
    ("Jeep Renegade", "Jeep", "Renegade", ["renegade"]),
    ("Volkswagen Golf VII", "Volkswagen", "Golf", ["golf"]),
    ("Volkswagen Polo", "Volkswagen", "Polo", ["polo"]),
    ("Volkswagen T-Roc", "Volkswagen", "T-Roc", ["roc"]),
    ("Renault Clio V", "Renault", "Clio", ["clio"]),
    ("Dacia Duster", "Dacia", "Duster", ["duster"]),
    ("Dacia Sandero", "Dacia", "Sandero", ["sandero"]),
    ("Peugeot 208", "Peugeot", "208", ["208"]),
    ("Citroën C3", "Citroën", "C3", ["c3"]),
    ("Ford Fiesta", "Ford", "Fiesta", ["fiesta"]),
    ("Ford Puma", "Ford", "Puma", ["puma"]),
    ("Toyota Yaris Hybrid", "Toyota", "Yaris", ["yaris"]),
    ("Opel Corsa", "Opel", "Corsa", ["corsa"]),
    ("BMW G20 3 Series", "BMW", "Serie 3", ["3", "series"]),
    ("BMW X1", "BMW", "X1", ["x1"]),
    ("Mercedes-Benz A-Class W177", "Mercedes-Benz", "Classe A", ["a"]),
    ("Audi A3 8Y", "Audi", "A3", ["a3"]),
    ("Tesla Model 3", "Tesla", "Model 3", ["model", "3"]),
    ("Ferrari 488 GTB", "Ferrari", "488 GTB", ["488"]),
    ("Lamborghini Huracán", "Lamborghini", "Huracán", ["hurac"]),
    ("Porsche 911 992", "Porsche", "911", ["911"]),
    ("Mini Cooper F56", "Mini", "Cooper", ["mini"]),
    ("Smart Fortwo", "Smart", "Fortwo", ["fortwo"]),
    ("Nissan Qashqai", "Nissan", "Qashqai", ["qashqai"]),
    ("Kia Picanto", "Kia", "Picanto", ["picanto"]),
    ("Hyundai i10", "Hyundai", "i10", ["i10"]),
    ("Skoda Octavia", "Skoda", "Octavia", ["octavia"]),
    ("SEAT Ibiza 6F", "Seat", "Ibiza", ["ibiza"]),
    ("Suzuki Jimny", "Suzuki", "Jimny", ["jimny"]),
    ("Land Rover Defender", "Land Rover", "Defender", ["defender"]),
    ("Fiat Nuova 500 1960s", "Fiat", "500", ["nuova", "500"]),
    ("Piaggio Ape", "Piaggio", "Ape", ["ape"]),
]
BAD = re.compile(r"interior|engine|motor\b|logo|badge|dashboard|cockpit|wheel|seat\b|detail|steering|emblem|headlight|taillight|diagram|plan|drawing|svg|brochure|poster|museum|model car|toy|scale|parking|sensor|burnt|\br5\b|armaturenbrett|sprint|classic|solitude| & |\bii\b|rally|police|crash|accident|wreck|\bgt3\b", re.I)
OK_LICENSE = re.compile(r"^(CC0|CC BY|CC BY-SA|Public domain|PD|CC-BY)", re.I)


def get(params: dict) -> dict:
    url = API + "?" + urllib.parse.urlencode(params)
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=30, context=CTX) as r:
        return json.load(r)


def strip(s: str) -> str:
    return html.unescape(re.sub(r"<[^>]+>", "", s or "")).strip()


def slug(s: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", s.lower()).strip("-")


def main() -> None:
    OUT.mkdir(exist_ok=True)
    truth, lic = [], []
    for qi, (q, make, model, must) in enumerate(QUERIES):
        data = get({
            "action": "query", "format": "json", "generator": "search", "gsrnamespace": 6,
            "gsrsearch": f"{q} filetype:bitmap", "gsrlimit": 30,
            "prop": "imageinfo", "iiprop": "url|size|extmetadata|mime", "iiurlwidth": 1024,
        })
        pages = sorted(data.get("query", {}).get("pages", {}).values(), key=lambda p: p.get("index", 0))
        taken = 0
        for p in pages:
            if taken >= PER_MODEL:
                break
            title = p["title"]
            ii = (p.get("imageinfo") or [{}])[0]
            ext = ii.get("extmetadata", {})
            license_name = strip(ext.get("LicenseShortName", {}).get("value", ""))
            tl = title.lower()
            if (ii.get("mime") != "image/jpeg" or not OK_LICENSE.match(license_name) or BAD.search(tl)
                    or not all(w in tl for w in must) or ii.get("width", 0) < 1000 or ii.get("width", 0) < ii.get("height", 0)):
                continue
            taken += 1
            fname = f"{slug(make)}_{slug(model)}_{qi}-{taken}.jpg"
            req = urllib.request.Request(ii["thumburl"], headers={"User-Agent": UA})
            with urllib.request.urlopen(req, timeout=60, context=CTX) as r:
                (OUT / fname).write_bytes(r.read())
            truth.append({"file": fname, "make": make, "model": model, "generation": ""})
            lic.append({"file": fname, "title": title, "license": license_name,
                        "author": strip(ext.get("Artist", {}).get("value", "")),
                        "page": ii.get("descriptionurl", "")})
            print(fname, "<-", title, f"[{license_name}]")
            time.sleep(1.0)
        if taken == 0:
            print("NESSUN RISULTATO per", q, file=sys.stderr)
        time.sleep(0.5)
    for name, rows in (("truth.csv", truth), ("LICENSES.csv", lic)):
        with open(OUT / name, "w", newline="", encoding="utf-8") as f:
            w = csv.DictWriter(f, fieldnames=list(rows[0]))
            w.writeheader()
            w.writerows(rows)
    print(len(truth), "immagini")


if __name__ == "__main__":
    main()
