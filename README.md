# SENSOTOYS · Canal digital de venta (prototipo académico)

Tarea 1 de Soluciones Informáticas para la Empresa (UCAM).
**Prototipo académico sin actividad comercial real.** Todos los datos, usuarios y pagos son ficticios.

## Arquitectura

| Capa | Dónde está | Qué hace |
|---|---|---|
| Interfaz | `*.html`, `css/`, `js/ui.js` | Pantallas, formularios y validación rápida para el usuario |
| Acceso a datos | `js/datos.js` | Único fichero que habla con Supabase |
| Lógica de negocio | `sql/04_seguridad_y_funciones.sql` (y sus correcciones en `sql/09_correcciones.sql`) | Precios, cupones, envío, stock, pago simulado y eventos, dentro de PostgreSQL |
| Persistencia | Supabase (PostgreSQL) | Tablas de `sql/01` a `sql/03` |

La web se publica como páginas estáticas en GitHub Pages y llama a Supabase desde el navegador con la clave pública. La seguridad la dan las políticas RLS y las funciones de la base de datos, no el navegador.

## Estructura

```
index.html        Inicio
catalogo.html     Catálogo con filtro por categoría (?categoria=slug)
producto.html     Ficha de producto (?slug=...)
carrito.html      Carrito (se guarda en el navegador hasta comprar)
checkout.html     Datos de envío, cupón y pago simulado
pedido.html       Mis pedidos / detalle de un pedido (?codigo=...)
soporte.html      Ayuda y postventa (incidencias)
login.html        Entrada con cuentas de prueba
admin.html        Back-office: pedidos, estados, eventos, incidencias, exportación
config.js         URL y clave pública de Supabase
css/estilos.css
img/productos/    Fotos de producto (<slug>-<color>.webp, con <slug>.webp como alternativa)
js/datos.js       Capa de acceso a datos
js/ui.js          Cabecera, pie, carrito y utilidades
sql/              Scripts de la base de datos
```

## Instalación

1. En Supabase > SQL Editor, ejecutar en orden `01_esquema.sql`, `02_datos_catalogo.sql`, crear los usuarios de prueba (ver abajo), `03_datos_pedidos.sql`, `04_seguridad_y_funciones.sql`, `05_maquina_estados_pedido.sql` (transiciones de estado permitidas), `06_validar_cupon.sql` (validación de cupones desde el checkout), `08_metricas.sql` (vistas del back-office) y `09_correcciones.sql` (correcciones de lógica, seguridad e índices). No existe `07`: la numeración salta de 06 a 08. Los scripts se ejecutan una sola vez cada uno y en este orden; `09` se puede repetir sin problema.
2. Copiar en `config.js` la URL del proyecto y la clave **pública** (Project Settings > API Keys). Nunca la clave secret ni la service_role.
3. Subir todo al repositorio de GitHub y activar GitHub Pages (Settings > Pages > Deploy from a branch > `main` / raíz).

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

- Tarjeta aceptada: `4242 4242 4242 4242`
- Tarjeta rechazada: cualquier número de 16 cifras acabado en `0000` (el pedido queda "Con incidencia")
- Cupón válido: `BIENVENIDA10` (10 %, pedido mínimo 20 €, un solo uso por cliente; si el pedido se cancela, el cupón vuelve a estar disponible). Cupón caducado: `VERANO5`
- Envío 3,95 €, gratis desde 45 €. Máximo 3 unidades por producto.

## Eventos

| Evento | Dónde se genera |
|---|---|
| product.viewed, cart.item_added, checkout.started | Navegador → función `registrar_evento()` |
| order.created, payment.simulated | Dentro de `crear_pedido()` |
| support.requested | Dentro de `crear_incidencia()` |

Se guardan en la tabla `eventos` y se consultan o exportan (JSON y CSV) desde el back-office.

## Limitaciones conocidas

- El pago es simulado; no hay pasarela real.
- El carrito se guarda en el navegador, por usuario, hasta la compra (el evento `cart.item_added` sí queda en la base de datos).
- Cualquiera puede registrar eventos de navegación, así que podrían inflarse artificialmente.
- El desglose de IVA se aplica solo a los productos; el envío se muestra sin desglose.
- El plan gratuito de Supabase pausa el proyecto tras una semana sin actividad.
