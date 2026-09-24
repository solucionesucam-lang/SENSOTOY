-- =====================================================================
-- SENSOTOYS · Prototipo académico SIE
-- 03_datos_pedidos.sql — Perfiles, pedidos, pagos, incidencias y eventos
--
-- ANTES de ejecutarlo, crea estos 5 usuarios en
-- Supabase > Authentication > Users > Add user > Create new user
-- (marca "Auto Confirm User"). Son cuentas ficticias de prueba:
--   admin@sensotoys-demo.test
--   cliente1@sensotoys-demo.test ... cliente4@sensotoys-demo.test
-- El trigger del esquema les crea el perfil automáticamente.
--
-- Ejecutar una sola vez sobre una base recién creada.
-- =====================================================================

-- 0. Comprobación: si faltan usuarios, se detiene y no inserta nada
do $$
begin
  if (select count(*) from perfiles where email like '%@sensotoys-demo.test') < 5 then
    raise exception 'Faltan usuarios de prueba: créalos primero en Authentication.';
  end if;
end $$;


-- 1. Nombres y roles de los perfiles de prueba
update perfiles set nombre = d.nombre, rol = d.rol
from (values
  ('admin@sensotoys-demo.test',    'Administración SENSOTOYS', 'admin'),
  ('cliente1@sensotoys-demo.test', 'Cliente de Prueba Uno',    'cliente'),
  ('cliente2@sensotoys-demo.test', 'Cliente de Prueba Dos',    'cliente'),
  ('cliente3@sensotoys-demo.test', 'Cliente de Prueba Tres',   'cliente'),
  ('cliente4@sensotoys-demo.test', 'Cliente de Prueba Cuatro', 'cliente')
) as d(email, nombre, rol)
where perfiles.email = d.email;


-- 2. Pedidos. base_imponible, iva y total los calcula la base de datos sola
--    (columnas generadas en 01_esquema.sql), así que aquí solo se escriben
--    subtotal, descuento y gastos_envio.
--    · Envío 3,95 €; gratis si (subtotal - descuento) >= 45 €
--    · Tarjeta terminada en 0000 = pago rechazado = pedido con incidencia

-- Pedido 1 · enviado · envío gratis (67,70 € >= 45 €)
with p as (
  insert into pedidos (usuario_id, estado, subtotal, descuento, gastos_envio,
                       envio_nombre, envio_direccion, envio_cp, envio_ciudad, envio_provincia, creado_en)
  select id, 'enviado', 67.70, 0, 0,
         'Cliente de Prueba Dos', 'Calle de Prueba, 2', '28001', 'Madrid', 'Madrid', '2026-09-22 19:05+02'
  from perfiles where email = 'cliente2@sensotoys-demo.test'
  returning id
), l as (
  insert into lineas_pedido (pedido_id, variante_id, nombre_producto, descripcion_variante, precio_unitario, cantidad, importe)
  select p.id, v.id, pr.nombre, v.color || ' · Talla ' || v.talla, v.precio, x.cantidad, v.precio * x.cantidad
  from p, (values ('SNS-SET-LAV-U', 2), ('SNS-POP-VER-M', 1)) as x(sku, cantidad)
  join variantes v on v.sku = x.sku join productos pr on pr.id = v.producto_id
)
insert into pagos (pedido_id, proveedor, metodo, importe, resultado, ultimos4, creado_en)
select id, 'simulado', 'tarjeta', 67.70, 'aceptado', '4242', '2026-09-22 19:05:20+02' from p;

-- Pedido 2 · creado · contra reembolso (pago pendiente hasta la entrega)
with p as (
  insert into pedidos (usuario_id, estado, subtotal, descuento, gastos_envio,
                       envio_nombre, envio_direccion, envio_cp, envio_ciudad, envio_provincia, creado_en)
  select id, 'creado', 25.20, 0, 3.95,
         'Cliente de Prueba Cuatro', 'Avenida Ficticia, 4', '50001', 'Zaragoza', 'Zaragoza', '2026-09-23 12:30+02'
  from perfiles where email = 'cliente4@sensotoys-demo.test'
  returning id
), l as (
  insert into lineas_pedido (pedido_id, variante_id, nombre_producto, descripcion_variante, precio_unitario, cantidad, importe)
  select p.id, v.id, pr.nombre, v.color || ' · Talla ' || v.talla, v.precio, x.cantidad, v.precio * x.cantidad
  from p, (values ('SNS-ANI-AZU-U', 1), ('SNS-CUB-GRI-S', 1)) as x(sku, cantidad)
  join variantes v on v.sku = x.sku join productos pr on pr.id = v.producto_id
)
insert into pagos (pedido_id, proveedor, metodo, importe, resultado, ultimos4, creado_en)
select id, 'simulado', 'contrareembolso', 29.15, 'pendiente', null, '2026-09-23 12:30:10+02' from p;

