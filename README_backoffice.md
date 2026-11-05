# Back-office SENSOTOYS · Supabase #2

> **Prototipo académico** (SIE · Tarea 2, UCAM). Sin actividad comercial real. Todos los datos son de prueba.

El back-office es un **sistema independiente de la tienda**. Tiene su propio proyecto de Supabase, con su base de datos PostgreSQL, sus usuarios y sus claves. No comparte tablas con la tienda (Supabase #1). La única vía de entrada de datos son los **eventos** que la tienda envía a n8n:

```
Tienda (Supabase #1)                 n8n                          Back-office (Supabase #2)
tabla eventos ──trigger──► webhook POST /sensotoys-eventos ──► rpc integrar_evento(p)
  (sql/19, pg_net + Vault)     (cabecera x-sensotoys-secret)      ├─ clientes / pedidos_bo / lineas_bo / tickets
                                                                  └─ log_integracion  (n8n)
                                                                  aprobaciones_agente (agente IA + Telegram)
                                                                         ▲
                                                 App Vue (solo lectura) ─┘  vistas de métricas (sql/21)
```

## Enlaces

| Qué | URL |
|---|---|
| App del back-office (Vue) | https://solucionesucam-lang.github.io/SENSOTOY/backoffice/ |
| API del back-office | https://pybmlynfbzqxlhkajodj.supabase.co |
| n8n | https://sensotoys-sie.app.n8n.cloud |

## Scripts SQL del back-office

Se ejecutan **en el SQL Editor del Supabase #2**, en este orden:

| Orden | Script | Qué hace |
|---|---|---|
| 1 | `sql/17_backoffice_esquema.sql` | Crea las 6 tablas, restricciones e índices, y activa RLS |
| 2 | `sql/18_n8n_esquema.sql` | Crea el rol `n8n_svc` y el esquema `n8n` (solo si n8n guarda sus datos en esta base; en n8n Cloud no hace falta) |
| 3 | `sql/20_backoffice_rls.sql` | Permisos (GRANT/REVOKE) y políticas RLS de solo lectura |
| 4 | `sql/21_metricas_backoffice.sql` | Vistas del cuadro de mando |
| 5 | `sql/23_historial_cliente.sql` | Vista de historial del cliente para el agente |
| 6 | `sql/24_integrar_evento.sql` | Función `integrar_evento` (entrada única de datos) |
| 7 | `sql/25_datos_prueba_backoffice.sql` | Preparación de la demo, **por apartados** (vaciado, Telegram, comprobaciones) |

Los scripts `19`, `26` y `27` son **de la tienda (Supabase #1)**, no de este proyecto.

Después de ejecutar el `18`, cambia la contraseña de `n8n_svc` desde el panel (Database → Roles). El valor `CAMBIAR_EN_EL_PANEL` es un marcador.

## Modelo de datos

| Tabla | Contenido | Clave de idempotencia |
|---|---|---|
| `clientes` | Copia del cliente de la tienda + `telegram_chat_id` de la cuenta de prueba | `usuario_tienda_id` |
| `pedidos_bo` | Pedido: código, importe, estado, fecha | `pedido_tienda_id`, `codigo_tienda` (UNIQUE) |
| `lineas_bo` | Líneas de cada pedido | (`pedido_id`, `sku`) UNIQUE |
| `tickets` | Incidencias postventa ligadas al cliente y, si hay, al pedido | `incidencia_tienda_id` UNIQUE |
| `log_integracion` | Una fila por evento procesado: `ok`, `error` o `duplicado`, mensaje, payload e id de ejecución de n8n | — |
| `aprobaciones_agente` | Propuesta estructurada del agente IA y la decisión humana | — |

No hay claves foráneas hacia la tienda: son bases de datos distintas. Los identificadores de la tienda se guardan como datos.

Reglas que impone la propia base de datos:
- Los estados solo admiten los valores de la tienda.
- Un ticket `resuelta` exige `resuelto_en`.
- Una propuesta `aprobado` o `rechazado` exige `revisor` y `decidido_en`.
- `confianza` está entre 0 y 1.

## Función `integrar_evento(p jsonb)`

Es la única puerta de escritura. n8n la llama con `POST /rest/v1/rpc/integrar_evento` y el cuerpo `{"p": <evento>}`.

- Procesa `order.created`, `payment.simulated`, `order.status_changed` y `support.requested`.
- Escribe cliente, pedido y líneas, o el ticket, en **una sola transacción**: si algo falla, no queda nada a medias.
- **Idempotencia en dos niveles:** si el `evento_id` ya consta como `ok` en `log_integracion`, devuelve `duplicado` sin escribir; además, las restricciones UNIQUE impiden duplicar filas.
- **Eventos desordenados:** un `order.created` que llega tarde no devuelve el pedido a un estado anterior.
- Un `order.status_changed` de un pedido que aún no existe queda como **pendiente de sincronización**.
- Solo puede ejecutarla `service_role` (la clave secreta, que solo está en n8n).

Respuesta (JSON): `resultado` (`ok`, `duplicado` o `error`), `tipo`, `evento_id`, `mensaje` y, según el caso, `cliente_id`, `pedido_id`, `ticket_id` y `codigo`.

## Vistas

| Vista | Uso |
|---|---|
| `v_metricas_resumen` | Pedidos totales, importe total y medio (sin cancelados), tickets abiertos, propuestas del agente vs. aprobadas |
| `v_pedidos_por_estado` | Pedidos por estado |
| `v_integraciones_por_resultado` | Eventos ok / error / duplicado |
| `v_agente_por_estado` | Propuestas del agente por estado |
| `v_pedidos_por_dia` | Histórico diario (gráfico de barras), hora de Madrid |
| `v_historial_cliente` | Pedidos y tickets de un cliente, **sin email ni Telegram** (minimización de datos) |

Todas usan `security_invoker`, así que respetan el RLS de quien consulta.

## Seguridad

| Quién | Credencial | Puede |
|---|---|---|
| Visitante sin sesión | clave publicable | nada |
| Usuario del back-office (app Vue) | clave publicable + sesión | solo leer |
| n8n | clave secreta (`sb_secret_…`) | leer y escribir |
| n8n autoalojado (opcional) | rol `n8n_svc` | solo su esquema `n8n` |

- Dos capas: permisos de PostgreSQL y políticas RLS de solo lectura.
- El registro de usuarios está desactivado: solo existen las cuentas creadas por el grupo.
- La clave publicable de `backoffice/src/config.js` es pública por diseño; no da permisos por sí sola.
- **Ninguna clave secreta, contraseña ni token está en el repositorio.** La clave secreta solo está en las credenciales de n8n.

## Usuarios de prueba

Las cuentas del back-office se crean en **Authentication → Users → Add user** (con *Auto Confirm User*).

| Rol | Email | Contraseña |
|---|---|---|
| Revisor del back-office | `[EMAIL DE PRUEBA]` | se facilita al profesor por el Campus Virtual, no en el repositorio |

Los clientes del back-office son las cuentas de prueba de la tienda (`@sensotoys-demo.test`).

## Cómo comprobar que funciona

En el SQL Editor del Supabase #2:

```sql
-- Últimos eventos recibidos y su resultado
select evento_id, tipo_evento, resultado, mensaje, creado_en
from public.log_integracion order by id desc limit 10;

-- Resumen del cuadro de mando
select * from public.v_metricas_resumen;

-- Propuestas del agente y decisión humana
select id, ticket_id, tipo_caso, prioridad, confianza, estado, revisor, decidido_en
from public.aprobaciones_agente order by id desc;
```

Para reenviar un evento desde la tienda (Supabase #1): `select public.enviar_evento_n8n(<evento_id>);`. Si ya estaba integrado, aparece como `duplicado` en `log_integracion` y no cambia nada.

## Ejecutar la app en local

```bash
cd backoffice
npm ci
npm run dev        # http://localhost:5173/SENSOTOY/backoffice/
```

Se publica sola en GitHub Pages con cada push a `main` (`.github/workflows/pages.yml`).

## Limitaciones conocidas

- n8n escribe con la clave secreta, que se salta RLS. Como mejora, se usaría un rol de base de datos con permiso de escritura solo en las tablas necesarias.
- Si n8n no está disponible, los eventos no llegan: quedan registrados como fallidos en `envios_webhook` (tienda) y se reenvían a mano. Es seguro gracias a la idempotencia. En producción se usaría una cola con reintentos.
- El cuadro de mando no se actualiza solo: hay que recargar la página.
- Plan gratuito de Supabase: los proyectos se pausan tras un periodo sin uso.
