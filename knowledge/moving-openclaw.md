# OpenClaw — cómo mover / replicar / acceder / desplegar

> Estrategias que usan los usuarios para llevar OpenClaw de un lugar a otro.
> Investigado desde docs locales + oficiales + comunidad. Fuentes citadas. 2026-08-08.

---

## Modelo mental clave

OpenClaw corre **un único Gateway (el "master") que es dueño de TODO el estado**
(sesiones, auth profiles, canales, credenciales). Todo lo demás (app macOS, nodos
iOS/Android, CLI remoto) es un **cliente**.

➡️ **"Mover la instancia" = mover el host del Gateway.** El estado vive en `~/.openclaw/`
(o `~/.openclaw-<profile>/`, o `OPENCLAW_STATE_DIR`).
Fuentes: `gateway/remote.md`, `network.md`, `install/migrating.md`.

Hay **4 estrategias distintas** — no confundirlas:

| | Estrategia | Para qué |
|---|-----------|----------|
| **A** | Mudanza total | Llevar toda la instancia a otra máquina |
| **B** | Réplica de config | Misma config en varias máquinas |
| **C** | Acceso remoto | No mover: conectarse a un Gateway central |
| **D** | Despliegue VPS/cloud | Correr el Gateway en infraestructura |

---

## (A) MUDANZA TOTAL — máquina a máquina

### A1. Copiar el state dir (método oficial) — `install/migrating.md`
Conserva canales, sesiones y credenciales **sin re-emparejar**.
```bash
# Máquina vieja
openclaw gateway stop                      # PRIMERO: que no cambien archivos
cd ~ && tar -czf openclaw-state.tgz .openclaw
# Transferir (scp / rsync -a / disco) e instalar el CLI en la nueva máquina
cd ~ && tar -xzf openclaw-state.tgz
openclaw doctor && openclaw gateway restart && openclaw status
```
- **Mueve TODO**: config, auth profiles (API keys + OAuth), `credentials/`, sesiones, login WhatsApp/Telegram, workspace (MEMORY.md, USER.md, skills).
- ⚠️ **Nunca copiar solo `openclaw.json`** → canales quedan deslogueados.
- Mismo `--profile`/`OPENCLAW_STATE_DIR`. Permisos del usuario que corre el Gateway.
- En modo remoto: migrar el **host del Gateway**, no el laptop.
- 🔐 El tar lleva **credenciales en claro** → cifrar el backup, canal seguro, rotar si hay sospecha.

### A2. `openclaw backup create` (snapshot portable) — `cli/backup.md`
Alternativa más limpia al tar manual; "portable across hosts".
```bash
openclaw backup create                 # .tar.gz con manifest.json
openclaw backup create --verify
openclaw backup create --no-include-workspace   # más liviano
openclaw backup create --only-config            # solo openclaw.json
openclaw backup verify <archive>
```
- Snapshotea SQLite de forma segura (`VACUUM INTO`). Omite volátiles (logs, colas, sockets) y `node_modules` de plugins (rebuild con `openclaw plugins update`).
- **No hay `backup restore`**: se extrae el archivo y se corre `openclaw doctor`.
- No cifra por sí mismo.

### A3. `openclaw migrate` — NO es machine-to-machine
Importa desde **otros agentes** (Claude Code, Codex, Hermes), no mueve OpenClaw entre máquinas. Preview-first, secretos opt-in (`--include-secrets`). `cli/migrate.md`.

### Limpiar la máquina vieja
`openclaw reset --scope full` (borra state+workspace, mantiene CLI) o `openclaw uninstall --all`. Hacer `openclaw backup create` antes. `cli/reset.md`, `cli/uninstall.md`.

---

## (B) RÉPLICA de config a varias máquinas

**No hay comando de sync nativo.** La estrategia documentada (`start/setup.md`):

- Mantener personalización en `~/.openclaw/openclaw.json` + `~/.openclaw/workspace/` (fuera del repo de código, para que updates no la toquen).
- **Versionar el workspace como repo git privado** = el mecanismo de réplica (clonar en cada máquina). ← conecta con nuestro [config-management.md](./config-management.md).
- Bootstrap sin wizard completo: `openclaw setup --baseline`.
- **Multiple gateways** (`gateway/multiple-gateways.md`): réplica **en el mismo host** con aislamiento (perfiles + puertos), ej. `openclaw --profile rescue onboard` + `gateway install --port 19789`. NO es replicar a otras máquinas.
- ⚠️ Copiar el state dir completo a varias máquinas **duplica credenciales** → `chmod 700 ~/.openclaw`.

---

## (C) ACCESO REMOTO a un Gateway central (no mover)

Bind por defecto: loopback `ws://127.0.0.1:18789` (`gateway.port`).

### C1. Túnel SSH (fallback universal) — `gateway/remote.md`
```bash
ssh -N -L 18789:127.0.0.1:18789 user@gateway-host
```
Config durable de cliente: `gateway.mode: "remote"` + `gateway.remote.url`/`.token` (macOS: `.sshTarget`). Persistencia macOS: `~/.ssh/config` LocalForward + LaunchAgent con KeepAlive.
⚠️ `--url` nunca reusa credenciales implícitas → pasar `--token`/`--password` explícito.

### C2. Tailscale (VPN/tailnet) — `gateway/tailscale.md`
- `gateway.tailscale.mode: "serve"` (solo tailnet, HTTPS + identity headers) o `"funnel"` (público, **exige** `auth.mode: "password"`).
- O bind directo `gateway.bind: "tailnet"` + token → `ws://<tailscale-ip>:18789`.
- Sirve para Control UI, WS y nodos.

