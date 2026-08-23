# Patrón: mover el trabajo caro fuera de los agentes OpenClaw (workers + delegación a Claude)

> **Alma del proyecto:** OpenClaw es el *mensajero* (recibe por WhatsApp, gatilla procesos en la Mac, devuelve feedback corto). Los agentes *operativos* son Claude (Orca / ACP) sobre los repos de `~/projects`. El costo pesado cae en Claude; el criterio de arquitecto decide cuándo basta un modelo barato.

**Fuentes:** doc local `/opt/homebrew/lib/node_modules/openclaw/docs/{tools/acp-agents.md,tools/subagents.md,gateway/cli-backends.md,providers/anthropic.md,concepts/session-tool.md}`, `openclaw.json` (leído 2026-08-22), `orca --help`, `openclaw agent --help`.

**Fecha:** 2026-08-22 · **Autor:** arquitecto de agentes (repo `~/orca/workspaces/openclaw/main`)
**Estado 2026-08-22:** aplicado ya → modelos por tarea (frente 2: sofia/andres→gpt-5.4; claudio/corfo/acuaria-branding→gpt-5.4-mini), `agents.defaults.subagents.model=openai/gpt-5.4-mini`, `runTimeoutSeconds=900`, skill `delegar-a-claude` + `bin/handoff.sh` + `bin/notificar.sh` en el workspace de `main`. Pendiente con OK de Rodrigo: instalar `acpx` (restart), fallback `claude-cli`, scripts de `cv`, modelo de `adondepo`/`acuarito`.

## 0. Estado verificado (no asumido)

| Hecho | Cómo se verificó |
|---|---|
| 9 agentes; al inicio todos `openai/gpt-5.5` (hoy ya repartidos por tarea, ver estado arriba) | `openclaw.json` → `agents.list[]` |
| Modelos ya declarados: `gpt-5.5`, `gpt-5.4`, `gpt-5.4-mini`, `codex-auto-review` | `agents.defaults.models` |
| `tools.profile: "coding"` global → **`sessions_spawn` YA está disponible** | `openclaw.json` + `docs/concepts/session-tool.md` |
| `tools.sessions.visibility: "all"` | `openclaw.json` |
| Exec allowlist tiene **1 sola entrada**: `adondepo → subir-eventos.sh` | `openclaw approvals get` |
| `main` y `cv` tienen `tools.alsoAllow: ["browser","exec"]` | `openclaw.json` |
| `acuarito` está en lockdown real (sandbox docker `network:none`, deny masivo incl. `sessions_spawn`) | `openclaw.json` |
| **`acpx` NO está instalado** (`plugins.entries` = openai, codex, whatsapp, firecrawl, browser; `acp: null`) | `openclaw plugins list` + config |
| `claude -p` existe con `--model`, `--output-format json`, `--permission-mode`, `--add-dir` | `claude --help` |
| Orca vivo, runtime ready, app v1.4.180 | `orca status --json` |
| `orca worktree create` **exige `--name`**; con `--agent --json` devuelve `result.agentTerminalHandle` | `orca worktree create --help` |
| `orca terminal read` soporta `--cursor`/`--limit` (lectura incremental) | `orca terminal read --help` |
| `openclaw agent` acepta `--agent`, `--model`, `--deliver`, `--reply-to`, `--reply-channel`, `--message-file`, `--timeout` | `openclaw agent --help` |

**Consecuencia de diseño #1:** el camino más barato ya está habilitado (`sessions_spawn` con `model` por hijo). No hay que instalar nada para empezar.

---

## 1. Matriz de decisión de enrutamiento

Cinco ejecutores. La regla es **bajar de fila solo cuando la de arriba no alcanza**.

| # | Ejecutor | Cómo se invoca | Modelo | Cuándo |
|---|---|---|---|---|
| **a** | El propio agente responde | (nada) | `gpt-5.4-mini` para saludo/ack/notificación · `gpt-5.4` conversación normal · `gpt-5.5` solo si hay riesgo irreversible | Respuesta ≤5 líneas sin herramientas, o confirmar/negar algo que ya sabe |
| **b** | Worker efímero OpenClaw | `sessions_spawn({model:"openai/gpt-5.4-mini", context:"isolated"})` | `gpt-5.4-mini` | Extraer/clasificar/resumir texto que **no debe entrar al contexto del padre** |
| **c** | Script determinista | `exec` de un script en allowlist | **sin LLM** | El resultado es reproducible: navegar, scrapear, hacer HTTP, mover archivos, contar |
| **d** | Claude vía ACP | `sessions_spawn({runtime:"acp", agentId:"claude", cwd:"<repo>"})` | `sonnet` (default) / `opus` (excepción) | Tarea **acotada** sobre un repo, con resultado que vuelve al chat. Requiere instalar `acpx` |
| **e** | Claude en Orca | `orca worktree create --agent claude` / `orca terminal create` | `sonnet` / `opus` | Sesión **larga** que Rodrigo supervisa en pantalla, o que él va a continuar a mano |

