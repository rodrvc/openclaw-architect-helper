# OpenClaw Architect Helper

> **Qué es:** un proyecto **Claude arquitecto de OpenClaw**. Sirve para **construir y
> configurar** instancias de OpenClaw para clientes.
> **Qué NO es:** NO es OpenClaw, NO es un workspace de OpenClaw, NO trabaja como OpenClaw.
> El OpenClaw que funciona vive en `~/.openclaw/` (binario en `/opt/homebrew/`); este repo
> solo lo estudia, documenta y configura.

## Estructura

| Ruta | Contenido |
|------|-----------|
| [`OPENCLAW-KNOWLEDGE-INDEX.md`](./OPENCLAW-KNOWLEDGE-INDEX.md) | Índice maestro de todo el conocimiento |
| [`knowledge/`](./knowledge/) | Base de conocimiento viva de OpenClaw (crece con lo que aprendemos) |
| [`research/`](./research/) | Investigaciones puntuales (ej. plugin WhatsApp imBee) |
| [`issues/`](./issues/) | Pendientes/tareas del proyecto |
| [`.claude/skills/`](./.claude/skills/) | Skills de Claude Code del arquitecto (export/import de config) |

## Skills incluidas

- **`openclaw-config-portable`** (export) — empaqueta config + personalidad ligera de OpenClaw (sin secretos) + genera prompt de traspaso.
- **`openclaw-config-import`** (import) — instala ese paquete en un OpenClaw existente (respalda, pregunta conflictos, aplica tras confirmar).

## Reglas de mantenimiento

1. Toda información relevante de OpenClaw se registra en `knowledge/` (con su fuente).
2. No llenar con info no verificada; agregar a medida que se confirma.
3. Este proyecto es de arquitectura/conocimiento; **no ejecuta OpenClaw**.
4. Nunca versionar secretos (ver `.gitignore`).

> Nota: `openclaw-config-portable/` (el paquete generado) es su propio repo git y está
> excluido de este repo — contiene un `.env` con secretos.
