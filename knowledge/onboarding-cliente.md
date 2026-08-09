# Runbook — Onboarding de un cliente nuevo (de cero a bot vivo)

> Secuencia ejecutable canónica para montar un bot de OpenClaw para un cliente.
> Ejemplo guía: una **llantería**. Cada paso con comandos reales y verificación.
> Prerrequisito: OpenClaw instalado (CLI + Node, NO Bun) y un gateway operativo.

---

## Resumen del flujo

```
1. Definir el negocio       → decisiones (nombre agente, tono, canal)
2. Crear el agente          → create agent + workspace
3. Escribir la personalidad → SOUL.md / AGENTS.md / USER.md
4. Elegir y conectar canal  → árbol de decisión QR / imBee / Cloud API
5. Enrutar canal → agente   → binding ACP
6. Control de acceso        → dmPolicy / allowFrom
7. Smoke test               → probar desde otro teléfono
8. Verificación final       → checklist
```

---

## Paso 0 — Respaldo previo (si el OpenClaw ya está en uso)

```bash
openclaw backup create --verify
```
Punto de retorno si algo sale mal. Omitir solo si es una instancia recién instalada y vacía.

---

## Paso 1 — Definir el negocio (decisiones antes de tocar nada)

Responder con el usuario:
- **id del agente** (kebab-case, ej. `llantas`).
- **Tono/rol**: cómo debe hablar (vendedor cercano, formal, etc.).
- **Qué hace**: catálogo, precios, horarios, qué NO debe prometer.
- **Fase**: ¿demo/validación o producción real? → decide el canal (paso 4).
- **Número WhatsApp**: dedicado (recomendado), nunca el personal del dueño.

---

## Paso 2 — Crear el agente

```bash
create agent llantas workspace /Users/rodrigodev/.openclaw/agents/llantas/workspace model openai/gpt-5.5
```
Cada agente = workspace + agentDir + session store propios (aislado de otros agentes).
Verificar:
```bash
openclaw status        # el agente 'llantas' debe aparecer
```

---

## Paso 3 — Escribir la personalidad

En el workspace del agente (`~/.openclaw/agents/llantas/workspace/`):

- **`SOUL.md`** — la voz: tono, opiniones, brevedad, límites. Corto y filoso. Es lo que hace
  que no suene genérico. (Ver `knowledge/openclaw-features.md` §3.)
- **`AGENTS.md`** — reglas de negocio: qué vende, precios, horarios, qué NO prometer.
- **`USER.md`** — sobre el dueño/negocio (⚠️ PII: no versionar si tiene datos personales).

Mantener breve y concreto. Probar el tono en consola antes de conectar el canal.

---

## Paso 4 — Elegir y conectar el canal (árbol de decisión)

```
¿Es demo/validación?  ──SÍ──►  QR / Baileys  (gratis, rápido; riesgo de ban; número de PRUEBA)
        │
        NO (producción real)
        │
¿El dueño desconfía / no da claves Meta?  ──SÍ──►  BSP imBee  (openclaw-channel-whatsapp-official)
        │                                            free tier; oficial Meta; sin ban
        NO
        │
        ▼
   WhatsApp Cloud API (Meta)  ──►  hay que construir con SDK (webhook). Mayor esfuerzo.
```

### Opción A — QR / Baileys (demo)
```bash
openclaw plugins install clawhub:@openclaw/whatsapp
openclaw channels add --channel whatsapp --account llantas
openclaw channels login --channel whatsapp --account llantas   # muestra QR → escanear
openclaw gateway
```
⚠️ Número de prueba. Riesgo de ban. Teléfono vinculado debe estar encendido 24/7.

### Opción B — BSP imBee (producción, dueño desconfiado)
```bash
openclaw plugins install openclaw-channel-whatsapp-official
openclaw channels add            # elegir "Official WhatsApp API (via imBee)"
# escanear QR de imBee + enviar código de pareo desde WhatsApp
```
Oficial Meta, sin ban. Ver `research/whatsapp-official-imbee.md` (precios/reseñas/privacidad) antes de producción.

### Opción C — Cloud API (Meta directo)
No hay plugin listo → construir canal con el SDK (`sdk-channel-inbound/outbound.md`, `webhooks.md`).
Requiere Business Manager verificado + webhook HTTPS 24/7 + plantillas aprobadas. Es desarrollo.

---

## Paso 5 — Enrutar el canal al agente (binding ACP)

En `openclaw.json` (vía `openclaw config` preferido):
```json5
bindings: [
  { type: "acp", agentId: "llantas",
    match: { channel: "whatsapp", accountId: "llantas", peer: { kind: "direct", id: "*" } } }
]
```
Cada cliente que escribe a ese número → sesión propia con memoria aislada (automático).

---

## Paso 6 — Control de acceso

```json5
channels: { whatsapp: { accounts: { llantas: {
  dmPolicy: "open",        // pairing | allowlist | open | disabled
  // allowFrom: ["+569..."]  // si quieres restringir a números concretos
}}}}
```
- `pairing` (default): desconocidos piden aprobación → bueno para pruebas controladas.
- `open`: atiende a cualquiera (requiere `allowFrom: ["*"]`) → para atención pública real.

Aplicar validando:
```bash
openclaw config validate
openclaw doctor && openclaw gateway restart
```

---

## Paso 7 — Smoke test

1. Desde **otro teléfono**, escribir al número del bot.
2. Confirmar que responde con el tono definido (SOUL.md).
3. Escribir desde un **segundo** número → confirmar que su memoria es independiente.
4. Revisar logs si no responde:
   ```bash
   openclaw channels status --probe
   openclaw logs --follow
   ```

---

## Paso 8 — Checklist de verificación final

- [ ] `openclaw status` muestra el agente y el canal enlazados.
- [ ] `openclaw channels status --probe` = linked/healthy.
- [ ] El bot responde desde un teléfono externo.
- [ ] La memoria por número funciona (2 clientes distintos = 2 contextos).
- [ ] El tono coincide con SOUL.md.
- [ ] `openclaw secrets audit --check` sin plaintext (si se versionará la config).
- [ ] Número dedicado (no el personal del dueño).
- [ ] Gateway como servicio de fondo (para que el reconnect siga vivo).
- [ ] Si es QR: el teléfono vinculado queda encendido 24/7.

---

## Troubleshooting rápido

| Síntoma | Acción |
|---------|--------|
| No responde | `openclaw channels status --probe` → si "not linked", re-login QR |
| Reconnect loop (`status=408`) | ajustar `web.whatsapp.*` (ver `knowledge/openclaw.md` §reconexión) |
| Sesión perdida | respaldar credencial + `channels logout/login` (re-QR) |
| Deploy 24/7 | mover gateway a VPS → `knowledge/moving-openclaw.md` + `local-vs-remote-gateway.md` |

---

## Fuentes

- Comandos y arquitectura: `knowledge/openclaw.md`, `knowledge/openclaw-features.md`
- Canal WhatsApp: docs `channels/whatsapp.md`; BSP: `research/whatsapp-official-imbee.md`
- Deploy/mover: `knowledge/moving-openclaw.md`, `knowledge/local-vs-remote-gateway.md`