### Matriz tarea → ejecutor

| Tarea | Ejecutor | Modelo | Por qué |
|---|---|---|---|
| "hola", "gracias", ack de recepción | **a** | `gpt-5.4-mini` | Cero herramientas. Hoy quema `gpt-5.5` sin razón |
| "¿en qué quedó X?" (lee memoria/archivo) | **a** | `gpt-5.4` | Lectura corta, sin riesgo |
| Validar URL de Instagram + encolar | **a** | `gpt-5.4-mini` | Regex + escribir JSON. `adondepo` no necesita 5.5 para esto |
| Scrapear post de Instagram y subir a prod | **c** | sin LLM | **Ya existe** (`subir-eventos.sh`). Patrón de referencia |
| Leer una oferta de LinkedIn y decidir fit | **b** | `gpt-5.4-mini` | La página nunca entra al contexto de `cv`; sale JSON de ~400 bytes |
| Postular en LinkedIn (llenar modales) | **c** | sin LLM | El DOM está documentado; es un script, no razonamiento |
| Escribir carta de presentación personalizada | **b** | `gpt-5.4` | Texto corto, criterio bajo, no toca disco |
| "arregla el bug de fecha en city-activities-api" | **d** | `sonnet` | Código + tests, acotado, resultado al chat |
| "refactoriza el clasificador" / diseño arquitectónico | **e** | `opus` | Largo, iterativo, Rodrigo quiere ver la pantalla |
| Borrar eventos de prod / tocar `openclaw.json` / restart gateway | **a** + confirmación humana | `gpt-5.5` | **Daño irreversible → modelo capaz + OK explícito.** Nunca se delega a ciegas |
| Resumir 40 mensajes del grupo | **b** | `gpt-5.4-mini` | Trabajo de tijera |

### Regla de oro (una línea)

> Si el output cabe en 3 líneas y el input es grande → **worker**. Si el input y el output son chicos → **el agente**. Si es reproducible → **script**. Si toca código → **Claude**.

---

## 2. Patrón "explorador" (worker efímero que no contamina el contexto)

### El problema real

Hoy `cv` mete páginas enteras de LinkedIn a su contexto. Cada oferta son ~15-40k tokens de `gpt-5.5`. Un lote de 10 ofertas ≈ 300k tokens del plan Codex, para tomar 10 decisiones de 20 bytes cada una.

### Contrato

**Entrada** (lo que el agente le pasa al worker): ≤ 500 bytes. Una URL o un identificador + qué extraer. Nunca contenido.

**Salida** (lo que el worker devuelve al agente): **JSON, ≤ 800 bytes, campos fijos**. Si no cabe, se trunca y se marca `"truncated": true`. La regla dura: *el worker devuelve conclusiones, no evidencia*.

### Cuál de los tres mecanismos usar

Hay tres formas de sacar el trabajo, y **no son intercambiables**:

| Mecanismo | Cuándo | Contexto del padre |
|---|---|---|
| `exec` de script | El resultado es determinista | Solo entra el stdout del script (controlado por el script) |
| `sessions_spawn` mini | Hace falta criterio sobre texto largo | **Nada** — sesión aislada; solo llega el announce |
| Cola maildir | Fire-and-forget, tarda >2 min, o debe sobrevivir al reinicio del gateway | Solo el ack |

**Decisión: para el explorador se usa `exec` de un script que hace el navegar, y `sessions_spawn` mini solo si hace falta juicio sobre el texto.** La razón: el navegador es determinista, el criterio no. Separarlos evita pagar un LLM por hacer clicks.

### 2.1 Ejemplo concreto — cv / LinkedIn

**Script nuevo:** `~/projects/rodrigo-career/scripts/explorar-oferta.sh` (~60 líneas)

