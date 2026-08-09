# Plugin `openclaw-channel-whatsapp-official` (imBee) — precios y reseñas

> Investigación al 2026-08-08. Fuentes al final. **Corrige** la suposición inicial de que
> "no existía integración WhatsApp por proveedor para OpenClaw": **sí existe.**

## Qué es

- Plugin de **comunidad** en ClawHub (publicado por `dearken10`), backend operado por **imBee**.
- Conecta OpenClaw a WhatsApp vía la **cuenta BSP verificada de imBee** (Business Solution Provider) → tráfico por la **infraestructura oficial de Meta**.
- **NO** usa Baileys ni protocolos reverse-engineered. **NO** requiere que tú verifiques negocio en Meta ni montes servidor.

## Cómo funciona (transporte)

- imBee corre la WhatsApp Business Account verificada + el ruteo + la capa de seguridad.
- Pareo por **QR de imBee** (no el QR frágil de WhatsApp Web) + **código de pareo** enviado desde WhatsApp.
- Mensajes reenviados a tu agente en **<500 ms**.
- imBee actúa como **proxy transparente**: *"payloads reenviados en memoria, nunca escritos a disco"* (afirmación del proveedor).

## Instalación

```bash
openclaw plugins install openclaw-channel-whatsapp-official
openclaw channels add            # elegir "Official WhatsApp API (via imBee)"
# escanear QR → enviar código de pareo desde WhatsApp → agente en vivo
```
Setup declarado: **< 2 minutos**.

## Precios (⚠️ incompleto — no publican tiers detallados)

| Ítem | Dato encontrado |
|------|-----------------|
| **Free tier** | Sí. Número **compartido**, **sin tarjeta**. |
| **Prueba** | **30 días** de trial. |
| **Números dedicados / branded** | Planes **pagos** (enterprise). Precio **no publicado**. |
| **Multi-agente, broadcast, omnichannel** | En infraestructura BSP de imBee (pago). |

> **Pendiente**: obtener precios reales de planes pagos y del número dedicado (requiere "Book a demo").

## Seguridad / privacidad (afirmaciones del proveedor)

- TLS 1.2+ en conexiones.
- Verificación de webhook HMAC-SHA256.
- *"El contenido de los mensajes nunca se almacena de forma persistente en el servidor de ruteo de imBee."*
- Autenticación Bearer token por instancia.
- Códigos de pareo: un solo uso, expiran en 10 min, 2.8 billones (trillion) de combinaciones.

## Reseñas / testimonios

- **No se encontraron reseñas de usuarios, ratings ni testimonios** públicos verificables al 2026-08-08.
- Solo material del propio proveedor (marketing). **Trust signal externo: bajo/ausente.**

## Evaluación para uso con clientes

**A favor:**
- Elimina el **riesgo de ban** (es oficial Meta).
- Elimina la dependencia del teléfono físico 24/7.
- Resuelve el **dueño desconfiado**: imBee es el BSP, el dueño no entrega claves suyas.
- Free tier para validar sin costo.

**En contra / a vigilar:**
- Es **tercero**: tus conversaciones pasan por servidores de imBee. La no-persistencia es *su* afirmación, no auditada.
- **Sin reseñas independientes** → confiabilidad no comprobada por terceros.
- Free tier usa **número compartido** (no sirve para marca propia de un negocio).
- Precios de producción **opacos** (hay que pedir demo).

## Recomendación

1. Probar en **free tier** para validar el flujo técnico.
2. Antes de ponerlo frente a un cliente real: **due diligence de imBee** (privacidad, SLA, precio del número dedicado).
3. Comparar contra: (a) QR/Baileys gratis para demos, (b) construir conector BSP propio con el SDK de canales.

## Fuentes

- ClawHub: https://clawhub.ai/dearken10/plugins/openclaw-channel-whatsapp-official
- ClawHub (oficial imBee): https://clawhub.ai/plugins/openclaw-channel-whatsapp-official
- imBee: https://www.imbee.io/resource/openclaw-whatsapp-plugin
- Doc WhatsApp OpenClaw: https://docs.openclaw.ai/channels/whatsapp
