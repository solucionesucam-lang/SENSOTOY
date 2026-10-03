-- =====================================================================
-- SENSOTOYS · Prototipo académico SIE
-- 07_evento_estado.sql — Tipos de evento nuevos y vista de exportación
-- Ejecutar DESPUÉS de 01 a 06 y ANTES de 08 y 09. Se puede repetir sin problema.
--
-- Qué hace:
--   1. Amplía el CHECK eventos_tipo_check de eventos.tipo con
--      'order.status_changed' (cambio de estado de un pedido) y
--      'stock.replenished' (reposición de stock, sql/14).
--   2. Crea la vista v_eventos_export para consumo externo
--      (security_invoker: siguen aplicándose las RLS de quien consulta).
--
-- La lógica de cambiar_estado_pedido() ya no está aquí: vive en
-- 10 (versión puente) y en 12 (versión definitiva).
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
-- 2. Vista para consumo externo
-- ---------------------------------------------------------------------
create or replace view public.v_eventos_export
with (security_invoker = true) as
select
  e.id,
  e.tipo,
  e.creado_en  as fecha,
  p.codigo     as pedido_codigo,
  u.email      as usuario_email,
  e.datos
from public.eventos e
left join public.pedidos p on p.id = e.pedido_id
left join public.perfiles u on u.id = e.usuario_id;

revoke all on public.v_eventos_export from public, anon;
grant select on public.v_eventos_export to authenticated;
