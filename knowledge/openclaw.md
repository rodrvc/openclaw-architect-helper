# Base de conocimiento OpenClaw (memoria viva)

> Documento **vivo**. Se agrega información **a medida que la aprendemos y confirmamos**.
> Cada afirmación importante lleva su fuente. Última actualización: 2026-08-08.

---

## Dónde buscar información de OpenClaw

| Fuente | Ubicación | Para qué |
|--------|-----------|----------|
| **Docs locales** | `/opt/homebrew/lib/node_modules/openclaw/docs/` | Referencia principal. Instalada con el paquete. |
| **Docs online** | https://docs.openclaw.ai | Misma doc, versión web. |
| **Fuente** | https://github.com/openclaw/openclaw | Cuando la doc no alcanza. |
| **ClawHub** | https://clawhub.ai — CLI: `openclaw plugins search "<x>"` | **Marketplace de plugins de comunidad.** ⚠️ EXISTE, no olvidar. |

### Mapa de carpetas de docs (lo más útil)
- `channels/` → un `.md` por canal (whatsapp, telegram, slack, signal, discord, sms...). `whatsapp.md` es clave.
- `gateway/` → configuración, autenticación, background-process, secrets, sandboxing.
- `plugins/` → `plugin-inventory.md` (catálogo oficial), `community.md`, y `sdk-channel-*.md` (construir canales propios), `building-plugins.md`, `webhooks.md`.
- `providers/` → proveedores de **modelos de IA** (Anthropic, OpenAI, etc.), NO de WhatsApp.
- `concepts/` → `multi-agent.md` (routing multi-agente).
- `clawhub/` → publicar y CLI de ClawHub.

---

## Arquitectura en 3 capas

Modelo mental para multi-cliente (fuente: `concepts/multi-agent.md`, `channels/whatsapp.md`):

```
1 Instancia OpenClaw (un gateway, una máquina)
│
├── Agente "llantas"      → un número WhatsApp → atiende a TODOS sus clientes
│     ├── sesión +569...1  (memoria propia)
│     └── sesión +569...2  (memoria propia)
│
└── Agente "veterinaria"  → otro número → sus propios clientes
```

- **Instancia**: NO una por negocio. Una sola aguanta muchos agentes.
- **Agente**: uno por negocio/rol. Ya existen `sofia` y `cv` como ejemplo. Se crean con `create agent <id> workspace <path> model <modelo>`.
- **Sesión**: automática por conversación. `session.dmScope` (default `main`) controla cómo se agrupan los DMs.

---

## WhatsApp — opciones de conexión

Fuente: `channels/whatsapp.md`, ClawHub, búsquedas web (2026-08).

### A) Plugin oficial `@openclaw/whatsapp` — QR / Baileys
- Doc textual: *"production-ready via WhatsApp Web (Baileys)"*, *"Login is QR-only"*, *"there is no separate Twilio WhatsApp channel"*.
- Instalar: `openclaw plugins install clawhub:@openclaw/whatsapp`
- Setup: `openclaw channels add --channel whatsapp` → `openclaw channels login --channel whatsapp` (muestra QR) → `openclaw gateway`.
- **No oficial de Meta** → riesgo de ban. Recomendado número dedicado.
- Multi-cuenta: `channels.whatsapp.accounts.<id>` → una cuenta WA por negocio.
- Bindings ACP para enrutar cuenta→agente:
  ```json5
  bindings: [{ type: "acp", agentId: "llantas",
    match: { channel: "whatsapp", accountId: "llantas", peer: { kind: "direct", id: "*" } } }]
  ```
- Credenciales: `~/.openclaw/credentials/whatsapp/<accountId>/creds.json`.
- Access control: `dmPolicy` (`pairing`|`allowlist`|`open`|`disabled`), `allowFrom`, `groupPolicy`.
- System prompts por grupo/DM: mapas `groups` y `direct` (con wildcard `"*"`).

### B) WhatsApp Cloud API (Meta oficial) — NO viene como plugin
- Requiere: Meta for Developers + Business Manager verificado + registrar número + token + webhook HTTPS público 24/7.
- Reglas: ventana de 24h para responder libre; fuera de eso, **plantillas aprobadas**. Costo por conversación.
- En OpenClaw: **hay que construir el canal** con el SDK (`sdk-channel-inbound/outbound.md`, `webhooks.md`). Es desarrollo, no config.

