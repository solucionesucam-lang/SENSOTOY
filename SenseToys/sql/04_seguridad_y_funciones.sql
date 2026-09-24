-- =====================================================================
-- SENSOTOYS · Prototipo académico SIE
-- 04_seguridad_y_funciones.sql — Qué puede hacer la web con cada tabla
-- Ejecutar DESPUÉS de 01, 02 y 03 (una sola vez).
--
-- Idea general:
--   · La web solo puede LEER tablas, y solo las filas que le tocan (RLS).
--   · La web NUNCA escribe directamente en las tablas. Para escribir llama
--     a funciones de la base de datos, que validan todo y calculan precios,
--     descuentos, envío y stock. Así nadie puede manipular un total desde
--     el navegador.
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1. ¿Es administrador quien hace la petición?
-- "security definer" = se ejecuta con permisos del dueño de la tabla, para
-- poder consultar perfiles sin chocar con sus propias políticas.
-- ---------------------------------------------------------------------
create or replace function public.es_admin()
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (select 1 from public.perfiles
                 where id = auth.uid() and rol = 'admin');
$$;


-- ---------------------------------------------------------------------
-- 2. PERMISOS DE LECTURA (GRANT) + POLÍTICAS (qué filas se ven)
-- anon = visitante sin sesión · authenticated = usuario con sesión
-- ---------------------------------------------------------------------

-- Catálogo: lo ve cualquiera
grant select on public.categorias, public.productos, public.variantes to anon, authenticated;

create policy "catalogo: todos ven categorias" on public.categorias
  for select to anon, authenticated using (true);
create policy "catalogo: todos ven productos activos" on public.productos
  for select to anon, authenticated using (activo);
create policy "catalogo: todos ven variantes activas" on public.variantes
  for select to anon, authenticated using (activo);

-- Datos de clientes: solo con sesión iniciada
grant select on public.perfiles, public.pedidos, public.lineas_pedido,
                public.pagos, public.incidencias to authenticated;

create policy "perfiles: el propio o admin" on public.perfiles
  for select to authenticated using (id = auth.uid() or public.es_admin());

create policy "pedidos: los propios o admin" on public.pedidos
  for select to authenticated using (usuario_id = auth.uid() or public.es_admin());

create policy "lineas: las de mis pedidos o admin" on public.lineas_pedido
  for select to authenticated using (
    exists (select 1 from public.pedidos p where p.id = pedido_id
            and (p.usuario_id = auth.uid() or public.es_admin())));

create policy "pagos: los de mis pedidos o admin" on public.pagos
  for select to authenticated using (
    exists (select 1 from public.pedidos p where p.id = pedido_id
            and (p.usuario_id = auth.uid() or public.es_admin())));

create policy "incidencias: las propias o admin" on public.incidencias
  for select to authenticated using (usuario_id = auth.uid() or public.es_admin());

-- Eventos: solo los lee el administrador (back-office y exportación)
grant select on public.eventos to authenticated;
create policy "eventos: solo admin" on public.eventos
  for select to authenticated using (public.es_admin());

-- cupones: sin permisos. La web no puede listarlos; solo se validan
-- dentro de crear_pedido().


-- ---------------------------------------------------------------------
-- 3. REGISTRAR EVENTOS DE NAVEGACIÓN
-- Solo los 3 eventos que ocurren en el navegador. order.created,
-- payment.simulated y support.requested los crea la propia base de datos
-- dentro de sus funciones, para que no se puedan falsificar.
-- ---------------------------------------------------------------------
create or replace function public.registrar_evento(
  p_tipo text, p_sesion text, p_datos jsonb default '{}')
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  if p_tipo not in ('product.viewed', 'cart.item_added', 'checkout.started') then
    raise exception 'Tipo de evento no permitido desde la web: %', p_tipo;
  end if;
  if length(coalesce(p_datos, '{}')::text) > 2000 then
    raise exception 'Datos del evento demasiado grandes';
  end if;
  insert into public.eventos (tipo, usuario_id, sesion_id, datos)
  values (p_tipo, auth.uid(), left(p_sesion, 60), coalesce(p_datos, '{}'));
end;
$$;


-- ---------------------------------------------------------------------
-- 4. CREAR PEDIDO (carrito → pedido + líneas + pago simulado + stock)
-- Todo ocurre en una sola transacción: si algo falla, no se guarda nada.
--
-- p_lineas: [{"variante_id": 1, "cantidad": 2}, ...]
-- p_envio:  {"nombre","direccion","cp","ciudad","provincia"}
-- p_metodo: 'tarjeta' o 'contrareembolso'
-- Tarjetas de prueba: 4242 4242 4242 4242 → aceptado
--                     cualquier número de 16 dígitos acabado en 0000 → rechazado
-- ---------------------------------------------------------------------
create or replace function public.crear_pedido(
  p_lineas  jsonb,
  p_envio   jsonb,
  p_metodo  text,
  p_tarjeta text default null,
  p_cupon   text default null,
  p_sesion  text default null)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  v_usuario   uuid := auth.uid();
  v_linea     record;
  v_num_filas int := 0;
  v_subtotal  numeric(10,2) := 0;
  v_descuento numeric(10,2) := 0;
  v_envio     numeric(10,2);
  v_cupon     public.cupones%rowtype;
  v_tarjeta   text;
  v_ultimos4  char(4);
  v_resultado text;
  v_estado    text;
  v_pedido    public.pedidos%rowtype;
