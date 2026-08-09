---
name: openclaw-config-portable
description: Prepara un paquete LIGERO y portable de la configuración y personalidad de un OpenClaw (openclaw.json + archivos .md del workspace + memoria), sin secretos, y genera un prompt de traspaso para que el próximo agente sepa cómo instalarlo en una máquina nueva. Úsalo cuando el usuario quiera mover, versionar, replicar o migrar la config/personalidad de OpenClaw entre computadoras sin copiar el state directory completo (.tgz gigante). Dispara con frases como "pasar mis configuraciones a otra compu", "mover la personalidad de OpenClaw", "versionar la config", "migrar OpenClaw ligero", "handoff de config".
---

# OpenClaw Config Portable

Empaqueta SOLO lo que define la config y personalidad de un OpenClaw (kilobytes de texto),
NO el state directory completo con sesiones/credenciales/SQLite. Deja los secretos fuera y
genera un prompt de traspaso para el agente que instalará todo en la máquina destino.

## Cuándo usarlo

- El usuario quiere llevar su config/personalidad de OpenClaw a otra computadora.
- Quiere versionar la config con git de forma sostenible (no mover el proyecto gigante).
- Necesita replicar la personalidad de un agente en varias máquinas.

## Qué SÍ se empaqueta (ligero, versionable)

| Fuente | Qué es |
|--------|--------|
| `~/.openclaw/openclaw.json` | Config: agentes, canales, bindings, plugins |
| `~/.openclaw/workspace/*.md` | Personalidad: `SOUL.md`, `AGENTS.md`, `USER.md`, `IDENTITY.md`, `TOOLS.md`, `HEARTBEAT.md` |
| `~/.openclaw/workspace/MEMORY.md` + `memory/` | Memoria |
| `~/.openclaw/workspace/skills/` | Skills propias del workspace (si existen) |

## Qué NUNCA se empaqueta

- `credentials/` (auth WhatsApp/Baileys, oauth) — secretos.
- `identity/`, `devices/`, `service-env/` — identidad/tokens del device.
- `*.sqlite*`, `state/`, `memory/*.sqlite`, sesiones — estado vivo, no config.
- `openclaw.json.bak*`, `.last-good`, `.pre-update` — copias con el token en claro.
- Cualquier `*-backup.tar.gz`, logs, media, tmp.

## Procedimiento

### Paso 0 — Ubicar la instancia
Confirma la ruta del state dir (default `~/.openclaw/`, o `OPENCLAW_STATE_DIR`/`--profile`).
Verifica que existe `openclaw.json` y `workspace/`.

### Paso 1 — Auditar secretos ANTES de empaquetar
El `openclaw.json` puede tener secretos en texto plano (ej. `gateway.auth.token`) y PII
(teléfonos en `channels.whatsapp.allowFrom`, `auth.profiles.*.email`).

```bash
openclaw secrets audit --check   # exit 0 = limpio; 1 = plaintext; 2 = refs sin resolver
```

Si hay plaintext, NO empaquetes el JSON tal cual. Propón moverlo a SecretRef primero:
```bash
openclaw config set gateway.auth.token --ref-provider default --ref-source env --ref-id OPENCLAW_GATEWAY_TOKEN --dry-run
```
Registra los nombres de las env vars necesarias para el `.env.example` (sin valores).

### Paso 2 — Crear el paquete portable
Crea un directorio de salida (por defecto un repo git) y copia SOLO lo ligero:

```bash
OUT=./openclaw-config-portable
mkdir -p "$OUT/workspace"
cp ~/.openclaw/openclaw.json "$OUT/openclaw.json"
# archivos de personalidad y memoria (los que existan):
cp ~/.openclaw/workspace/*.md "$OUT/workspace/" 2>/dev/null || true
cp -R ~/.openclaw/workspace/memory "$OUT/workspace/memory" 2>/dev/null || true
cp -R ~/.openclaw/workspace/skills "$OUT/workspace/skills" 2>/dev/null || true
```

Crea el `.gitignore` (defensa en profundidad):
```gitignore
.env
*.env
secrets.json
secrets/
auth.json
auth-profiles.json
*openclaw-backup.tar.gz
*.sqlite*
*.bak
*.bak.*
*.last-good
*.pre-update
*.rejected.*
credentials/
identity/
devices/
```

Crea `.env.example` con los NOMBRES de las env vars detectadas en el paso 1 (placeholders
obviamente falsos, nunca prefijos reales tipo `sk-`/`xoxb-`):
```
OPENCLAW_GATEWAY_TOKEN=example-token-not-real
```

### Paso 3 — Revisar PII
Antes de versionar, revisa `openclaw.json` y `USER.md`/`MEMORY.md` por PII (teléfonos, emails).
Si el destino es un repo compartido, considera mover la PII a un `$include` no versionado o placeholders.

### Paso 4 — Verificar e inicializar git
```bash
cd "$OUT" && git init -q && git add -A && git status
```
Confirma que NO se coló ningún secreto (revisa `git status` y el diff).

### Paso 5 — Generar el PROMPT DE TRASPASO
Escribe `$OUT/HANDOFF.md` con el prompt para el próximo agente (ver plantilla abajo).
Rellena las variables reales (agentes, canales, env vars).

## Plantilla del prompt de traspaso (HANDOFF.md)

```markdown
# Handoff: instalar esta config de OpenClaw en una máquina nueva

Eres un agente instalando una configuración PORTABLE de OpenClaw. Este paquete contiene
SOLO config + personalidad (sin secretos ni sesiones). Tu trabajo: dejar OpenClaw
funcionando con esta config en la máquina actual.

## Contexto del paquete
- Agentes definidos: <LISTA_AGENTES>
- Canales configurados: <LISTA_CANALES>
- Secretos requeridos (env vars, valores NO incluidos): <LISTA_ENV_VARS>

## Pasos
1. Instala OpenClaw (CLI + Node; NO Bun — falta node:sqlite) si no está.
2. Copia los archivos del paquete al state dir:
   - `openclaw.json` → `~/.openclaw/openclaw.json`
   - `workspace/*.md`, `workspace/memory/`, `workspace/skills/` → `~/.openclaw/workspace/`
3. Re-hidrata los secretos FUERA del repo: crea `~/.openclaw/.env` a partir de
   `.env.example` con los valores reales (pídeselos al usuario; NUNCA los inventes).
4. Valida: `openclaw secrets audit --check` (0 findings) y `openclaw config validate`.
5. Arranca: `openclaw doctor && openclaw gateway restart && openclaw status`.
6. Re-parea los canales que usan credenciales propias (ej. WhatsApp QR): las credenciales
   NO viajan en este paquete por seguridad, así que WhatsApp pedirá re-escanear el QR.

## Reglas
- NO pidas ni escribas valores de secretos en archivos versionados.
- Si `secrets audit` marca plaintext, detente y avisa al usuario antes de continuar.
- Confirma cambios destructivos con el usuario antes de aplicarlos.
```

## Notas importantes

- **WhatsApp por QR se re-parea** en la máquina nueva: las credenciales (`credentials/`)
  NO viajan por seguridad. Es esperado, no un error.
- Este skill produce un paquete **ligero** (KB de texto), no el `.tgz` del state dir completo.
  Para mudanza total con sesiones/credenciales incluidas, ese es otro flujo (tar del state dir).
- Preferir editar config vía `openclaw config set/patch --dry-run` (valida antes de escribir).
- Referencia de fondo: la base de conocimiento del arquitecto en el repo /openclaw
  (`knowledge/config-management.md`, `knowledge/moving-openclaw.md`, `knowledge/local-vs-remote-gateway.md`).