### C) BSP de comunidad — `openclaw-channel-whatsapp-official` (imBee) ✅ RECOMENDADO evaluar
- **SÍ existe** un plugin por proveedor (corrige la suposición inicial de que "no había"). Detalle completo en [research/whatsapp-official-imbee.md](../research/whatsapp-official-imbee.md).
- Oficial Meta vía imBee (BSP). Sin verificación Meta propia, sin servidor, sin Baileys.
- Resuelve el **dueño desconfiado**: imBee tiene el Business Manager; el dueño no entrega claves.

---

## Reconexión WhatsApp

Fuente: `channels/whatsapp.md` (Runtime model + Troubleshooting).

- **Auto**: el gateway posee el socket y un reconnect loop; watchdog vigila transporte y mensajes. Caídas normales se recuperan solas.
- **Diagnóstico primario**: `openclaw channels status --probe`.
  - linked/healthy → pasajero, no hacer nada.
  - not linked → re-escanear QR.
- **Reconnect loop** (`status=408`): ajustar en config
  ```json5
  { web: { whatsapp: { keepAliveIntervalMs: 15000, connectTimeoutMs: 60000, defaultQueryTimeoutMs: 60000 } } }
  ```
  Herramientas: `openclaw doctor`, `openclaw logs --follow`, `openclaw gateway status`.
- **Re-link seguro** (respaldar antes):
  ```bash
  cp -a ~/.openclaw/credentials/whatsapp/<id> ~/.openclaw/credentials/whatsapp/<id>.bak
  openclaw channels logout --channel whatsapp --account <id>
  openclaw channels login  --channel whatsapp --account <id>
  ```
- **Runtime**: requiere **Node** (no Bun — falta `node:sqlite`).

---

## Riesgos de producción

- **Ban** (solo QR/Baileys): inherente, no eliminable; mitigar con volumen humano y número dedicado.
- **Teléfono físico** (QR): debe estar encendido con red 24/7. Punto único de falla.
- **Fragilidad de sesión**: algunas caídas requieren re-QR manual.
- **Responsabilidad**: si banean al cliente, la responsabilidad recae en quien lo montó.
- **Regla de oro**: nunca poner en QR un número que al cliente le dolería perder.
- **Estrategia por fase**: demo → QR (número de prueba); producción → BSP (imBee) o Cloud API.

---

## Ecosistema: ClawHub y plugins

- **ClawHub** (https://clawhub.ai): marketplace de plugins de comunidad (canales, tools, providers, hooks).
  - Buscar: `openclaw plugins search "<término>"`
  - Instalar: `openclaw plugins install clawhub:<paquete>` (o `npm:<paquete>`)
  - Gestionar: ver `plugins/manage-plugins.md`.
- **Plugins oficiales relevantes** (`plugins/plugin-inventory.md`):
  - `@openclaw/whatsapp` — canal WhatsApp Web (QR).
  - `@openclaw/sms` — SMS por Twilio.
  - `@openclaw/voice-call` — llamadas (Twilio/Telnyx/Plivo).
  - `@openclaw/google-meet` — participante en Meet.
- **SDK de canales** (`plugins/sdk-channel-plugins.md`): permite construir un canal propio.
  El plugin posee config, seguridad, pairing, session grammar, outbound, threading.
  Core provee el `message` tool compartido y el dispatch. → Vía para un **conector BSP propio reutilizable**.

---

## Buenas prácticas acumuladas

- Un agente por negocio; una instancia para todos.
- Número WhatsApp **dedicado** por negocio (la doc lo recomienda explícitamente).
- Gateway como **servicio de fondo** (`gateway/background-process.md`) para que el reconnect siga vivo.
- Monitorear con `channels status` / heartbeat antes que se queje el cliente.
- Siempre respaldar credenciales antes de `logout`/re-link.

---

## Pendiente por confirmar / aprender

- Precios exactos y reseñas reales del plugin imBee (ver research; aún sin tiers públicos).
- Cómo se ve exactamente construir un conector BSP con el SDK (tamaño del trabajo).
- **Buscar skill de construcción de agente OpenClaw** → issue #001.
