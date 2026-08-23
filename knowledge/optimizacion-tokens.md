# Optimización de tokens de la flota OpenClaw — informe y guardarraíles (2026-08-22)

> **Alma del proyecto:** OpenClaw es el **mensajero/orquestador** (WhatsApp → gatilla procesos
> en la Mac → feedback corto). Los **agentes operativos son Claude** (Orca / ACP) en los repos
> de `~/projects`; el costo pesado cae en Claude, no en la cuota Codex. Criterio de arquitecto:
> modelo barato cuando no hay daño irreversible; modelo capaz cuando sí lo hay.
> Patrón completo: [`patron-workers-delegacion.md`](./patron-workers-delegacion.md).

**Contexto:** cuota Codex (único perfil OAuth `openai`, compartido por los 9 agentes) agotada
hasta el 27-08 08:00 GMT-4. Causa medida por el Claude anterior: ~11,8 M tokens de input en
1.016 llamadas; el contexto se reenvía completo en cada turno.

## 1. Qué cambió (medido antes → después)

### Peso de arranque por llamada (`scripts/check-prompt-budget.sh`)

| Agente | Antes (B) | Después (B) | Techo | Estado |
|---|---|---|---|---|
| main | 23.254 (*) | **12.122** | 12 KB | ✅ |
| sofia | 17.747 | 11.443 | 8 KB | ⚠️ SOUL.md genérico 1.8 KB + USER 2.9 KB (decisión) |
| andres | 19.755 | 8.850 | 8 KB | ⚠️ 658 B sobre (SOUL + MEMORY reales) |
| claudio | 14.155 | 7.618 | 6 KB | ⚠️ SOUL 2.5 KB + MEMORY 1.5 KB |
| adondepo | 18.213 | 11.709 | 12 KB | ✅ (SOUL 8 KB no tocado: side effects en prod) |
| acuarito | 14.404 | 14.404 | 9 KB | ⛔ no tocado (lockdown) — pendiente aplicar AGENTS base |
| cv | 17.347 | 17.347 | 12 KB | ⛔ vive en repo `rodrigo-career` (AGENTS.md del repo manda) |
| corfo | 8.643 | 8.643 | 6 KB | ⛔ workspace = repo `corfo-finder` |
| acuaria-branding | 6.714 | 6.714 | 6 KB | ⛔ workspace = repo `personal-brand` |
| **Flota** | **146.303** | **99.275** | | **−47 KB/llamada (−32 %)** |

(*) El prompt original contaba 29.325 B para `main` incluyendo `PROJECTS.md` (6.071 B), pero
**`PROJECTS.md` NO es archivo de bootstrap** (verificado: no aparece en `dist/` de OpenClaw;
los inyectados son AGENTS, SOUL, TOOLS, IDENTITY, USER, HEARTBEAT, BOOTSTRAP, MEMORY).

Qué se hizo (todo con respaldo `*.bak-20260822-optim` junto a cada archivo):
- **main:** AGENTS.md 8.376→2.797 (doctrina genérica fuera; **+ regla "Cuándo delegar a Claude"**),
  TOOLS.md 4.497→2.373 (índice; el cómo va a `orca skills get orca-cli`), MEMORY.md 4.949→2.238
  (duplicaba USER.md), SOUL.md plantilla genérica→**SOUL real de Lumen** 1.088 B (orquestador),
  PROJECTS.md 6.071→2.046 + `projects/index.md` 4.302 bajo demanda.
- **AGENTS.md compartido** (7.196 B idéntico en andres/claudio/adondepo/acuarito + variante sofia):
  base única de 1.805 B (`shared/AGENTS.base.md` en el scratch de auditoría; copia en los 3
  workspaces + sofia con su sección "WhatsApp Delivery"). OpenClaw **no tiene includes/herencia**
  de AGENTS.md (solo hook `agent:bootstrap` de plugins), así que es copia de plantilla.
- **andres:** MEMORY.md 7.127→2.727; el procedimiento estable → `study/ai-103/RUNBOOK.md` (4.453).
- **IDENTITY.md** sin rellenar (plantilla 1.278 B con placeholders) → identidad real de ~150 B
  en andres/claudio/adondepo.

### Modelo por tarea (`agents.list[].model`, aplicado en caliente, sin restart)

| Agente | Antes | Después | Criterio |
|---|---|---|---|
| claudio, corfo, acuaria-branding | gpt-5.5 | **gpt-5.4-mini** | notificación/saludo, sin side effects |
| sofia, andres | gpt-5.5 | **gpt-5.4** | conversación con humano, sin escrituras externas |
| main, cv, adondepo | gpt-5.5 | gpt-5.5 | orquestador / side effects irreversibles |
| acuarito | gpt-5.5 | gpt-5.5 | lockdown: no se toca sin aviso (comando listo abajo) |

