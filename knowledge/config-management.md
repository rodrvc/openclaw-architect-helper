# OpenClaw — gestión de config: versionado seguro y portable

> Cómo versionar la config de OpenClaw con git, portable a otra máquina, SIN exponer API keys.
> Investigado desde docs locales. Fuentes citadas por línea. Última actualización: 2026-08-08.

---

## ⚠️ Estado real de ESTA máquina (mapeo 2026-08-08)

- `~/.openclaw/` **NO es repo git** (solo `~/.openclaw/workspace/` tiene su propio `.git`).
- **HALLAZGO DE SEGURIDAD**: `openclaw.json` tiene **`gateway.auth.token` en TEXTO PLANO** (no SecretRef). → issue #002.
- **PII en el JSON**: `channels.whatsapp.allowFrom[]` / `groupAllowFrom[]` y `bindings[].match.peer.id` (teléfonos, ID de grupo WhatsApp); `auth.profiles.*.email`.
- Agentes existentes: `main`, `sofia`, `cv` (cada uno con `workspace/` + `agent/`).
- `~/.openclaw/workspace/` ya versiona los archivos de "alma": `AGENTS.md`, `SOUL.md`, `IDENTITY.md`, `USER.md`, `TOOLS.md`, `HEARTBEAT.md`, `MEMORY.md` (revisar PII antes de publicar).
- Otras zonas sensibles presentes: `credentials/whatsapp/default/` (claves Baileys/Signal), `identity/` (device-auth), `devices/`, `service-env/` (env del daemon), `state/openclaw.sqlite`, `memory/*.sqlite`, `browser/.../user-data/` (cookies).

**Regla práctica de mapeo:** tratar `~/.openclaw/` como **"todo NUNCA versionar por defecto"** y hacer **allowlist explícita** solo de estructura no sensible (`openclaw.json` sanitizado + `.md` de workspace). `.gitignore` amplio con excepciones puntuales > lo inverso.

---

## Cómo se edita la config (CLI oficial) — preferir sobre editar JSON a mano

Fuente: `cli/config.md`, `cli/configure.md`.

- **`openclaw configure`** — wizard interactivo (requiere TTY). `--section workspace|model|web|gateway|daemon|channels|plugins|skills|health`.
- **`openclaw config get|set|unset|patch`** — ediciones no interactivas por path (`agents.list[0].id`), valores JSON5.
- **`openclaw config file`** — ruta activa del config. **`openclaw config schema`** — JSON schema. **`openclaw config validate [--json]`** — valida sin arrancar.
- **Validación al escribir**: `set/patch/unset` validan el config completo ANTES de escribir; si falla schema o parece clobber, la config activa **no se toca** y el rechazo va a `openclaw.json.rejected.*`.
- **`--dry-run`** valida (schema + resolvabilidad de SecretRefs) sin escribir. Úsalo como gate antes de commitear.
- Paths protegidos (`agents.list`, `models.providers*`, `plugins.entries`, `auth.profiles`): rechazan borrados salvo `--replace`; usar `--merge` para agregar.
- Tras escribir, la CLI dice si hace falta **reiniciar el gateway** (plugins.entries siempre lo requiere).
- Editar JSON a mano está permitido pero es "no confiable" hasta validar; `openclaw doctor --fix` repara o restaura `.last-good`.
- Mover el token a SecretRef (ejemplo real):
  ```bash
  openclaw config set gateway.auth.token --ref-provider default --ref-source env --ref-id OPENCLAW_GATEWAY_TOKEN
  ```

---

## Dónde vive la config (esta máquina)

- **`~/.openclaw/openclaw.json`** — config principal, formato **JSON5** (comentarios + comas colgantes OK). `docs/gateway/configuration.md:10`.
- OpenClaw hace **backups automáticos**: `.bak`, `.bak.1..4`, `.last-good`, `.pre-update`.
- Config rechazada al validar se guarda como `<path>.rejected.<timestamp>`. `configuration.md:94`.
- **`OPENCLAW_CONFIG_PATH`** — permite tener el config real FUERA de `~/.openclaw` (p.ej. dentro del repo git). Evitar symlinks (las escrituras atómicas reemplazan el target). `configuration.md:12`.
- **`$include`** — partir la config en varios archivos; paths resuelven bajo el dir de `openclaw.json`; para compartir árbol entre máquinas usar `OPENCLAW_INCLUDE_ROOTS`. `configuration.md:498-531`.

---

## Sistema de secretos (no poner keys en el JSON)

Tres mecanismos, de simple a robusto:

### a) Sustitución de env `${VAR}`
Cualquier string del config referencia una env var. `configuration.md:678-696`.
```json5
{ gateway: { auth: { token: "${OPENCLAW_GATEWAY_TOKEN}" } } }
```
Solo MAYÚSCULAS `[A-Z_][A-Z0-9_]*`; var faltante = error al cargar; escape `$${VAR}`; funciona en `$include`.

### b) SecretRef (oficial y recomendado)
Objeto uniforme: `{ source, provider, id }`. `secrets.md:104-155`.
- **env**: `{ source: "env", provider: "default", id: "OPENAI_API_KEY" }` (shorthand `"${OPENAI_API_KEY}"`). `id` ~ `^[A-Z][A-Z0-9_]{0,127}$`.
- **file**: `{ source: "file", provider: "filemain", id: "/providers/openai/apiKey" }` (JSON pointer o `"value"`).
- **exec**: `{ source: "exec", provider: "vault", id: "providers/openai/apiKey#value" }` (1Password `op`, Vault, Bitwarden `bws`, `pass`, `sops`).

