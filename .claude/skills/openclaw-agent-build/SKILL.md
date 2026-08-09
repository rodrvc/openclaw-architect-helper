---
name: openclaw-agent-build
description: Monta de cero un bot/agente de OpenClaw para un cliente o negocio nuevo (onboarding completo — de cero a bot vivo). Guía paso a paso definir el negocio, crear el agente (create agent), escribir la personalidad (SOUL.md/AGENTS.md/USER.md), decidir y conectar el canal WhatsApp (QR / imBee / Cloud API), enrutar el canal al agente (binding ACP), controlar el acceso (dmPolicy), correr el smoke test y verificar. Úsalo cuando el usuario quiera "crear un bot para un cliente nuevo", "montar un agente OpenClaw", "hacer onboarding de un cliente", "configurar un agente para un negocio" (llantería, restaurante, tienda, etc.), "conectar WhatsApp a un agente" o "dejar un bot atendiendo".
---

# OpenClaw Agent Build (onboarding de cliente)

Operacionaliza el runbook de onboarding: llevar un OpenClaw de cero a un **bot vivo**
atendiendo por WhatsApp para un cliente. Este skill es la secuencia accionable; la fuente
detallada con comandos completos, ejemplos y troubleshooting es
`knowledge/onboarding-cliente.md` (léelo cuando necesites el detalle de un paso).

Ejemplo guía a lo largo del flujo: una **llantería** (`agentId: llantas`).

## Cuándo usarlo

- El usuario quiere un bot nuevo para un cliente/negocio y hay que montarlo end-to-end.
- Ya existe OpenClaw instalado (CLI + Node, **NO Bun**) y un gateway operativo.
- Para mover/replicar una config existente entre máquinas, usa `openclaw-config-portable`
  / `openclaw-config-import` en su lugar (ver "Relación con otros skills").

## Principios de seguridad (NO negociables)

1. **Respalda antes de tocar nada** si el OpenClaw ya está en uso:
   `openclaw backup create --verify`. Es el punto de retorno. Omitir solo en instancia
   recién instalada y vacía.
2. **Prefiere la CLI validada** para editar config: `openclaw config set/patch ... --dry-run`
   antes de escribir; luego `openclaw config validate`. No edites `openclaw.json` a mano si
   hay un comando que lo haga.
3. **Confirma con el usuario antes de conectar el canal** (login QR / pareo imBee): es el
   paso que expone el número y puede causar ban. Nada de conectar sin OK explícito.
4. **Nunca versiones secretos**: credenciales de WhatsApp, tokens del gateway, `credentials/`.
   Si vas a versionar la config, corre `openclaw secrets audit --check` (0 findings).
5. **Revisa PII**: teléfonos, emails y datos del dueño (en `USER.md`, `allowFrom`,
   `auth.profiles`). No los expongas en repos compartidos.

## Secuencia

```
0. Respaldo previo          → openclaw backup create --verify
1. Definir el negocio       → decisiones (id, tono, qué hace, fase, número)
2. Crear el agente          → create agent + workspace aislado
3. Escribir personalidad    → SOUL.md / AGENTS.md / USER.md
4. Elegir y conectar canal  → árbol de decisión QR / imBee / Cloud  [CONFIRMAR]
5. Enrutar canal → agente   → binding ACP
6. Control de acceso        → dmPolicy / allowFrom
7. Smoke test               → probar desde otro teléfono
8. Checklist final          → verificar
```

### Paso 0 — Respaldo previo
```bash
openclaw backup create --verify
```

### Paso 1 — Definir el negocio (antes de tocar nada)
Acuerda con el usuario: **id del agente** (kebab-case, ej. `llantas`); **tono/rol**;
**qué hace** (catálogo, precios, horarios, qué NO prometer); **fase** (demo vs producción,
esto decide el canal del paso 4); **número WhatsApp** dedicado (nunca el personal del dueño).

### Paso 2 — Crear el agente
```bash
create agent llantas workspace ~/.openclaw/agents/llantas/workspace model openai/gpt-5.5
openclaw status   # 'llantas' debe aparecer
```
Cada agente = workspace + agentDir + session store propios (aislado de otros agentes).

