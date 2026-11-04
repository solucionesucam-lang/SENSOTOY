-- SENSOTOYS · Integración de Stripe en entorno de pruebas
-- PROPUESTA PENDIENTE DE REVISIÓN.
-- No ejecutar en Supabase #1 sin revisión del responsable.
--
-- Objetivo:
-- Crear pedidos con tarjeta pendientes de pago,
-- conservando el contrato de eventos de integración.


-- ---------------------------------------------------------------------
-- 1. Permitir pagos Stripe sin ultimos4, también al confirmar el pago.
--
-- El responsable ha confirmado que la restricción original
-- se llama pagos_check.
-- Stripe gestiona los datos de la tarjeta.
-- ---------------------------------------------------------------------

begin;

alter table public.pagos
  drop constraint if exists pagos_check;

alter table public.pagos
  add constraint pagos_tarjeta_ultimos4_check
  check (
    metodo <> 'tarjeta'
    or proveedor = 'stripe_test'
    or ultimos4 is not null
  );

-- ---------------------------------------------------------------------
-- 2. Adaptación de crear_pedido() para Stripe.
-- BORRADOR INCOMPLETO: no ejecutar.
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
  v_max       int := public.config_num('max_por_producto')::int;
  v_gratis    numeric := public.config_num('envio_gratis_desde');
  v_gastos    numeric := public.config_num('gastos_envio');
  v_elem      jsonb;
  v_lineas    jsonb;
  v_linea     record;
  v_excedido  text;
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
  if v_usuario is null then
    raise exception 'Tienes que iniciar sesión para comprar';
  end if;
  if p_lineas is null or jsonb_typeof(p_lineas) <> 'array'
     or jsonb_array_length(p_lineas) = 0 then
    raise exception 'El carrito está vacío';
  end if;
  if coalesce(p_metodo, '') not in ('tarjeta', 'contrareembolso') then
    raise exception 'Elige un método de pago válido (tarjeta o contra reembolso)';
  end if;
  if coalesce(trim(p_envio ->> 'nombre'), '') = '' or coalesce(trim(p_envio ->> 'direccion'), '') = ''
     or coalesce(trim(p_envio ->> 'ciudad'), '') = '' or coalesce(trim(p_envio ->> 'provincia'), '') = '' then
    raise exception 'Faltan datos de envío';
  end if;
  if coalesce(trim(p_envio ->> 'cp'), '') !~ '^[0-9]{5}$' then
    raise exception 'El código postal debe tener 5 dígitos';
  end if;

  for v_elem in select value from jsonb_array_elements(p_lineas) loop
    if jsonb_typeof(v_elem) <> 'object'
       or coalesce(v_elem ->> 'variante_id', '') !~ '^[0-9]{1,15}$'
       or coalesce(v_elem ->> 'cantidad', '') !~ '^[0-9]{1,6}$' then
      raise exception 'El carrito contiene una línea no válida';
    end if;
    if (v_elem ->> 'cantidad')::int not between 1 and v_max then
      raise exception 'Cantidad no válida: entre 1 y % unidades por producto', v_max;
    end if;
  end loop;

  select jsonb_agg(jsonb_build_object('variante_id', g.variante_id, 'cantidad', g.cantidad)
                   order by g.variante_id)
  into v_lineas
  from (select (x ->> 'variante_id')::bigint as variante_id,
               sum((x ->> 'cantidad')::int)::int as cantidad
        from jsonb_array_elements(p_lineas) as x
        group by 1) g;

  select pr.nombre into v_excedido
  from jsonb_to_recordset(v_lineas) as l(variante_id bigint, cantidad int)
  join public.variantes v on v.id = l.variante_id
  join public.productos pr on pr.id = v.producto_id
  group by pr.id, pr.nombre
  having sum(l.cantidad) > v_max
  limit 1;
  if found then
    raise exception 'Máximo % unidades por producto (revisa "%")', v_max, v_excedido;
  end if;

  for v_linea in
    select v.id, v.precio, v.stock, pr.nombre, l.cantidad
    from jsonb_to_recordset(v_lineas) as l(variante_id bigint, cantidad int)
    join public.variantes v on v.id = l.variante_id and v.activo
    join public.productos pr on pr.id = v.producto_id and pr.activo
    order by v.id
    for update of v
  loop
    if v_linea.cantidad > v_linea.stock then
      raise exception 'No queda stock suficiente de "%" (quedan %)', v_linea.nombre, v_linea.stock;
    end if;
    v_subtotal  := v_subtotal + v_linea.precio * v_linea.cantidad;
    v_num_filas := v_num_filas + 1;
  end loop;

  if v_num_filas <> jsonb_array_length(v_lineas) then
    raise exception 'Algún producto del carrito ya no está disponible';
  end if;

  if nullif(trim(p_cupon), '') is not null then
    select * into v_cupon from public.cupones where codigo = upper(trim(p_cupon));
    if not found or not v_cupon.activo
       or (v_cupon.valido_hasta is not null and v_cupon.valido_hasta < current_date) then
      raise exception 'El cupón no existe o ha caducado';
    end if;
    if v_subtotal < v_cupon.importe_minimo then
      raise exception 'El cupón exige un pedido mínimo de % €', v_cupon.importe_minimo;
    end if;
    if v_cupon.un_uso_por_cliente then
      perform 1 from public.perfiles where id = v_usuario for update;
      if public.cupon_ya_usado(v_cupon.codigo, v_usuario) then
        raise exception 'Ya has usado este cupón';
      end if;
    end if;
    if v_cupon.tipo = 'porcentaje' then
      v_descuento := round(v_subtotal * v_cupon.valor / 100, 2);
    else
      v_descuento := least(v_cupon.valor, v_subtotal);
    end if;
  end if;

  v_envio := case when v_subtotal - v_descuento >= v_gratis then 0 else v_gastos end;

  -- La creación del pedido ya no decide si la tarjeta se acepta.
  -- El resultado se confirmará después mediante Stripe.
  v_resultado := 'pendiente';
  v_estado := 'creado';
  v_ultimos4 := null;

  insert into public.pedidos (usuario_id, estado, subtotal, descuento, gastos_envio,
                              cupon_codigo, envio_nombre, envio_direccion,
                              envio_cp, envio_ciudad, envio_provincia)
  values (v_usuario, v_estado, v_subtotal, v_descuento, v_envio,
          v_cupon.codigo,
          trim(p_envio ->> 'nombre'), trim(p_envio ->> 'direccion'),
          trim(p_envio ->> 'cp'), trim(p_envio ->> 'ciudad'),
          trim(p_envio ->> 'provincia'))
  returning * into v_pedido;

  insert into public.lineas_pedido (pedido_id, variante_id, nombre_producto,
                                    descripcion_variante, precio_unitario,
                                    cantidad, importe)
  select v_pedido.id, v.id, pr.nombre, v.color || ' · Talla ' || v.talla,
         v.precio, l.cantidad, v.precio * l.cantidad
  from jsonb_to_recordset(v_lineas) as l(variante_id bigint, cantidad int)
  join public.variantes v on v.id = l.variante_id
  join public.productos pr on pr.id = v.producto_id;

  if v_resultado <> 'rechazado' then
    update public.variantes v
    set stock = v.stock - l.cantidad
    from jsonb_to_recordset(v_lineas) as l(variante_id bigint, cantidad int)
    where v.id = l.variante_id;
  end if;

   insert into public.pagos (
    pedido_id, proveedor, metodo, importe, resultado, ultimos4
  )
  values (
    v_pedido.id,
    case
      when p_metodo = 'tarjeta' then 'stripe_test'
      else 'simulado'
    end,
    p_metodo,
    v_pedido.total,
    v_resultado,
    v_ultimos4
  );

  -- El pedido ya tiene sus líneas: se puede registrar su creación.
  insert into public.eventos (
    tipo, usuario_id, sesion_id, pedido_id, datos
  )
  values (
    'order.created',
    v_usuario,
    left(p_sesion, 60),
    v_pedido.id,
    jsonb_build_object(
      'codigo', v_pedido.codigo,
      'total', v_pedido.total,
      'lineas', v_num_filas,
      'cupon', v_cupon.codigo
    )
  );

  -- Conservamos el comportamiento anterior del contra reembolso.
  -- El evento de tarjeta se registrará al confirmar el pago con Stripe.
  if p_metodo = 'contrareembolso' then
    insert into public.eventos (
      tipo, usuario_id, sesion_id, pedido_id, datos
    )
    values (
      'payment.simulated',
      v_usuario,
      left(p_sesion, 60),
      v_pedido.id,
      jsonb_build_object(
        'metodo', p_metodo,
        'resultado', v_resultado,
        'ultimos4', v_ultimos4,
        'importe', v_pedido.total
      )
    );
  end if;
return jsonb_build_object(
    'codigo', v_pedido.codigo,
    'estado', v_estado,
    'resultado', v_resultado,
    'total', v_pedido.total
  );
end;
$$;

revoke execute on function public.crear_pedido(jsonb, jsonb, text, text, text, text)
  from public, anon, authenticated;
grant execute on function public.crear_pedido(jsonb, jsonb, text, text, text, text)
  to authenticated;
commit;
