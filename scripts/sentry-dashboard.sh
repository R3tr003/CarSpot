#!/usr/bin/env bash
# Crea o aggiorna le dashboard CarSpot su Sentry (org andrea-qm, regione EU):
#   · Panoramica       salute dell'app: crash, sessioni, utenti, errori, hang, problemi aperti
#   · Prestazioni      avvio, flussi dell'app (cattura, sync, profilo, login), frame lenti
#   · Rete e backend   Supabase, Clerk, Mixpanel: latenze, errori, endpoint, SwiftData locale
#   · Utenti e provenienza  paese/città (dall'IP, approssimativi), utenti attivi, release, iPhone
#   · Gioco e uso      metriche applicative: catture, esiti, rarità, login, schermate, coda sync
#   · Dispositivo e sessioni  avvii, durata sessioni, rete, permessi, camera, memoria, temperatura
# Ogni widget è validato da Sentry prima dell'invio: quelli rifiutati vengono saltati e
# stampati (così una metrica non ancora arrivata non blocca tutta la dashboard).
# Rilanciarlo è sicuro: le dashboard con lo stesso titolo vengono aggiornate, non duplicate.
#
# Il token NON sta nel repo: Sentry → profilo → User Auth Tokens, permessi
# Organization Read & Write + Project Read.
#   SENTRY_AUTH_TOKEN=… ./scripts/sentry-dashboard.sh
set -euo pipefail

: "${SENTRY_AUTH_TOKEN:?Imposta SENTRY_AUTH_TOKEN (token personale Sentry)}"
export SENTRY_ORG="andrea-qm" SENTRY_PROJECT="carspot" SENTRY_API="https://de.sentry.io/api/0"

python3 - <<'PY'
import json, os, sys, subprocess

ORG, PROJECT, API = os.environ["SENTRY_ORG"], os.environ["SENTRY_PROJECT"], os.environ["SENTRY_API"]
TOKEN = os.environ["SENTRY_AUTH_TOKEN"]

def call(method, path, body=None):
    # curl e non urllib: usa i certificati di macOS (il Python di python.org spesso
    # non li ha e fallisce con CERTIFICATE_VERIFY_FAILED).
    cmd = ["curl", "-sS", "-X", method, API + path, "-w", "\n%{http_code}",
           "-H", f"Authorization: Bearer {TOKEN}", "-H", "Content-Type: application/json"]
    if body is not None: cmd += ["--data-binary", "@-"]
    r = subprocess.run(cmd, input=json.dumps(body).encode() if body is not None else None,
                       capture_output=True)
    if r.returncode != 0: sys.exit(f"curl non riuscito: {r.stderr.decode(errors='replace')}")
    raw, _, code = r.stdout.decode(errors="replace").rpartition("\n")
    try: return int(code), (json.loads(raw) if raw.strip() else None)
    except ValueError: return int(code), raw

status, project = call("GET", f"/projects/{ORG}/{PROJECT}/")
if status != 200: sys.exit(f"Progetto non trovato ({status}): {project}")
PID = int(project["id"])

# ---------- costruttori ----------
def W(title, display, wtype, aggregates, columns=(), conditions="", orderby="", w=2, h=2, limit=None, desc=None):
    q = {"name": "", "fields": list(columns) + list(aggregates), "aggregates": list(aggregates),
         "columns": list(columns), "conditions": conditions, "orderby": orderby}
    out = {"title": title, "displayType": display, "widgetType": wtype, "interval": "1h",
           "queries": [q], "layout": {"w": w, "h": h, "minH": 1 if display == "big_number" else 2}}
    if limit: out["limit"] = limit
    if desc: out["description"] = desc
    return out

big    = lambda t, wt, agg, cond="", desc=None: W(t, "big_number", wt, [agg], conditions=cond, w=1, h=1, desc=desc)
spans  = "spans"; errors = "error-events"; release = "metrics"; issues = "issue"; tm = "tracemetrics"
FLOWS  = "span.op:[capture,sync,profile,auth]"
HTTP   = "span.op:http.client"