-- Pedido 3 · con incidencia · tarjeta 0000 rechazada
with p as (
  insert into pedidos (usuario_id, estado, subtotal, descuento, gastos_envio,
                       envio_nombre, envio_direccion, envio_cp, envio_ciudad, envio_provincia, creado_en)
  select id, 'incidencia', 20.45, 0, 3.95,
         'Cliente de Prueba Uno', 'Plaza del Ejemplo, 1', '46001', 'Valencia', 'Valencia', '2026-09-23 15:12+02'
  from perfiles where email = 'cliente1@sensotoys-demo.test'
  returning id
), l as (
  insert into lineas_pedido (pedido_id, variante_id, nombre_producto, descripcion_variante, precio_unitario, cantidad, importe)
  select p.id, v.id, pr.nombre, v.color || ' · Talla ' || v.talla, v.precio, x.cantidad, v.precio * x.cantidad
  from p, (values ('SNS-PUL-ROA-S', 1), ('SNS-TUB-TUR-L', 1)) as x(sku, cantidad)
  join variantes v on v.sku = x.sku join productos pr on pr.id = v.producto_id
)
insert into pagos (pedido_id, proveedor, metodo, importe, resultado, ultimos4, creado_en)
select id, 'simulado', 'tarjeta', 24.40, 'rechazado', '0000', '2026-09-23 15:12:25+02' from p;

-- Pedido 4 · pendiente de preparación · cupón BIENVENIDA10 (-5,78 €) y envío gratis
with p as (
  insert into pedidos (usuario_id, estado, subtotal, descuento, gastos_envio, cupon_codigo,
                       envio_nombre, envio_direccion, envio_cp, envio_ciudad, envio_provincia, creado_en)
  select id, 'preparacion', 57.80, 5.78, 0, 'BIENVENIDA10',
         'Cliente de Prueba Tres', 'Calle Inventada, 3', '41001', 'Sevilla', 'Sevilla', '2026-09-23 16:58+02'
  from perfiles where email = 'cliente3@sensotoys-demo.test'
  returning id
), l as (
  insert into lineas_pedido (pedido_id, variante_id, nombre_producto, descripcion_variante, precio_unitario, cantidad, importe)
  select p.id, v.id, pr.nombre, v.color || ' · Talla ' || v.talla, v.precio, x.cantidad, v.precio * x.cantidad
  from p, (values ('SNS-PAN-DOR-L', 2), ('SNS-POP-ROS-M', 1), ('SNS-NUB-CEL-M', 1)) as x(sku, cantidad)
  join variantes v on v.sku = x.sku join productos pr on pr.id = v.producto_id
)
insert into pagos (pedido_id, proveedor, metodo, importe, resultado, ultimos4, creado_en)
select id, 'simulado', 'tarjeta', 52.02, 'aceptado', '7721', '2026-09-23 16:58:40+02' from p;

-- Pedido 5 · cancelado por el cliente antes de pagar (sin pago)
with p as (
  insert into pedidos (usuario_id, estado, subtotal, descuento, gastos_envio,
                       envio_nombre, envio_direccion, envio_cp, envio_ciudad, envio_provincia, creado_en)
  select id, 'cancelado', 29.90, 0, 3.95,
         'Cliente de Prueba Dos', 'Calle de Prueba, 2', '28001', 'Madrid', 'Madrid', '2026-09-23 17:41+02'
  from perfiles where email = 'cliente2@sensotoys-demo.test'
  returning id
)
insert into lineas_pedido (pedido_id, variante_id, nombre_producto, descripcion_variante, precio_unitario, cantidad, importe)
select p.id, v.id, pr.nombre, v.color || ' · Talla ' || v.talla, v.precio, x.cantidad, v.precio * x.cantidad
from p, (values ('SNS-SET-LAV-U', 1)) as x(sku, cantidad)
join variantes v on v.sku = x.sku join productos pr on pr.id = v.producto_id;

