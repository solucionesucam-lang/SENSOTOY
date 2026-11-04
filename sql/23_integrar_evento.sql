-- =====================================================================
-- SENSOTOYS · Prototipo académico SIE (sin actividad comercial real)
-- 24_integrar_evento.sql — Guardar en el back-office un evento de la
-- tienda (Supabase #2)
--
-- OJO: se ejecuta en el proyecto del BACK-OFFICE (Supabase #2).
-- Ejecutar DESPUÉS de 17 y 20. Se puede repetir sin problema.
--
-- Reparto de responsabilidades:
--   · n8n ORQUESTA: recibe el webhook, valida el payload, llama a esta
--     función, registra el resultado en log_integracion y notifica.
--   · Esta función PERSISTE: escribe cliente, pedido, líneas o ticket
--     en UNA sola transacción. Si algo falla, no queda nada a medias.
--
-- n8n la llama con:
--   POST https://<proyecto>.supabase.co/rest/v1/rpc/integrar_evento
--   cabecera apikey = clave secreta del back-office
--   body = { "p": <payload v1 que envía la tienda (sql/19)> }
--
-- Siempre responde 200 con un JSON:
--   { "resultado": "ok" | "duplicado" | "error", "mensaje": "...",
--     "tipo", "evento_id", "cliente_id", "pedido_id", "ticket_id", "codigo" }
-- y n8n decide la rama según "resultado".
--
-- Idempotencia en dos niveles:
--   1. Si el evento_id ya se integró con éxito (hay una fila "ok" en
--      log_integracion), no se repite nada → "duplicado".
--   2. Los UNIQUE de sql/17 (pedido_tienda_id, codigo_tienda,
--      incidencia_tienda_id, (pedido_id, sku)) impiden duplicar datos
--      aunque el nivel 1 falle (p. ej. si n8n no llegó a escribir el log).
--
-- Orden de llegada: order.created y payment.simulated se generan en la
-- misma operación de la tienda y llegan casi a la vez. Por eso los dos
-- crean el pedido si no existe, y order.created NUNCA sobrescribe el
-- estado (si el pago llegó antes, el pedido ya está en "pagado").
-- =====================================================================

create or replace function public.integrar_evento(p jsonb)
returns jsonb
language plpgsql
set search_path = ''
as $$
declare
  v_tipo       text   := p ->> 'tipo';
  v_evento_id  bigint;
  v_cliente    jsonb  := p -> 'cliente';
  v_pedido     jsonb  := p -> 'pedido';
  v_incid      jsonb  := p -> 'incidencia';
  v_cliente_id bigint;
  v_pedido_id  bigint;
  v_ticket_id  bigint;
  v_estado     text;
begin
  -- -------------------------------------------------------------------
  -- 0. Comprobaciones mínimas (n8n ya valida, esto es la segunda red)
  -- -------------------------------------------------------------------
  v_evento_id := nullif(p ->> 'evento_id', '')::bigint;
  if v_evento_id is null or v_tipo is null then
    return jsonb_build_object('resultado', 'error', 'tipo', v_tipo,
             'mensaje', 'Payload sin evento_id o sin tipo');
  end if;

  -- Nivel 1 de idempotencia: ¿este evento ya se integró bien?
  if exists (select 1 from public.log_integracion
             where evento_id = v_evento_id and resultado = 'ok') then
    return jsonb_build_object('resultado', 'duplicado', 'tipo', v_tipo,
             'evento_id', v_evento_id,
             'mensaje', 'El evento ' || v_evento_id || ' ya se había integrado');
  end if;

  -- -------------------------------------------------------------------
  -- 1. Cambio de estado: solo actualiza un pedido que ya exista
  -- -------------------------------------------------------------------
  if v_tipo = 'order.status_changed' then
    v_estado := coalesce(v_pedido ->> 'estado', p -> 'datos' ->> 'a');

    update public.pedidos_bo
       set estado = v_estado
     where pedido_tienda_id = (v_pedido ->> 'pedido_tienda_id')::bigint
    returning id, cliente_id into v_pedido_id, v_cliente_id;

    if v_pedido_id is null then
      return jsonb_build_object('resultado', 'error', 'tipo', v_tipo,
               'evento_id', v_evento_id,
               'mensaje', 'Pendiente de sincronización: el pedido '
                          || coalesce(v_pedido ->> 'codigo', '?')
                          || ' todavía no está en el back-office');
    end if;

    return jsonb_build_object('resultado', 'ok', 'tipo', v_tipo,
             'evento_id', v_evento_id, 'pedido_id', v_pedido_id,
             'cliente_id', v_cliente_id, 'codigo', v_pedido ->> 'codigo',
             'mensaje', 'Pedido ' || (v_pedido ->> 'codigo') || ' → ' || v_estado);
  end if;

  if v_tipo not in ('order.created', 'payment.simulated', 'support.requested') then
    return jsonb_build_object('resultado', 'error', 'tipo', v_tipo,
             'evento_id', v_evento_id,
             'mensaje', 'Tipo de evento no soportado: ' || v_tipo);
  end if;

  -- -------------------------------------------------------------------
  -- 2. Cliente: crear o actualizar (no toca telegram_chat_id)
  -- -------------------------------------------------------------------
  insert into public.clientes (usuario_tienda_id, email, nombre)
  values ((v_cliente ->> 'usuario_tienda_id')::uuid,
          v_cliente ->> 'email',
          v_cliente ->> 'nombre')
  on conflict (usuario_tienda_id) do update
     set email = excluded.email,
         nombre = excluded.nombre
  returning id into v_cliente_id;

  -- -------------------------------------------------------------------
  -- 3. Pedido + líneas (order.created y payment.simulated)
  -- -------------------------------------------------------------------
  if v_tipo in ('order.created', 'payment.simulated') then
    if jsonb_array_length(coalesce(v_pedido -> 'lineas', '[]'::jsonb)) = 0 then
      raise exception 'El pedido % no trae líneas', v_pedido ->> 'codigo';
    end if;

    insert into public.pedidos_bo
      (codigo_tienda, pedido_tienda_id, cliente_id, importe, estado, fecha_pedido)
    values (v_pedido ->> 'codigo',
            (v_pedido ->> 'pedido_tienda_id')::bigint,
            v_cliente_id,
            (v_pedido ->> 'total')::numeric,
            v_pedido ->> 'estado',
            (v_pedido ->> 'creado_en')::timestamptz)
    on conflict (pedido_tienda_id) do update
       -- order.created no cambia el estado de un pedido que ya existe
       set estado  = case when v_tipo = 'order.created'
                          then public.pedidos_bo.estado
                          else excluded.estado end,
           importe = excluded.importe
    returning id into v_pedido_id;

    insert into public.lineas_bo
      (pedido_id, sku, nombre_producto, descripcion_variante, precio_unitario, cantidad)
    select v_pedido_id,
           l ->> 'sku',
           l ->> 'nombre_producto',
           l ->> 'descripcion_variante',
           (l ->> 'precio_unitario')::numeric,
           (l ->> 'cantidad')::int
    from jsonb_array_elements(v_pedido -> 'lineas') as l
    on conflict (pedido_id, sku) do nothing;

    return jsonb_build_object('resultado', 'ok', 'tipo', v_tipo,
             'evento_id', v_evento_id, 'cliente_id', v_cliente_id,
             'pedido_id', v_pedido_id, 'codigo', v_pedido ->> 'codigo',
             'mensaje', 'Pedido ' || (v_pedido ->> 'codigo') || ' integrado ('
                        || (select estado from public.pedidos_bo where id = v_pedido_id) || ')');
  end if;

  -- -------------------------------------------------------------------
  -- 4. Incidencia → ticket (support.requested)
  -- -------------------------------------------------------------------
  if v_incid is null or v_incid = 'null'::jsonb then
    raise exception 'support.requested sin datos de incidencia';
  end if;

  -- El pedido puede no existir (incidencia sin pedido, o aún no integrado)
  select id into v_pedido_id from public.pedidos_bo
  where pedido_tienda_id = (v_pedido ->> 'pedido_tienda_id')::bigint;

  insert into public.tickets
    (incidencia_tienda_id, cliente_id, pedido_id, motivo, mensaje, estado, abierto_en)
  values ((v_incid ->> 'incidencia_tienda_id')::bigint,
          v_cliente_id,
          v_pedido_id,
          v_incid ->> 'motivo',
          v_incid ->> 'mensaje',
          'abierta',
          (v_incid ->> 'creado_en')::timestamptz)
  on conflict (incidencia_tienda_id) do nothing
  returning id into v_ticket_id;

  if v_ticket_id is null then
    return jsonb_build_object('resultado', 'duplicado', 'tipo', v_tipo,
             'evento_id', v_evento_id, 'cliente_id', v_cliente_id,
             'mensaje', 'La incidencia ' || (v_incid ->> 'incidencia_tienda_id')
                        || ' ya tenía ticket');
  end if;

  return jsonb_build_object('resultado', 'ok', 'tipo', v_tipo,
           'evento_id', v_evento_id, 'cliente_id', v_cliente_id,
           'pedido_id', v_pedido_id, 'ticket_id', v_ticket_id,
           'codigo', v_pedido ->> 'codigo',
           'mensaje', 'Ticket ' || v_ticket_id || ' creado ('
                      || (v_incid ->> 'motivo') || ')');

exception when others then
  -- Cualquier error de datos (estado no válido, fecha mal, etc.):
  -- se deshace TODO lo de esta llamada y se devuelve el motivo.
  return jsonb_build_object('resultado', 'error', 'tipo', v_tipo,
           'evento_id', v_evento_id,
           'mensaje', sqlerrm, 'codigo_error', sqlstate);
end;
$$;


-- ---------------------------------------------------------------------
-- Permisos: SOLO n8n (clave secreta = rol service_role) puede llamarla.
-- La app Vue (authenticated) y la clave pública (anon) no.
-- ---------------------------------------------------------------------
revoke execute on function public.integrar_evento(jsonb) from public, anon, authenticated;
grant  execute on function public.integrar_evento(jsonb) to service_role;
