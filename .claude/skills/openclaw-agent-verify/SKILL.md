---
name: openclaw-agent-verify
description: Verifica que un agente OpenClaw quedó bien configurado (binding, canal, grupo, workspace, personalidad, lockdown) y mantiene el mapa del equipo — qué agente es quién, con qué grupo o número habla y para qué. Úsalo después de montar un agente nuevo con openclaw-agent-build, cuando un agente "no responde" o "responde el que no es", antes de mandar un mensaje y no saber a qué grupo va, o como chequeo periódico de salud del equipo. Dispara con frases como "revisa que el agente quedó bien", "verifica la configuración de los agentes", "a qué grupo está conectado X", "quién es cada agente", "el bot no me responde", "me contesta otro agente".
---

# OpenClaw Agent Verify — auditoría y mapa del equipo

Dos cosas que hacen falta cada vez que se monta un agente y nunca están a mano:

1. **¿Quedó bien configurado?** — binding, canal, workspace, personalidad, blindaje.
2. **¿Quién es quién?** — qué grupo es cuál, con quién habla cada agente y para qué.

Este skill resuelve ambas. Complementa a `openclaw-agent-build` (que monta) verificando
que lo montado **de verdad funciona**.

## Uso rápido

```bash
python3 .claude/skills/openclaw-agent-verify/scripts/verify_agents.py            # todos
python3 .claude/skills/openclaw-agent-verify/scripts/verify_agents.py corfo      # uno
python3 .claude/skills/openclaw-agent-verify/scripts/verify_agents.py --json     # para procesar
```

Solo **lee** `~/.openclaw/openclaw.json` y los workspaces. No modifica nada ni manda mensajes.
Sale con código 1 si hay problemas.

Qué revisa por agente: que tenga binding; que el grupo enlazado esté declarado en
`channels.whatsapp.groups`; que un número enlazado esté en `allowFrom` (si no, no puede
escribirle); que el workspace exista y tenga `SOUL.md`/`AGENTS.md`/`USER.md`; que un `SOUL.md`
sospechosamente corto no siga siendo el template; y que un agente que habla en grupo tenga
`tools.deny` (lockdown).

## Prueba de routing (la parte que el script NO puede hacer)

⚠️ **El script es estático**: lee la config, no prueba el camino real de un mensaje entrante.

Una trampa verificada el 2026-08-17: `openclaw agent --to <destino>` **siempre** resuelve a
`agent:main:main`, incluso apuntando al grupo de `adondepo`, que sí funciona en producción. Esa
llamada es una invocación **saliente** por CLI y no ejercita el routing entrante.

Conclusión: **no uses `openclaw agent --to` para probar routing.** Da un falso negativo.

La única prueba válida:

1. Escribirle al bot **desde WhatsApp** (al grupo o al DM, según su binding).
2. Ver qué agente atendió:

```bash
openclaw status 2>&1 | grep -A 20 "Sessions"     # sesiones activas y su agente
openclaw logs --follow                            # en vivo mientras llega el mensaje
```

3. La sesión debe ser `agent:<id>:...`, no `agent:main:...`.

Si atiende `main` en vez del agente esperado, el binding no está ganando. Antes de tocar
`bindings` en `openclaw.json`, respalda (`openclaw backup create --verify`) y ten presente que
mover el binding de `main` **afecta a todos los agentes**.

## Mapa del equipo

`<repo privado de la flota>/mapa-equipo.md (p. ej. ~/projects/openclaw-fleet-rodrigo) (FUERA del repo: contiene teléfonos y JIDs)` guarda quién es quién: agente, canal, grupo o número, propósito y
notas. La config sabe *que* existe un binding a `<jid-del-grupo>@g.us`, pero no que ese
grupo es "el de adondepo donde escribe tal persona" — eso es lo que este archivo conserva.

**Mantenlo al día**: al montar un agente nuevo, agrega su fila; si cambia un binding,
actualízala. Es memoria barata que evita reconstruir el contexto en cada sesión.

Para regenerar la parte técnica (ids, bindings) desde la config real:

```bash
openclaw agents bindings
python3 .claude/skills/openclaw-agent-verify/scripts/verify_agents.py --json
```

Lo que el script no puede saber —el nombre humano del grupo, quién escribe ahí, para qué
sirve— se completa a mano una vez.

⚠️ **PII**: ese archivo tiene números de teléfono e ids de grupo. No lo publiques en un repo
compartido sin revisarlo (`openclaw secrets audit --check` no cubre PII).

## Checklist para un agente recién montado

- [ ] `verify_agents.py <id>` sin problemas.
- [ ] **Prueba de routing real** desde WhatsApp: atiende él, no `main`.
- [ ] Responde con el tono de su `SOUL.md` (no el genérico del template).
- [ ] Si habla con terceros: lockdown aplicado y contención verificada
      (ver paso 6.5 de `openclaw-agent-build`).
- [ ] Fila agregada en `<repo privado de la flota>/mapa-equipo.md (p. ej. ~/projects/openclaw-fleet-rodrigo) (FUERA del repo: contiene teléfonos y JIDs)`.
- [ ] Si editaste `SOUL.md`/`AGENTS.md`/`USER.md`: `openclaw gateway restart` (se cargan al
      iniciar sesión; las sesiones vivas conservan la versión anterior).

## Relacionado

- `openclaw-agent-build` — montar el agente (este skill verifica lo que aquel construye).
- `knowledge/depurar-agentes.md` — cuando responde raro: dónde vive su comportamiento real y
  por qué un skill de Claude Code **no** lo afecta.
- `knowledge/onboarding-cliente.md` — runbook completo con comandos.
