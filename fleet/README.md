# `fleet/` — flota como código

Herramienta para **exportar, aplicar y verificar** una instancia de OpenClaw
como archivos versionables. Sirve para mudar una flota a otra máquina, replicarla
para un cliente, o detectar que la instancia viva se desvió de lo versionado.

Probado contra OpenClaw `2026.7.1-2`.

---

## Separación pública / privada — léelo antes de usarlo

Son **dos repos distintos** y confundirlos filtra datos personales:

| | Repo público (este) | Repo privado de la flota |
|---|---|---|
| Qué contiene | los scripts `fleet/*.sh` y plantillas genéricas | la exportación real: `fleet.json`, workspaces, crons |
| Datos personales | **ninguno** — ni teléfonos, ni JIDs, ni rutas absolutas | sí: números, grupos, nombres, rutas |
| Visibilidad | público | **privado, siempre** |

`export.sh --out <dir>` escribe **siempre** en el repo privado. Este repo solo
guarda la herramienta. Antes de commitear aquí:

```bash
grep -rnE "@g\.us|120363|AIza|sk-[A-Za-z0-9]{10}" fleet/   # debe salir vacío
```

Una exportación **no es publicable** aunque el escaneo de secretos pase: no
contiene tokens, pero sí contiene PII (teléfonos en `allowFrom`, JIDs de grupo
en `bindings`, mensajes de cron).

---

## Uso

```bash
# 1. Exportar la instancia viva al repo privado (solo lectura)
fleet/export.sh --out ~/projects/<tu-repo-de-flota>

# 2. Aplicar esa flota a otra instancia
fleet/bootstrap.sh --fleet ~/projects/<tu-repo-de-flota>

# 3. Comprobar que instancia y flota coinciden
fleet/verify.sh --fleet ~/projects/<tu-repo-de-flota>
```

Los tres respetan `OPENCLAW_STATE_DIR` y `OPENCLAW_CONFIG_PATH`, así que se
pueden apuntar a una instancia de prueba sin tocar la real:

```bash
OPENCLAW_STATE_DIR=$HOME/oc-test OPENCLAW_CONFIG_PATH=$HOME/oc-test/openclaw.json \
  fleet/bootstrap.sh --fleet ~/projects/<flota> --skip-plugins --crons-file
```

Todos aceptan `--help`. `bootstrap.sh` acepta `--dry-run`.

### Opciones que importan

| Flag | Para qué |
|---|---|
| `export.sh --with-memory` | incluye `memory/` (por defecto **no**: son notas personales) |
| `bootstrap.sh --skip-plugins` | no instala plugins (evita un `npm install` repetido) |
| `bootstrap.sh --crons-file` | escribe el store de cron directo, **solo instancias de prueba** |
| `bootstrap.sh --dry-run` | imprime sin escribir nada |

---

## Formato de `<fleet>/`

| Archivo | Contenido |
|---|---|
| `fleet.json` | `agents`, `bindings`, `session`, `tools`, `acp`, `messages`, `skills`, `hooks` y `plugins.entries` reducido a `{enabled, config}` |
| `channels.json` | solo política: `dmPolicy`, `allowFrom`, `groupPolicy`… (nunca credenciales) |
| `agents/<id>/` | los `.md` del workspace + `skills/`, `people/`, `study/`, `projects/`, `bin/` |
| `crons.json` | jobs reducidos a los campos que acepta `openclaw cron add` |
| `exec-approvals.json` | allowlist por agente (**sin** el `socket.token`) |
| `plugins.json` | plugins no-bundled, con su spec npm real para `plugins install` |
| `manifest.json` | versión de openclaw, fecha, hostname, lista de agentes |

**Nunca se exporta**: `auth`, `gateway`, `channels` (credenciales), `meta`,
`wizard`, ni ninguna clave cuyo nombre matchee `/key|token|secret|password|credential/i`
**cuyo valor sea un string**. (La condición del string es deliberada:
`skills.entries["1password"]` matchea el patrón pero su valor es un objeto de
configuración, y borrarlo perdería config real.)

Las rutas bajo `$HOME` se guardan como `~/…` y se expanden al aplicar.

**Se excluye del workspace**: `.git`, `.openclaw`, `*.bak*`, `media/`,
`outputs/`, `node_modules/`, `openclaw-workspace-state.json`, `memory/` (salvo
`--with-memory`), y todo archivo > 1 MB. Esto es lo que baja un workspace de
145 MB a ~700 KB. De `queue/` se guarda solo la estructura de directorios.

Cada `export.sh` termina con un **escaneo de secretos** obligatorio sobre el
directorio exportado; si encuentra algo, falla y no deja commitear.

---

## Limitaciones

- **Los logins no viajan.** Ni OAuth, ni API keys, ni la sesión de WhatsApp. Son
  pasos manuales: los lista `CHECKLIST.md`, que `bootstrap.sh` imprime al final.
- **Un número de WhatsApp vive en una sola instancia.** Apaga el gateway viejo
  *antes* de escanear el QR en el nuevo, o los dos se pelean la sesión.
- **Agentes con `sandbox.mode` requieren docker** en la máquina destino;
  `bootstrap.sh` avisa si falta.
- **`cron add` y `approvals allowlist add` necesitan un gateway vivo.** Sin él,
  `bootstrap.sh` corta por timeout y sugiere `--crons-file` (que escribe el
  store directamente y es solo para pruebas); la allowlist cae automáticamente a
  escribir el archivo.
- **Las rutas son relativas a `$HOME`.** Un workspace fuera de `$HOME` se exporta
  con su ruta absoluta y no será portable.
- **`bootstrap.sh` re-enraiza los workspaces** al state dir destino. Sin esto,
  aplicar una flota a una instancia de prueba escribiría sobre los workspaces de
  producción, porque las rutas guardadas apuntan al state dir original. Si un
  workspace queda fuera del state dir destino, se salta con un aviso.
- **`check-prompt-budget.sh` falla a propósito en instancias de prueba**: exige
  que los workspaces estén bajo `~/.openclaw/` (regla 0 del repo). `verify.sh`
  lo distingue y no lo cuenta como error cuando el state dir no es el real.
- **OpenClaw migra `exec-approvals.json` y `cron/jobs.json` a SQLite** y renombra
  los archivos a `*.migrated`. `export.sh` lee la allowlist por CLI
  (`openclaw approvals get --json`) y cae a `.migrated` si hace falta; `verify.sh`
  acepta ambos nombres del store de cron. Si ves `allowlist 0 patterns` en una
  instancia que sí tenía allowlist, es esto.
- `verify.sh` compara **configuración**, no contenido de workspaces.

---

## Plantillas

`templates/` trae `SOUL.md`, `AGENTS.md` y `PROJECT.md` genéricos para arrancar
un agente nuevo. Son plantillas: reemplaza los `<placeholders>`.
