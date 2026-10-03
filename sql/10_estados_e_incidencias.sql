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

  begin
    insert into public.eventos (tipo, usuario_id, pedido_id, datos)
    values ('order.status_changed', auth.uid(), p_pedido_id,
            jsonb_build_object('de', v_pedido.estado, 'a', p_estado));
  exception when check_violation then null;
  end;
end;
$$;
create or replace function public.crear_incidencia(
  p_motivo text, p_mensaje text, p_pedido_id bigint default null, p_sesion text default null)
returns bigint
language plpgsql security definer set search_path = ''
as $$
declare
  vUsuario uuid := auth.uid();
  vId bigint;
  vAnterior text;
begin
  if vUsuario is null then
    raise exception 'Tienes que iniciar sesión para abrir una incidencia';
  end if;
  if p_pedido_id is not null then
    select estado into vAnterior from public.pedidos
    where id = p_pedido_id and usuario_id = vUsuario for update;
    if not found then
      raise exception 'Ese pedido no es tuyo';
    end if;
  end if;

  insert into public.incidencias (usuario_id, pedido_id, motivo, mensaje)
  values (vUsuario, p_pedido_id, p_motivo, trim(p_mensaje))
  returning id into vId;

  insert into public.eventos (tipo, usuario_id, sesion_id, pedido_id, datos)
  values ('support.requested', vUsuario, left(p_sesion, 60), p_pedido_id,
          jsonb_build_object('incidencia_id', vId, 'motivo', p_motivo));

  if vAnterior is not null and exists (
       select 1 from public.transiciones_pedido
       where estado_desde = vAnterior and estado_hasta = 'incidencia') then
    update public.pedidos set estado = 'incidencia' where id = p_pedido_id;
    begin
      insert into public.eventos (tipo, usuario_id, sesion_id, pedido_id, datos)
      values ('order.status_changed', vUsuario, left(p_sesion, 60), p_pedido_id,
              jsonb_build_object('de', vAnterior, 'a', 'incidencia'));
    exception when check_violation then null;
    end;
  end if;

  return vId;
end;
$$;
