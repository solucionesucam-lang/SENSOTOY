alter table public.cupones add column if not exists un_uso_por_cliente boolean not null default false;
update public.cupones set un_uso_por_cliente = true where codigo = 'BIENVENIDA10';


create index if not exists eventos_usuario_id_idx on public.eventos (usuario_id);
create index if not exists eventos_pedido_id_idx on public.eventos (pedido_id);
create index if not exists incidencias_usuario_id_idx on public.incidencias (usuario_id);
create index if not exists incidencias_pedido_id_idx on public.incidencias (pedido_id);
create index if not exists lineas_pedido_variante_id_idx on public.lineas_pedido (variante_id);
create index if not exists pedidos_cupon_codigo_idx on public.pedidos (cupon_codigo);


drop policy if exists "perfiles: el propio o admin" on public.perfiles;
create policy "perfiles: el propio o admin" on public.perfiles
  for select to authenticated
  using (id = (select auth.uid()) or (select public.es_admin()));

drop policy if exists "pedidos: los propios o admin" on public.pedidos;
create policy "pedidos: los propios o admin" on public.pedidos
  for select to authenticated
  using (usuario_id = (select auth.uid()) or (select public.es_admin()));

drop policy if exists "lineas: las de mis pedidos o admin" on public.lineas_pedido;
create policy "lineas: las de mis pedidos o admin" on public.lineas_pedido
  for select to authenticated using (
    exists (select 1 from public.pedidos p where p.id = lineas_pedido.pedido_id
            and (p.usuario_id = (select auth.uid()) or (select public.es_admin()))));

drop policy if exists "pagos: los de mis pedidos o admin" on public.pagos;
create policy "pagos: los de mis pedidos o admin" on public.pagos
  for select to authenticated using (
    exists (select 1 from public.pedidos p where p.id = pagos.pedido_id
            and (p.usuario_id = (select auth.uid()) or (select public.es_admin()))));

drop policy if exists "incidencias: las propias o admin" on public.incidencias;
create policy "incidencias: las propias o admin" on public.incidencias
  for select to authenticated
  using (usuario_id = (select auth.uid()) or (select public.es_admin()));

drop policy if exists "eventos: solo admin" on public.eventos;
create policy "eventos: solo admin" on public.eventos
  for select to authenticated using ((select public.es_admin()));

grant select on public.transiciones_pedido to authenticated;
drop policy if exists "transiciones: solo admin" on public.transiciones_pedido;
create policy "transiciones: solo admin" on public.transiciones_pedido
  for select to authenticated using ((select public.es_admin()));


