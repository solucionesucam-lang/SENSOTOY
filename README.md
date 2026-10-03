# SENSOTOYS · Canal digital de venta (prototipo académico)

Tarea 1 de Soluciones Informáticas para la Empresa (UCAM).
**Prototipo académico sin actividad comercial real.** Todos los datos, usuarios y pagos son ficticios.

## Arquitectura

| Capa | Dónde está | Qué hace |
|---|---|---|
| Interfaz | `*.html`, `css/`, `js/ui.js` | Pantallas, formularios y validación rápida para el usuario |
| Acceso a datos | `js/datos.js` | Único fichero que habla con Supabase |
| Lógica de negocio | `sql/04` a `sql/16` | Precios, cupones, envío, stock, estados, incidencias, pago simulado y eventos, dentro de PostgreSQL |
| Persistencia | Supabase (PostgreSQL) | Tablas de `sql/01` a `sql/03` |

La web se publica como páginas estáticas en GitHub Pages y llama a Supabase desde el navegador con la clave pública. La seguridad la dan las políticas RLS y las funciones de la base de datos, no el navegador.

Sin frameworks. La única librería externa es `supabase-js`, fijada en la versión **2.117.2** (import desde jsDelivr en `js/datos.js`). Las fuentes Fraunces y Karla están en local, en `fonts/` (`fraunces.woff2` y `karla.woff2`, cargadas con `@font-face` en `css/estilos.css`), sin peticiones a Google Fonts.

## Estructura

```
index.html        Inicio
catalogo.html     Catálogo con filtro por categoría (?categoria=slug)
producto.html     Ficha de producto (?slug=...)
carrito.html      Carrito (se guarda en el navegador hasta comprar)
checkout.html     Datos de envío, cupón y pago simulado
pedido.html       Mis pedidos / detalle de un pedido (?codigo=...), cancelación
soporte.html      Ayuda y postventa (incidencias)
login.html        Entrada con cuentas de prueba
admin.html        Back-office: pedidos, estados, eventos, incidencias, stock, exportación
config.js         URL y clave pública de Supabase
css/estilos.css
fonts/            Fuentes locales (Fraunces y Karla)
img/productos/    Fotos de producto (<slug>-<color>.webp, con <slug>.webp como alternativa)
js/datos.js       Capa de acceso a datos
js/ui.js          Cabecera, pie, carrito y utilidades
sql/              Scripts de la base de datos y sql/pruebas.sql
```

## Instalación

### 1. Base de datos

En Supabase > SQL Editor, ejecuta los scripts de `sql/` en este orden exacto:

1. `01_esquema.sql`
2. `02_datos_catalogo.sql`
3. **Crear los usuarios de prueba** (ver más abajo)
4. `03_datos_pedidos.sql`
5. `04_seguridad_y_funciones.sql`
6. `05_maquina_estados_pedido.sql`
7. `06_validar_cupon.sql`
8. `07_evento_estado.sql`
9. `08_metricas.sql`
10. `09_correcciones.sql`
11. `10_estados_e_incidencias.sql`
12. `11_configuracion.sql`
13. `12_estados_y_eventos.sql`
14. `13_incidencias.sql`
15. `14_stock.sql`
16. `15_avance_automatico.sql`
17. `16_metricas_y_destacados.sql`
18. `pruebas.sql` (opcional; no deja datos, ver "Pruebas de la lógica")

La numeración es continua, de 01 a 16. `07` solo amplía el `CHECK` de `eventos.tipo` con los 8 tipos de evento y crea la vista `v_eventos_export`. `10` es un puente: define `cambiar_estado_pedido()` y `crear_incidencia()` con eventos, y `12` y `13` las sustituyen; si se relanza después de `12`, detecta `aplicar_cambio_estado()` y no pisa nada. Los scripts `07` y `10` a `16` son idempotentes (se pueden repetir sin problema). `01` a `06` y `08` se ejecutan una sola vez, en este orden; `09` también se puede repetir.

**Si la base ya tenía el `07` y el `10` antiguos** (los de `main`, con función y `search_path = public`): basta ejecutar `07` y `10` nuevos (opcional) y después `11` a `16`. `12` y `13` sustituyen las funciones y el `CHECK` final queda con los 8 tipos.