Los crons de sofia/andres/claudio heredan el modelo del agente (`Model: -` en `cron list`).

### Workers baratos por defecto
`agents.defaults.subagents.model = openai/gpt-5.4-mini` y `runTimeoutSeconds = 900`: todo
`sessions_spawn` nace en mini salvo override explícito (`sessions_spawn.model`).

### Piezas nuevas en el workspace de `main`
- `skills/delegar-a-claude/SKILL.md` (3 KB, cuerpo bajo demanda): ACP vs Orca, handoff, espera
  con backoff, plantilla WhatsApp de 4 líneas.
- `bin/handoff.sh` (genera `/tmp/handoff-<slug>.md` ≤2000 B) · `bin/notificar.sh` (cierra el ciclo
  por WhatsApp con `openclaw agent --message-file --deliver`).

### `memory-engineer` (agente de Claude Code, `~/.claude/agents/memory-engineer.md`)
Reescrito (respaldo `.bak-20260822`): protocolo MEDIR→LEER→CLASIFICAR→ENTREGAR, formato de salida
obligatorio (tabla bytes + diff + delta), layout de memoria OpenClaw/Claude Code, `model: sonnet`.
Causa del boilerplate: sin obligación de medir, sin formato, sin vocabulario concreto.

## 2. Qué NO cambió y por qué (decisiones de Rodrigo)

| Pendiente | Por qué no se aplicó | Comando listo |
|---|---|---|
| **Dreaming** (frente 1) | Clave vive en `plugins.entries.*` → **requiere restart del gateway** (corta a los 9). Además: dreaming **no compacta** el contexto; promueve recalls a MEMORY.md y escribe DREAMS.md. Con `Recall store: 0 entries` no hay nada que promover todavía. Útil, no urgente. | `openclaw config set plugins.entries.memory-core.config.dreaming.enabled true` + `...dreaming.model openai/gpt-5.4-mini` + `...subagent.allowModelOverride true` → restart. O desde el chat como owner: `/dreaming on`. |
| **Fallback `claude-cli`** (para no quedar mudo al agotar Codex) | Consume la suscripción Claude de Rodrigo (otro bolsillo) y es texto sin tools. Decisión de costo. | `openclaw models auth login --provider anthropic --method cli` → `openclaw models fallbacks add claude-cli/claude-sonnet-5` → `openclaw config set agents.defaults.cliBackends.claude-cli.command ~/.local/bin/claude` (gateway bajo launchd, PATH mínimo). Probar: `openclaw agent --agent main -m hola --model claude-cli/claude-sonnet-5`. |
| **ACP (`acpx`)** — el camino oficial para que `main` lance Claude Code y el resultado vuelva al chat | Instalación + restart. Trampa: default `nonInteractivePermissions=fail` → escrituras revientan sin TTY. | ver `patron-workers-delegacion.md` §3.2 |
| `acuarito` AGENTS.md base + modelo | Regla 6 (lockdown). Cambios son ortogonales a la seguridad pero se avisan. | `cp <base> ~/.openclaw/agents/acuarito/workspace/AGENTS.md`; `openclaw config set 'agents.list[5].model' openai/gpt-5.4-mini` |
| `adondepo` → gpt-5.4-mini y SOUL 8 KB → SOUL 3.6 KB + `PROCEDIMIENTO.md` | Escribe a prod (regla 7). Borrador listo en la auditoría. | — |
| `cv`, `corfo`, `acuaria-branding` | Workspaces = repos; el AGENTS.md del repo es ley. `cv` (10.7 KB): candidato "Plataformas y acceso" → archivo aparte. | — |
| SOUL.md genérico en sofia (1.8 KB) / USER 2.9 KB | Personalidad del agente de relación: decisión humana. | — |
| Techo 4 KB para notificación | Irreal: AGENTS base+IDENTITY+TOOLS+HEARTBEAT ≈ 3 KB antes de una línea de SOUL. Techo ajustado a **6 KB** (acuarito 9 KB por SOUL de seguridad). | — |
| Allowlist exec para `main` (`bin/handoff.sh`, `bin/notificar.sh`) | Ampliar allowlist es decisión de seguridad. | `openclaw approvals allowlist add --agent main ~/.openclaw/workspace/bin/handoff.sh` |

## 3. Guardarraíles