```bash
#!/bin/bash
# Uso: explorar-oferta.sh <url-linkedin>
# Imprime UN objeto JSON de <=800 bytes. Nunca imprime la pagina.
set -euo pipefail
URL="$1"
PAGE=$(orca tab create --url "$URL" --json | jq -r '.result.browserPageId')
trap 'orca tab close --page "$PAGE" --json >/dev/null 2>&1 || true' EXIT
orca eval --page "$PAGE" --json --expression '...extrae titulo/empresa/modalidad/idioma/salario...' \
  | jq -c '{url:$u, titulo, empresa, modalidad, idioma, salario, easy_apply, extracto: (.desc[0:600])}' --arg u "$URL"
```

- Usa el **browser de Orca** (`--page` siempre), como ya manda el `AGENTS.md` de `rodrigo-career`. No `agent-browser` (puertos 9222/9333 en conflicto).
- Cierra **solo su pestaña** (trap EXIT) — regla ya escrita en ese repo.
- El `extracto` de 600 chars es lo único de la página que puede viajar; el resto queda en el navegador.

**Y el juicio:** el agente `cv` pasa ese JSON de 800 bytes a un worker mini:

```
sessions_spawn({
  label: "fit-oferta",
  model: "openai/gpt-5.4-mini",
  context: "isolated",
  prompt: "Decide fit segun 04-TEMPLATES-Y-CRITERIOS.md. Devuelve SOLO:
           {\"fit\":\"si|no\",\"motivo\":\"<=80 chars\",\"cv\":\"ES|EN\"}\n<json>"
})
```

**Ahorro:** 40k tokens de `gpt-5.5` → 800 bytes de `gpt-5.4-mini`. Dos órdenes de magnitud.

### 2.2 Ejemplo concreto — adondepo / Instagram

**Ya está resuelto y es el patrón de referencia.** No tocar. Lo que hace bien:

- El agente solo escribe `queue/inbox/<ts>-<shortcode>.json` (escritura atómica `.tmp` → `mv`).
- El ejecutor (`process_event_queue.py`, fuera del agente) hace Chrome + scraping + verificación contra prod.
- El wrapper devuelve un bloque **ya redactado** entre `---8<---` / `--->8---` que el agente pega **literal**.

**La lección transportable:** el ejecutor no devuelve datos crudos, devuelve *el mensaje ya escrito*. La función `motivo_simple()` traduce `og:url`/`Chrome`/`timeout` a lenguaje humano **en Python, gratis**, en vez de pagarle a un LLM por redactar. Eso es mover trabajo caro fuera del agente sin usar otro LLM.

**Único cambio propuesto:** bajar `adondepo` a `gpt-5.4-mini`. Su SOUL.md ya es determinista (valida regex, encola, ejecuta 1 comando, pega bloque literal). No necesita 5.5.

---

## 3. Patrón "delegar a Claude"

Hay **dos caminos oficiales** y se eligen por criterio distinto.

### 3.1 Comparación

| | **ACP** (`sessions_spawn runtime:"acp"`) | **Orca** (`orca terminal/worktree`) |
|---|---|---|
| Estado | ⚠️ requiere instalar `acpx` | ✅ funciona hoy |
| Resultado vuelve | **solo** — announce al chat de origen | hay que hacer polling con `terminal read --cursor` |
| Visible para Rodrigo | no (background task) | **sí**, en su pantalla |
| Controles | `/acp model`, `/acp steer`, `/acp cancel`, `/acp timeout` | `terminal send --interrupt` |
| Puede continuar a mano | no | **sí** — Rodrigo se sienta y sigue |
| Aislamiento git | `cwd` (worktree activo) | `worktree create` = checkout separado |

**Regla:** **ACP para tarea acotada con resultado al chat. Orca para sesión larga que Rodrigo supervisa.**

Y un tercer camino que **no es delegación** pero se confunde: `claude-cli/<model>` como *fallback de modelo* — ver §6.

### 3.2 Camino A — ACP (recomendado, requiere instalación)

Instalación (3 comandos + restart, **necesita OK de Rodrigo**, el restart corta a los 9 agentes):

```bash
openclaw plugins install @openclaw/acpx
openclaw config set plugins.entries.acpx.enabled true
openclaw config set acp.enabled true
openclaw config set acp.backend acpx
openclaw config set acp.allowedAgents '["claude"]'   # solo claude, no los 13 harness
openclaw config set plugins.entries.acpx.config.permissionMode approve-reads
openclaw config set plugins.entries.acpx.config.nonInteractivePermissions deny
```

