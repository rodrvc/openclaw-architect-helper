#!/usr/bin/env bash
# Guardarraíl: falla (exit 1) si el peso de arranque de algún agente OpenClaw supera su techo.
# Peso de arranque = suma de los .md que se inyectan en CADA llamada al modelo.
# Uso: scripts/check-prompt-budget.sh [--json]     (lee ~/.openclaw/openclaw.json, no escribe nada)
set -euo pipefail
CFG="${OPENCLAW_CONFIG_PATH:-$HOME/.openclaw/openclaw.json}"
python3 - "$CFG" "${1:-}" <<'PY'
import json, os, sys
cfg_path, mode = sys.argv[1], sys.argv[2]
c = json.load(open(os.path.expanduser(cfg_path)))
# Archivos que OpenClaw inyecta al arranque de cada sesión (ver knowledge/optimizacion-tokens.md)
BOOT = ["AGENTS.md","SOUL.md","USER.md","IDENTITY.md","TOOLS.md","MEMORY.md","HEARTBEAT.md","BOOTSTRAP.md"]  # PROJECTS.md NO es bootstrap (verificado en dist/)
# Techos por perfil (bytes). Perfil por defecto = notificación (el más estricto) para obligar a clasificar agentes nuevos.
KB = 1024
CEILING = {
    "main": 12*KB,                                   # orquestador
    "cv": 12*KB, "adondepo": 12*KB,                  # agénticos con side effects (asumido = techo de main)
    "sofia": 8*KB, "andres": 8*KB,                   # conversacionales
    "claudio": 6*KB, "corfo": 6*KB, "acuaria-branding": 6*KB,   # notificación / saludo (4 KB es irreal: AGENTS base+IDENTITY+TOOLS+HEARTBEAT ya suman ~3 KB)
    "acuarito": 9*KB,                                # notificación bajo lockdown: SOUL de seguridad (4.3 KB) no se recorta
}
DEFAULT = 6*KB
ws = {"main": c["agents"]["defaults"]["workspace"]}
for a in c["agents"]["list"]:
    ws[a["id"]] = a.get("workspace", ws["main"])
rows, fail = [], False
HOME_OC = os.path.expanduser('~/.openclaw/')
for aid, w in ws.items():
    w = os.path.expanduser(w); total = 0; parts = []
    if not w.startswith(HOME_OC):
        print(f"FALLA principio: {aid} vive en {w} (workspace debe estar bajo ~/.openclaw/; el repo es un parámetro en PROJECT.md)"); fail = True
    for f in BOOT:
        p = os.path.join(w, f)
        if os.path.isfile(p):
            s = os.path.getsize(p); total += s; parts.append(f"{f}={s}")
    ceil = CEILING.get(aid, DEFAULT); ok = total <= ceil; fail |= (not ok)
    rows.append({"agent": aid, "bytes": total, "ceiling": ceil, "ok": ok, "files": parts})
if mode == "--json":
    print(json.dumps(rows, indent=1)); sys.exit(1 if fail else 0)
print(f"{'agente':18s}{'bytes':>8s}{'techo':>8s}  estado")
for r in rows:
    print(f"{r['agent']:18s}{r['bytes']:8d}{r['ceiling']:8d}  {'OK' if r['ok'] else 'EXCEDE'}   " + " ".join(r['files']))
tot = sum(r['bytes'] for r in rows)
print(f"\nTOTAL flota: {tot} B  ({tot//1024} KB)")
if fail:
    print("\nFALLA: hay agentes sobre su techo. Criterio: el prompt describe al agente; lo que cambia la respuesta en <20% de las llamadas va a un archivo bajo demanda o a una skill.")
    sys.exit(1)
print("\nOK: todos los agentes dentro de su techo.")
PY
