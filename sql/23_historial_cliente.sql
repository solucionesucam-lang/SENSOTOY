-- =====================================================================
-- SENSOTOYS · Prototipo académico SIE (sin actividad comercial real)
-- 23_historial_cliente.sql — Vista para la herramienta de consulta del
-- agente de IA (Supabase #2, back-office)
--
-- OJO: se ejecuta en el proyecto del BACK-OFFICE (Supabase #2).
-- Ejecutar DESPUÉS de 17 y 20. Se puede repetir sin problema.
--
-- Una fila por cliente con TODO su historial en una sola consulta:
-- sus pedidos (con líneas) y sus tickets. El agente la consulta así:
--   GET /rest/v1/v_historial_cliente?cliente_id=eq.<id>
-- (el cliente_id sale del propio ticket).
--
-- Minimización de datos: la vista NO incluye el email ni el
-- telegram_chat_id del cliente. El agente no los necesita para proponer
-- una respuesta, y así esos datos no se envían al modelo de IA.
-- =====================================================================

create or replace view public.v_historial_cliente
with (security_invoker = true) as
select
  c.id     as cliente_id,
  c.nombre,

  -- Resumen rápido
  (select count(*) from public.pedidos_bo p where p.cliente_id = c.id)       as num_pedidos,
  (select count(*) from public.tickets t
     where t.cliente_id = c.id and t.estado <> 'resuelta')                  as tickets_sin_resolver,

  -- Pedidos, del más reciente al más antiguo, con sus líneas
  coalesce((
    select jsonb_agg(jsonb_build_object(
             'pedido_id',    p.id,
             'codigo',       p.codigo_tienda,
             'estado',       p.estado,
             'importe',      p.importe,
             'fecha_pedido', p.fecha_pedido,
             'lineas', coalesce((
                select jsonb_agg(jsonb_build_object(
                         'sku',       l.sku,
                         'producto',  l.nombre_producto,
                         'variante',  l.descripcion_variante,
                         'cantidad',  l.cantidad,
                         'importe',   l.importe) order by l.id)
                from public.lineas_bo l where l.pedido_id = p.id), '[]'::jsonb))
           order by p.fecha_pedido desc)
    from public.pedidos_bo p where p.cliente_id = c.id), '[]'::jsonb)       as pedidos,

  -- Tickets, del más reciente al más antiguo
  coalesce((
    select jsonb_agg(jsonb_build_object(
             'ticket_id',     t.id,
             'pedido_codigo', p.codigo_tienda,
             'motivo',        t.motivo,
             'mensaje',       t.mensaje,
             'prioridad',     t.prioridad,
             'estado',        t.estado,
             'abierto_en',    t.abierto_en,
             'resuelto_en',   t.resuelto_en)
           order by t.abierto_en desc)
    from public.tickets t
    left join public.pedidos_bo p on p.id = t.pedido_id
    where t.cliente_id = c.id), '[]'::jsonb)                                as tickets
from public.clientes c;


-- Permisos: igual que el resto del back-office (sql/20 y sql/21)
revoke all on public.v_historial_cliente from public, anon, authenticated;
grant select on public.v_historial_cliente to authenticated;

-- Comprobación rápida:
-- select * from public.v_historial_cliente;