# Metriche applicative (Explore → Metrics): func(value,nome,tipo,unità)
def m(func, name, kind, unit="-"): return f"{func}(value,{name},{kind},{unit})"

DASHBOARDS = {
"CarSpot · Panoramica": [
    big("Sessioni senza crash", release, "crash_free_rate(session)", desc="Quota di sessioni concluse senza crash."),
    big("Utenti senza crash", release, "crash_free_rate(user)"),
    big("Sessioni", release, "sum(session)"),
    big("Utenti attivi", release, "count_unique(user)"),
    big("Errori", errors, "count()"),
    big("App bloccata (hang)", errors, "count()", "error.mechanism:AppHang"),
    W("Sessioni per esito", "area", release, ["sum(session)"], columns=["session.status"], w=3, h=2, limit=5),
    W("Errori nel tempo", "line", errors, ["count()", "count_unique(user)"], w=3, h=2),
    W("Problemi aperti", "table", issues, [], columns=["issue", "assignee", "title"],
      conditions="is:unresolved", orderby="date", w=6, h=3),
    W("Errori per area dell'app", "bar", errors, ["count()"], columns=["area"], orderby="-count()", w=2, h=2, limit=8),
    W("Errori per tipo", "table", errors, ["count()"], columns=["error_type", "error_code"],
      orderby="-count()", w=2, h=2, limit=10),
    W("Errori per release", "table", errors, ["count()", "count_unique(user)"], columns=["release"],
      orderby="-count()", w=2, h=2, limit=10),
    W("Crash per release", "table", release, ["crash_free_rate(session)", "sum(session)"], columns=["release"],
      orderby="-sum(session)", w=3, h=2, limit=10),
    W("Dispositivi e iOS", "table", errors, ["count()"], columns=["device", "os"], orderby="-count()", w=3, h=2, limit=10),
],
"CarSpot · Prestazioni": [
    big("Avvio a freddo p95", spans, "p95(span.duration)", "span.op:app.start.cold"),
    big("Avvio a caldo p95", spans, "p95(span.duration)", "span.op:app.start.warm"),
    big("Cattura completa p95", spans, "p95(span.duration)", "span.description:capture.pipeline"),
    big("Riconoscimento p95", spans, "p95(span.duration)", "span.description:capture.recognize"),
    big("Caricamento profilo p95", spans, "p95(span.duration)", "span.description:profile.load"),
    big("Sync in arrivo p95", spans, "p95(span.duration)", "span.description:sync.pull"),
    W("Tempi dei flussi CarSpot", "table", spans, ["count()", "p50(span.duration)", "p95(span.duration)", "max(span.duration)"],
      columns=["span.description"], conditions=FLOWS, orderby="-p95(span.duration)", w=6, h=3, limit=20),
    W("Cattura: passi p95", "line", spans, ["p95(span.duration)"], columns=["span.description"],
      conditions="span.description:[capture.pipeline,capture.prepare,capture.anonymize,capture.recognize,capture.save,capture.rarity]",
      orderby="-p95(span.duration)", w=3, h=2, limit=6),
    W("Sync, profilo e login p95", "line", spans, ["p95(span.duration)"], columns=["span.description"],
      conditions="span.description:[sync.push,sync.pull,profile.load,auth.code.send,auth.code.verify]",
      orderby="-p95(span.duration)", w=3, h=2, limit=5),
    W("Avvio app p50 / p95", "line", spans, ["p50(span.duration)", "p95(span.duration)"],
      conditions="span.op:[app.start.cold,app.start.warm]", w=3, h=2),
    W("Flussi falliti", "table", spans, ["count()"], columns=["span.description", "span.status"],
      conditions=FLOWS + " !span.status:ok", orderby="-count()", w=3, h=2, limit=10),
    W("Quante volte (al giorno)", "bar", spans, ["count()"], columns=["span.description"],
      conditions=FLOWS, orderby="-count()", w=3, h=2, limit=8),
    W("Frame lenti e bloccati", "line", spans, ["avg(mobile.slow_frames)", "avg(mobile.frozen_frames)"],
      conditions="is_transaction:true", w=3, h=2),
],
"CarSpot · Rete e backend": [
    big("Supabase p95", spans, "p95(span.duration)", HTTP + " span.domain:*supabase.co"),
    big("Clerk p95", spans, "p95(span.duration)", HTTP + " span.domain:*clerk.accounts.dev"),
    big("Richieste fallite", spans, "count()", HTTP + " !span.status:ok"),
    big("Richieste totali", spans, "count()", HTTP),
    big("Database locale p95", spans, "p95(span.duration)", "span.op:db.sql.query"),
    big("Mixpanel p95", spans, "p95(span.duration)", HTTP + " span.domain:*mixpanel.com"),
    W("Endpoint: volume e latenza", "table", spans, ["count()", "p50(span.duration)", "p95(span.duration)"],
      columns=["span.description"], conditions=HTTP, orderby="-count()", w=6, h=3, limit=20),
    W("Latenza p95 per servizio", "line", spans, ["p95(span.duration)"], columns=["span.domain"],
      conditions=HTTP, orderby="-p95(span.duration)", w=3, h=2, limit=5),
    W("Richieste per servizio", "bar", spans, ["count()"], columns=["span.domain"],
      conditions=HTTP, orderby="-count()", w=3, h=2, limit=5),
    W("Codici di risposta", "table", spans, ["count()"], columns=["span.domain", "http.response.status_code"],
      conditions=HTTP, orderby="-count()", w=3, h=2, limit=12),
    W("Endpoint più lenti", "table", spans, ["p95(span.duration)", "count()"], columns=["span.description"],
      conditions=HTTP, orderby="-p95(span.duration)", w=3, h=2, limit=10),
    W("Query SwiftData più lente", "table", spans, ["p95(span.duration)", "count()"], columns=["span.description"],
      conditions="span.op:[db.sql.query,db.sql.transaction]", orderby="-p95(span.duration)", w=6, h=2, limit=10),
],
"CarSpot · Utenti e provenienza": [
    # Paese/città li ricava Sentry dall'IP della connessione (approssimativi, mai il GPS).
    big("Utenti unici (24h)", spans, "count_unique(user.id)"),
    big("Paesi", spans, "count_unique(user.geo.country_code)"),
    big("Città", spans, "count_unique(user.geo.city)"),
    big("Utenti con errori", errors, "count_unique(user)"),
    W("Utenti per paese", "table", spans, ["count_unique(user.id)", "count()"], columns=["user.geo.country_code"],
      orderby="-count_unique(user.id)", w=3, h=3, limit=10),
    W("Utenti per città", "table", spans, ["count_unique(user.id)", "count()"],
      columns=["user.geo.country_code", "user.geo.city"], orderby="-count_unique(user.id)", w=3, h=3, limit=10),
    W("Utenti attivi nel tempo", "line", spans, ["count_unique(user.id)"], w=3, h=2),
    W("Attività per paese nel tempo", "area", spans, ["count()"], columns=["user.geo.country_code"],
      orderby="-count()", w=3, h=2, limit=5),
    W("Errori per paese", "bar", errors, ["count()"], columns=["geo.country_code"], orderby="-count()", w=2, h=2, limit=8),
    W("Utenti per release", "table", release, ["count_unique(user)", "sum(session)"], columns=["release"],
      orderby="-sum(session)", w=2, h=2, limit=10),
    W("Modelli di iPhone e iOS", "table", errors, ["count_unique(user)"], columns=["device", "os"],
      orderby="-count_unique(user)", w=2, h=2, limit=10),
],
"CarSpot · Gioco e uso": [
    big("Catture avviate", tm, m("sum", "capture.started", "counter")),
    big("Carte salvate", tm, m("sum", "card.saved", "counter")),
    big("Sfide riscattate", tm, m("sum", "challenge.claimed", "counter")),
    big("In coda per il cloud", tm, m("avg", "sync.pending", "gauge")),
    W("Esiti della cattura", "bar", tm, [m("sum", "capture.outcome", "counter")], columns=["outcome"],
      orderby=f"-{m('sum', 'capture.outcome', 'counter')}", w=3, h=2, limit=8),
    W("Carte salvate per rarità", "bar", tm, [m("sum", "card.saved", "counter")], columns=["rarity"],
      orderby=f"-{m('sum', 'card.saved', 'counter')}", w=3, h=2, limit=4),
    W("Durata cattura p50 / p95 (ms)", "line", tm,
      [m("p50", "capture.duration", "distribution", "millisecond"), m("p95", "capture.duration", "distribution", "millisecond")], w=3, h=2),
    W("Confidenza riconoscimento", "line", tm,
      [m("p50", "recognition.confidence", "distribution"), m("p10", "recognition.confidence", "distribution")], w=3, h=2),
    W("Accessi per metodo ed esito", "categorical_bar", tm, [m("sum", "auth.sign_in", "counter")], columns=["method", "result"],
      orderby=f"-{m('sum', 'auth.sign_in', 'counter')}", w=3, h=2, limit=10),
    W("Schermate aperte", "bar", tm, [m("sum", "screen.view", "counter")], columns=["screen"],
      orderby=f"-{m('sum', 'screen.view', 'counter')}", w=3, h=2, limit=8),
    W("Sync: inviati e falliti", "line", tm, [m("sum", "sync.pushed", "counter"), m("sum", "sync.failure", "counter")], w=3, h=2),
    W("Dimensione collezione", "line", tm, [m("avg", "collection.size", "gauge"), m("max", "collection.size", "gauge")], w=3, h=2),
    W("Livello dei giocatori", "line", tm, [m("avg", "player.level", "gauge"), m("max", "player.level", "gauge")], w=3, h=2),
    W("Sfide completate oggi", "line", tm, [m("avg", "challenge.progress", "gauge")], w=3, h=2),
    W("Dettagli carta aperti per rarità", "bar", tm, [m("sum", "card.view", "counter")], columns=["rarity"],
      orderby=f"-{m('sum', 'card.view', 'counter')}", w=3, h=2, limit=4),
    W("Altezza del pannello usata", "bar", tm, [m("sum", "panel.detent", "counter")], columns=["detent"],
      orderby=f"-{m('sum', 'panel.detent', 'counter')}", w=3, h=2, limit=3),
    W("Interazioni con la mappa", "line", tm, [m("sum", "map.interaction", "counter")], w=3, h=2),
    W("Setup profilo: passi raggiunti", "bar", tm, [m("sum", "setup.step", "counter")], columns=["step"],
      orderby=f"-{m('sum', 'setup.step', 'counter')}", w=3, h=2, limit=8),
    W("Errori mostrati all'utente", "bar", tm, [m("sum", "ui.error", "counter")], columns=["error"],
      orderby=f"-{m('sum', 'ui.error', 'counter')}", w=3, h=2, limit=10),
    W("Modifiche profilo e impostazioni", "categorical_bar", tm, [m("sum", "profile.edit", "counter")], columns=["field", "origin"],
      orderby=f"-{m('sum', 'profile.edit', 'counter')}", w=3, h=2, limit=6),
],
"CarSpot · Dispositivo e sessioni": [
    big("Avvii a freddo", tm, m("sum", "app.launch", "counter")),
    big("Durata sessione p50 (s)", tm, m("p50", "app.session.duration", "distribution", "second")),
    big("Avvisi di memoria", tm, m("sum", "memory.warning", "counter")),
    big("Camera pronta p95 (ms)", tm, m("p95", "camera.ready", "distribution", "millisecond")),
    W("Avvii per tipo", "bar", tm, [m("sum", "app.launch", "counter")], columns=["kind"],
      orderby=f"-{m('sum', 'app.launch', 'counter')}", w=2, h=2, limit=2),
    W("Rete al rientro nell'app", "bar", tm, [m("sum", "app.foreground", "counter")], columns=["network"],
      orderby=f"-{m('sum', 'app.foreground', 'counter')}", w=2, h=2, limit=4),
    W("Durata sessioni p50 / p95 (s)", "line", tm,
      [m("p50", "app.session.duration", "distribution", "second"), m("p95", "app.session.duration", "distribution", "second")], w=2, h=2),
    W("Permessi concessi", "categorical_bar", tm, [m("avg", "permission.status", "gauge")], columns=["permission", "status"],
      orderby=f"-{m('avg', 'permission.status', 'gauge')}", w=3, h=2, limit=10),
    W("Camera non disponibile", "bar", tm, [m("sum", "camera.unavailable", "counter")], columns=["reason"],
      orderby=f"-{m('sum', 'camera.unavailable', 'counter')}", w=3, h=2, limit=3),
    W("Temperatura e risparmio energetico", "line", tm,
      [m("max", "device.thermal", "gauge"), m("avg", "device.low_power", "gauge")], w=3, h=2),
    W("Tempo di apertura camera p50 / p95 (ms)", "line", tm,
      [m("p50", "camera.ready", "distribution", "millisecond"), m("p95", "camera.ready", "distribution", "millisecond")], w=3, h=2),
],
}

