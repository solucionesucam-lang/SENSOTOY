-- =====================================================================
-- SENSOTOYS · Prototipo académico SIE
-- 08_metricas.sql — Vistas de métricas para el back-office (Tarea 2)
-- Ejecutar DESPUÉS de 01, 02, 03 y 04.
--
-- security_invoker = true: la vista consulta con los permisos y las
-- políticas RLS de quien la usa, así que ya queda restringida a admin
-- por las políticas de pedidos, lineas_pedido y pagos de 04.
-- =====================================================================

create view public.v_ventas_por_producto
with (security_invoker = true) as
select
  pr.id            as producto_id,
  pr.nombre        as producto,
  sum(lp.cantidad) as unidades,
  sum(lp.importe)  as importe
from public.lineas_pedido lp
join public.variantes v  on v.id = lp.variante_id
join public.productos pr on pr.id = v.producto_id
where exists (
  select 1 from public.pagos pg
  where pg.pedido_id = lp.pedido_id and pg.resultado = 'aceptado'
)
group by pr.id, pr.nombre
order by importe desc;

create view public.v_resumen_ventas
with (security_invoker = true) as
with pedidos_pagados as (
  select distinct p.id, p.total
  from public.pedidos p
  where exists (
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

grant select on public.v_ventas_por_producto, public.v_resumen_ventas to authenticated;
