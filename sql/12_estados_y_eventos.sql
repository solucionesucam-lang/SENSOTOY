-- =====================================================================
-- SENSOTOYS · Prototipo académico SIE
-- 12_estados_y_eventos.sql — Cambios de estado: una sola lógica interna
-- Ejecutar DESPUÉS de 11. Se puede repetir sin problema.
--
-- Qué hace:
--   1. Amplía los tipos de evento (order.status_changed, stock.replenished).
--   2. Guarda cuándo cambió por última vez el estado de cada pedido
--      (estado_cambiado_en) y si el pedido llegó a enviarse.
--   3. Mueve la lógica de cambiar_estado_pedido() (sql/09) a una función
--      interna, aplicar_cambio_estado(), sin comprobar si se es admin y
--      sin permiso de ejecución para la web. La usan el admin, el cliente
--      (cancelar_mi_pedido) y el avance automático (sql/15).
--   4. Cancelar un pedido que llegó a enviarse ya no devuelve el stock:
--      las unidades salieron del almacén.
--   5. Permite al cliente cancelar su pedido mientras esté en "creado".
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1. Tipos de evento permitidos
-- ---------------------------------------------------------------------
alter table public.eventos drop constraint if exists eventos_tipo_check;
alter table public.eventos add constraint eventos_tipo_check
  check (tipo in ('product.viewed', 'cart.item_added', 'checkout.started',
                  'order.created', 'payment.simulated', 'support.requested',
                  'order.status_changed', 'stock.replenished'));


-- ---------------------------------------------------------------------
-- 2. Columnas nuevas de pedidos
-- Los pedidos que ya existían toman como fecha de último cambio el
-- momento de ejecutar este script (así el avance automático no los
-- mueve todos de golpe).
-- ---------------------------------------------------------------------
alter table public.pedidos add column if not exists estado_cambiado_en timestamptz not null default now();
alter table public.pedidos add column if not exists llego_a_enviarse boolean not null default false;

update public.pedidos set llego_a_enviarse = true
where estado = 'enviado' and not llego_a_enviarse;

create index if not exists pedidos_estado_cambiado_en_idx on public.pedidos (estado_cambiado_en);

create or replace function public.marcar_cambio_estado()
returns trigger
language plpgsql set search_path = ''
as $$
begin
  if new.estado is distinct from old.estado then
    new.estado_cambiado_en := now();
    if new.estado = 'enviado' then
      new.llego_a_enviarse := true;
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists pedidos_marcar_cambio_estado on public.pedidos;
create trigger pedidos_marcar_cambio_estado
  before update of estado on public.pedidos
  for each row execute function public.marcar_cambio_estado();


-- ---------------------------------------------------------------------
-- 3. Lógica interna del cambio de estado (sin comprobar admin)
-- ---------------------------------------------------------------------
create or replace function public.aplicar_cambio_estado(
  p_pedido_id bigint, p_estado text, p_automatico boolean default false)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_pedido public.pedidos%rowtype;
  v_pago   public.pagos%rowtype;
  v_sin    text;
begin
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

  -- Validar un pago que se había rechazado: ahora sí sale el stock
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

  -- Cancelar devuelve el stock, salvo que el pago estuviera rechazado
  -- (nunca salió) o que el pedido llegara a enviarse (ya salió).
  if p_estado = 'cancelado'
     and coalesce(v_pago.resultado, '') <> 'rechazado'
     and not v_pedido.llego_a_enviarse then
    perform 1 from public.variantes
    where id in (select variante_id from public.lineas_pedido where pedido_id = p_pedido_id)
    order by id for update;

    update public.variantes v set stock = v.stock + lp.cantidad
    from public.lineas_pedido lp
    where lp.pedido_id = p_pedido_id and lp.variante_id = v.id;
  end if;

  update public.pedidos set estado = p_estado where id = p_pedido_id;

  insert into public.eventos (tipo, usuario_id, pedido_id, datos)
  values ('order.status_changed', auth.uid(), p_pedido_id,
          jsonb_build_object('de', v_pedido.estado, 'a', p_estado, 'automatico', p_automatico));
end;
$$;

revoke execute on function public.aplicar_cambio_estado(bigint, text, boolean)
  from public, anon, authenticated;


-- ---------------------------------------------------------------------
-- 4. Cambio de estado desde el back-office (solo admin)
-- Mismo nombre y parámetros que en 04, 05 y 09: js/datos.js no cambia.
-- ---------------------------------------------------------------------
create or replace function public.cambiar_estado_pedido(p_pedido_id bigint, p_estado text)
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  if not public.es_admin() then
    raise exception 'Solo un administrador puede cambiar estados';
  end if;
  perform public.aplicar_cambio_estado(p_pedido_id, p_estado, false);
end;
$$;

revoke execute on function public.cambiar_estado_pedido(bigint, text) from public, anon, authenticated;
grant execute on function public.cambiar_estado_pedido(bigint, text) to authenticated;


-- ---------------------------------------------------------------------
-- 5. El cliente cancela su propio pedido (solo mientras está "creado")
-- Reutiliza aplicar_cambio_estado(): devuelve el stock y deja libre el
-- cupón de un solo uso (cupon_ya_usado ignora los pedidos cancelados).
-- ---------------------------------------------------------------------
create or replace function public.cancelar_mi_pedido(p_codigo text)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_usuario uuid := auth.uid();
  v_pedido  public.pedidos%rowtype;
begin
  if v_usuario is null then
    raise exception 'Tienes que iniciar sesión para cancelar un pedido';
  end if;

  select * into v_pedido from public.pedidos
  where codigo = p_codigo and usuario_id = v_usuario for update;
  if not found then
    raise exception 'Pedido no encontrado';
  end if;

  if v_pedido.estado <> 'creado' then
    raise exception 'Solo se puede cancelar un pedido mientras está en "Creado"';
  end if;

  perform public.aplicar_cambio_estado(v_pedido.id, 'cancelado', false);
end;
$$;

revoke execute on function public.cancelar_mi_pedido(text) from public, anon, authenticated;
grant execute on function public.cancelar_mi_pedido(text) to authenticated;
