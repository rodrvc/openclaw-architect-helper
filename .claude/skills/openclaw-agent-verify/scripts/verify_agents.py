#!/usr/bin/env python3
"""Audita los agentes OpenClaw: routing real, canal, workspace y personalidad.

Solo LEE. No modifica configuracion ni manda mensajes.

Uso:
    python3 verify_agents.py            # todos los agentes
    python3 verify_agents.py corfo      # uno solo
    python3 verify_agents.py --json     # salida para procesar
"""
from __future__ import annotations

import json
import os
import sys
from pathlib import Path

CONFIG = Path(os.path.expanduser("~/.openclaw/openclaw.json"))
AGENTS_DIR = Path(os.path.expanduser("~/.openclaw/agents"))
PERSONALITY = ["SOUL.md", "AGENTS.md", "USER.md"]


def load_config() -> dict:
    if not CONFIG.exists():
        sys.exit(f"No existe {CONFIG}")
    return json.loads(CONFIG.read_text())


def binding_label(match: dict) -> str:
    peer = match.get("peer") or {}
    if peer.get("kind"):
        return f"{peer['kind']}:{peer.get('id', '?')}"
    if match.get("accountId"):
        return f"accountId={match['accountId']}"
    return "?"


def analyze(cfg: dict, only: str | None = None) -> list[dict]:
    """Un dict por agente, con los problemas detectados."""
    bindings = cfg.get("bindings", [])
    wa = cfg.get("channels", {}).get("whatsapp", {})
    groups_known = set(wa.get("groups", {}).keys())
    allow_from = set(wa.get("allowFrom", []) or [])
    group_allow = set(wa.get("groupAllowFrom", []) or [])

    # Bindings catch-all: capturan una cuenta entera, sin peer especifico.
    catch_all = [
        (i, b) for i, b in enumerate(bindings)
        if not (b.get("match", {}).get("peer") or {}).get("kind")
        and b.get("match", {}).get("accountId")
    ]

    out = []
    for agent in cfg.get("agents", {}).get("list", []):
        aid = agent.get("id")
        if only and aid != only:
            continue

        row = {
            "id": aid,
            "workspace": agent.get("workspace"),
            "model": agent.get("model"),
            "bindings": [],
            "problems": [],
            "notes": [],
        }

        mine = [(i, b) for i, b in enumerate(bindings) if b.get("agentId") == aid]
        for i, b in mine:
            row["bindings"].append({"index": i, "label": binding_label(b.get("match", {}))})

        if not mine:
            row["problems"].append("sin binding: no lo alcanza ningun canal")

        # --- Routing: un catch-all ANTERIOR se come los mensajes entrantes ---
        for idx, b in mine:
            peer = (b.get("match") or {}).get("peer") or {}
            if not peer.get("kind"):
                continue
            for ci, cb in catch_all:
                if cb.get("agentId") == aid:
                    continue
                if ci < idx:
                    row["notes"].append(
                        f"convive con el catch-all de '{cb.get('agentId')}' "
                        f"(accountId={cb['match']['accountId']}, indice {ci} < {idx}). "
                        f"En la practica los bindings de grupo SI ganan; los de peer "
                        f"direct estan sin confirmar. Comprobar con un mensaje real "
                        f"(ver 'Prueba de routing' en SKILL.md)."
                    )

        # --- Grupos declarados vs usados ---
        for idx, b in mine:
            peer = (b.get("match") or {}).get("peer") or {}
            if peer.get("kind") == "group":
                gid = peer.get("id", "")
                if gid not in groups_known:
                    row["problems"].append(
                        f"grupo {gid} enlazado pero NO declarado en "
                        f"channels.whatsapp.groups"
                    )
            elif peer.get("kind") == "direct":
                num = peer.get("id", "")
                if num not in allow_from:
                    row["problems"].append(
                        f"numero {num} enlazado pero NO esta en allowFrom: no podra escribirle"
                    )

        # --- Workspace y personalidad ---
        ws = Path(agent.get("workspace") or "")
        if not ws.exists():
            row["problems"].append(f"workspace no existe: {ws}")
        else:
            faltan = [f for f in PERSONALITY if not (ws / f).exists()]
            if faltan:
                row["notes"].append(f"sin {', '.join(faltan)} en el workspace")
            soul = ws / "SOUL.md"
            if soul.exists() and soul.stat().st_size < 400:
                row["notes"].append("SOUL.md muy corto: puede seguir siendo el template")

        # --- Agente en grupo => revisar blindaje ---
        en_grupo = any(
            ((b.get("match") or {}).get("peer") or {}).get("kind") == "group"
            for _, b in mine
        )
        if en_grupo:
            tools = agent.get("tools") or {}
            if not tools.get("deny"):
                row["notes"].append(
                    "habla en un grupo (terceros) y no tiene tools.deny: revisar lockdown"
                )
            row["notes"].append(
                f"groupAllowFrom actual: {sorted(group_allow) or 'vacio'}"
            )

        out.append(row)
    return out


def main() -> int:
    args = [a for a in sys.argv[1:] if a != "--json"]
    as_json = "--json" in sys.argv
    only = args[0] if args else None

    rows = analyze(load_config(), only)
    if as_json:
        print(json.dumps(rows, indent=2, ensure_ascii=False))
        return 1 if any(r["problems"] for r in rows) else 0

    con_problemas = 0
    for r in rows:
        icon = "OK " if not r["problems"] else "!! "
        print(f"\n{icon}{r['id']}")
        print(f"   workspace: {r['workspace']}")
        for b in r["bindings"]:
            print(f"   binding  : [{b['index']}] {b['label']}")
        for p in r["problems"]:
            print(f"   PROBLEMA : {p}")
        for n in r["notes"]:
            print(f"   nota     : {n}")
        if r["problems"]:
            con_problemas += 1

    print(f"\n{len(rows)} agente(s); {con_problemas} con problemas.")
    print("Este chequeo es ESTATICO: lee la config, no prueba el routing real.")
    print("La unica prueba valida del camino entrante es escribirle desde WhatsApp")
    print("y ver que sesion atiende (ver 'Prueba de routing' en SKILL.md).")
    return 1 if con_problemas else 0


if __name__ == "__main__":
    sys.exit(main())
