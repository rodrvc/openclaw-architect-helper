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

### Paso 1 — Auditar secretos ANTES de empaquetar (GATE BLOQUEANTE — HARD STOP)

El `openclaw.json` puede tener secretos en texto plano (ej. `gateway.auth.token`) y PII
(teléfonos en `channels.whatsapp.allowFrom`, `auth.profiles.*.email`).

```bash
openclaw secrets audit --check   # exit 0 = limpio; 1 = plaintext; 2 = refs sin resolver
```

**Este paso es un GATE, no una advertencia.** Evalúa el exit code ANTES de tocar el Paso 2:

- **`exit 0`** → limpio, puedes continuar al Paso 2 copiando `openclaw.json` tal cual.
- **`exit != 0`** (1 = plaintext, 2 = refs sin resolver) → **DETENTE AQUÍ.** Está PROHIBIDO
  ejecutar `cp ~/.openclaw/openclaw.json` en el Paso 2 mientras el audit no salga limpio.
  No hay excepción "solo por esta vez" ni "ya avisé al usuario": si el JSON tiene un secreto
  en claro, NO se empaqueta el original, punto. Ve al Paso 1.1 para sanitizar una COPIA.

Este gate existe porque un agente apurado podría auditar, ver plaintext, y copiar igual
"solo con una advertencia" — eso es exactamente lo que causó el issue #002
(`gateway.auth.token` en texto plano llegó a versionarse). No repitas ese error.

#### Paso 1.1 — Sanitizar la COPIA (solo si el audit falló)

**Nunca edites el `openclaw.json` original del state dir.** Trabaja siempre sobre una copia
en el directorio de salida, reemplazando las claves sensibles conocidas por SecretRefs
(`${ENV_VAR}`) y moviendo el valor real a un `.env` fuera de git.

```bash
OUT=./openclaw-config-portable
mkdir -p "$OUT/workspace"
cp ~/.openclaw/openclaw.json "$OUT/openclaw.json"   # copia de trabajo, se sanitiza en el mismo lugar
```

Sanitiza la copia con un script inline de `python3` (lee el JSON, reemplaza las claves
sensibles conocidas por su referencia de env var, y escribe el valor real aparte en un
`.env` gitignored — nunca en el JSON versionado):

```bash
python3 - "$OUT/openclaw.json" "$OUT/.env" <<'PYEOF'
import json, sys

json_path, env_path = sys.argv[1], sys.argv[2]

with open(json_path) as f:
    cfg = json.load(f)

# Mapa: ruta punteada dentro del JSON -> nombre de env var a usar como SecretRef.
# Ampliar esta lista si `openclaw secrets audit --check` reporta otras claves en claro.
SENSITIVE_KEYS = {
    ("gateway", "auth", "token"): "OPENCLAW_GATEWAY_TOKEN",
}

def get_in(d, path):
    for k in path:
        if not isinstance(d, dict) or k not in d:
            return None
        d = d[k]
    return d

def set_in(d, path, value):
    for k in path[:-1]:
        d = d.setdefault(k, {})
    d[path[-1]] = value

secrets_found = {}
for path, env_name in SENSITIVE_KEYS.items():
    value = get_in(cfg, path)
    if isinstance(value, str) and value and not value.startswith("${"):
        secrets_found[env_name] = value
        set_in(cfg, path, "${%s}" % env_name)

with open(json_path, "w") as f:
    json.dump(cfg, f, indent=2)
    f.write("\n")

if secrets_found:
    with open(env_path, "a") as f:
        for env_name, value in secrets_found.items():
            f.write(f"{env_name}={value}\n")
    print(f"Sanitizados {len(secrets_found)} secreto(s) -> {env_path} (NO versionar este archivo)")
else:
    print("No se encontraron valores en claro para las claves conocidas; revisa el audit manualmente.")
PYEOF
```

Alternativa equivalente con `jq` si se prefiere evitar python3 (solo cubre `gateway.auth.token`;
para más claves, repetir el patrón):

```bash
TOKEN=$(jq -r '.gateway.auth.token' "$OUT/openclaw.json")
if [ -n "$TOKEN" ] && [ "$TOKEN" != "null" ] && [[ "$TOKEN" != '${'* ]]; then
  jq '.gateway.auth.token = "${OPENCLAW_GATEWAY_TOKEN}"' "$OUT/openclaw.json" > "$OUT/openclaw.json.tmp" \
    && mv "$OUT/openclaw.json.tmp" "$OUT/openclaw.json"
  echo "OPENCLAW_GATEWAY_TOKEN=$TOKEN" >> "$OUT/.env"
fi
```

