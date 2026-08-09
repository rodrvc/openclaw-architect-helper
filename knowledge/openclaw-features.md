# OpenClaw — otras funcionalidades investigadas

> Barrido de la documentación local (`/opt/homebrew/lib/node_modules/openclaw/docs/`).
> Cada punto con su fuente. Última actualización: 2026-08-08.
> Relevancia marcada para nuestro caso (bot para clientes / escuelas).

---

## 1. Memoria (cómo recuerda OpenClaw) ⭐ muy relevante

Fuente: `concepts/memory.md`, `concepts/active-memory.md`.

- OpenClaw recuerda **escribiendo archivos Markdown** en el workspace del agente (`~/.openclaw/workspace`). **No hay estado oculto** — solo recuerda lo que se guarda a disco.
- Tres archivos de memoria por agente:
  - **`MEMORY.md`** — largo plazo (hechos, preferencias, decisiones). Se carga al inicio de sesión.
  - **`memory/YYYY-MM-DD.md`** — notas diarias (contexto corrido). Hoy y ayer se cargan solos en `/new` o `/reset`.
  - (variantes con slug las escribe el hook de session-memory).
- **Active memory** (plugin opcional): un sub-agente de recall que corre **antes** de la respuesta e inyecta memoria relevante. Útil en chats conversacionales (ej. atención a clientes) para que recuerde sin que el usuario diga "acuérdate". Se puede acotar a `main` + DMs.
- Otros backends de memoria: `memory-honcho`, `memory-qmd`, `memory-lancedb`, `memory-wiki` (búsqueda semántica).

---

## 2. Workspace del agente

Fuente: `concepts/agent-workspace.md`.

- El workspace es el **home del agente**: cwd de las herramientas de archivo + contexto. Tratarlo como memoria y mantenerlo privado.
- Separado de `~/.openclaw/` (config, credenciales, sesiones).
- ⚠️ **No es un sandbox duro**: rutas absolutas pueden salir del workspace salvo que actives sandboxing.

---

## 3. Personalidad: SOUL.md / AGENTS.md / USER.md ⭐ relevante

Fuente: `concepts/soul.md`, `concepts/system-prompt.md`, `concepts/multi-agent.md`.

- **`SOUL.md`** — la "voz" del agente: tono, opiniones, brevedad, humor, límites. OpenClaw lo inyecta en las sesiones. Es lo que se edita para que no suene genérico/corporativo. Corto y filoso > largo y vago.
- **`AGENTS.md`** — reglas/persona del agente. **`USER.md`** — info del usuario/dueño.
- **System prompt**: OpenClaw lo construye por cada run (no hay prompt default en runtime). Se ensambla por capas; plugins de provider pueden aportar guía sin reemplazarlo.
- → Para cada negocio (llantas, escuela) su propio SOUL.md = tono distinto sin cambiar de instancia.

---

## 4. Multi-agente y bindings (confirmado a fondo) ⭐ clave

Fuente: `concepts/multi-agent.md`.

- Varios agentes **aislados** en un mismo gateway. Cada agente tiene:
  - **Workspace** (files, AGENTS.md/SOUL.md/USER.md).
  - **State dir** (`agentDir`): auth, model registry, config por agente.
  - **Session store**: historial en `~/.openclaw/agents/<agentId>/sessions`.
- **Bindings** mapean una cuenta de canal (un número WhatsApp, un workspace Slack) → un agente.
- Auth por agente. Soporta **varias cuentas del mismo canal** (ej. dos números WhatsApp).
- Esto confirma la arquitectura: 1 instancia → N agentes → cuentas de canal enrutadas por binding.

---

## 5. Automatización — bot que actúa solo ⭐ relevante para "24/7"

Fuente: `automation/cron-jobs.md`, `automation/hooks.md`, `automation/standing-orders.md`, `gateway/heartbeat.md`.