### Paso 3 — Escribir la personalidad
En `~/.openclaw/agents/<id>/workspace/`:
- **`SOUL.md`** — la voz: tono, opiniones, brevedad, límites. Corto y filoso.
- **`AGENTS.md`** — reglas de negocio: qué vende, precios, horarios, qué NO prometer.
- **`USER.md`** — sobre el dueño/negocio. ⚠️ PII: no versionar si tiene datos personales.

Breve y concreto. Prueba el tono en consola **antes** de conectar el canal.

### Paso 4 — Elegir y conectar el canal (árbol de decisión) — CONFIRMAR
```
¿demo/validación?  ──SÍ──►  A) QR / Baileys (gratis, rápido; riesgo ban; número de PRUEBA)
     │ NO (producción)
¿dueño desconfía / no da claves Meta?  ──SÍ──►  B) BSP imBee (oficial Meta, free tier, sin ban)
     │ NO
     ▼  C) WhatsApp Cloud API (Meta directo) — sin plugin listo, es desarrollo con SDK
```
- **A) QR/Baileys**: `openclaw plugins install clawhub:@openclaw/whatsapp` →
  `channels add/login` (escanear QR) → `openclaw gateway`. Teléfono vinculado 24/7.
- **B) imBee**: `openclaw plugins install openclaw-channel-whatsapp-official` →
  `channels add` (elegir "Official WhatsApp API (via imBee)") → QR + código de pareo.
  Lee `research/whatsapp-official-imbee.md` antes de producción.
- **C) Cloud API**: construir el canal con el SDK (webhooks). Mayor esfuerzo.

Confirma con el usuario **antes** de ejecutar el login/pareo. Comandos completos en el runbook.

### Paso 5 — Enrutar el canal al agente (binding ACP)
En `openclaw.json` (vía `openclaw config` preferido), un binding `acp` que matchee
`channel: whatsapp` + `accountId` + peer directo `*` hacia `agentId`. Cada cliente que
escribe → sesión propia con memoria aislada (automático). Ver runbook para el JSON exacto.

### Paso 6 — Control de acceso
```json5
channels.whatsapp.accounts.<id>.dmPolicy: "pairing" | "allowlist" | "open" | "disabled"
```
`pairing` (default) para pruebas controladas; `open` (con `allowFrom: ["*"]`) para atención
pública. Aplica validando: `openclaw config validate && openclaw doctor && openclaw gateway restart`.

### Paso 7 — Smoke test
Desde **otro teléfono**, escribe al bot → confirma tono (SOUL.md). Desde un **segundo**
número → confirma memoria independiente. Si no responde:
`openclaw channels status --probe` y `openclaw logs --follow`.

### Paso 8 — Checklist de verificación final
- [ ] `openclaw status` muestra agente + canal enlazados.
- [ ] `openclaw channels status --probe` = linked/healthy.
- [ ] Responde desde un teléfono externo, con el tono de SOUL.md.
- [ ] Memoria por número funciona (2 clientes = 2 contextos).
- [ ] `openclaw secrets audit --check` sin plaintext (si se versionará la config).
- [ ] Número dedicado (no el personal del dueño).
- [ ] Gateway como servicio de fondo (reconnect sobrevive).
- [ ] Si es QR: teléfono vinculado encendido 24/7.

## Relación con otros skills

- **`openclaw-config-portable`**: cuando el bot ya está montado y quieres empaquetar su
  config/personalidad (ligero, sin secretos) para moverlo/versionarlo a otra máquina.
- **`openclaw-config-import`**: para instalar ese paquete ligero dentro de un OpenClaw ya
  existente. Este skill (`openclaw-agent-build`) monta desde cero; los otros dos mueven una
  config ya construida entre máquinas.

## Referencia

- **Runbook fuente (detalle, comandos completos, troubleshooting)**: `knowledge/onboarding-cliente.md`
- Comandos y arquitectura: `knowledge/openclaw.md`, `knowledge/openclaw-features.md`
- Canal WhatsApp / BSP: docs `channels/whatsapp.md`, `research/whatsapp-official-imbee.md`
- Deploy 24/7 / mover gateway: `knowledge/moving-openclaw.md`, `knowledge/local-vs-remote-gateway.md`
