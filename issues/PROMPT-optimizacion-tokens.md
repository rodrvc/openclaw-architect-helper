> **Estado 2026-08-22:** ejecutado. Informe en [`../knowledge/optimizacion-tokens.md`](../knowledge/optimizacion-tokens.md); pendientes con decisión de Rodrigo en [`003-optimizacion-pendientes-decision.md`](./003-optimizacion-pendientes-decision.md).

# Tarea: recuperar y blindar el presupuesto de tokens de una flota OpenClaw

Sos arquitecto de agentes. Trabajás sobre una instalación **real y en producción** de
OpenClaw en la máquina de Rodrigo (macOS). El usuario se quedó **sin cuota del proveedor
por 5 días** (reset: 27 de agosto, 8:00 AM GMT-4) y sus 9 agentes están caídos.

Tu trabajo NO es solo bajar el consumo: es **mover el trabajo caro fuera del lugar caro** y
dejar guardarraíles para que no se repita.

---

## Contexto verificado (no lo re-descubras, sí re-verificá antes de escribir)

**La causa medida:** 44.8 MB de contexto enviado históricamente ≈ 11.8 M tokens de *input*,
en 1.016 llamadas. El contexto se reenvía completo en cada turno, así que una sesión de 51
turnos costó 2.5 MB. El piso por llamada es 38.8 KB (~10k tokens) *antes* de que nadie hable:
17.8 KB de systemPrompt + ~6 KB de definiciones de tools (la de `cron` sola pesa 4 KB).

**Consumo por agente** (MB de contexto / llamadas): main 19.1/404 · sofia 8.8/212 ·
adondepo 8.6/191 · andres 5.9/137 · cv 1.2/27 · resto menor.

**Peso de arranque por agente** (suma de .md del workspace, se paga en CADA llamada):

| Agente | Bytes | Los gordos |
|---|---|---|
| main | 29.325 | AGENTS 8376 · PROJECTS 6071 · MEMORY 4949 · TOOLS 4497 · USER 2810 |
| andres | 19.755 | AGENTS 7196 · MEMORY 7127 · SOUL 2167 |
| adondepo | 18.213 | AGENTS 7196 · SOUL 8082 |
| sofia | 17.747 | AGENTS 8401 · USER 2949 |
| cv | 17.347 | AGENTS 10733 |
| acuarito | 14.404 | AGENTS 7196 · SOUL 4273 |
| claudio | 14.155 | AGENTS 7196 · SOUL 2549 |
| corfo | 8.643 | AGENTS 2664 |
| acuaria-branding | 6.714 | AGENTS 2261 |

**Tres hallazgos confirmados:**
1. **9 de 9 agentes en `openai/gpt-5.5`** (el más caro). `gpt-5.4-mini` y `gpt-5.4` ya están
   declarados en `agents.defaults.models` y **nadie los usa**.
2. **`AGENTS.md` duplicado**: hash `c9a664b73200`, 7.196 B **idénticos** en `acuarito`,
   `adondepo`, `andres`, `claudio`. Mismo texto pagado 4 veces por llamada.
3. **`Dreaming: off`** en los 5 agentes con memoria, y `Recall store: 0 promoted`. OpenClaw
   trae consolidación de memoria (`openclaw memory promote`, `rem-harness`, `rem-backfill`)
   y **nunca se encendió**. Por eso el contexto solo crece.

**Línea base correcta que ya existe:** `TOOLS.md` de 876 B funciona bien en 4 agentes.
Los 4.497 B de `main` son la desviación, no el estándar.

**Ya hecho, no lo repitas:** los 3 crons de `cv` (LinkedIn, postulación ML/Amazon, reporte de
mercado) están `enabled: false`, verificado. Quedan 6 activos: 3 de `sofia`, 2 de `andres`,
1 de `claudio`.

---

## Reglas de trabajo (no negociables)

1. **Medí antes y después de cada cambio.** Reportá el delta en bytes/llamada. Un cambio sin
   número medido no está hecho.
2. **Verificá que el comando surtió efecto, no que salió sin error.** Trampa real de esta
   CLI: `openclaw cron disable --id <id>` **falla en silencio** — el id va posicional
   (`openclaw cron disable <id>`). Siempre confirmá leyendo el estado (`openclaw cron get <id>`).
3. **Backup antes de tocar** `~/.openclaw/openclaw.json`:
   `cp ~/.openclaw/openclaw.json ~/.openclaw/openclaw.json.bak-<motivo>-$(date +%Y%m%d-%H%M%S)`
   Después: `openclaw config validate`.
4. **Preferí la CLI validada** (`openclaw config set/patch --dry-run`, `openclaw agents ...`)
   sobre editar el JSON a mano.
5. **`openclaw gateway restart` corta a TODOS los agentes.** Pedí OK a Rodrigo antes. No hay
   `gateway reload`.
6. **No toques la config de `acuarito`** sin avisar explícitamente: está bajo lockdown de
   seguridad (sandbox Docker `network:none`, 28 tools denegadas) tras una suplantación.
7. **Confirmá con Rodrigo** antes de borrar contenido de un workspace o cambiar el modelo de
   un agente con side effects (`cv`, `adondepo`).
8. **No inventes números.** Si un dato no lo mediste en esta sesión, decí que no lo verificaste.

---

## Los 6 frentes, en orden de ejecución

### 1. Encender la consolidación de memoria [primero: ya está construido]

