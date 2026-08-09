# Índice — Conocimiento OpenClaw (arquitecto)

Índice del conocimiento acumulado sobre **cómo construir y configurar OpenClaw** para clientes.
Rol: arquitecto de OpenClaw (no es OpenClaw). Vive en el proyecto `/openclaw`.

Todos los conceptos y decisiones de arquitectura que hemos tocado, con dónde profundizar.

## 1. Arquitectura multi-cliente de OpenClaw

- **Tres capas de separación** — [detalle](./knowledge/openclaw.md#arquitectura-en-3-capas):
  - **Instancia** OpenClaw → **una sola** para todos los clientes. NO una por negocio.
  - **Agente** → **uno por negocio/rol** (ej. `llantas`, `veterinaria`). Personalidad, workspace, memoria propios.
  - **Sesión** → **automática, una por número** que escribe. Memoria aislada por cliente final.
- **Un agente por negocio basta** — no se necesita instancia separada por cliente.
- **Memoria por número** es automática (`session.dmScope`): cada teléfono = su historial.
- **Comportamientos distintos** = distintos agentes + system prompts por grupo/DM.

## 2. Canales / WhatsApp — cómo exponerlo a clientes

- **Plugin oficial `@openclaw/whatsapp`** → solo **QR (WhatsApp Web / Baileys)**. No oficial de Meta.
- **QR: pros/contras** — [detalle](./knowledge/openclaw.md#whatsapp-opciones-de-conexión):
  - Pro: gratis, inmediato, cero fricción para el cliente final.
  - Contra: **riesgo de ban**, depende de teléfono físico 24/7, sesión frágil.
- **WhatsApp Cloud API (Meta oficial)** — sin ban, sin teléfono, pero: verificación de negocio,
  webhook público 24/7, plantillas aprobadas, costo por conversación, y **no viene como plugin** → habría que construirlo con el SDK de canales.
- **Alternativa por proveedor (BSP): `openclaw-channel-whatsapp-official` (imBee)** — **SÍ existe**, plugin de comunidad en ClawHub. Oficial Meta vía imBee, tier gratis, resuelve el problema del "dueño desconfiado" (imBee es el BSP, el dueño no entrega claves). → [research](./research/whatsapp-official-imbee.md).

## 3. Reconexión y robustez (para producción)

- **OpenClaw se reconecta solo** (watchdog + reconnect loop) ante caídas normales.
- **Escenario A** (reconnect loop): `openclaw channels status --probe` → `openclaw doctor` → ajustar `web.whatsapp.*`.
- **Escenario B** (sesión perdida): respaldar credencial y re-escanear QR.
- **Prevención**: número+teléfono dedicados siempre encendidos, gateway como servicio de fondo, monitoreo (heartbeat).
- [detalle](./knowledge/openclaw.md#reconexión-whatsapp).

## 4. Riesgos al exponer a clientes reales

- Ban del número (QR), dependencia de teléfono físico, fragilidad de sesión, **responsabilidad tuya**.
- **Regla de oro**: nunca poner en QR un número que al cliente le dolería perder.
- **Fase demo → QR con número de prueba. Fase producción → BSP (imBee) o Cloud API.**
- [detalle](./knowledge/openclaw.md#riesgos-de-producción).

## 5. Ecosistema de extensión

- **ClawHub** = marketplace de plugins de comunidad. `openclaw plugins search/install clawhub:<pkg>`.
- **SDK de canales** = permite construir un canal propio (ej. conector a un BSP) → sería un activo reutilizable.
- [detalle](./knowledge/openclaw.md#ecosistema-clawhub-y-plugins).

## 6. Otras funcionalidades investigadas

Barrido amplio de los docs → [`knowledge/openclaw-features.md`](./knowledge/openclaw-features.md):

- **Memoria** (MEMORY.md, notas diarias, active memory, backends semánticos).
- **Workspace** del agente (home + memoria; no es sandbox duro).
- **Personalidad**: SOUL.md / AGENTS.md / USER.md + system prompt por-run.
- **Multi-agente y bindings** (confirmado a fondo: 1 instancia → N agentes → cuentas de canal).
- **Automatización**: cron, heartbeat, hooks, webhooks, **standing orders** (autoridad autónoma), TaskFlow.
- **Skills**: qué son, cómo se cargan, cómo crear una propia (ligado al issue #001).
- **Runtimes**: OpenClaw nativo, Codex, ACP.
- **Seguridad**: sandboxing, permission modes, exec-approvals, threat model.
- **UI/canales**: Control UI, Dashboard, TUI, WebChat, Nodes (audio/cámara/voicewake), +15 canales.
- **Herramientas**: búsqueda web (múltiples backends), browser, code-execution, media generation, subagents, llm-task.

## 7. Gestión de config (versionado seguro + portable)

Cómo modificar y versionar la config de OpenClaw sin exponer secretos → [`knowledge/config-management.md`](./knowledge/config-management.md):

- **Config vive en** `~/.openclaw/openclaw.json` (JSON5) + backups automáticos (`.bak*`, `.last-good`, `.pre-update`).
- **Editar vía CLI** (`openclaw config set/patch` + `--dry-run`, `openclaw configure`) — valida antes de escribir.
- **Secretos fuera del JSON**: env `${VAR}`, **SecretRef** (`{source,provider,id}` con env/file/exec: 1Password/Vault/etc.).
- **Versionar**: repo git con `.gitignore` restrictivo + `$include` + `OPENCLAW_CONFIG_PATH`; secretos vía `.env`/gestor, plantillas `.example`.
- **Portar a otra máquina**: clonar repo → `OPENCLAW_CONFIG_PATH` → re-hidratar secretos → `secrets audit --check` → `doctor`.
- ⚠️ `openclaw backup` (.tar.gz) lleva credenciales → **nunca a git**.
- ⚠️ **Estado actual**: `gateway.auth.token` en texto plano (issue #002).

## 8. Mover / replicar / desplegar OpenClaw

Cómo los usuarios llevan OpenClaw de un lugar a otro → [`knowledge/moving-openclaw.md`](./knowledge/moving-openclaw.md):

- Modelo: **1 Gateway master dueño del estado** (`~/.openclaw/`); mover instancia = mover ese host.
- **(A) Mudanza total**: `openclaw gateway stop` → tar de `~/.openclaw/` (o `openclaw backup create`) → instalar CLI → `openclaw doctor`. Nunca solo `openclaw.json`. Lleva secretos en claro.
- **(B) Réplica**: sin sync nativo; versionar workspace/config como git privado (+ SecretRef).
- **(C) Acceso remoto**: SSH tunnel, Tailscale serve/funnel, o nodos emparejados → se conectan al Gateway central, no lo mueven.
- **(D) Despliegue VPS/cloud**: Gateway en servidor como fuente de verdad (DigitalOcean/Oracle/RPi/contenedor EasyRunner); loopback + SSH/Tailscale.
- **Recomendación para clientes**: **D + B** (VPS 24/7 + config versionada) con acceso por Tailscale/SSH; la mudanza (A) queda como DR.

## 9. Local vs remoto: proyectos locales + config cómoda + 24/7

Resolviendo la tensión → [`knowledge/local-vs-remote-gateway.md`](./knowledge/local-vs-remote-gateway.md):

- **NO usa Redis** — estado = SQLite + archivos. Personalidad = Markdown (se mueve con git, no Redis).
- El Gateway y sus **file tools solo tocan la máquina donde corre**. Un node remoto da **solo shell** (`exec host=node`), no file tools nativas.
- **Opción A** (Gateway en Mac + Tailscale + no-sleep): proyectos locales + config local ✅, pero 24/7 depende del Mac.
- **Opción B+C** (Gateway VPS + node local + config por git/SSH): 24/7 real ✅, pero proyectos locales solo por shell y sync manual.
- **Recomendación**: separar en **2 Gateways** — uno en el Mac para dev, otro(s) en VPS para bots de clientes; personalidad/config compartida por git.

## 10. Skills del arquitecto

Skills de Claude Code versionadas en este repo (`.claude/skills/`):

- **`openclaw-config-portable`** (export) — prepara un paquete ligero y portable de config + personalidad de OpenClaw (sin secretos) y genera un prompt de traspaso (`HANDOFF.md`). Resuelve el "no quiero mover todo el proyecto gigante".
- **`openclaw-config-import`** (import) — instala ese paquete ligero en un OpenClaw YA EXISTENTE: respalda con el backup oficial, detecta conflictos y pregunta caso a caso (merge/reemplazar/omitir), prepara el plan y NO aplica hasta que el usuario confirme.

**Nota:** para restauración total de una instancia (DR) existe el **backup OFICIAL** `openclaw backup create --verify` (pesado, con secretos). Los dos skills de arriba son el flujo **ligero** export↔import.

## 11. Pendientes / issues

- [`issues/001-buscar-skill-construccion-agente-openclaw.md`](./issues/001-buscar-skill-construccion-agente-openclaw.md)
- [`issues/002-token-gateway-en-texto-plano.md`](./issues/002-token-gateway-en-texto-plano.md) — ⚠️ seguridad