Después de sanitizar, **re-corre el audit sobre la copia** antes de seguir:
```bash
openclaw secrets audit --check --config "$OUT/openclaw.json"
```
Si sigue marcando plaintext (p. ej. otra clave no cubierta por `SENSITIVE_KEYS`), añade esa
clave al mapa y repite. NO avances al Paso 3 hasta que este audit sobre la copia salga limpio.

Registra en `$OUT/.env.example` los NOMBRES de las env vars usadas (sin valores reales — ver
Paso 2). El `$OUT/.env` con los valores reales NUNCA se versiona (ya está en `.gitignore`,
ver Paso 2).

### Paso 2 — Crear el paquete portable
Si el audit del Paso 1 salió limpio directamente (exit 0), crea el directorio de salida y
copia lo ligero (incluido `openclaw.json` tal cual, sin pasar por el Paso 1.1):

```bash
OUT=./openclaw-config-portable
mkdir -p "$OUT/workspace"
cp ~/.openclaw/openclaw.json "$OUT/openclaw.json"
# archivos de personalidad y memoria (los que existan):
cp ~/.openclaw/workspace/*.md "$OUT/workspace/" 2>/dev/null || true
cp -R ~/.openclaw/workspace/memory "$OUT/workspace/memory" 2>/dev/null || true
cp -R ~/.openclaw/workspace/skills "$OUT/workspace/skills" 2>/dev/null || true
```

Si en cambio el audit falló y pasaste por el Paso 1.1, `$OUT/openclaw.json` YA es la copia
sanitizada (no la vuelvas a copiar desde `~/.openclaw/`, la sobrescribirías con la versión en
claro). Solo copia el resto:

```bash
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

### Paso 3 — Revisar PII (advertir y ofrecer sanitizar, no es un gate automático)

`openclaw secrets audit --check` audita **secretos** (tokens, API keys), no PII. La PII no
hace fallar el audit pero igual es sensible — revísala explícitamente antes de versionar:

- `auth.profiles.*.email` en `openclaw.json` → email del usuario.
- `channels.whatsapp.allowFrom[]` / `groupAllowFrom[]` en `openclaw.json` → teléfonos.
- `bindings[].match.peer.id` en `openclaw.json` → teléfonos / ID de grupo WhatsApp.
- `USER.md` / `MEMORY.md` → puede contener nombre completo, email, teléfono, dirección, etc.

Detecta rápido con grep sobre la copia ya sanitizada (no el original):
```bash
grep -nE '"email"\s*:|allowFrom|groupAllowFrom|peer' "$OUT/openclaw.json"
grep -nEi '[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}|\+?[0-9]{8,}' "$OUT/workspace"/*.md 2>/dev/null
```

Si encuentras PII y el destino es un repo compartido (o público):
- **Ofrece sanitizar** antes de continuar — no lo hagas en silencio ni lo dejes pasar sin
  preguntar. Opciones a proponer al usuario:
  - Reemplazar el valor por un placeholder obvio en la copia (`"email": "user@example.com"`,
    `"allowFrom": ["+00000000000"]`).
  - Extraer la PII a un archivo no versionado (`workspace/private.md` o similar) referenciado
    vía `$include` desde el `.md`/JSON principal, y añadirlo al `.gitignore`.
- Si el usuario confirma que el repo es privado y de un solo dueño, puedes dejar la PII tal
  cual, pero deja constancia en `HANDOFF.md` de qué PII quedó incluida.
- A diferencia del Paso 1 (secretos), este paso **no aborta automáticamente** el empaquetado —
  requiere una decisión del usuario. Pero no omitas la advertencia: preguntar es obligatorio.

### Paso 4 — Verificar e inicializar git
```bash
cd "$OUT" && git init -q && git add -A && git status
```
Confirma que NO se coló ningún secreto: `.env` no debe aparecer en `git status` (lo bloquea
el `.gitignore` del Paso 2), y `grep` sobre `git diff --cached -- openclaw.json` no debe
mostrar valores en claro para las `SENSITIVE_KEYS` del Paso 1.1 — solo `${ENV_VAR}`.

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
