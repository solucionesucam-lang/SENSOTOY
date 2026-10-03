-- =====================================================================
-- SENSOTOYS · Prototipo académico SIE
-- 16_metricas_y_destacados.sql — Porcentaje de rechazos y "Destacados"
-- Ejecutar DESPUÉS de 12. Se puede repetir sin problema.
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1. pct_rechazados cuenta TODOS los pagos
-- En 09 se excluían los pedidos cancelados, y con ellos desaparecían los
-- rechazos que acabaron en cancelación. La facturación y el número de
-- pedidos siguen sin contar los cancelados.
-- ---------------------------------------------------------------------
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
         count(*) filter (where resultado = 'rechazado') as rechazados
  from public.pagos
)
select
  rp.pedidos,
  rp.facturacion,
  case when rp.pedidos = 0 then 0 else round(rp.facturacion / rp.pedidos, 2) end as ticket_medio,
  round(coalesce(100.0 * rpg.rechazados / nullif(rpg.total_pagos, 0), 0), 2)     as pct_rechazados
from resumen_pedidos rp, resumen_pagos rpg;

grant select on public.v_resumen_ventas to authenticated;


-- ---------------------------------------------------------------------
-- 2. Productos destacados del inicio
-- Primero las ediciones limitadas y, dentro de cada grupo, los más
-- vendidos (unidades de pedidos no cancelados con pago aceptado). Solo
-- productos activos con stock. Es una función security definer porque
-- los visitantes no pueden leer pedidos: solo reciben ids y unidades.
-- ---------------------------------------------------------------------
create or replace function public.productos_destacados(p_limite int default 4)
returns table (producto_id bigint, unidades bigint)
language sql stable security definer set search_path = ''
as $$
  select pr.id, coalesce(vt.unidades, 0)::bigint
  from public.productos pr
  left join (
    select v.producto_id, sum(lp.cantidad) as unidades
    from public.lineas_pedido lp
    join public.pedidos pe on pe.id = lp.pedido_id and pe.estado <> 'cancelado'
    join public.variantes v on v.id = lp.variante_id
    where exists (select 1 from public.pagos pg
                  where pg.pedido_id = lp.pedido_id and pg.resultado = 'aceptado')
    group by v.producto_id
  ) vt on vt.producto_id = pr.id
  where pr.activo
    and exists (select 1 from public.variantes v
                where v.producto_id = pr.id and v.activo and v.stock > 0)
  order by pr.es_edicion_limitada desc, coalesce(vt.unidades, 0) desc, pr.id
  limit greatest(1, least(coalesce(p_limite, 4), 12));
$$;

revoke execute on function public.productos_destacados(int) from public;
grant execute on function public.productos_destacados(int) to anon, authenticated;