`Dreaming: off` en `main`, `sofia`, `andres`, `cv`, `adondepo`. Investigá con
`openclaw memory --help`, `openclaw memory status --agent <id>` y la doc oficial
(`/opt/homebrew/lib/node_modules/openclaw/docs/` o https://docs.openclaw.ai) cómo se activa,
qué hace exactamente y **cuánto cuesta correrlo** (si la consolidación misma consume tokens,
programala fuera de hora y decilo).

Objetivo: que la memoria se compacte sola en vez de crecer para siempre. Verificá con
`memory status` que pasa a `on` y que `promoted` deja de ser 0.

### 2. Modelo por tarea [el mayor ahorro inmediato, ~15 min]

Criterio: **un agente que no puede causar daño irreversible no justifica el modelo caro; uno
que sí puede, no se abarata nunca para ahorrar.**

| Perfil | Agentes | Modelo |
|---|---|---|
| Notificación / saludo (sin side effects, salida acotada) | `claudio`, `acuarito`, `corfo`, `acuaria-branding` | `openai/gpt-5.4-mini` |
| Conversacional con humano, sin escrituras externas | `sofia`, `andres` | `openai/gpt-5.4` |
| Agéntico con side effects irreversibles | `cv` (postula en LinkedIn), `adondepo` (escribe a prod) | `openai/gpt-5.5` |
| Orquestador | `main` | `openai/gpt-5.5` |

Aplicá con `openclaw config set ... --dry-run` primero. Los de la última columna NO se tocan.

### 3. Deduplicar `AGENTS.md` [7.196 B × 4 agentes]

Averiguá **primero** si OpenClaw soporta includes o herencia de instrucciones
(`agents.defaults`, algún mecanismo de shared prompt). Si existe, usalo. Si no, generá cada
`AGENTS.md` desde una plantilla única con un script, dejando en cada workspace solo el delta
específico del agente. Meta: bajar de 7.196 B a ~2-3 KB por agente.

### 4. Adelgazar los prompts (techos duros)

Techos: **`main` ≤ 12 KB · conversacional ≤ 8 KB · notificación ≤ 4 KB.**

Criterio para decidir qué se queda: *el prompt describe al agente; las herramientas describen
al mundo.* Si un contenido cambia la respuesta en menos del ~20% de las llamadas, **no va en
el prompt** — va a un archivo que el agente lea bajo demanda o a una skill.

Casos concretos:
- **`main` (29.325 B → ≤12 KB).** `PROJECTS.md` (6.071 B) es información pura, no identidad:
  convertilo en archivo de consulta bajo demanda y sacalo del arranque. `TOOLS.md` (4.497 B)
  debe volver a ser un índice tipo los 876 B de los otros agentes: nombre de herramienta +
  una línea de cuándo usarla; el "cómo" va a la skill. Ojo: parte de este peso lo agregó otro
  agente hoy mismo, no asumas que es contenido histórico valioso.
- **`andres`**: `MEMORY.md` de 7.127 B — candidato a consolidación (frente 1).
- **`adondepo`**: `SOUL.md` de 8.082 B.
- **`cv`**: `AGENTS.md` de 10.733 B (vive en el repo `~/projects/rodrigo-career`, ahí manda el
  `AGENTS.md` del repo — coordiná con esa regla, no la rompas).

Escribí un script de verificación que **falle** si un agente supera su techo, para poder
correrlo periódicamente.

### 5. Mover el trabajo caro fuera del agente caro [el cambio de fondo]

Esta es la parte que más importa y la que no resuelven los recortes:

- **Scraping y búsquedas → workers exploradores.** Hoy `cv` (LinkedIn) y `adondepo`
  (Instagram) meten páginas enteras al contexto del agente principal. Diseñá un patrón donde
  un worker efímero y barato haga la navegación/extracción y devuelva **solo el resultado
  estructurado**. `adondepo` ya usa un patrón parecido (cola `queue/inbox/` + ejecutor
  `~/projects/city-activities-api/scraper/subir-eventos.sh`): estudialo como referencia.
- **Trabajo de código → delegar a Claude en Orca.** `main` ya sabe orquestar Orca (está
  documentado en su `TOOLS.md`: `orca terminal create/split/send`, `orca worktree create`).
  Eso saca el razonamiento largo de la cuota de OpenClaw. Definí cuándo delegar y dejalo
  escrito como regla.

Entregá un diseño concreto con el patrón, no una recomendación genérica.

### 6. Mejorar el agente `memory-engineer`

Definición en `~/.claude/agents/memory-engineer.md`. Su doctrina ya es correcta ("prioriza
referencias antes que copia", "guarda la unidad más pequeña que siga siendo útil") pero
**Rodrigo reporta que responde boilerplate en vez de soluciones concretas**.

Diagnosticá por qué y arreglalo: probablemente le falta obligación de **medir antes de
opinar** y de entregar el cambio aplicable en vez de principios. Buscá skills existentes que
le sirvan (`find-skills`, ClawHub, `openclaw plugins search`) antes de escribir una nueva.

Criterio de éxito: ante "revisá la memoria de X", debe responder con archivos concretos,
bytes medidos y un diff propuesto — no con una lista de buenas prácticas.

---

## Entregable

Un informe con:
1. **Qué cambiaste**, con bytes/llamada antes → después por agente, y el total estimado.
2. **Qué NO cambiaste y por qué** (bloqueado, riesgoso, necesita decisión de Rodrigo).
3. **Los guardarraíles que dejaste**: el script de techos, la regla escrita, dónde vive cada cosa.
4. **Diseño del patrón de workers** (frente 5), concreto y aplicable.
5. **Cualquier dato del contexto de arriba que hayas encontrado desactualizado.** Un archivo
   de estado (`~/.openclaw/cron/jobs.json.migrated`) resultó ser de junio y contradecía al CLI
   en vivo; el CLI tenía razón. Desconfiá de archivos sueltos, preferí la CLI.

Trabajá de forma incremental y verificable. Después de cada frente, medí y reportá antes de
seguir al siguiente.