begin
  -- 4.1 Comprobaciones básicas
  if v_usuario is null then
    raise exception 'Tienes que iniciar sesión para comprar';
  end if;
  if p_lineas is null or jsonb_typeof(p_lineas) <> 'array'
     or jsonb_array_length(p_lineas) = 0 then
    raise exception 'El carrito está vacío';
  end if;
  if p_metodo not in ('tarjeta', 'contrareembolso') then
    raise exception 'Método de pago no válido';
  end if;
  if coalesce(trim(p_envio ->> 'nombre'), '') = '' or coalesce(trim(p_envio ->> 'direccion'), '') = ''
     or coalesce(trim(p_envio ->> 'ciudad'), '') = '' or coalesce(trim(p_envio ->> 'provincia'), '') = '' then
    raise exception 'Faltan datos de envío';
  end if;
  if coalesce(trim(p_envio ->> 'cp'), '') !~ '^[0-9]{5}$' then
    raise exception 'El código postal debe tener 5 dígitos';
  end if;

  -- 4.2 Líneas: precio y stock SIEMPRE de la base de datos.
  -- "for update" bloquea esas variantes hasta terminar, para que dos
  -- compras a la vez no vendan la misma última unidad.
  for v_linea in
    select v.id, v.precio, v.stock, (x ->> 'cantidad')::int as cantidad
    from jsonb_array_elements(p_lineas) as x
    join public.variantes v on v.id = (x ->> 'variante_id')::bigint and v.activo
    join public.productos pr on pr.id = v.producto_id and pr.activo
    for update of v
  loop
    if v_linea.cantidad is null or v_linea.cantidad not between 1 and 3 then
      raise exception 'Cantidad no válida: máximo 3 unidades por producto';
    end if;
    if v_linea.cantidad > v_linea.stock then
      raise exception 'No queda stock suficiente de uno de los productos (quedan %)', v_linea.stock;
    end if;
    v_subtotal  := v_subtotal + v_linea.precio * v_linea.cantidad;
    v_num_filas := v_num_filas + 1;
  end loop;

  if v_num_filas <> jsonb_array_length(p_lineas) then
    raise exception 'Algún producto del carrito ya no está disponible';
  end if;

  -- 4.3 Cupón
  if nullif(trim(p_cupon), '') is not null then
    select * into v_cupon from public.cupones where codigo = upper(trim(p_cupon));
    if not found or not v_cupon.activo
       or (v_cupon.valido_hasta is not null and v_cupon.valido_hasta < current_date) then
      raise exception 'El cupón no existe o ha caducado';
    end if;
    if v_subtotal < v_cupon.importe_minimo then
      raise exception 'El cupón exige un pedido mínimo de % €', v_cupon.importe_minimo;
    end if;
    if v_cupon.tipo = 'porcentaje' then
      v_descuento := round(v_subtotal * v_cupon.valor / 100, 2);
    else
      v_descuento := least(v_cupon.valor, v_subtotal);
    end if;
  end if;

  -- 4.4 Envío: 3,95 €, gratis desde 45 € (después del descuento)
  v_envio := case when v_subtotal - v_descuento >= 45 then 0 else 3.95 end;

  -- 4.5 Pago simulado (solo se guardan los 4 últimos dígitos)
  if p_metodo = 'tarjeta' then
    v_tarjeta := regexp_replace(coalesce(p_tarjeta, ''), '\s', '', 'g');
    if v_tarjeta !~ '^[0-9]{16}$'
       or not (v_tarjeta like '4242%' or v_tarjeta like '%0000') then
      raise exception 'Usa una tarjeta de prueba (4242 4242 4242 4242, o una acabada en 0000 para simular un rechazo)';
    end if;
    v_ultimos4 := right(v_tarjeta, 4);
    if v_ultimos4 = '0000' then
      v_resultado := 'rechazado';  v_estado := 'incidencia';
    else
      v_resultado := 'aceptado';   v_estado := 'pagado';
    end if;
  else
    v_resultado := 'pendiente';    v_estado := 'creado';
  end if;

  -- 4.6 Guardar el pedido (base, IVA y total los calcula la tabla sola)
  insert into public.pedidos (usuario_id, estado, subtotal, descuento, gastos_envio,
                              cupon_codigo, envio_nombre, envio_direccion,
                              envio_cp, envio_ciudad, envio_provincia)
  values (v_usuario, v_estado, v_subtotal, v_descuento, v_envio,
          v_cupon.codigo,
          trim(p_envio ->> 'nombre'), trim(p_envio ->> 'direccion'),
          trim(p_envio ->> 'cp'), trim(p_envio ->> 'ciudad'),
          trim(p_envio ->> 'provincia'))
  returning * into v_pedido;

  -- 4.7 Líneas del pedido: copia de nombre, variante y precio
  insert into public.lineas_pedido (pedido_id, variante_id, nombre_producto,
                                    descripcion_variante, precio_unitario,
                                    cantidad, importe)
  select v_pedido.id, v.id, pr.nombre, v.color || ' · Talla ' || v.talla,
         v.precio, (x ->> 'cantidad')::int, v.precio * (x ->> 'cantidad')::int
  from jsonb_array_elements(p_lineas) as x
  join public.variantes v on v.id = (x ->> 'variante_id')::bigint
  join public.productos pr on pr.id = v.producto_id;

  -- 4.8 Descontar stock (si el pago se rechaza, no se descuenta)
  if v_resultado <> 'rechazado' then
    update public.variantes v
    set stock = v.stock - (x ->> 'cantidad')::int
    from jsonb_array_elements(p_lineas) as x
    where v.id = (x ->> 'variante_id')::bigint;
  end if;

  -- 4.9 Pago y eventos
  insert into public.pagos (pedido_id, proveedor, metodo, importe, resultado, ultimos4)
  values (v_pedido.id, 'simulado', p_metodo, v_pedido.total, v_resultado, v_ultimos4);

  insert into public.eventos (tipo, usuario_id, sesion_id, pedido_id, datos) values
    ('order.created', v_usuario, left(p_sesion, 60), v_pedido.id,
     jsonb_build_object('codigo', v_pedido.codigo, 'total', v_pedido.total,
                        'lineas', v_num_filas, 'cupon', v_cupon.codigo)),
    ('payment.simulated', v_usuario, left(p_sesion, 60), v_pedido.id,
     jsonb_build_object('metodo', p_metodo, 'resultado', v_resultado,
                        'ultimos4', v_ultimos4, 'importe', v_pedido.total));

  return jsonb_build_object('codigo', v_pedido.codigo, 'estado', v_estado,
                            'resultado', v_resultado, 'total', v_pedido.total);