⚠️ **Trampa documentada:** el default es `permissionMode=approve-reads` + `nonInteractivePermissions=fail`. En ACP no hay TTY, así que **cualquier escritura revienta con `PermissionPromptUnavailableError`**. Para que un Claude ACP pueda escribir código hay que subir a `approve-all` — que es el break-glass del harness. Recomendación: empezar en `approve-reads` + `deny` (degrada en vez de crashear) y usarlo primero para **tareas de lectura/diagnóstico**. Subir a `approve-all` solo tras probarlo, y nunca con `acuarito` en el árbol.

Uso desde el agente `main`:

```
sessions_spawn({
  runtime: "acp",
  agentId: "claude",
  cwd: "~/projects/city-activities-api",
  label: "fix-fecha",
  prompt: "<handoff, ver 3.4>"
})
```

Desde WhatsApp Rodrigo también puede: `/acp spawn claude --bind here`, luego `/acp status`, `/acp steer ...`, `/acp close`.

### 3.3 Camino B — Orca (funciona hoy)

Protocolo paso a paso para el agente `main`:

```bash
# 1. Confirmar runtime
orca status --json | jq -e '.result.runtime.reachable'

# 2. Worktree aislado (--name es OBLIGATORIO)
H=$(orca worktree create --name "fix-fecha-$(date +%s)" \
      --repo path:~/projects/city-activities-api \
      --agent claude --no-parent --json \
    | jq -r '.result.agentTerminalHandle // .result.startupTerminal.handle')

# 3. Esperar a que el TUI esté listo (si no, el texto se pierde a medias)
orca terminal wait --terminal "$H" --for tui-idle --timeout-ms 60000 --json

# 4. Mandar el handoff APUNTANDO A UN ARCHIVO, no pegando texto
orca terminal send --terminal "$H" \
  --text "Lee /tmp/handoff-fix-fecha.md y ejecutalo. Al terminar escribe /tmp/result-fix-fecha.json" \
  --enter --json

# 5. Poll con backoff: 30s, 60s, 120s, 120s... (NO cada 5s: eso es costo oculto)
#    Condicion de termino = EXISTE el archivo de resultado. No parsear el TUI.
```

**Trampas ya conocidas (memoria `orquestar-orca-desde-agentes`):** `send` sin `--enter` solo escribe; `split` devuelve el handle en `result.split`; dos agentes en el mismo worktree se pisan.

### 3.4 Formato del handoff (≤ 2000 bytes, en archivo)

El agente escribe `/tmp/handoff-<slug>.md`. **Nunca se pega el contexto en el prompt** — regla que ya está en `TOOLS.md` de `main`.

```markdown
# Tarea: <una línea>
REPO: ~/projects/<repo>
PEDIDO POR: Rodrigo, WhatsApp, <fecha>
## Contexto (3 bullets máx)
- <síntoma observable, no diagnóstico>
## Hecho (criterio de terminado)
- [ ] <verificable: test pasa / endpoint devuelve X>
## Límites
- NO tocar prod. NO commitear a main. NO `openclaw config`.
- Si necesitas una decisión de producto, PARA y escribe `needs_input`.
## Salida obligatoria
Escribe /tmp/result-<slug>.json:
{"status":"done|failed|needs_input","resumen":"<=200 chars",
 "archivos":["..."],"siguiente":"<=100 chars","branch":"..."}
```

Las reglas del repo (AGENTS.md/CLAUDE.md, skills) **no se copian** — Claude las lee solo al abrir ahí. Copiarlas causa el drift documentado en `depurar-agente-openclaw`.

### 3.5 Vuelta del resultado

**Camino A (ACP):** automático. El announce llega al chat de origen. Nada que construir.

**Camino B (Orca):** el que gana es **que el worker se anuncie solo**, no que el agente haga polling. Última línea del handoff:

```bash
openclaw agent --agent main --session-key agent:main:main \
  --message-file /tmp/result-<slug>.json --deliver
```

Verificado que ese comando funciona (memoria `main-arquitecto-openclaw`: 6 llamadas sin fallos). **Sin `--deliver` no manda nada a WhatsApp** — sirve para probar. Con `--deliver` sale por el binding de `main` (`channel:whatsapp, accountId:default`).