- `scripts/check-prompt-budget.sh` — falla (exit 1) si un agente supera su techo; `--json` para
  automatizar. Correr tras tocar cualquier `.md` de workspace o crear un agente.
- Regla escrita en `~/.openclaw/workspace/AGENTS.md` → "Cuándo delegar a Claude".
- Skill `delegar-a-claude` + `bin/handoff.sh` (límite duro 2000 B) + plantilla WhatsApp 4 líneas.
- `agents.defaults.subagents.model = gpt-5.4-mini` (workers baratos por defecto) + timeout 900 s.
- Matriz de enrutamiento tarea → ejecutor → modelo en `patron-workers-delegacion.md` §1.

## 4. Datos del contexto original que resultaron desactualizados o incorrectos

- `PROJECTS.md` no es bootstrap (ver arriba): `main` pesaba 23.254 B, no 29.325.
- Heartbeat: **no** es el gran consumidor hoy (5 turnos reales en transcripts de `main`; 0 en el
  resto). Solo sofia (1 tarea) y cv (3) tienen HEARTBEAT.md activo.
- `corfo` y `acuaria-branding` sí tienen .md de arranque, pero en sus repos (`~/projects/...`),
  no en `~/.openclaw/agents/<id>/workspace`.
- `openclaw agents list` muestra 7 agentes en la salida truncada; la config tiene 9.
- Errores `error (4x)` en crons de sofia/andres = `FailoverError: Codex usage limit` (cuota), no bug.

## 5. Más allá de lo pedido (lo que el plan no veía)

1. **Un solo perfil OAuth para toda la flota**: `main` (19 MB de contexto) puede dejar mudos a los 8
   restantes. Mitigación real: fallback `claude-cli` + empujar trabajo a scripts sin LLM.
2. **ACP es el mecanismo oficial** de "OpenClaw mensajero → Claude operativo" (`sessions_spawn
   runtime:"acp"`, `/acp spawn claude --bind here`), con entrega automática del resultado al chat.
   Es la pieza que hace realidad el alma del proyecto; requiere instalar `acpx` (restart).
3. Sesiones de `cv` con mediana 631 KB y máximo 2 MB: es el síntoma exacto de "página entera en
   el contexto". El explorador (`explorar-oferta.sh` + worker mini) lo baja 2 órdenes de magnitud.
4. `sofia` tenía una regla "WhatsApp Delivery" (`message(action="send")`) que los demás no tienen:
   probable fix de entrega del runtime Codex; conservado en sofia, vale revisar si aplica a todos.
5. Opciones de contexto no usadas: `agents.defaults.contextPruning` (cache-ttl) y
   `agents.defaults.compaction.{model, keepRecentTokens}` — compactación con modelo barato.

## 6. Actualización 2026-08-22 (tarde): acpx instalado, Gemini como fallback

- **`acpx` instalado y probado**: `acp.enabled=true`, `backend=acpx`, `allowedAgents=["claude"]`,
  `permissionMode=approve-reads`, `nonInteractivePermissions=deny`. Claude Code vía
  `sessions_spawn({runtime:"acp", agentId:"claude", model:"sonnet", thinking:"low", cwd})` terminó
  una tarea de lectura en 45 s (`status: done`).
  Trampas encontradas: (a) sin `model` explícito el spawn hereda `agents.defaults.subagents.model`
  (`gpt-5.4-mini`) → "issue with the selected model"; (b) `thinking:"off"` → Claude rechaza
  `effort: off`; (c) un `/model` pinneado por usuario en `agent:main:main` es estricto y rompe el
  announce de vuelta (se limpió; respaldo `sessions.json.bak-20260822-override`).
- **Gemini**: el camino Gemini CLI OAuth está **muerto para cuentas personales**
  (`IneligibleTierError … migrate to Antigravity`). Se usó **API key** (`openclaw models auth
  paste-api-key --provider google`, perfil `google:manual`). `google/gemini-3.5-flash` quedó como
  `fallbacks` de los 9 agentes menos `acuarito` (primario sigue `openai/*`). Failover real probado
  con `claudio`. `gemini-3.1-pro-preview` **fuera**: 429 sin cuota en el plan gratis y enfría al
  proveedor entero. `agents.defaults.models` es allowlist: todo modelo usado debe estar declarado.
- `agents.defaults.subagents.thinking=low` (evita `effort: off` en spawns).
- **Ida y vuelta confirmada** (Codex activo): hijo ACP `done` en 27-65 s, announce recibido por `main`, respuesta en formato WhatsApp de 4 líneas ("Resultado: 234" archivos .ts).