-- Pedido 6 · pagado · el mismo ejemplo que la vista previa (42,85 €)
with p as (
  insert into pedidos (usuario_id, estado, subtotal, descuento, gastos_envio,
                       envio_nombre, envio_direccion, envio_cp, envio_ciudad, envio_provincia, creado_en)
  select id, 'pagado', 38.90, 0, 3.95,
         'Cliente de Prueba Uno', 'Plaza del Ejemplo, 1', '46001', 'Valencia', 'Valencia', '2026-09-23 18:07:15+02'
  from perfiles where email = 'cliente1@sensotoys-demo.test'
  returning id
), l as (
  insert into lineas_pedido (pedido_id, variante_id, nombre_producto, descripcion_variante, precio_unitario, cantidad, importe)
  select p.id, v.id, pr.nombre, v.color || ' · Talla ' || v.talla, v.precio, x.cantidad, v.precio * x.cantidad
  from p, (values ('SNS-AUR-ROS-M', 1), ('SNS-CUB-VER-S', 1)) as x(sku, cantidad)
  join variantes v on v.sku = x.sku join productos pr on pr.id = v.producto_id
)
insert into pagos (pedido_id, proveedor, metodo, importe, resultado, ultimos4, creado_en)
select id, 'simulado', 'tarjeta', 42.85, 'aceptado', '4242', '2026-09-23 18:07:16+02' from p;


-- 3. Incidencias (formulario de soporte)
insert into incidencias (usuario_id, pedido_id, motivo, mensaje, estado, creado_en)
select u.id, pe.id, i.motivo, i.mensaje, i.estado, i.fecha::timestamptz
from (values
  ('cliente1@sensotoys-demo.test', '2026-09-23 15:12+02', 'pago_rechazado',
   'Me ha rechazado el pago con la tarjeta de prueba y el pedido se ha quedado bloqueado.', 'abierta', '2026-09-23 15:20:47+02'),
  ('cliente2@sensotoys-demo.test', '2026-09-22 19:05+02', 'retraso_envio',
   'El seguimiento no se ha actualizado desde ayer, ¿podéis revisarlo?', 'resuelta', '2026-09-23 10:02:00+02')
) as i(email, fecha_pedido, motivo, mensaje, estado, fecha)
join perfiles u on u.email = i.email
join pedidos pe on pe.usuario_id = u.id and pe.creado_en = i.fecha_pedido::timestamptz;


