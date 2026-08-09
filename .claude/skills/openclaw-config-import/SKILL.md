---
name: openclaw-config-import
description: Importa un paquete LIGERO de config/personalidad de OpenClaw (creado por openclaw-config-portable) dentro de un OpenClaw YA EXISTENTE en la máquina actual. Detecta conflictos con la config existente y PREGUNTA al usuario (merge vs reemplazar) caso a caso; respalda con el backup oficial antes; prepara el plan y NO aplica hasta que el usuario confirme. Úsalo cuando el usuario quiera instalar, agregar, importar o aplicar un backup ligero de config a un OpenClaw existente. Dispara con frases como "importar la config ligera", "agregar esta configuración a mi OpenClaw", "instalar el backup ligero", "aplicar el handoff", "traer la personalidad a este proyecto".
---

# OpenClaw Config Import

Instala un paquete ligero (de `openclaw-config-portable`) en un OpenClaw **ya existente**,
sin pisar a ciegas lo que la máquina destino ya tiene. Es la mitad **import** del flujo
export↔import. Respalda antes, detecta conflictos, pregunta, y aplica solo tras confirmación.

## Cuándo usarlo

- El usuario tiene un paquete portable (`openclaw.json` sanitizado + `workspace/*.md` + `HANDOFF.md`)
  y quiere aplicarlo a un OpenClaw que ya corre en esta máquina.
- Diferencia con export: **export** = crear el paquete; **import** (este) = instalarlo.

## Principios (no negociables)

- **Respaldar SIEMPRE antes de tocar nada** (backup oficial completo).
- **Preguntar en cada conflicto**: nunca borrar config existente sin confirmación.
- **Preparar y mostrar el plan; NO aplicar hasta que el usuario apruebe** el paso final.
- **Nunca escribir valores de secretos** en archivos versionados; los secretos van a `.env`/secret store.

## Procedimiento

### Paso 0 — Localizar paquete y destino
- Paquete origen: pedir la ruta (contiene `openclaw.json`, `workspace/`, `.env.example`, `HANDOFF.md`).
- Destino: state dir del OpenClaw local (`~/.openclaw/` o `OPENCLAW_STATE_DIR`/`--profile`).
- Leer el `HANDOFF.md` del paquete para conocer agentes, canales y env vars requeridas.

### Paso 1 — RESPALDO oficial completo (antes de todo)
```bash
openclaw backup create --verify
```
Confirmar que el backup quedó bien. Este es el punto de retorno si algo sale mal.
(Es el backup OFICIAL — pesado, con secretos; guardarlo seguro, no en git.)

### Paso 2 — Diff entre paquete y config existente
Comparar `paquete/openclaw.json` contra `~/.openclaw/openclaw.json` a nivel de:
- **Agentes** (`agents.list[]`): cuáles son nuevos, cuáles ya existen (por `id`).
- **Canales** (`channels.*`): nuevos vs existentes.
- **Bindings** (`bindings[]`).
- **Personalidad** (`workspace/*.md`): archivos nuevos vs archivos que ya existen (se sobrescribirían).
- **Memoria/skills**: nuevos vs colisiones.

Presentar un resumen claro: "N agentes nuevos, M en conflicto; estos .md se sobrescribirían".

### Paso 3 — PREGUNTAR por cada conflicto
Para cada colisión (un `id` de agente, un canal, un `.md` que ya existe), preguntar al usuario:
- **Merge/mantener ambos** (cuando aplique),
- **Reemplazar** (usar la versión del paquete),
- **Omitir** (dejar la del destino).
No asumir; el usuario decide caso a caso. Registrar las decisiones en un plan.

### Paso 4 — Secretos (env vars)
- Leer `.env.example` del paquete → lista de env vars requeridas (ej. `OPENCLAW_GATEWAY_TOKEN`).
- Verificar si ya están en `~/.openclaw/.env` del destino. Si faltan, **pedir los valores al
  usuario** y escribirlos SOLO en `~/.openclaw/.env` (fuera de git). Nunca inventarlos.

### Paso 5 — Construir el PLAN y mostrarlo (NO aplicar aún)
Componer el resultado en un archivo temporal / dry-run, y mostrar al usuario:
- Qué agentes/canales/bindings se agregan o cambian.
- Qué archivos de workspace se copian/sobrescriben.
- Qué env vars se necesitan.
- El resultado de la validación:
  ```bash
  openclaw config validate            # sobre el JSON resultante propuesto
  openclaw config patch --stdin --dry-run < plan.json5   # si se aplica por patch
  openclaw secrets audit --check
  ```
- **Detenerse aquí.** Pedir confirmación explícita antes del paso 6.

### Paso 6 — Aplicar (solo tras confirmación del usuario)
Preferir la vía validada de la CLI sobre editar el JSON a mano:
```bash
# ejemplo: aplicar cambios de config por patch (ya validado en dry-run)
openclaw config patch --stdin < plan.json5
```
Copiar los archivos de workspace aprobados a `~/.openclaw/workspace/`.
Luego:
```bash
openclaw secrets audit --check     # 0 findings
openclaw doctor && openclaw gateway restart && openclaw status
```

### Paso 7 — Canales con credenciales propias
Los canales que usan credenciales (ej. WhatsApp) **no llegan en el paquete ligero** →
re-parear: `openclaw channels login --channel whatsapp` (QR). Avisar que es esperado.

### Paso 8 — Verificación final
- `openclaw status` muestra los agentes esperados.
- Confirmar con el usuario que la personalidad/config quedó como deseaba.
- Si algo falla: restaurar desde el backup del paso 1 (extraer el `.tgz` + `openclaw doctor`).

## Reglas de seguridad

- NUNCA aplicar sin el backup del paso 1 hecho y verificado.
- NUNCA sobrescribir config/personalidad existente sin preguntar (paso 3).
- NUNCA escribir secretos en archivos versionados; solo en `~/.openclaw/.env` o secret store.
- Si `openclaw secrets audit --check` marca plaintext tras aplicar, avisar al usuario.
- Confirmar explícitamente antes del paso 6 (aplicar).

## Relación con el otro skill

- **`openclaw-config-portable`** (export): crea el paquete ligero + `HANDOFF.md`.
- **`openclaw-config-import`** (este): instala ese paquete en un OpenClaw existente.
- Para restauración total de una instancia (DR), usar el backup OFICIAL completo
  (`openclaw backup create` → extraer + `openclaw doctor`), no este flujo ligero.

## Referencia

Base de conocimiento del arquitecto en el repo /openclaw:
`knowledge/config-management.md`, `knowledge/moving-openclaw.md`.
