-- =====================================================================
-- SENSOTOYS · Prototipo académico SIE
-- 15_avance_automatico.sql — Avance automático de pedidos cada 5 horas
-- Ejecutar DESPUÉS de 12. Se puede repetir sin problema.
--
-- avanzar_pedidos() mueve un paso los pedidos que llevan 5 horas o más
-- en el mismo estado (estado_cambiado_en, sql/12):
--   pagado -> preparacion · preparacion -> enviado
--   creado -> preparacion (solo si el pago es contra reembolso)
-- No toca nunca los pedidos en "incidencia" ni "cancelado". Cada avance
-- registra order.status_changed con {"de", "a", "automatico": true}.
-- Un pedido avanza como mucho un paso por ejecución.
--
-- Se programa con pg_cron cada hora. Activa la extensión antes en
-- Supabase: Database > Extensions > pg_cron (ver README).
-- =====================================================================

create or replace function public.avanzar_pedidos()
returns int
language plpgsql security definer set search_path = ''
as $$
declare
  v_pedido    record;
  v_siguiente text;
  v_avanzados int := 0;
begin
  for v_pedido in
    select p.id, p.estado,
           (select pg.metodo from public.pagos pg
            where pg.pedido_id = p.id order by pg.id desc limit 1) as metodo
    from public.pedidos p
    where p.estado in ('creado', 'pagado', 'preparacion')
      and p.estado_cambiado_en <= now() - interval '5 hours'
    order by p.estado_cambiado_en, p.id
    for update of p skip locked
  loop
    v_siguiente := case v_pedido.estado
      when 'pagado'      then 'preparacion'
      when 'preparacion' then 'enviado'
      when 'creado'      then case when v_pedido.metodo = 'contrareembolso' then 'preparacion' end
    end;
    continue when v_siguiente is null;

    begin
      perform public.aplicar_cambio_estado(v_pedido.id, v_siguiente, true);
      v_avanzados := v_avanzados + 1;
    exception when others then
      -- Un pedido que falle no debe frenar a los demás
      raise warning 'No se pudo avanzar el pedido %: %', v_pedido.id, sqlerrm;
    end;
  end loop;
  return v_avanzados;
end;
$$;

revoke execute on function public.avanzar_pedidos() from public, anon, authenticated;


-- ---------------------------------------------------------------------
-- Programación con pg_cron (cada hora, en punto).
-- Si la extensión no está disponible, el script avisa y sigue: la
-- función queda creada y se puede programar más tarde repitiendo el
-- script.
-- ---------------------------------------------------------------------
do $$
begin
  if not exists (select 1 from pg_extension where extname = 'pg_cron')
     and exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    begin
      create extension pg_cron;
    exception when others then
      raise notice 'No se pudo activar pg_cron automáticamente (%). Actívalo en Database > Extensions y repite este script.', sqlerrm;
    end;
  end if;

  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    -- Con el mismo nombre de tarea, schedule() la actualiza en vez de duplicarla
    execute $cron$select cron.schedule('avanzar_pedidos', '0 * * * *', 'select public.avanzar_pedidos()')$cron$;
    raise notice 'Tarea "avanzar_pedidos" programada cada hora.';
  else
    raise notice 'pg_cron no está activo: los pedidos NO avanzarán solos hasta activarlo y repetir este script.';
  end if;
end $$;