create or replace function public.cupon_ya_usado(p_codigo text, p_usuario uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (select 1 from public.pedidos
                 where usuario_id = p_usuario and cupon_codigo = p_codigo
                   and estado <> 'cancelado');
$$;

revoke execute on function public.cupon_ya_usado(text, uuid) from public, anon, authenticated;


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
    if (v_elem ->> 'cantidad')::int not between 1 and 3 then
      raise exception 'Cantidad no válida: entre 1 y 3 unidades por producto';
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
  having sum(l.cantidad) > 3
  limit 1;
  if found then
    raise exception 'Máximo 3 unidades por producto (revisa "%")', v_excedido;
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

  v_envio := case when v_subtotal - v_descuento >= 45 then 0 else 3.95 end;

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


create or replace function public.cambiar_estado_pedido(p_pedido_id bigint, p_estado text)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_pedido public.pedidos%rowtype;
  v_pago   public.pagos%rowtype;
  v_sin    text;
begin
  if not public.es_admin() then
    raise exception 'Solo un administrador puede cambiar estados';
  end if;

  select * into v_pedido from public.pedidos where id = p_pedido_id for update;
  if not found then
    raise exception 'Pedido no encontrado';
  end if;

  if v_pedido.estado = p_estado then
    raise exception 'El pedido ya está en el estado "%"', p_estado;
  end if;

  if not exists (
    select 1 from public.transiciones_pedido
    where estado_desde = v_pedido.estado and estado_hasta = p_estado
  ) then
    raise exception 'No se puede pasar un pedido de "%" a "%"', v_pedido.estado, p_estado;
  end if;

  select * into v_pago from public.pagos
  where pedido_id = p_pedido_id order by id desc limit 1 for update;

  if p_estado = 'preparacion' and v_pago.resultado = 'rechazado' then
    raise exception 'El pago está rechazado: pasa primero el pedido a "pagado"';
  end if;

  if p_estado = 'pagado' and v_pago.resultado = 'rechazado' then
    perform 1 from public.variantes
    where id in (select variante_id from public.lineas_pedido where pedido_id = p_pedido_id)
    order by id for update;

    select pr.nombre || ' (' || v.color || ' · ' || v.talla || ')' into v_sin
    from public.lineas_pedido lp
    join public.variantes v on v.id = lp.variante_id
    join public.productos pr on pr.id = v.producto_id
    where lp.pedido_id = p_pedido_id and v.stock < lp.cantidad
    order by v.id limit 1;
    if found then
      raise exception 'No hay stock suficiente de % para validar el pago', v_sin;
    end if;

    update public.variantes v set stock = v.stock - lp.cantidad
    from public.lineas_pedido lp
    where lp.pedido_id = p_pedido_id and lp.variante_id = v.id;
  end if;

  if p_estado = 'pagado' and v_pago.resultado in ('pendiente', 'rechazado') then
    update public.pagos set resultado = 'aceptado' where id = v_pago.id;
  end if;

  if p_estado = 'enviado' and v_pago.metodo = 'contrareembolso' and v_pago.resultado = 'pendiente' then
    update public.pagos set resultado = 'aceptado' where id = v_pago.id;
  end if;

  if p_estado = 'cancelado' and coalesce(v_pago.resultado, '') <> 'rechazado' then
    update public.variantes v set stock = v.stock + lp.cantidad
    from public.lineas_pedido lp
    where lp.pedido_id = p_pedido_id and lp.variante_id = v.id;
  end if;

  update public.pedidos set estado = p_estado where id = p_pedido_id;
end;
$$;


create or replace function public.validar_cupon(p_codigo text, p_subtotal numeric)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_codigo    text := upper(trim(coalesce(p_codigo, '')));
  v_subtotal  numeric := coalesce(p_subtotal, 0);
  v_usuario   uuid := auth.uid();
  v_cupon     public.cupones%rowtype;
  v_descuento numeric;
begin
  if v_codigo = '' then
    return jsonb_build_object('valido', false, 'mensaje', 'Introduce un cupón.',
                              'codigo', '', 'descuento', 0);
  end if;

  select * into v_cupon from public.cupones where codigo = v_codigo;
  if not found or not v_cupon.activo
     or (v_cupon.valido_hasta is not null and v_cupon.valido_hasta < current_date) then
    return jsonb_build_object('valido', false, 'mensaje', 'El cupón no existe o ha caducado',
                              'codigo', v_codigo, 'descuento', 0);
  end if;

  if v_subtotal < v_cupon.importe_minimo then
    return jsonb_build_object('valido', false,
                              'mensaje', format('El cupón exige un pedido mínimo de %s €', trim_scale(v_cupon.importe_minimo)),
                              'codigo', v_codigo, 'descuento', 0);
  end if;

  if v_cupon.un_uso_por_cliente and v_usuario is not null
     and public.cupon_ya_usado(v_cupon.codigo, v_usuario) then
    return jsonb_build_object('valido', false, 'mensaje', 'Ya has usado este cupón',
                              'codigo', v_codigo, 'descuento', 0);
  end if;

  if v_cupon.tipo = 'porcentaje' then
    v_descuento := round(v_subtotal * v_cupon.valor / 100, 2);
  else
    v_descuento := least(v_cupon.valor, v_subtotal);
  end if;

  return jsonb_build_object('valido', true,
                            'mensaje', 'Cupón aplicado: -' || replace(to_char(v_descuento, 'FM999990.00'), '.', ',') || ' €',
                            'codigo', v_cupon.codigo, 'descuento', v_descuento);
end;
$$;


create or replace view public.v_ventas_por_producto
with (security_invoker = true) as
select
  pr.id            as producto_id,
  pr.nombre        as producto,
  sum(lp.cantidad) as unidades,
  sum(lp.importe)  as importe
from public.lineas_pedido lp
join public.pedidos pe   on pe.id = lp.pedido_id and pe.estado <> 'cancelado'
join public.variantes v  on v.id = lp.variante_id
join public.productos pr on pr.id = v.producto_id
where exists (
  select 1 from public.pagos pg
  where pg.pedido_id = lp.pedido_id and pg.resultado = 'aceptado'
)
group by pr.id, pr.nombre
order by importe desc;

create or replace view public.v_resumen_ventas
with (security_invoker = true) as
with pedidos_pagados as (
  select distinct p.id, p.total
  from public.pedidos p
  where p.estado <> 'cancelado'
    and exists (
      select 1 from public.pagos pg
      where pg.pedido_id = p.id and pg.resultado = 'aceptado'
    )
),
resumen_pedidos as (
  select count(*) as pedidos, coalesce(sum(total), 0) as facturacion
  from pedidos_pagados
),
resumen_pagos as (
  select count(*) as total_pagos,
         count(*) filter (where pg.resultado = 'rechazado') as rechazados
  from public.pagos pg
  join public.pedidos p on p.id = pg.pedido_id and p.estado <> 'cancelado'
)
select
  rp.pedidos,
  rp.facturacion,
  case when rp.pedidos = 0 then 0 else round(rp.facturacion / rp.pedidos, 2) end as ticket_medio,
  round(coalesce(100.0 * rpg.rechazados / nullif(rpg.total_pagos, 0), 0), 2)     as pct_rechazados
from resumen_pedidos rp, resumen_pagos rpg;

grant select on public.v_ventas_por_producto, public.v_resumen_ventas to authenticated;


revoke execute on function
  public.crear_pedido(jsonb, jsonb, text, text, text, text),
  public.cambiar_estado_pedido(bigint, text)
from public, anon, authenticated;
grant execute on function
  public.crear_pedido(jsonb, jsonb, text, text, text, text),
  public.cambiar_estado_pedido(bigint, text)
to authenticated;
revoke execute on function public.validar_cupon(text, numeric) from public;
grant execute on function public.validar_cupon(text, numeric) to anon, authenticated;