- **Cron** (scheduler del gateway): trabajos programados, wakeups, recordatorios. Puede entregar salida a un chat, webhook o a nada. Ej: reporte semanal automático.
- **Heartbeat**: latido periódico (distinto de cron; ver tabla de decisión en `/automation`).
- **Hooks**: scripts que corren dentro del gateway ante eventos (`/new`, `/reset`, `/stop`, compaction, ciclo de vida, flujo de mensajes). Se activan al configurarlos. Pueden venir dentro de plugins.
- **Webhooks**: endpoints HTTP para que sistemas externos disparen trabajo en OpenClaw.
- **Standing orders**: dan al agente **autoridad operativa permanente** para "programas" definidos (scope, triggers, escalación). El agente actúa autónomo dentro de esos límites y solo escala excepciones. → Muy útil para un bot que opera solo con reglas claras.
- **TaskFlow / Tasks / Poll / ClawFlow**: flujos de tareas gestionadas.

---

## 6. Skills (enseñar al agente a usar herramientas) ⭐ relevante (issue #001)

Fuente: `tools/skills.md`, `tools/creating-skills.md`, `tools/skill-workshop.md`.

- **Skills** = archivos Markdown (`SKILL.md` con frontmatter YAML) que enseñan al agente **cómo y cuándo** usar herramientas.
- OpenClaw carga skills bundled + overrides locales, y las **filtra** por entorno, config y presencia de binarios.
- Se pueden **crear skills propias** (custom workspace skills) y publicarlas. Hay **Skill Workshop** para proponer skills a revisión del agente.
- CLI: `openclaw skills`. → Directamente relacionado con el issue #001 (skill de construcción de agente).

---

## 7. Runtimes de agente

Fuente: `concepts/agent-runtimes.md`.

- Un **runtime** posee un loop de modelo (recibe prompt, maneja tool calls nativos, devuelve el turno).
- Distinto de "provider" (quién sirve el modelo) y "model". Opciones: OpenClaw nativo, **Codex**, **ACP**, otros harness nativos.
- Relevante si algún cliente necesita un harness específico.

---

## 8. Seguridad y sandboxing ⭐ relevante para clientes

Fuente: `gateway/sandboxing.md`, `security/THREAT-MODEL-ATLAS.md`, `tools/permission-modes.md`, `tools/exec-approvals.md`.

- **Sandboxing** off por default. `agents.defaults.sandbox` (global) o por agente. El gateway siempre corre en el host; solo la **ejecución de herramientas** entra al sandbox. No es barrera perfecta, pero limita el daño.
- **Permission modes** y **exec-approvals**: controlar qué puede ejecutar el agente y qué requiere aprobación.
- Hay **modelo de amenazas** documentado (`THREAT-MODEL-ATLAS.md`) e **incident-response**.
- → Para exponer a clientes: evaluar sandbox + approvals para acotar qué hace el agente.

---

## 9. Superficies de interacción (UI/canales) 

Fuente: `web/` , `nodes/`.

- **Control UI / Dashboard / TUI / WebChat**: interfaces del gateway (chat, config, sesiones) — `web/control-ui.md`, `web/webchat.md`, `web/tui.md`.
- **Nodes**: entradas multimedia — audio, cámara, imágenes, ubicación, **voicewake**, media-understanding (`nodes/`).
- Muchos canales soportados (index.md): Discord, Google Chat, iMessage, Matrix, MS Teams, Signal, Slack, Telegram, WhatsApp, Zalo, IRC, Nostr, etc.

---

## 10. Herramientas destacadas del agente

Fuente: `tools/index.md` y varios.

- **Búsqueda web**: múltiples backends (Brave, DuckDuckGo, Exa, Perplexity, Tavily, SearXNG, Firecrawl, Gemini/Grok/Kimi/Minimax/Ollama search).
- **Browser control** (`tools/browser.md`), **code-execution**, **apply-patch/diffs**, **PDF**, **image/music/video generation**, **TTS**, **llm-task** (delegar sub-tareas a un LLM).
- **Subagents** (`tools/subagents.md`), **multi-agent-sandbox-tools**, **loop-detection**, **thinking**.
- **ACP agents** (`tools/acp-agents.md`): conectar agentes vía Agent Client Protocol.

---

## Ideas / hilos a profundizar después

- Cómo exactamente **active memory** mejora la atención a clientes (config y costo).
- **Standing orders** para un bot escolar (ej. "responde dudas 24/7, escala al profesor si X").
- Backends de memoria semántica (`memory-lancedb`, `memory-wiki`) para base de conocimiento de un negocio.
- Sandbox + approvals recomendados por defecto al exponer a clientes.
- Confirmar el flujo de **crear una skill propia** para el issue #001.
