# Issue #001 — Buscar skill de tipo "construcción de agente OpenClaw"

**Estado:** abierto
**Prioridad:** alta
**Creado:** 2026-08-08

## Descripción

Debemos buscar una **skill de construcción/configuración de agentes de OpenClaw** —
algo que sistematice cómo un arquitecto (este proyecto) crea y configura agentes
OpenClaw para clientes, en vez de armar cada uno a mano.

## Objetivo

Encontrar (o, si no existe, definir la necesidad de crear) una skill que cubra:

- Crear un agente por negocio (workspace, modelo, system prompt).
- Conectar el canal correcto (QR / BSP imBee / Cloud API) según la fase.
- Configurar memoria por número, bindings ACP, access control.
- Buenas prácticas de reconexión y robustez para producción.

## Dónde buscar

- [ ] Skills locales de Claude Code (`find-skills`, listado de skills disponibles).
- [ ] ClawHub — `openclaw plugins search "agent"` / skills de OpenClaw.
- [ ] Docs OpenClaw: `plugins/`, `concepts/multi-agent.md`, `start/wizard.md`.
- [ ] GitHub del proyecto OpenClaw.

## Resultado esperado

- Referencia a la skill si existe, **o**
- Decisión de construir una skill/plantilla propia de "arquitecto OpenClaw" en este repo.

## Notas

- Relacionado con la nota de `knowledge/openclaw.md` → sección "Pendiente por confirmar / aprender".
