# OpenClaw — proyectos locales + config cómoda + disponibilidad 24/7

> Cómo resolver la tensión: el Gateway toca solo la máquina donde corre, pero
> queremos proyectos locales + editar config en local + disponibilidad.
> Investigado desde docs locales. Fuentes por ruta. 2026-08-08.

---

## Hechos base (confirmados)

- **NO usa Redis.** El estado canónico es **SQLite + archivos** (`node:sqlite`; por eso no corre en Bun). No hay backend externo que apuntar a otra máquina. Personalidad = archivos Markdown; config = `openclaw.json`; estado = SQLite local.
- **El Gateway y sus file tools (`write`/`edit`/`apply_patch`) SOLO tocan la máquina donde corre el Gateway.** El workspace vive en el host del Gateway. Fuente: `concepts/agent-workspace.md:10-11,126`.
- **Node host**: un node en otra máquina puede ejecutar `system.run`/`system.which` (shell) — pero **solo shell**. Las file tools nativas NO se enrutan a un node. `nodes/index.md:58-66,148-165`; `tools/exec.md:71` ("`exec host=node` is the only shell-execution path for nodes").

➡️ Consecuencia: **"proyectos locales + config local"** y **"Gateway en VPS 24/7"** tiran en direcciones opuestas. No hay opción perfecta; hay que elegir según prioridad.

---

## Mover personalidad/config "fácil" (sin Redis)

La personalidad **ya es fácil de mover** — son archivos de texto, se versionan con git:

| Qué | Dónde | Versionable |
|-----|-------|-------------|
| Personalidad (SOUL/AGENTS/USER/IDENTITY.md) | `~/.openclaw/workspace/*.md` | ✅ git |
| Config estructural | `openclaw.json` | ✅ (secretos en SecretRef) |
| Memoria | `MEMORY.md`, `memory/*.md` | ✅ git |
| Sesiones/estado | SQLite | ❌ estado vivo |
| Credenciales | `credentials/`, auth | ⚠️ nunca versionar |

El `~/.openclaw/workspace/` **ya es un repo git** en esta máquina. Ese es el mecanismo "fácil": git, no Redis. Ver [config-management.md](./config-management.md) y [moving-openclaw.md](./moving-openclaw.md).

---

## Las arquitecturas reales

### A. Gateway en el Mac, always-on (expuesto por Tailscale) ⭐ para dev/config local
- Gateway local + **launchd** (se reinicia solo). Expuesto por **Tailscale Serve** (`bind: loopback`, `tailscale.mode: serve`) o túnel SSH.
- **Pros**: file tools nativas + `exec` directos sobre `~/projects`; config y workspace locales, edición trivial; sin doble salto.
- **Contra**: "always-on" limitado a que el Mac **no duerma/apague**. launchd reinicia pero no despierta un Mac dormido. Hay que configurar no-sleep (o Mac mini dedicado).
- Fuentes: `gateway/remote.md:19-25`, `platforms/macos.md:41-48`, `gateway/tailscale.md:27-36`.

### B. Gateway en VPS 24/7 + node host en el Mac
- Gateway en VPS; `openclaw node run/install` en el Mac; `tools.exec.host=node`, `tools.exec.node=<mac>`; misma tailnet.
- **Pros**: disponibilidad real 24/7; proyectos locales accesibles vía `exec host=node`.
- **Contra**: **solo shell** llega al Mac; `write/edit/apply_patch` y workspace nativo siguen en el VPS. Approvals por node; node debe estar encendido y pareado.
- Fuentes: `nodes/index.md:58-66,148-165,418-489`, `tools/exec.md:71`.

### C. Gateway en VPS + config editada en local (git / CLI remota)
- Editar `openclaw.json`/workspace en local y aplicar al VPS:
  - **CLI por SSH** con hot reload: `ssh user@vps 'openclaw config patch --stdin' < patch.json5` (`cli/config.md:258-263`; hot reload `gateway/configuration.md:534-586`).
  - **`OPENCLAW_CONFIG_PATH`** apuntando a un archivo en un repo (no symlink) (`gateway/configuration.md:12`).
  - **git workflow del workspace**: editar local → `git push` → `git pull` en VPS (`concepts/agent-workspace.md:122-222`).
  - **Control UI remoto** (pestaña Config) vía Tailscale/SSH.
- ⚠️ No hay sync automático local↔VPS documentado; el `git pull` en el VPS es manual.

### D. Gateway en desktop de casa siempre encendido
- Si tus proyectos vivieran en ese desktop: always-on real + file tools nativas. No aplica si los proyectos están en el laptop.

---

## Recomendación (según prioridad)

**Separar dos usos distintos en dos Gateways:**

1. **Asistente de desarrollo** (toca `~/projects`, editas config cómodo)
   → **Opción A: Gateway en tu Mac** + Tailscale + no-sleep. Gana proyectos locales + config fácil.

2. **Bots de clientes** (WhatsApp 24/7 para llanterías/escuelas)
   → **Opción D(VPS) + B**: Gateway(s) en VPS, fuente de verdad 24/7, config versionada con git. No necesita tus proyectos locales.

**La personalidad/config se mueve entre ambos con git** (Markdown + `openclaw.json` + SecretRef). Eso es lo "fácil de mover" — sin Redis.

### Si insistes en UN solo Gateway
- Priorizas **dev/config local** → A (Mac always-on).
- Priorizas **24/7 para clientes** → B+C (VPS + node local, aceptando que el Mac se toca por shell y la config se sincroniza por git/SSH manual).

---

## Advertencias de la doc

- Bind no-loopback exige auth (token/password); hosts públicos exigen `wss://`. `gateway/remote.md:119-134`.
- Pareo de node + `system.run` requieren approval explícito y allowlist por node. `nodes/index.md:38-41,138-145`.
- No hay sincronización automática config/workspace local↔VPS; git pull en VPS es manual.

## Fuentes

- `concepts/agent-workspace.md`, `nodes/index.md`, `tools/exec.md`, `tools/code-execution.md`
- `gateway/remote.md`, `gateway/tailscale.md`, `gateway/configuration.md`, `cli/config.md`
- `platforms/macos.md`, `concepts/managed-worktrees.md`