-- 4. Eventos de negocio
-- El pedido de cada evento se localiza por su cliente y su fecha de creación.
insert into eventos (tipo, usuario_id, sesion_id, pedido_id, datos, creado_en)
select e.tipo, u.id, e.sesion, pe.id, e.datos::jsonb, e.fecha::timestamptz
from (values
  -- Visitante anónimo que solo mira (sin usuario)
  ('product.viewed',    null, 'ses-anon-01', null, '{"producto":"nube-mochi-aurora","sku":"SNS-AUR-LAV-M"}', '2026-09-23 11:48:02+02'),
  ('product.viewed',    null, 'ses-anon-01', null, '{"producto":"set-calma-nocturna","sku":"SNS-SET-LAV-U"}', '2026-09-23 11:49:30+02'),
  -- Recorrido completo del pedido 6 (cliente1)
  ('product.viewed',    'cliente1@sensotoys-demo.test', 'ses-demo-06', null, '{"producto":"nube-mochi-aurora","sku":"SNS-AUR-ROS-M"}', '2026-09-23 18:04:11+02'),
  ('cart.item_added',   'cliente1@sensotoys-demo.test', 'ses-demo-06', null, '{"sku":"SNS-AUR-ROS-M","cantidad":1,"precio":24.90}', '2026-09-23 18:04:48+02'),
  ('product.viewed',    'cliente1@sensotoys-demo.test', 'ses-demo-06', null, '{"producto":"cubo-infinito-mate","sku":"SNS-CUB-VER-S"}', '2026-09-23 18:05:02+02'),
  ('cart.item_added',   'cliente1@sensotoys-demo.test', 'ses-demo-06', null, '{"sku":"SNS-CUB-VER-S","cantidad":1,"precio":14.00}', '2026-09-23 18:05:20+02'),
  ('checkout.started',  'cliente1@sensotoys-demo.test', 'ses-demo-06', null, '{"lineas":2,"subtotal":38.90}', '2026-09-23 18:06:02+02'),
  ('order.created',     'cliente1@sensotoys-demo.test', 'ses-demo-06', '2026-09-23 18:07:15+02', '{"total":42.85}', '2026-09-23 18:07:15+02'),
  ('payment.simulated', 'cliente1@sensotoys-demo.test', 'ses-demo-06', '2026-09-23 18:07:15+02', '{"resultado":"aceptado","ultimos4":"4242","importe":42.85}', '2026-09-23 18:07:16+02'),
  -- Resto de pedidos
  ('order.created',     'cliente2@sensotoys-demo.test', 'ses-demo-01', '2026-09-22 19:05+02', '{"total":67.70}', '2026-09-22 19:05:00+02'),
  ('payment.simulated', 'cliente2@sensotoys-demo.test', 'ses-demo-01', '2026-09-22 19:05+02', '{"resultado":"aceptado","ultimos4":"4242","importe":67.70}', '2026-09-22 19:05:20+02'),
  ('order.created',     'cliente4@sensotoys-demo.test', 'ses-demo-02', '2026-09-23 12:30+02', '{"total":29.15}', '2026-09-23 12:30:00+02'),
  ('payment.simulated', 'cliente4@sensotoys-demo.test', 'ses-demo-02', '2026-09-23 12:30+02', '{"resultado":"pendiente","metodo":"contrareembolso","importe":29.15}', '2026-09-23 12:30:10+02'),
  ('order.created',     'cliente1@sensotoys-demo.test', 'ses-demo-03', '2026-09-23 15:12+02', '{"total":24.40}', '2026-09-23 15:12:00+02'),
  ('payment.simulated', 'cliente1@sensotoys-demo.test', 'ses-demo-03', '2026-09-23 15:12+02', '{"resultado":"rechazado","ultimos4":"0000","importe":24.40}', '2026-09-23 15:12:25+02'),
  ('support.requested', 'cliente1@sensotoys-demo.test', 'ses-demo-03', '2026-09-23 15:12+02', '{"motivo":"pago_rechazado"}', '2026-09-23 15:20:47+02'),
  ('order.created',     'cliente3@sensotoys-demo.test', 'ses-demo-04', '2026-09-23 16:58+02', '{"total":52.02,"cupon":"BIENVENIDA10"}', '2026-09-23 16:58:00+02'),
  ('payment.simulated', 'cliente3@sensotoys-demo.test', 'ses-demo-04', '2026-09-23 16:58+02', '{"resultado":"aceptado","ultimos4":"7721","importe":52.02}', '2026-09-23 16:58:40+02'),
  ('order.created',     'cliente2@sensotoys-demo.test', 'ses-demo-05', '2026-09-23 17:41+02', '{"total":33.85}', '2026-09-23 17:41:00+02'),
  ('support.requested', 'cliente2@sensotoys-demo.test', 'ses-demo-01', '2026-09-22 19:05+02', '{"motivo":"retraso_envio"}', '2026-09-23 10:02:00+02')
) as e(tipo, email, sesion, fecha_pedido, datos, fecha)
left join perfiles u on u.email = e.email
left join pedidos pe on pe.usuario_id = u.id and pe.creado_en = e.fecha_pedido::timestamptz;


-- 5. Comprobación: el subtotal de cada pedido debe coincidir con sus líneas
--    (si esta consulta devuelve filas, hay un pedido mal calculado)
select p.codigo, p.subtotal, sum(l.importe) as suma_lineas
from pedidos p join lineas_pedido l on l.pedido_id = p.id
group by p.id, p.codigo, p.subtotal
having p.subtotal <> sum(l.importe);