Así el polling pasa a ser **red de seguridad**, no el mecanismo: `main` chequea una vez a los N minutos, no cada 30s.

### 3.6 Timeout y fallo

| Situación | Acción |
|---|---|
| >20 min sin `result.json` | 1 recordatorio vía `terminal send`. Nada más |
| >40 min | Reportar "sigue trabajando, terminal `<handle>`" y **soltar el poll** |
| `status: failed` | Reportar el resumen tal cual. **No relanzar automáticamente** (regla ya probada en adondepo: reintento ciego duplica trabajo) |
| `status: needs_input` | Preguntarle a Rodrigo por WhatsApp, y `terminal send` con la respuesta |
| Orca caído (`status` no ok) | "No puedo abrir el editor ahora" — **no** intentar `claude` suelto por `exec` |

### 3.7 Regla escrita para pegar en `AGENTS.md` de `main` (574 bytes)

```markdown
## Cuándo delegar a Claude (no lo hagas tú)

Delega si se cumple UNA:
- Toca código de un repo de ~/projects (leer, arreglar, escribir, tests).
- Necesitas leer >3 archivos para responder.
- La tarea dura >5 min o requiere iterar.
- Pide diseño, refactor o revisión.

NO delegues (hazlo tú, corto):
- Responder qué/dónde/en qué quedó algo que ya sabes.
- Encolar, disparar un script de la allowlist, reportar su salida.
- Cualquier cosa destructiva → pide OK a Rodrigo primero.

Cómo: tarea acotada → ACP (resultado llega al chat).
Sesión larga que Rodri mira → Orca worktree.
Handoff SIEMPRE en archivo (≤2000 bytes), nunca pegado.
Modelo: sonnet. Opus solo si Rodrigo lo pide.
```

---

## 4. Feedback conciso por WhatsApp

El mensajero **no repite el razonamiento del worker**. Traduce.

### Plantilla (4 líneas máx)

```
<emoji-estado> <qué pasó, 1 línea>
<resultado concreto, 1-2 líneas>
→ <siguiente paso o "nada que hacer">
<ruta/link si aplica>
```

Estados: ✅ listo · ⚠️ hecho con reparos · ❌ falló · ⏳ en curso · ❓ necesito que decidas

**Ejemplos:**

```
✅ Arreglado el bug de fecha en city-activities-api
Los eventos sin hora ya no se guardan como 00:00 UTC. 3 tests nuevos, pasan.
→ Falta que revises el PR antes de mergear
rama: fix/fecha-utc-1755
```

```
❓ La oferta de Globant pide pretensión en USD
No sé si aplicar los 3.500 o subir a 4.500 (el rol es lead).
→ Dime cuál y sigo con el resto del lote
```

### Reglas duras

1. **Nunca** pegar el JSON del worker ni el stdout del script (excepción: bloques ya redactados para pegar literal, como el de adondepo).
2. **Nunca** rutas internas, nombres de endpoints ni API keys en grupos con terceros (terceros). En el DM de Rodrigo la ruta sí sirve.
3. **Siempre** cerrar el ciclo, incluso con "revisé y no había nada" — el silencio se lee como olvido (regla ya en el SOUL de adondepo, funcionó).
4. WhatsApp: sin tablas markdown, sin headers. Bullets y **negrita**.

---

## 5. Qué falta construir / qué se reutiliza

### Ya existe y se reutiliza (no tocar)

| Qué | Dónde |
|---|---|
| Cola maildir + audit + estados por carpeta | `~/.openclaw/agents/adondepo/workspace/queue/` |
| Ejecutor con preflight y verificación | `city-activities-api/scraper/process_event_queue.py` |
| Wrapper + traductor a lenguaje humano | `scraper/subir-eventos.sh` (`motivo_simple()`) |
| Reglas de browser Orca (`--page`, cerrar solo lo propio) | `rodrigo-career/AGENTS.md` + `TOOLS.md` |
| Reglas de orquestación Orca + trampas | `~/.openclaw/workspace/TOOLS.md` §Orca |
| Skill de arquitecto | `~/.openclaw/workspace/skills/openclaw-architect/` |
| `sessions_spawn` habilitado | `tools.profile:"coding"` (ya activo) |

### Por construir

