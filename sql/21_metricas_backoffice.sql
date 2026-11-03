-- =====================================================================
-- SENSOTOYS · Prototipo académico SIE (sin actividad comercial real)
-- 21_metricas_backoffice.sql — Vistas del cuadro de mando (Supabase #2)
--
-- OJO: se ejecuta en el proyecto del BACK-OFFICE (Supabase #2).
-- Ejecutar DESPUÉS de 17 y 20. Se puede repetir sin problema.
--
-- Métricas definidas en docs/metricas.md:
--   M1 Pedidos totales ............ v_metricas_resumen
--   M2 Importe total .............. v_metricas_resumen
--   M3 Pedidos por estado ......... v_pedidos_por_estado
--   M4 Tickets abiertos ........... v_metricas_resumen
--   M5 Integraciones ok/error/dup . v_integraciones_por_resultado
--   M6 Propuestas vs aprobadas .... v_agente_por_estado (+ resumen)
--   G1 Pedidos por día (barras) ... v_pedidos_por_dia
--
-- Todas las cifras salen de las tablas que rellena n8n: ninguna se
-- escribe a mano.
--
-- security_invoker = true: la vista se consulta con los permisos de
-- QUIEN la lee (la cuenta "authenticated" de la app Vue), así que se
-- aplican el RLS y los GRANT de sql/20. Sin esto, la vista se ejecutaría
-- como su dueño (postgres) y se saltaría el RLS.
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1. Resumen: una sola fila con las cifras de las tarjetas (M1, M2, M4, M6)
-- ---------------------------------------------------------------------
create or replace view public.v_metricas_resumen
with (security_invoker = true) as
select
  -- M1: todos los pedidos que han llegado de la tienda
  (select count(*) from public.pedidos_bo)                         as pedidos_totales,
  -- M2: importe de los pedidos NO cancelados (un pedido cancelado no es venta)
  (select coalesce(sum(importe), 0)
     from public.pedidos_bo where estado <> 'cancelado')           as importe_total,
  -- Valor medio del pedido (M2 / pedidos no cancelados); null si no hay
  (select round(avg(importe), 2)
     from public.pedidos_bo where estado <> 'cancelado')           as importe_medio,
  -- M4: tickets sin resolver (abierta + en_curso)
  (select count(*) from public.tickets where estado <> 'resuelta') as tickets_abiertos,
  -- M6: propuestas del agente y cuántas aprobó una persona
  (select count(*) from public.aprobaciones_agente)                as propuestas_agente,
  (select count(*) from public.aprobaciones_agente
     where estado = 'aprobado')                                    as propuestas_aprobadas;


-- ---------------------------------------------------------------------
-- 2. M3: pedidos por estado (salen todos los estados, también los que
--    tienen 0, para que el gráfico/tabla no cambie de forma)
-- ---------------------------------------------------------------------
create or replace view public.v_pedidos_por_estado
with (security_invoker = true) as
select e.orden, e.estado, count(p.id) as pedidos
from (values (1, 'creado'), (2, 'pagado'), (3, 'preparacion'),
             (4, 'enviado'), (5, 'cancelado'), (6, 'incidencia')) as e(orden, estado)
left join public.pedidos_bo p on p.estado = e.estado
group by e.orden, e.estado;


-- ---------------------------------------------------------------------
-- 3. M5: ejecuciones de la integración por resultado (ok / error / duplicado)
-- ---------------------------------------------------------------------
create or replace view public.v_integraciones_por_resultado
with (security_invoker = true) as
select r.orden, r.resultado, count(l.id) as ejecuciones
from (values (1, 'ok'), (2, 'error'), (3, 'duplicado')) as r(orden, resultado)
left join public.log_integracion l on l.resultado = r.resultado
group by r.orden, r.resultado;


-- ---------------------------------------------------------------------
-- 4. M6: propuestas del agente por estado final
-- ---------------------------------------------------------------------
create or replace view public.v_agente_por_estado
with (security_invoker = true) as
select s.orden, s.estado, count(a.id) as propuestas
from (values (1, 'aprobado'), (2, 'pendiente_revision'),
             (3, 'rechazado'), (4, 'simulado')) as s(orden, estado)
left join public.aprobaciones_agente a on a.estado = s.estado
group by s.orden, s.estado;


-- ---------------------------------------------------------------------
-- 5. G1: pedidos por día (para el gráfico de barras)
--    · El día se calcula en hora de Madrid: un pedido a las 00:30 en
--      España sería "del día anterior" en UTC.
--    · Se rellenan con 0 los días sin pedidos entre el primero y hoy,
--      para que el gráfico no se salte días.
--    · fecha_pedido = cuándo se hizo en la tienda (no cuándo llegó).
-- ---------------------------------------------------------------------
create or replace view public.v_pedidos_por_dia
with (security_invoker = true) as
with por_dia as (
  select (fecha_pedido at time zone 'Europe/Madrid')::date as dia,
         count(*)                                               as pedidos,
         coalesce(sum(importe) filter (where estado <> 'cancelado'), 0) as importe
  from public.pedidos_bo
  group by 1
),
dias as (
  select generate_series(
           (select min(dia) from por_dia),
           greatest((select max(dia) from por_dia),
                    (now() at time zone 'Europe/Madrid')::date),
           interval '1 day')::date as dia
)
select d.dia,
       coalesce(p.pedidos, 0) as pedidos,
       coalesce(p.importe, 0) as importe
from dias d
left join por_dia p on p.dia = d.dia;


-- ---------------------------------------------------------------------
-- 6. Permisos: igual que las tablas (sql/20)
--    Supabase da por defecto permisos a anon/authenticated en todo lo
--    nuevo del esquema public, así que se quitan y se da solo lectura.
-- ---------------------------------------------------------------------
revoke all on public.v_metricas_resumen, public.v_pedidos_por_estado,
              public.v_integraciones_por_resultado, public.v_agente_por_estado,
              public.v_pedidos_por_dia
  from public, anon, authenticated;

grant select on public.v_metricas_resumen, public.v_pedidos_por_estado,
                public.v_integraciones_por_resultado, public.v_agente_por_estado,
                public.v_pedidos_por_dia
  to authenticated;


-- ---------------------------------------------------------------------
-- 7. Comprobación rápida (ejecutar aparte si se quiere)
-- ---------------------------------------------------------------------
-- select * from public.v_metricas_resumen;
-- select * from public.v_pedidos_por_estado order by orden;
-- select * from public.v_integraciones_por_resultado order by orden;
-- select * from public.v_agente_por_estado order by orden;
-- select * from public.v_pedidos_por_dia order by dia;
