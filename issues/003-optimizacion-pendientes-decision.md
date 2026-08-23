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
- [x] `fleet/` hecho y probado en instancia aislada (verify 20/20 OK). Herramienta en este repo (`fleet/README.md`); la flota real en el repo PRIVADO `rodrvc/openclaw-fleet-rodrigo` (incluye `mapa-equipo.md`).

## Estado al 2026-08-23 (leer esto primero para seguir)

**Hecho:** flota 146 KB → 65 KB de arranque por llamada; modelos por tarea + fallback Gemini flash; workers mini;
heartbeats 0m; resets por inactividad; pruning; `acpx` instalado y probado ida y vuelta; Lumen sin rol de
arquitecto; sofia acotada; principio "agentes se comunican con los proyectos, no viven en ellos" aplicado a
todos (cv y acuaria-branding con workspace propio; repos limpios de archivos de agente); `corfo` retirado y
**`opportunity-finder` creado** (oportunidades para Acuaria Labs, lee el estado del repo bajo demanda, delega
a Claude); explorador de `cv` mergeado + allowlist; `fleet/` + repo privado de la flota.

**Regla operativa:** todo cambio en la instancia termina con `fleet/export.sh --out ~/projects/openclaw-fleet-rodrigo`
+ commit en ese repo, y `scripts/check-prompt-budget.sh` en verde. Crear agentes: skill `openclaw-agent-build`
(bloque "Reglas de la flota"). Verificar: `openclaw-agent-verify`.

**Siguiente, en orden (todos aprobados por Rodrigo en principio):**
1. `recordatorios` (audios + cron + memoria de tareas; Rodrigo crea el grupo de WhatsApp primero).
2. Grupo **dev** enlazado a ACP (`/acp spawn claude --bind here`) con un worktree real.
3. Unificar **branding** (renombrar `acuaria-branding` → `branding`, 3 perfiles) cuando exista su grupo.
4. `investigador` (trending tech, cron + explorador, flash/mini).
5. Decisiones aún abiertas: dreaming (restart), ACP `approve-all` para que Claude escriba código, `adondepo` a mini.
6. Medir el ahorro real tras el reset de Codex (27-08) con `openclaw status --usage`.