# ---------- layout: big number in fila da 6, poi blocchi a due colonne ----------
def place(widgets):
    x = y = row_h = 0
    for wd in widgets:
        L = wd["layout"]
        if x + L["w"] > 6: x, y, row_h = 0, y + row_h, 0
        L["x"], L["y"] = x, y
        x += L["w"]; row_h = max(row_h, L["h"])
    return widgets

def validate(widget):
    # Endpoint usato dall'editor di Sentry per controllare un widget prima di salvarlo.
    status, body = call("POST", f"/organizations/{ORG}/dashboards/widgets/", {**widget, "projects": [PID]})
    return status in (200, 201), body

status, existing = call("GET", f"/organizations/{ORG}/dashboards/?per_page=100")
by_title = {d["title"]: d["id"] for d in existing} if status == 200 else {}

for title, widgets in DASHBOARDS.items():
    ok_widgets, skipped = [], []
    # La posizione serve già alla validazione; poi si ricompatta senza i widget scartati.
    for wd in place(widgets):
        ok, body = validate(wd)
        (ok_widgets if ok else skipped).append(wd if ok else (wd["title"], body))
    if not ok_widgets:
        # Mai sovrascrivere una dashboard esistente con zero widget.
        print(f"✗ {title}: nessun widget valido, dashboard lasciata com'è")
        for name, why in skipped:
            print(f"   saltato «{name}»: {json.dumps(why, ensure_ascii=False)[:300]}")
        continue
    payload = {"title": title, "projects": [PID], "period": "7d", "widgets": place(ok_widgets)}
    if title in by_title:
        status, body = call("PUT", f"/organizations/{ORG}/dashboards/{by_title[title]}/", {**payload, "id": by_title[title]})
        did = by_title[title]
    else:
        status, body = call("POST", f"/organizations/{ORG}/dashboards/", payload)
        did = body.get("id") if isinstance(body, dict) else None
    if status in (200, 201):
        print(f"✓ {title}: {len(ok_widgets)} widget → https://{ORG}.sentry.io/dashboard/{did}/")
    else:
        print(f"✗ {title}: Sentry ha risposto {status}: {body}")
    for name, why in skipped:
        print(f"   saltato «{name}»: {json.dumps(why, ensure_ascii=False)[:300]}")
PY