Dependencias (según sus cabeceras): `03` necesita los usuarios ya creados; `04` va después de `01`, `02` y `03`; `05` después de `01` a `04`; `07` después de `01` a `06` y antes de `08` y `09`; `08` después de `01` a `04`; `10` después de `09` y antes de `11`; `11` después de `01` a `06`, `08` y `09`; `12` después de `11`; `13`, `14`, `15` y `16` después de `12`.

**Usuarios de prueba, antes del 03.** Créalos en Supabase > Authentication > Users > Add user > Create new user, marcando "Auto Confirm User" (lista en "Usuarios de prueba"). El trigger del esquema crea el perfil de cada uno. `03_datos_pedidos.sql` comprueba primero que existen los 5 usuarios: si falta alguno se detiene sin insertar nada. Después, con ellos, crea perfiles, pedidos, pagos, incidencias y eventos de ejemplo; debe ejecutarse una sola vez sobre una base recién creada.

### 2. Configuración de la web

Copia en `config.js` la URL del proyecto y la clave **pública** (Project Settings > API Keys). Nunca la clave secret ni la service_role.

### 3. Publicación

Sube todo al repositorio de GitHub y activa GitHub Pages (Settings > Pages > Deploy from a branch > rama de publicación / raíz).

## Ejecución en local

Los módulos de JavaScript no funcionan abriendo el fichero con doble clic. Hay que servir la carpeta, por ejemplo:

```
python -m http.server 8000
```

y abrir `http://localhost:8000`. También sirve la extensión Live Server de VS Code.

## Usuarios de prueba

Creados en Supabase > Authentication > Users > Add user (marcando "Auto Confirm User"):

| Correo | Rol |
|---|---|
| admin@sensotoys-demo.test | admin (acceso al back-office) |
| cliente1@sensotoys-demo.test … cliente4@sensotoys-demo.test | cliente |

Contraseña: la que haya elegido el grupo para las cuentas de prueba (no reutilizar contraseñas personales).

## Datos para probar

- Tarjeta aceptada: `4242 4242 4242 4242`.
- Tarjeta rechazada: cualquier número de 16 cifras acabado en `0000` (el pedido queda "Con incidencia").
- Cupón válido: `BIENVENIDA10` (10 %, pedido mínimo 20 €, un solo uso por cliente; si el pedido se cancela, el cupón vuelve a estar disponible). Cupón caducado: `VERANO5`.
- Envío, envío gratis y máximo por producto: ver "Configuración de negocio".

## Configuración de negocio

Las constantes viven en la tabla `configuracion` (`sql/11`). La web las lee con `obtener_configuracion()` y `crear_pedido()` las usa desde la misma tabla, así que no se desincronizan.

| Clave | Valor inicial | Significado |
|---|---|---|
| `max_por_producto` | 3 | Unidades máximas de un mismo producto por pedido |
| `envio_gratis_desde` | 45 | Importe (IVA incl., tras descuento) desde el que el envío es gratis |
| `gastos_envio` | 3,95 | Gastos de envío por debajo de ese importe |

Para cambiarlas, en el SQL Editor: `update public.configuracion set valor = 5 where clave = 'gastos_envio';`. La tabla no tiene permisos para la web: solo la leen las funciones. Volver a ejecutar `sql/11` no pisa los valores que ya hayas cambiado.

## Estados del pedido

Los saltos permitidos están en una tabla (`sql/05`). Toda la lógica de cambio vive en la función interna `aplicar_cambio_estado()` (`sql/12`), que usan el admin, el cliente y el avance automático.

