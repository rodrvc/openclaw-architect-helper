# 003 — Optimización de tokens: pendientes que necesitan decisión de Rodrigo

Origen: `knowledge/optimizacion-tokens.md` §2 (2026-08-22). Todo lo de abajo tiene comando listo ahí.

- [ ] **Dreaming** (requiere restart del gateway, o `/dreaming on` como owner desde el chat) — con `dreaming.model = gpt-5.4-mini`.
- [ ] ~~Fallback `claude-cli`~~ — ya no urge: Gemini flash cubre el fallback con tools.
- [x] **Instalar `acpx`** — hecho 2026-08-22, probado (lectura). Pendiente: subir a `approve-all` para que Claude escriba código (decisión).
- [x] **Gemini como fallback** — hecho por API key (`gemini-3.5-flash`). Pendiente: `acuarito`.
- [ ] `acuarito`: AGENTS.md base (1.8 KB en vez de 7.2 KB) + modelo mini. Ortogonal al lockdown, pero se avisa.
- [ ] `adondepo`: modelo mini + SOUL 8 KB → 3.6 KB + `PROCEDIMIENTO.md` (borrador en la auditoría).
- [ ] `cv`: construir `scripts/explorar-oferta.sh` + `postular-easy-apply.sh` en `rodrigo-career` (patrón explorador) y allowlist.
- [ ] Allowlist exec de `main` para `bin/handoff.sh` / `bin/notificar.sh`.
- [ ] SOUL.md genérico de `sofia` (plantilla 1.8 KB) → SOUL real; ¿propagar "WhatsApp Delivery" a los demás?
- [ ] Heartbeat: `agents.defaults.heartbeat.{isolatedSession:true, lightContext:true}` como guardarraíl barato.
- [ ] Medir el ahorro real tras el reset del 27-08: `openclaw status --usage`, tokens por evento subido / por postulación.

## Hecho 2026-08-22 (tarde, aprobado por Rodrigo)
- Lumen sin rol de arquitecto (TOOLS/IDENTITY recortados, skills retiradas); IDENTITY acotada a "agente general que reporta y delega".
- `tools.profile: messaging` (+`group:memory`) para claudio y sofia (antes `coding` global → ~6 KB de tools por llamada que no usaban).
- Heartbeats apagados globalmente (`agents.defaults.heartbeat.every=0m`); HEARTBEAT.md de sofia vaciado.
- Crons de sofia → `gpt-5.4-mini` explícito. Crons restantes: 6 (sofia 3, andres 2, claudio 1), sesiones aisladas.
- `sofia`: mentionPatterns solo `@Sofia/@sofia/@Sofía/@sofía`; SOUL/USER/IDENTITY reescritos y acotados a "relación de pareja" (17.7 KB → ver script).
- `corfo` retirado de `agents.list` y bindings (repo `~/projects/corfo-finder` intacto).
- Roster acordado: main · cv · sofia · adondepo · andres · claudio · acuarito · **branding** (unificar 3 perfiles sobre acuaria-branding) · **recordatorios** (nuevo, audios+cron) · **investigador** (nuevo) · dev = sesiones ACP enlazadas a grupos, sin agente propio.
- Siguiente: crear `recordatorios` con `openclaw-agent-build`; grupo dev enlazado a ACP; `branding`; `investigador`.

- [x] Principio "comunicarse con el proyecto, no vivir en él": cv y acuaria-branding con workspace propio; guardarraíl en el script. `feat/explorar-oferta` mergeado en rodrigo-career (`1837a25`, sin push) y allowlist de cv agregada; renombrar `acuaria-branding` → `branding` cuando se cree el grupo.
- [ ] `fleet/` (flota como código: export.sh, bootstrap.sh, verify.sh, CHECKLIST.md) — aprobado en principio, por arrancar.