Providers bajo `secrets.providers`. `secrets.md:158-198`:
```json5
{
  secrets: {
    providers: {
      default:  { source: "env" },
      filemain: { source: "file", path: "~/.openclaw/secrets.json", mode: "json" },
      vault:    { source: "exec", command: "/usr/local/bin/openclaw-vault-resolver", passEnv: ["PATH","VAULT_ADDR"], jsonOnly: true },
    },
    defaults: { env: "default", file: "filemain", exec: "vault" },
  },
}
```

**Superficie que acepta SecretRef** (`secretref-credential-surface.md:20-136`): `models.providers.*.apiKey`, `channels.telegram.botToken`, `channels.slack.botToken`, `channels.discord.token`, `gateway.auth.token`, `plugins.entries.*.config.webSearch.apiKey`, etc.
**NO soportado** (rotating/OAuth/minted): `auth-profiles.oauth.*`, `channels.whatsapp.creds.json`, `hooks.token`. `:142-154`.

### Seguridad del sistema de secretos
- Resueltos a snapshot en memoria; **fail-fast** si un SecretRef no resuelve. `secrets.md:21-29`.
- Si hay plaintext + ref juntos, gana el ref. `:566`.
- ⚠️ SecretRef reduce blast radius pero **NO es aislamiento de proceso**: un plaintext legible por el agente sigue siendo leíble. Proteger archivos con permisos OS. `secrets.md:17-19,46-61`.

---

## Backup / migración oficial

### `openclaw backup` — `docs/cli/backup.md`
Crea `.tar.gz` con estado, config, auth profiles, **credenciales**, sesiones y (opc.) workspaces.
```bash
openclaw backup create               # todo (SENSIBLE: lleva secretos)
openclaw backup create --only-config # solo el JSON activo (más chico)
openclaw backup create --verify
openclaw backup verify <archive>
```
⚠️ El backup completo **incluye credenciales** → es un archivo sensible, **NO se commitea a git**. `backup.md:11,40`.

### `openclaw migrate` — `docs/cli/migrate.md`
Para importar desde Claude Code / Codex / Hermes. Preview-first, **redacta secretos** en planes. Secretos NO se importan salvo `--include-secrets --yes`. Crea backup antes de aplicar. `:50-52,86,90,95-97`.

### Gestión de secretos — `docs/cli/secrets.md`
```bash
openclaw secrets audit --check   # escanea plaintext/refs sin resolver (exit 1/2)
openclaw secrets configure       # planner: migra plaintext → SecretRef
openclaw secrets apply --from <plan> [--dry-run]
openclaw secrets reload          # re-resuelve refs en runtime
```

---

## Flujo recomendado (versionado portable, secretos fuera)

### `.gitignore`
```gitignore
.env
*.env
secrets.json
secrets/
auth.json
auth-profiles.json
*openclaw-backup.tar.gz
agents/*/agent/*.sqlite*
*.rejected.*
```

### Qué versionar
- **SÍ**: `openclaw.json` + includes (con SecretRefs, no valores), `.env.example`/`secrets.example.json`, `.gitignore`, `README`.
- **NO**: `.env`, `secrets.json`, `auth*.json`, `.sqlite` de agentes, cualquier `*-backup.tar.gz`.

### Estructura de repo
```
openclaw-config/
  openclaw.json      # {source,provider,id} en cada credencial
  agents.json5       # vía $include
  channels.json5     # vía $include
  .env.example       # nombres de vars, SIN valores reales
  .gitignore
  README.md
```

### Máquina origen
1. `openclaw secrets audit --check` → ver plaintext.
2. `openclaw secrets configure` → mapear campos a SecretRef.
3. Repetir audit hasta **"clean"**.
4. Elegir fuente: `env` (personal) o `exec`/Vault/1Password (equipo).
5. Estructurar repo, `OPENCLAW_CONFIG_PATH` al json del repo (o clonar en `~/.openclaw` + `OPENCLAW_INCLUDE_ROOTS`).
6. `git add/commit/push` (tras audit limpio).

### Máquina destino
1. Instalar OpenClaw + `git clone` del repo.
2. `export OPENCLAW_CONFIG_PATH=/ruta/repo/openclaw.json` (+ `OPENCLAW_INCLUDE_ROOTS` si aplica).
3. Re-hidratar secretos FUERA del repo: `.env` desde `.env.example`, o autenticar el gestor (Vault/1Password).
4. Validar: `openclaw secrets audit --check` (0 findings) → `openclaw secrets reload` → `openclaw doctor`.

### Plantillas `.example` (convención)
Usar placeholders **obviamente falsos** (`example-openai-key-not-real`), nunca prefijos que parezcan reales (`sk-…`, `xoxb-…`, `AKIA…`). `secret-placeholder-conventions.md`.

---

## Reglas de oro (transversales)

- El `.tar.gz` de backup **nunca** va a git (contiene credenciales). Solo DR / mudanza puntual por canal seguro.
- SecretRef ≠ aislamiento de proceso → proteger archivos de secretos con permisos OS/contenedor.
- Config con **validación estricta**: claves desconocidas o tipos inválidos impiden el arranque → útil como "test" al portar (`openclaw config validate` / `openclaw doctor --fix`). `configuration.md:71-88`.
- No dar por terminada la migración de secretos hasta que `openclaw secrets audit --check` salga limpio.

---

## Fuentes

- `gateway/secrets.md`, `gateway/configuration.md`, `gateway/configuration-reference.md`
- `reference/secret-placeholder-conventions.md`, `reference/secretref-credential-surface.md`
- `cli/backup.md`, `cli/migrate.md`, `cli/secrets.md`, `cli/config.md`
- `gateway/security/secure-file-operations.md`