- **Cancelación por el cliente:** `cancelar_mi_pedido()` deja al cliente cancelar su pedido solo mientras esté en `creado` (botón en `pedido.html`). Devuelve el stock y libera el cupón de un solo uso.
- **Cancelar un pedido que ya llegó a enviarse no devuelve el stock:** las unidades salieron del almacén.
- **Avance automático cada 5 h** (`sql/15`): `avanzar_pedidos()` mueve un paso los pedidos que llevan 5 horas o más en el mismo estado: `pagado` a `preparacion`, `preparacion` a `enviado`, y `creado` a `preparacion` solo si el pago es contra reembolso. Nunca toca pedidos en `incidencia` ni `cancelado`, y un pedido avanza como mucho un paso por ejecución. Se programa con pg_cron cada hora en punto.
  - **Activar pg_cron:** Supabase > Database > Extensions > pg_cron, y después volver a ejecutar `sql/15_avance_automatico.sql`. Si pg_cron no está activo, el script avisa con un `notice` y los pedidos NO avanzarán solos hasta activarlo y repetir el script.
  - Los pedidos existentes empiezan a contar desde la migración (`sql/12` toma el momento de ejecutarse como fecha del último cambio), para que no avancen todos de golpe.

## Incidencias

- `crear_incidencia()` (`sql/13`) registra siempre la incidencia, pero **solo los motivos `producto_defectuoso` y `retraso_envio` mueven el pedido al estado `incidencia`**. Con `otro` y `pago_rechazado` la incidencia se registra y el pedido no cambia.
- El admin gestiona cada incidencia con `cambiar_estado_incidencia()`: `abierta` → `en_curso` → `resuelta`.

## Stock

`reponer_stock()` (`sql/14`, solo admin, desde el back-office) suma de **1 a 500** unidades a una variante. En ediciones limitadas no deja superar la tirada: el stock de todas las variantes del producto más lo ya vendido tiene que ser menor o igual que `unidades_edicion`. Lo vendido son las líneas de pedidos no cancelados y de cancelados que llegaron a enviarse. La vista `v_stock_variantes` muestra el stock por variante.

## Eventos

Se guardan en la tabla `eventos`. Tipos permitidos por el `CHECK` (`sql/07`, repetido en `sql/12`):

| Evento | Quién lo dispara |
|---|---|
| `product.viewed` | Navegador (`producto.html`) → `registrar_evento()` |
| `cart.item_added` | Navegador (`producto.html`) → `registrar_evento()` |
| `checkout.started` | Navegador (`checkout.html`) → `registrar_evento()` |
| `order.created` | `crear_pedido()` |
| `payment.simulated` | `crear_pedido()` |
| `support.requested` | `crear_incidencia()` |
| `order.status_changed` | `aplicar_cambio_estado()`: cambio del admin, cancelación del cliente (`cancelar_mi_pedido()`) y avance automático (en ese caso con `{"de", "a", "automatico": true}` y sin usuario) |
| `stock.replenished` | `reponer_stock()` |

**Exportación:** desde el back-office (`admin.html`), los eventos se exportan como JSON (`eventos-sensotoys.json`) y los pedidos como CSV (`pedidos-sensotoys.csv`, separado por `;` y con BOM para que Excel abra bien las tildes).

## Pruebas de la lógica (`sql/pruebas.sql`)

Ejecutar después de todos los scripts (01 a 16) y con los usuarios de prueba creados. En el SQL Editor, **selecciona un bloque cada vez** (de `do $$` a `$$;`, cada uno marcado con `-- @prueba n`) y pulsa Run. Cada bloque termina siempre con un `raise exception` que **deshace todo lo que hizo, así que no deja datos**; el mensaje del error es el resultado:

- `PRUEBA n · OK: ...` → la prueba pasa.
- `PRUEBA n · FALLO: ...` → hay un fallo en la lógica.

Salida esperada: las 10 pruebas dan `OK` (transiciones prohibidas, incidencias, reponer stock, cupón de un solo uso, avance automático, cancelación del cliente, cancelar tras enviar, gestión de incidencias, configuración y rechazos, destacados). Cada bloque simula un usuario con `request.jwt.claims` y crea su propio producto de prueba, así que no depende del catálogo.

## Limitaciones conocidas

- El pago es simulado; no hay pasarela real.
- El carrito se guarda en el navegador, por usuario, hasta la compra (el evento `cart.item_added` sí queda en la base de datos).
- Cualquiera puede registrar eventos de navegación, así que podrían inflarse artificialmente.
- El desglose de IVA se aplica solo a los productos; el envío se muestra sin desglose.
- El plan gratuito de Supabase pausa el proyecto tras una semana sin actividad.
