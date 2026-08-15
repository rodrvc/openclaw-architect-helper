# OpenClaw — depurar un agente que responde raro

> Qué revisar cuando un agente ya montado no se comporta como esperas, y cómo diseñar
> instrucciones para que no dependa del criterio del modelo en lo que no puede fallar.
> Aprendido depurando el agente `adondepo` (~1 día, 2026-08-11/12). Aplica a cualquier agente.

---

## 1. El comportamiento vive en el workspace del agente, NO en los skills de Claude Code

Si un agente responde algo raro **de forma consistente**, casi nunca "se desvía": está
**obedeciendo una instrucción literal**. Búscala antes de tocar cualquier otra cosa.

Dónde mirar, en orden:

| Archivo | Qué contiene |
|---|---|
| `~/.openclaw/agents/<id>/workspace/SOUL.md` | La fuente real: rol, tono, qué hace, cómo reporta |
| `.../workspace/AGENTS.md` | Reglas operativas |
| `.../workspace/USER.md`, `TOOLS.md` | Contexto del dueño, notas de entorno |
| `~/.openclaw/agents/<id>/sessions/skills-prompts/` | Catálogo **real** de skills que ve el agente |

### ⚠️ Trampa cara (perdí un día en esto)

`~/.claude/skills/<nombre>/SKILL.md` es de **Claude Code**, no de OpenClaw. Un agente
OpenClaw **NUNCA lo lee** — ni siquiera aparece en su catálogo de skills. Editarlo creyendo
que corriges al agente no tiene ningún efecto.

Antes de editar un skill para "arreglar" a un agente, confirma que ese skill está en
`sessions/skills-prompts/`. Si no está, el archivo que buscas es el `SOUL.md`.

**Caso real:** el agente respondía siempre "Hubo un problema técnico al subirlo. Rodrigo lo
revisa." en vez del error concreto. Ese texto estaba escrito **literal** en su `SOUL.md`,
junto a un "NO des detalles técnicos". El agente obedecía a la perfección.

### Después de editar el SOUL

`SOUL.md` se carga al iniciar sesión: `openclaw gateway restart`. Las sesiones vivas pueden
seguir con la versión anterior en contexto.

---

## 2. Determinismo: sacar del LLM lo que no debe variar

**Síntoma:** el agente resumía lotes de resultados mixtos (unos OK, otros fallidos) en un
mensaje genérico, perdiendo qué falló y por qué. Empeorado porque su `SOUL.md` pedía "sé
breve en grupos" — una instrucción empujando contra la otra.

**Patrón:** si un detalle no puede salir mal, que lo **genere código** y el LLM solo lo
**transporte**.

- El script emite un bloque ya formateado, entre marcas (`---8<---` / `--->8---`).
- La instrucción al agente pasa a ser: **"pégalo literal, no lo reescribas"**. El agente
  aporta el saludo y el tono alrededor, nunca el contenido.

Esto es un **contrato** entre el script y el agente: por eso es correcto que las marcas
aparezcan en ambos lados. No es acoplamiento accidental.

### Tensión a considerar

Si el bloque va a un canal con terceros (clientes, un grupo), los motivos técnicos crudos no
pueden salir tal cual. La traducción también va en **código**, con un **fallback neutro**
para lo no mapeado — así un motivo nuevo nunca filtra rutas ni nombres internos.

```
og:url / Chrome  →  "no se pudo leer el post desde Instagram"
(no mapeado)     →  "no se pudo procesar"
```

### Alternativas descartadas

- **Solo instrucción en el SOUL** ("lista siempre el detalle"): es lo que ya falló. El modelo
  resume cuando el contexto crece o cuando otra instrucción compite.
- **Que el script mande el mensaje directo al canal**: determinista al 100%, pero pierde el
  tono y obliga a manejar credenciales del gateway en el script. Solo vale si el aviso debe
  salir aunque el agente esté caído.

---

## 3. Verificar el estado real antes de concluir

Dos errores propios en la misma sesión, ambos por quedarme con la primera explicación
plausible:

**Falso OK de un health check.** Chrome se había auto-actualizado, así que asumí
incompatibilidad con Playwright y lo actualicé. No era eso: el proceso de Chrome estaba
**huérfano** — vivo, con el puerto 9222 respondiendo `200`, pero con **cero pestañas**.
Playwright moría al pedir `contexts[0]`. El chequeo miraba `/json/version` (¿responde?) en
vez de `/json/list` (¿hay un target usable?).

> **"Responde el puerto" no es "está sano".** Un health check debe verificar el
> sub-recurso que realmente vas a usar.

**Lectura vieja tomada como verdad.** Afirmé que dos cuentas estaban desactivadas basándome
en una consulta anterior; ya estaban activas. Estuve a punto de proponer un `UPDATE` en la
base de datos de **producción** sin necesidad.

> Antes de proponer una acción sobre producción, **relee la fuente**. El costo de un
> `curl` es cero comparado con el de una escritura innecesaria.

---

## 4. Checklist rápido

Cuando un agente responde raro:

- [ ] ¿La respuesta es **consistente**? → busca la instrucción literal en `SOUL.md`.
- [ ] ¿Estás editando un skill? → confirma que aparece en `sessions/skills-prompts/`.
- [ ] ¿Editaste el SOUL? → `openclaw gateway restart`.
- [ ] ¿El detalle que se pierde **no puede fallar**? → que lo genere el script; el agente lo pega.
- [ ] ¿Ese texto va a terceros? → traducción y fallback neutro en código.
- [ ] ¿Diagnosticaste por un health check? → ¿verifica el recurso real o solo que "responda"?
- [ ] ¿Vas a tocar producción? → relee el estado actual primero.

---

## Relacionado

- [`onboarding-cliente.md`](./onboarding-cliente.md) — montar un agente de cero (paso 3: escribir la personalidad).
- [`openclaw-features.md`](./openclaw-features.md) — memoria, skills, automatización.
- Skill `openclaw-agent-build` — secuencia accionable de onboarding.
