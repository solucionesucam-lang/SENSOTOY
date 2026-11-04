-- =====================================================================
-- SENSOTOYS · Prototipo académico SIE (sin actividad comercial real)
-- 19_webhook_eventos.sql — Envío de eventos de la tienda a n8n
--
-- OJO: se ejecuta en el proyecto de la TIENDA (Supabase #1).
-- Ejecutar DESPUÉS de 16. Se puede repetir sin problema.
--
-- Qué hace:
--   1. Cada vez que se inserta en "eventos" un evento de negocio
--      (order.created, payment.simulated, order.status_changed,
--      support.requested), lo envía por HTTP POST al webhook de n8n.
--      product.viewed, cart.item_added y checkout.started NO se envían.
--   2. Antes de enviarlo, lo completa con los datos que el back-office
--      necesita (cliente, pedido con sus líneas, incidencia), para que n8n
--      no tenga que consultar la base de datos de la tienda.
--   3. Añade la cabecera x-sensotoys-secret, que n8n comprueba para
--      rechazar llamadas que no vengan de la tienda.
--   4. Guarda cada envío en envios_webhook para poder ver luego si n8n
--      respondió bien (trazabilidad del lado de la tienda).
--
-- Es lo mismo que hacen por dentro los "Database Webhooks" del panel
-- (extensión pg_net), pero con filtro por tipo y payload completo.
--
-- La URL de n8n y el secreto NO están en este fichero: se guardan en el
-- Vault de Supabase (ver README / instrucciones de configuración).
--
-- Si n8n está caído o no hay URL configurada, la compra NO falla:
-- el error se apunta en envios_webhook y la tienda sigue funcionando.
-- =====================================================================


-- ---------------------------------------------------------------------
-- 0. Extensión para hacer peticiones HTTP desde la base de datos
-- (si da error, actívala en Database > Extensions > pg_net)
-- ---------------------------------------------------------------------
create extension if not exists pg_net;


-- ---------------------------------------------------------------------
-- 1. Registro de envíos (lado tienda)
-- ---------------------------------------------------------------------
create table if not exists public.envios_webhook (
  id         bigint generated always as identity primary key,
  evento_id  bigint not null references public.eventos(id) on delete cascade,
  request_id bigint,                -- id de la petición en pg_net (null = no se envió)
  nota       text,                  -- motivo si no se pudo enviar
  creado_en  timestamptz not null default now()
);

create index if not exists envios_webhook_evento_idx on public.envios_webhook (evento_id);

-- Solo se consulta desde el SQL Editor: nadie de la web puede verla.
alter table public.envios_webhook enable row level security;
revoke all on public.envios_webhook from anon, authenticated;


-- ---------------------------------------------------------------------
-- 2. Construir el payload (contrato de integración v1)
-- ---------------------------------------------------------------------
create or replace function public.payload_evento_n8n(p_evento_id bigint)
returns jsonb
language plpgsql stable security definer set search_path = ''
as $$
declare
  v_ev        public.eventos%rowtype;
  v_cliente   uuid;
  v_pedido    jsonb;
  v_incid     jsonb;
  v_inc_id    bigint;
begin
  select * into v_ev from public.eventos where id = p_evento_id;
  if not found then
    return null;
  end if;

  -- Pedido con sus líneas (si el evento va ligado a un pedido)
  if v_ev.pedido_id is not null then
    select jsonb_build_object(
             'pedido_tienda_id', p.id,
             'codigo',           p.codigo,
             'estado',           p.estado,
             'total',            p.total,
             'creado_en',        p.creado_en,
             'lineas', coalesce((
                select jsonb_agg(jsonb_build_object(
                         'sku',                  v.sku,
                         'nombre_producto',      lp.nombre_producto,
                         'descripcion_variante', lp.descripcion_variante,
                         'precio_unitario',      lp.precio_unitario,
                         'cantidad',             lp.cantidad)
                       order by lp.id)
                from public.lineas_pedido lp
                join public.variantes v on v.id = lp.variante_id
                where lp.pedido_id = p.id), '[]'::jsonb)),
           p.usuario_id
      into v_pedido, v_cliente
    from public.pedidos p
    where p.id = v_ev.pedido_id;
  end if;

  -- Incidencia (support.requested lleva su id en datos)
  if v_ev.tipo = 'support.requested' then
    v_inc_id := nullif(v_ev.datos ->> 'incidencia_id', '')::bigint;
    select jsonb_build_object(
             'incidencia_tienda_id', i.id,
             'motivo',               i.motivo,
             'mensaje',              i.mensaje,
             'estado',               i.estado,
             'creado_en',            i.creado_en),
           i.usuario_id
      into v_incid, v_cliente
    from public.incidencias i
    where i.id = v_inc_id;
  end if;

  -- El cliente es el DUEÑO del pedido o de la incidencia, no quien generó
  -- el evento (en order.status_changed puede ser el admin o el sistema).
  v_cliente := coalesce(v_cliente, v_ev.usuario_id);

  return jsonb_build_object(
    'version',    1,
    'origen',     'sensotoys-tienda',
    'evento_id',  v_ev.id,
    'tipo',       v_ev.tipo,
    'creado_en',  v_ev.creado_en,
    'datos',      v_ev.datos,
    'cliente', (select jsonb_build_object(
                         'usuario_tienda_id', u.id,
                         'email',             u.email,
                         'nombre',            u.nombre)
                from public.perfiles u where u.id = v_cliente),
    'pedido',     v_pedido,
    'incidencia', v_incid
  );
end;
$$;


-- ---------------------------------------------------------------------
-- 3. Enviar un evento a n8n (la usa el trigger y sirve para reenviar
--    a mano: select public.enviar_evento_n8n(123); )
-- ---------------------------------------------------------------------
create or replace function public.enviar_evento_n8n(p_evento_id bigint)
returns bigint
language plpgsql security definer set search_path = ''
as $$
declare
  v_url     text;
  v_secreto text;
  v_req     bigint;
begin
  select decrypted_secret into v_url
  from vault.decrypted_secrets where name = 'n8n_webhook_url';
  select decrypted_secret into v_secreto
  from vault.decrypted_secrets where name = 'n8n_webhook_secret';

  if v_url is null or v_secreto is null then
    insert into public.envios_webhook (evento_id, nota)
    values (p_evento_id, 'Sin URL o secreto en el Vault: no se envía');
    return null;
  end if;

  v_req := net.http_post(
    url     := v_url,
    body    := public.payload_evento_n8n(p_evento_id),
    headers := jsonb_build_object('Content-Type', 'application/json',
                                  'x-sensotoys-secret', v_secreto),
    timeout_milliseconds := 30000   -- margen por si Render está despertando
  );

  insert into public.envios_webhook (evento_id, request_id)
  values (p_evento_id, v_req);
  return v_req;

exception when others then
  -- Pase lo que pase con la integración, la compra no se deshace.
  insert into public.envios_webhook (evento_id, nota)
  values (p_evento_id, 'Error al preparar el envío: ' || sqlerrm);
  return null;
end;
$$;


-- ---------------------------------------------------------------------
-- 4. Trigger: solo eventos de negocio
-- ---------------------------------------------------------------------
create or replace function public.trg_evento_a_n8n()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  perform public.enviar_evento_n8n(new.id);
  return null;
end;
$$;

drop trigger if exists eventos_a_n8n on public.eventos;
create trigger eventos_a_n8n
  after insert on public.eventos
  for each row
  when (new.tipo in ('order.created', 'payment.simulated',
                     'order.status_changed', 'support.requested'))
  execute function public.trg_evento_a_n8n();


-- ---------------------------------------------------------------------
-- 5. Nadie desde la web puede llamar a estas funciones por la API
-- ---------------------------------------------------------------------
revoke execute on function public.payload_evento_n8n(bigint) from public, anon, authenticated;
revoke execute on function public.enviar_evento_n8n(bigint)  from public, anon, authenticated;
revoke execute on function public.trg_evento_a_n8n()         from public, anon, authenticated;


-- ---------------------------------------------------------------------
-- 6. Vista para revisar los envíos y la respuesta de n8n
--    (pg_net guarda las respuestas unas horas en net._http_response)
-- ---------------------------------------------------------------------
create or replace view public.v_envios_webhook
with (security_invoker = true) as
select
  w.id,
  w.creado_en,
  e.id          as evento_id,
  e.tipo,
  w.request_id,
  r.status_code,           -- 200 = n8n lo recibió
  r.timed_out,
  coalesce(w.nota, r.error_msg) as problema
from public.envios_webhook w
join public.eventos e on e.id = w.evento_id
left join net._http_response r on r.id = w.request_id;

revoke all on public.v_envios_webhook from public, anon, authenticated;