### C3. Nodos móviles/remotos — `nodes/index.md`, `gateway/pairing.md`
- Un **nodo** (iOS/Android/macOS/headless) es un **periférico, NO un Gateway**: se conecta al WS con `role: "node"` y expone comandos (`camera.*`, `canvas.*`, `system.run`) vía `node.invoke`.
- Ejecutar comandos en otra máquina: `openclaw node run --host <gateway-host> --port 18789`. Requiere pairing: `openclaw devices list/approve`.
- Pairing: el Gateway es la fuente de verdad; tokens rotan; state en `~/.openclaw/nodes/paired.json` (secreto). Breaking change 2026.3.31: comandos de nodo deshabilitados hasta aprobar pairing.
- Discovery Bonjour/mDNS (`_openclaw-gw._tcp`) es conveniencia LAN-only; cross-network usa Tailscale o SSH.
- ⚠️ Nodos con `system.run` = acceso a ejecución; comandos peligrosos requieren opt-in `gateway.nodes.allowCommands`.

---

## (D) DESPLIEGUE en servidor / VPS / cloud

Modelo (`vps.md`): Gateway en el VPS = **fuente de verdad**; te conectas por Control UI / SSH / Tailscale; respaldar state+workspace con `openclaw backup create`. Seguro por defecto: loopback + SSH/Tailscale. Bind `lan`/`tailnet` → obliga `gateway.auth.token`/`.password`.

- **`vps.md`** (Linux hub): "shared company agent" (usuario OS dedicado, sin cuentas personales), `openclaw onboard --install-daemon` (systemd user + `loginctl enable-linger`).
- **DigitalOcean** (`install/digitalocean.md`): Droplet Ubuntu 24.04 (~$6/mes 1GB), Node 24, usuario no-root, swap, acceso SSH/Tailscale.
- **Oracle** (`install/oracle.md`): Always Free ARM, Tailscale SSH, loopback + token + serve, `chmod 700 ~/.openclaw`, `openclaw security audit`.
- **Raspberry Pi** (`install/raspberry-pi.md`): always-on ARM barato (solo Gateway; modelos por API).
- **Linux** (`platforms/linux.md`): requiere **Node** (no Bun — falta `node:sqlite`); systemd user vs system.
- **EasyRunner** (`platforms/easyrunner.md`): **containerizado** `ghcr.io/openclaw/openclaw` detrás de Caddy (Podman/Compose). Volúmenes persistentes para `/home/node/.openclaw` (+ workspace); token en secret manager; backup del volumen antes de updates.

**Requisitos** (comunidad): dev 2 vCPU / 4GB; prod 4 vCPU / 8GB + 20GB SSD. Mudanza ~60-90 min.

**Nota** (`start/bootstrapping.md`): el bootstrapping (seed de AGENTS.md/SOUL.md/IDENTITY.md) corre siempre en el **host del Gateway** → refuerza que mover la instancia = mover ese host.

---

## Qué NO son métodos de mover (aclaraciones)

- `gateway/background-process.md` → tool `exec`/`process`, no mudanza.
- `concepts/managed-worktrees.md` → worktrees git por tarea de agente, feature de ejecución.
- `concepts/channel-docking.md` → `/dock-<channel>` reenvía respuestas de una sesión entre canales; no mueve nada.

---

## Comparación para NUESTRO caso (bots para clientes)

| Estrategia | Portable | Versionable/auditable | Secretos | Cuándo usarla |
|-----------|----------|----------------------|----------|---------------|
| **A. Mudanza (tar/backup)** | Sí, todo-en-uno | ❌ No (blob con secretos) | En claro dentro del tar | Migración puntual de una máquina |
| **B. Git del workspace + config** | Sí, por partes | ✅ Sí | Fuera del repo (SecretRef) | Réplica limpia, portabilidad continua |
| **C. Acceso remoto** | N/A (no mueve) | N/A | Quedan en el central | Un solo Gateway, muchos accesos |
| **D. VPS/cloud** | Sí (es el destino) | Combinable con B | En el servidor / secret manager | **Producción real para clientes** |

**Recomendación para clientes**: la combinación ganadora es **D + B**:
- El Gateway vive en un **VPS** (fuente de verdad, 24/7, no depende de tu laptop).
- La **config/workspace se versiona con git** (estrategia B + [config-management.md](./config-management.md)), secretos vía SecretRef/secret manager.
- Acceso por **Tailscale/SSH** (estrategia C).
- La mudanza total (A) queda como herramienta de **respaldo/DR**, no como el flujo diario.

---

## Fuentes

- `install/migrating.md`, `cli/backup.md`, `cli/migrate.md`, `cli/reset.md`, `cli/uninstall.md`
- `gateway/remote.md`, `gateway/remote-gateway-readme.md`, `gateway/multiple-gateways.md`, `gateway/tailscale.md`, `network.md`, `gateway/pairing.md`, `gateway/discovery.md`, `gateway/bonjour.md`
- `nodes/index.md`, `start/setup.md`, `start/bootstrapping.md`, `vps.md`
- `install/digitalocean.md`, `install/oracle.md`, `install/raspberry-pi.md`, `platforms/linux.md`, `platforms/easyrunner.md`
- Comunidad: docs.openclaw.ai/install/migrating, boxmining.com, techradar.com
