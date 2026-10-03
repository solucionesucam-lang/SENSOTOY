-- =====================================================================
-- 07_evento_estado.sql · Persona 4 (Eventos y trazabilidad)
-- 1) Amplía el CHECK de eventos.tipo con 'order.status_changed'
-- 2) cambiar_estado_pedido() registra el evento con {"de": ..., "a": ...}
-- 3) Vista v_eventos_export (security_invoker) para consumo externo
--
-- ANTES DE EJECUTAR, en el SQL Editor de Supabase:
--   a) Ver la restricción real:
--      select conname, pg_get_constraintdef(oid)
--      from pg_constraint
--      where conrelid = 'public.eventos'::regclass and contype = 'c';
--   b) Ver la función actual (firma, nombres de parámetros, tipo de estado):
--      select pg_get_functiondef('public.cambiar_estado_pedido'::regproc);
--   c) Ver columnas de eventos (¿usuario_id? ¿pedido_id?):
--      select column_name, data_type from information_schema.columns
--      where table_name = 'eventos';
-- Ajusta lo marcado con [REVISAR] si no coincide.
-- =====================================================================

-- ---------- 1. Ampliar el CHECK de eventos.tipo ----------
-- Se localiza el nombre real de la restricción (no se asume) y se sustituye.
do $$
declare r record;
begin
  for r in
    select conname
    from pg_constraint
    where conrelid = 'public.eventos'::regclass
      and contype = 'c'
      and pg_get_constraintdef(oid) ilike '%tipo%'
  loop
    execute format('alter table public.eventos drop constraint %I', r.conname);
  end loop;
end $$;

alter table public.eventos
  add constraint eventos_tipo_check check (tipo in (
    'product.viewed', 'cart.item_added', 'checkout.started',
    'order.created', 'payment.simulated', 'support.requested',
    'order.status_changed'
  ));

-- ---------- 2. cambiar_estado_pedido() con evento ----------
-- [REVISAR] Mantén EXACTAMENTE la firma de la función original
-- (nombres y tipos de parámetros) o create or replace fallará.
-- Si pedidos.estado es un enum, usa p_estado::estado_pedido en el update.
create or replace function public.cambiar_estado_pedido(p_pedido_id bigint, p_estado text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_anterior text;
begin
  if not public.es_admin() then
    raise exception 'Solo el administrador puede cambiar el estado';
  end if;

  select estado::text into v_anterior
  from pedidos where id = p_pedido_id for update;

  if not found then
    raise exception 'Pedido no encontrado';
  end if;

  -- Si no cambia nada, no se ensucia el registro de eventos
  if v_anterior = p_estado then
    return;
  end if;

  update pedidos set estado = p_estado where id = p_pedido_id;

  -- [REVISAR] nombres de columnas de eventos
  insert into eventos (tipo, usuario_id, pedido_id, datos)
  values ('order.status_changed', auth.uid(), p_pedido_id,
          jsonb_build_object('de', v_anterior, 'a', p_estado));
end;
$$;

-- ---------- 3. Vista para consumo externo ----------
-- security_invoker = true: la vista se ejecuta con los permisos de quien
-- consulta, así que siguen aplicándose las RLS de eventos/pedidos/perfiles.
create or replace view public.v_eventos_export
with (security_invoker = true) as
select
  e.id,
  e.tipo,
  e.creado_en        as fecha,
  p.codigo           as pedido_codigo,
  u.email            as usuario_email,
  e.datos
from eventos e
left join pedidos p on p.id = e.pedido_id
left join perfiles u on u.id = e.usuario_id;   -- [REVISAR] si perfiles no tiene email

grant select on public.v_eventos_export to authenticated;

-- ---------- Comprobaciones ----------
-- select tipo, count(*) from eventos group by tipo order by tipo;
-- select * from v_eventos_export order by fecha desc limit 10;
