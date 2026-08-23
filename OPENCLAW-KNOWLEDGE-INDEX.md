# Índice — Conocimiento OpenClaw (arquitecto)

Índice del conocimiento acumulado sobre **cómo construir y configurar OpenClaw** para clientes.
Rol: arquitecto de OpenClaw (no es OpenClaw). Vive en el proyecto `/openclaw`.

> 🚪 **Empieza por [`AGENTS.md`](./AGENTS.md)** (protocolo de arranque del agente).
> 🎯 **Tarea más común**: crear un bot para un cliente → [`knowledge/onboarding-cliente.md`](./knowledge/onboarding-cliente.md).

## 0. Mapa por tarea — "quiero hacer X"

Punto de entrada rápido por intención, además de la organización temática de abajo (secciones 1-11).
Para cada tarea: qué doc leer primero y qué skill usar (si aplica).

| Quiero... | Leo primero | Uso este skill |
|---|---|---|
| **Crear un bot nuevo para un cliente** (de cero a bot vivo) | [`knowledge/onboarding-cliente.md`](./knowledge/onboarding-cliente.md) — runbook paso a paso | `openclaw-agent-build` *(en construcción, ver sección 11)* |
| **Elegir cómo conectar WhatsApp** (QR vs BSP vs Cloud API) | [`knowledge/openclaw.md`](./knowledge/openclaw.md#whatsapp-opciones-de-conexión) para las opciones; [`research/whatsapp-official-imbee.md`](./research/whatsapp-official-imbee.md) si el cliente desconfía y no da claves Meta | — (ver árbol de decisión en `onboarding-cliente.md` Paso 4) |
| **Versionar o mover la config a git de forma segura** | [`knowledge/config-management.md`](./knowledge/config-management.md) — SecretRef, `.gitignore`, `$include` | `openclaw-config-portable` (export ligero, sin secretos) |
| **Importar una config a otro OpenClaw ya existente** | [`knowledge/config-management.md`](./knowledge/config-management.md) + `HANDOFF.md` generado por el export | `openclaw-config-import` (detecta conflictos, pregunta, no aplica sin confirmar) |
| **Mudar toda la instancia a otra máquina** (DR / mudanza total, con secretos) | [`knowledge/moving-openclaw.md`](./knowledge/moving-openclaw.md) — opción (A) | — (usar `openclaw backup create --verify`, no los skills ligeros) |
| **Exportar/replicar/verificar toda la flota como código** (8 agentes, crons, plugins, allowlist) | [`fleet/README.md`](./fleet/README.md) — formato, separación público/privado, limitaciones | `fleet/export.sh` → `fleet/bootstrap.sh` → `fleet/verify.sh` |
| **Decidir local (Mac) vs VPS 24/7** | [`knowledge/local-vs-remote-gateway.md`](./knowledge/local-vs-remote-gateway.md) | — |
| **Verificar que un agente quedó bien montado** / saber qué grupo es cuál | [`skills/openclaw-agent-verify`](./.claude/skills/openclaw-agent-verify/SKILL.md) + el mapa del equipo (teléfonos/JIDs) en `<repo privado de la flota>/mapa-equipo.md (p. ej. ~/projects/openclaw-fleet-rodrigo)`, fuera del repo | `openclaw-agent-verify` |
| **Depurar un agente que responde raro** (genérico, ignora instrucciones) | [`knowledge/depurar-agentes.md`](./knowledge/depurar-agentes.md) — dónde vive su comportamiento real, determinismo por código, verificar antes de concluir | — |
| **Bajar el consumo de tokens / decidir qué modelo o agente hace cada tarea** | [`knowledge/optimizacion-tokens.md`](./knowledge/optimizacion-tokens.md) (informe + guardarraíles) · [`knowledge/patron-workers-delegacion.md`](./knowledge/patron-workers-delegacion.md) (matriz de enrutamiento, explorador, ACP/Orca, feedback WhatsApp) | `scripts/check-prompt-budget.sh`; skill `delegar-a-claude` (workspace de main) |
| **Entender la arquitectura general** (capas, memoria, multi-agente) | [`knowledge/openclaw.md`](./knowledge/openclaw.md#arquitectura-en-3-capas) | — |
| **Entender memoria, automatización (cron/hooks/standing orders), skills, seguridad** | [`knowledge/openclaw-features.md`](./knowledge/openclaw-features.md) | — |

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

### Flota como código (implementación de la opción B)

`fleet/` automatiza la réplica → [`fleet/README.md`](./fleet/README.md):

- **`fleet/export.sh --out <dir>`** — snapshot de la instancia viva (solo lectura): `fleet.json`
  (config sin `auth`/`gateway`/credenciales), workspaces de cada agente, `crons.json`,
  `plugins.json`, `channels.json` (solo política), `exec-approvals.json` (sin `socket.token`)
  y `manifest.json`. Termina con un **escaneo de secretos** que falla si encuentra algo.
- **`fleet/bootstrap.sh --fleet <dir>`** — aplica la flota a otra instancia vía
  `openclaw config set --batch-file` (regla 4), re-enraizando los workspaces al state dir
  destino; imprime `CHECKLIST.md` con los logins manuales que **no** viajan.
- **`fleet/verify.sh --fleet <dir>`** — tabla OK/DIFF de flota vs instancia (agentes, modelos,
  workspaces, bindings, sesión, crons, allowlist) + `scripts/check-prompt-budget.sh`.
- **Separación público/privado**: la herramienta vive en este repo público; la exportación
  (teléfonos, JIDs de grupo, mensajes de cron) va **siempre** a un repo privado aparte.
- Límites conocidos: los logins (OAuth/API keys/sesión WhatsApp) no viajan; un número de
  WhatsApp solo puede estar vivo en una instancia; `cron add` necesita gateway.

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
- **`openclaw-agent-build`** *(en construcción)* — sistematiza la creación de un agente por negocio (workspace, personalidad, canal, binding, control de acceso) siguiendo el runbook de `knowledge/onboarding-cliente.md`. Resuelve el issue #001.

**Nota:** para restauración total de una instancia (DR) existe el **backup OFICIAL** `openclaw backup create --verify` (pesado, con secretos). Los dos skills de config son el flujo **ligero** export↔import; `openclaw-agent-build` es un flujo distinto (construcción, no migración).

## 11. Pendientes / issues

- [`issues/001-buscar-skill-construccion-agente-openclaw.md`](./issues/001-buscar-skill-construccion-agente-openclaw.md)
  — **parcialmente resuelto**: el runbook [`knowledge/onboarding-cliente.md`](./knowledge/onboarding-cliente.md) ya cubre el "cómo". Pendiente convertirlo en la skill disparable `openclaw-agent-build`.
- [`issues/002-token-gateway-en-texto-plano.md`](./issues/002-token-gateway-en-texto-plano.md) — ⚠️ seguridad, **abierto pero en proceso**: el skill `openclaw-config-portable` ya implementa un hard-stop (Paso 1: audita secretos con `openclaw secrets audit --check` y se niega a empaquetar el JSON si hay plaintext), lo que evita que el token se filtre al versionar. Falta aplicar la solución de fondo (mover `gateway.auth.token` a SecretRef) sobre la instancia real.