| # | Ruta | ~Líneas | Qué hace |
|---|---|---|---|
| 1 | `~/projects/rodrigo-career/scripts/explorar-oferta.sh` | 60 | Abre oferta en Orca, extrae 8 campos, cierra su pestaña, imprime JSON ≤800B |
| 2 | `~/projects/rodrigo-career/scripts/postular-easy-apply.sh` | 120 | Recorre modales con las trampas ya documentadas (`-numeric`, `dispatchEvent`) |
| 3 | `~/.openclaw/workspace/skills/delegar-a-claude/SKILL.md` | 80 | Protocolo §3: elegir ACP vs Orca, escribir handoff, esperar, reportar |
| 4 | `~/.openclaw/workspace/bin/handoff.sh` | 40 | Escribe `/tmp/handoff-<slug>.md` desde argumentos (evita que el LLM improvise el formato) |
| 5 | Bloque §3.7 en `~/.openclaw/workspace/AGENTS.md` | 15 | Regla escrita de cuándo delegar |
| 6 | `~/.openclaw/workspace/bin/notificar.sh` | 25 | `openclaw agent --agent <x> --message-file <f> --deliver` con validación de tamaño |
| 7 | Ajustes de modelo en `openclaw.json` | — | ✅ hecho (sofia/andres→`gpt-5.4`; claudio/corfo/acuaria-branding→`gpt-5.4-mini`). Pendiente decisión: `adondepo`→`gpt-5.4-mini` (tiene side effects en prod; regla: confirmar con Rodrigo) |

**Orden sugerido:** 7 (gratis, ahorro inmediato) → 1 (mayor ahorro por unidad) → 5+3+4 (delegación) → 6 → 2.

### Allowlist a agregar (con OK de Rodrigo)

```bash
openclaw approvals allowlist add --agent cv "~/projects/rodrigo-career/scripts/explorar-oferta.sh"
openclaw approvals allowlist add --agent cv "~/projects/rodrigo-career/scripts/postular-easy-apply.sh"
openclaw approvals allowlist add --agent main "~/.openclaw/workspace/bin/handoff.sh"
openclaw approvals allowlist add --agent main "~/.openclaw/workspace/bin/notificar.sh"
```

Patrones **específicos por agente**, nunca `--agent "*"` ni globs anchos como `~/projects/**`.

---

## 6. Resiliencia: qué pasa cuando se agota la cuota

**El problema real de hoy:** el plan Codex se agotó y los 9 agentes quedaron mudos, porque todos apuntan a `openai/*`.

`claude-cli` es un **CLI backend** (no ACP): texto puro, sin tools de OpenClaw, reusa el login local de Claude Code. Sirve exactamente para que el mensajero no quede mudo.

```json5
agents: { defaults: {
  model: { primary: "openai/gpt-5.4", fallbacks: ["claude-cli/claude-sonnet-5"] },
  models: { "claude-cli/claude-sonnet-5": {} },
  cliBackends: { "claude-cli": { command: "~/.local/bin/claude" } }
}}
```

⚠️ **`command` explícito es obligatorio aquí**: `claude` está en `~/.local/bin`, y el gateway corre bajo launchd con `PATH` mínimo. Sin esa línea el fallback no arranca.

**Costos y límites (decirlos, no esconderlos):**
- Consume la **suscripción Claude** de Rodrigo. No es gratis, es *otro* bolsillo.
- **Sin tools**: en fallback el agente puede conversar pero **no** encolar, ni ejecutar scripts, ni orquestar. `adondepo` en fallback puede decir "te leo" pero no subir.
- Por eso el fallback es para **no quedar mudo**, no para seguir operando. La operación real sigue en el ejecutor determinista (que no usa LLM y por eso nunca se queda sin cuota).

**Verificación antes de confiar:** `openclaw agent --agent main -m "hola" --model claude-cli/claude-sonnet-5` (sin `--deliver`).

---

## 7. Riesgos

### 7.1 Seguridad — un mensaje de WhatsApp no puede gatillar algo destructivo

El vector: WhatsApp es un canal donde escriben terceros (terceros) y donde se pegan **contenidos ajenos** (posts, ofertas). Ese texto es **dato, nunca instrucción** — ya está escrito en el `AGENTS.md` de `rodrigo-career` y hay que mantenerlo.