end;
$$;


-- ---------------------------------------------------------------------
-- 5. ABRIR UNA INCIDENCIA (formulario de ayuda y postventa)
-- ---------------------------------------------------------------------
create or replace function public.crear_incidencia(
  p_motivo text, p_mensaje text, p_pedido_id bigint default null, p_sesion text default null)
returns bigint
language plpgsql security definer set search_path = ''
as $$
declare
  v_usuario uuid := auth.uid();
  v_id bigint;
begin
  if v_usuario is null then
    raise exception 'Tienes que iniciar sesión para abrir una incidencia';
  end if;
  if p_pedido_id is not null and not exists (
       select 1 from public.pedidos where id = p_pedido_id and usuario_id = v_usuario) then
    raise exception 'Ese pedido no es tuyo';
  end if;

  insert into public.incidencias (usuario_id, pedido_id, motivo, mensaje)
  values (v_usuario, p_pedido_id, p_motivo, trim(p_mensaje))
  returning id into v_id;

  insert into public.eventos (tipo, usuario_id, sesion_id, pedido_id, datos)
  values ('support.requested', v_usuario, left(p_sesion, 60), p_pedido_id,
          jsonb_build_object('incidencia_id', v_id, 'motivo', p_motivo));
  return v_id;
end;
$$;


-- ---------------------------------------------------------------------
-- 6. CAMBIAR EL ESTADO DE UN PEDIDO (solo back-office)
-- ---------------------------------------------------------------------
create or replace function public.cambiar_estado_pedido(p_pedido_id bigint, p_estado text)
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  if not public.es_admin() then
    raise exception 'Solo un administrador puede cambiar estados';
  end if;
  update public.pedidos set estado = p_estado where id = p_pedido_id;
  if not found then
    raise exception 'Pedido no encontrado';
  end if;
end;
$$;


-- ---------------------------------------------------------------------
-- 7. QUIÉN PUEDE LLAMAR A CADA FUNCIÓN
-- PostgreSQL deja ejecutar cualquier función a todo el mundo por defecto:
-- primero se quita ese permiso y luego se da solo a quien corresponde.
-- ---------------------------------------------------------------------
revoke execute on function
  public.es_admin(),
  public.registrar_evento(text, text, jsonb),
  public.crear_pedido(jsonb, jsonb, text, text, text, text),
  public.crear_incidencia(text, text, bigint, text),
  public.cambiar_estado_pedido(bigint, text)
from public, anon, authenticated;

grant execute on function public.registrar_evento(text, text, jsonb) to anon, authenticated;
grant execute on function
  public.es_admin(),
  public.crear_pedido(jsonb, jsonb, text, text, text, text),
  public.crear_incidencia(text, text, bigint, text),
  public.cambiar_estado_pedido(bigint, text)
to authenticated;
