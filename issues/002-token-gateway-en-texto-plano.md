# Issue #002 — `gateway.auth.token` en texto plano en openclaw.json

**Estado:** abierto
**Prioridad:** alta (seguridad)
**Creado:** 2026-08-08
**Detectado por:** mapeo de config (solo lectura).

## Problema

En `~/.openclaw/openclaw.json`, la clave **`gateway.auth.token`** está guardada como
**valor en texto plano**, no como SecretRef. Además, sus **backups** (`.bak`, `.bak.1..4`,
`.last-good`, `.pre-update`) también contienen el token en claro.

Esto es un bloqueante para versionar la config: no se puede commitear el JSON tal cual.

## PII adicional en el JSON (revisar antes de versionar)

- `channels.whatsapp.allowFrom[]` / `groupAllowFrom[]` → números de teléfono.
- `bindings[].match.peer.id` → teléfonos / ID de grupo WhatsApp.
- `auth.profiles.*.email` → email del usuario.

## Solución propuesta (no aplicada aún — requiere confirmación de Rodrigo)

1. Mover el token a una referencia por env:
   ```bash
   openclaw config set gateway.auth.token \
     --ref-provider default --ref-source env --ref-id OPENCLAW_GATEWAY_TOKEN --dry-run
   ```
   (primero `--dry-run`, luego sin él si valida).
2. Poner el valor real en `~/.openclaw/.env` (fuera de git) como `OPENCLAW_GATEWAY_TOKEN=...`.
3. Verificar con `openclaw secrets audit --check` hasta que salga limpio.
4. Decidir estrategia para la PII (teléfonos/email): posiblemente vía `$include` de un archivo no versionado, o placeholders en el repo.

## Notas

- Ver el flujo completo en [`knowledge/config-management.md`](../knowledge/config-management.md).
- **NO** commitear `openclaw.json` ni sus `.bak*` mientras el token esté en claro.