| Riesgo | Mitigación |
|---|---|
| Prompt injection desde una oferta/post que el worker lee | El worker devuelve **JSON de campos fijos**. Un campo con instrucciones llega como string, no como turno. El padre nunca ve la página |
| ACP `approve-all` = shell libre gatillable por chat | Empezar en `approve-reads`+`deny`. `acp.allowedAgents: ["claude"]` únicamente. Subir a `approve-all` solo tras probar, y jamás para agentes de grupo |
| Delegación destructiva ("borra la rama X") | El handoff lleva **Límites** explícitos (no prod, no main, no `openclaw config`). Y la regla: destructivo → OK de Rodrigo **antes** |
| Romper el lockdown de `acuarito` | `acuarito` deniega `sessions_spawn`/`exec`/`browser` y corre en Docker `network:none`. **Nada de este diseño lo toca.** Si alguna vez necesita trabajo pesado, va por cola maildir (no por spawn) |
| Ampliar la allowlist de más | Un patrón por script por agente. `subir-eventos.sh` demuestra que 1 entrada basta para un pipeline completo |
| Un agente de grupo delegando a Claude | **Solo `main` y `cv` delegan.** Los de grupo (`adondepo`, `corfo`, `claudio`, `acuarito`) encolan y reportan |

### 7.2 Costos ocultos

| Fuga | Tamaño | Qué hacer |
|---|---|---|
| **Heartbeats** | Medido 2026-08-22: solo `main` registra turnos de heartbeat reales (5 en transcripts); `sofia` (1 tarea) y `cv` (3 tareas) tienen HEARTBEAT.md activo pero sin turnos visibles. **No es el gran consumidor hoy.** Aun así, guardarraíl barato: `agents.defaults.heartbeat.{isolatedSession:true, lightContext:true, every:"2h"}` | Mantener HEARTBEAT.md solo con comentarios en agentes reactivos (`adondepo`, `claudio`, `andres`, `acuarito`, `corfo`, `acuaria-branding`) |
| **Polling** | `terminal read` cada 5s durante 20 min = 240 turnos del agente | Backoff 30/60/120s + que el worker se anuncie solo (§3.5). El poll es red de seguridad |
| **Sub-agente que hereda contexto** | `context:"fork"` copia el transcript del padre | Usar `context:"isolated"` (default) salvo que se necesite |
| **Sesiones que no se archivan** | `archiveAfterMinutes: 60` por defecto | Pasar `cleanup:"delete"` en workers efímeros |
| **Delegar de más** | Un `sessions_spawn` para responder "sí" cuesta más que responder "sí" | La lista NO-delegar de §3.7 |
| **ACP con Sonnet en loop** | Se paga la suscripción Claude | `/acp timeout <s>` y revisar background tasks |

### 7.3 Cómo medir que el ahorro es real

Sin medición esto es fe. Tres números, todos ya disponibles:

1. **Baseline antes de tocar nada.** `openclaw audit` (registros metadata-only de runs y tool actions) → tokens por agente/día durante 3 días. Es la línea base.
2. **Por tarea.** Contar `queue/audit.jsonl` de adondepo (eventos/día) y las filas nuevas de `postulaciones.csv` (postulaciones/lote). La métrica es **tokens por evento subido** y **tokens por postulación**, no tokens totales — si sube el volumen, el total sube aunque cada unidad sea más barata.
3. **Reparto.** `sessions_list` filtrando por `kinds` y `agentId` muestra cuánto se movió a hijos. Meta concreta: **>70% de los tokens del padre desplazados a mini o a scripts sin LLM**.

**Señal de que salió mal:** el volumen de `sessions_spawn` sube pero los tokens totales no bajan → se está delegando lo que el agente podía responder solo. Ahí la corrección es la lista NO-delegar, no más workers.

---

## 8. Las tres decisiones de diseño

1. **El explorador separa navegar (script, sin LLM) de juzgar (worker mini).** La página nunca entra al contexto del padre; solo cruza un JSON de ≤800 bytes. Es donde está el ahorro grande (2 órdenes de magnitud en `cv`).

2. **El worker se anuncia solo; el padre no hace polling.** ACP lo trae de fábrica (announce al chat). En Orca se consigue con `openclaw agent --deliver` como última línea del handoff. El polling queda como red de seguridad con backoff, no como mecanismo.

3. **El fallback `claude-cli` evita quedar mudo, no permite seguir operando** (es texto sin tools). Lo que de verdad sobrevive a una cuota agotada es el ejecutor determinista sin LLM — razón de más para empujar trabajo hacia la fila (c) de la matriz.
