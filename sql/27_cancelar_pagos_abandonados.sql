-- =====================================================================
-- SENSOTOYS · Prototipo académico SIE (sin actividad comercial real)
-- 27_cancelar_pagos_abandonados.sql — Cancelar pedidos con pago de
-- Stripe que nunca se completó (Supabase #1, la TIENDA)
--
-- OJO: se ejecuta en el proyecto de la TIENDA (Supabase #1).
-- Ejecutar DESPUÉS de sql/22_stripe_test.sql. Se puede repetir.
--
-- Por qué hace falta: con Stripe, crear_pedido (sql/22) deja el pedido
-- en "creado", el pago "pendiente" y RESERVA el stock (y el cupón, si
-- lo hay). Si el cliente cierra la página de Stripe sin pagar, nadie
-- confirma ese pago y la reserva se quedaría bloqueada para siempre.
--
-- Qué hace: cancela con aplicar_cambio_estado() (sql/12) los pedidos
-- Stripe pendientes más antiguos que el plazo indicado. Usar esa función
-- (y no un UPDATE directo) es lo que garantiza que:
--   · se devuelve el stock reservado (regla de cancelación de sql/12),
--   · el cupón vuelve a estar disponible (cupon_ya_usado ignora los
--     pedidos cancelados, sql/09),
--   · se registra el evento order.status_changed, que llega a n8n y
--     pone el pedido como cancelado también en el back-office.
--
-- El plazo debe ser MAYOR que la caducidad de la sesión de Stripe
-- (expires_at en crear-sesion-pago; mínimo de Stripe: 30 min), para no
-- cancelar un pedido que el cliente todavía puede pagar.
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1. Función
-- ---------------------------------------------------------------------
create or replace function public.cancelar_pagos_abandonados(p_minutos int default 60)
returns int
language plpgsql security definer set search_path = ''
as $$
declare
  v_pedido_id bigint;
  v_n         int := 0;
begin
  if p_minutos is null or p_minutos < 30 then
    raise exception 'El plazo debe ser de al menos 30 minutos (caducidad mínima de Stripe)';
  end if;

  for v_pedido_id in
    select p.id
    from public.pedidos p
    where p.estado = 'creado'
      and p.creado_en < now() - make_interval(mins => p_minutos)
      and exists (                       -- su ÚLTIMO pago es Stripe y sigue pendiente
        select 1 from public.pagos pg
        where pg.id = (select max(id) from public.pagos where pedido_id = p.id)
          and pg.proveedor = 'stripe_test'
          and pg.resultado = 'pendiente')
    order by p.id
  loop
    begin
      perform public.aplicar_cambio_estado(v_pedido_id, 'cancelado', true);
      v_n := v_n + 1;
    exception when others then
      -- Si un pedido falla (p. ej. Stripe lo confirmó justo ahora y ya no
      -- está en "creado"), se salta y se sigue con los demás.
      raise notice 'Pedido % no cancelado: %', v_pedido_id, sqlerrm;
    end;
  end loop;

  return v_n;
end;
$$;

-- Solo la base de datos (pg_cron) y el SQL Editor pueden llamarla.
revoke execute on function public.cancelar_pagos_abandonados(int) from public, anon, authenticated;


-- ---------------------------------------------------------------------
-- 2. ACTIVAR LA EJECUCIÓN AUTOMÁTICA (cuando P2 y P1 acuerden el plazo)
--    Cada 15 minutos, con el plazo acordado (aquí 60 minutos).
--    Ejecutar SOLO este bloque cuando se decida activarlo.
-- ---------------------------------------------------------------------
-- select cron.schedule('cancelar_pagos_abandonados', '*/15 * * * *',
--                      'select public.cancelar_pagos_abandonados(60)');
--
-- Para desactivarla:
-- select cron.unschedule('cancelar_pagos_abandonados');


-- ---------------------------------------------------------------------
-- 3. Comprobación manual (SQL Editor)
-- ---------------------------------------------------------------------
-- Pedidos Stripe pendientes y su antigüedad:
-- select p.codigo, p.estado, pg.resultado, now() - p.creado_en as antiguedad
-- from public.pedidos p join public.pagos pg on pg.pedido_id = p.id
-- where pg.proveedor = 'stripe_test' order by p.id desc;
--
-- Ejecutarla a mano (devuelve cuántos pedidos ha cancelado):
-- select public.cancelar_pagos_abandonados(60);