## Fuentes
Doc local `/opt/homebrew/lib/node_modules/openclaw/docs/` (`concepts/dreaming.md`, `cli/memory.md`,
`tools/subagents.md`, `tools/acp-agents.md`, `gateway/cli-backends.md`, `gateway/heartbeat.md`,
`providers/anthropic.md`, `cli/config.md`); `openclaw models list/status`, `openclaw cron list`,
`openclaw memory status --agent <id>`; mediciones con `wc -c` sobre los workspaces el 2026-08-22.

## 7. Patrón "contexto mínimo" por tipo de agente (2026-08-22, aprobado por Rodrigo)

**Principio:** un agente arranca con lo mínimo para *saber quién es y dónde buscar*; todo lo que
es procedimiento se lee bajo demanda; la memoria solo existe donde hay algo que recordar.

| Tipo | Agentes | Arranque (lo que se paga por llamada) | Bajo demanda | Memoria | Sesión |
|---|---|---|---|---|---|
| **Procedural** (le pides cosas, no recuerda) | adondepo, claudio, acuarito, acuaria-branding, futuros recordatorios/investigador/branding | SOUL ≤1.5-3.5 KB (identidad + reglas duras) · AGENTS base 1.8 KB · IDENTITY ~150 B · TOOLS 876 B | `PROCEDIMIENTO.md` / skills (solo nombre+descripción en el prompt) / scripts sin LLM | **ninguna** (sin MEMORY.md, sin `group:memory` salvo que la use) | reset por inactividad (DM 4 h, grupo 2 h) + diario 04:00 |
| **Con memoria** (acumula sobre una persona/tema) | sofia (pareja), andres (progreso), main (poco) | igual + MEMORY.md ≤2.5 KB (hechos centrales + punteros) | `people/*.md`, `study/*`, `projects/index.md` | `memory/` diario + promoción manual/dreaming | igual |
| **Agéntico en repo** | cv | el AGENTS.md del repo manda | skills del repo | la del repo | igual; las páginas nunca entran al contexto (explorador) |

Controles de la *sesión* (donde se acumulaba el gasto real):
- `session.reset`: diario 04:00 + `resetByType` direct **idle 240 min**, group **idle 120 min**
  (heartbeat/cron no mantienen viva la sesión). Antes: solo diario → sesiones de 2 MB en `cv`.
- `agents.defaults.contextPruning: {mode:"cache-ttl", ttl:"5m"}`: recorta resultados viejos de
  tools (exec, lecturas, búsquedas) antes de cada llamada; conversación intacta; últimos 3 turnos
  protegidos.
- `agents.defaults.heartbeat.every: "0m"`; crons en sesión aislada y modelo mini.
- Tools por perfil: `messaging` (+`group:memory`) para los que no ejecutan nada.

Aplicado hoy además: `adondepo` SOUL 8.1 → 3.6 KB + `PROCEDIMIENTO.md` (formato de cola y
reporte bajo demanda); `acuarito` AGENTS base + IDENTITY real (su SOUL de seguridad intacto).
Flota: **146 KB → 72 KB por llamada** en el día.

## 8. Principio de flota: los agentes se comunican con los proyectos, no viven en ellos (2026-08-22)

Regla de Rodrigo, obligatoria para todos los agentes: **workspace propio bajo
`~/.openclaw/agents/<id>/workspace`; el repo es un parámetro** (`PROJECT.md` con ruta, qué se
delega y qué scripts están en allowlist). El trabajo dentro del repo lo hace Claude (ACP/Orca,
`cwd` = repo, obedeciendo el AGENTS.md/CLAUDE.md del repo) o un script; el agente pide, espera y
reporta en ≤4 líneas. Ventajas: portabilidad (la flota no depende de rutas ni usuario), prompts
chicos, y las reglas del repo viven una sola vez (donde las lee Claude).

Aplicado hoy: `cv` (antes workspace = `~/projects/rodrigo-career`, 17.3 KB) → workspace propio
**5.1 KB** con SOUL de "mensajero de carrera", `PROJECT.md`, MEMORY de 378 B; ya no tiene `browser`
(solo `exec` para `explorar-oferta.sh`). `acuaria-branding` (antes `~/projects/personal-brand`) →
workspace propio **3.6 KB**, descrito ya como agente de branding con 3 perfiles. Sección "Proyectos:
te comunicas con ellos, no vives en ellos" agregada a la base AGENTS.md de todos.
Guardarraíl: `scripts/check-prompt-budget.sh` ahora **falla** si un workspace está fuera de
`~/.openclaw/`. Flota: **146 KB → 59 KB por llamada** en el día (−60 %).
