-- =====================================================================
-- SENSOTOYS · Integración de Stripe en entorno de pruebas
-- 28_confirmar_pago_stripe.sql
--
-- PROPUESTA PENDIENTE DE REVISIÓN Y PRUEBAS.
-- Guardar en GitHub. NO ejecutar todavía en Supabase.
--
-- Requiere:
--   · sql/12_estados_y_eventos.sql
--   · sql/22_stripe_test.sql
--
-- El webhook llamará a esta función DESPUÉS de verificar:
--   · La firma de Stripe.
--   · Que el evento corresponde al entorno de pruebas.
--   · Que la sesión está pagada.
--
-- Esta función no consulta Stripe ni realiza reembolsos.
-- Si encuentra el pedido cancelado, devuelve la acción
-- "reembolsar" para que el webhook gestione ese caso.
-- =====================================================================

begin;

create or replace function public.confirmar_pago_stripe(
  p_pedido_id bigint,
  p_pago_id bigint,
  p_session_id text,
  p_payment_intent text,
  p_evento_id text,
  p_importe_centimos bigint,
  p_moneda text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_pedido public.pedidos%rowtype;
  v_pago public.pagos%rowtype;
  v_ultimo_pago_id bigint;
  v_evento public.eventos%rowtype;
begin
  -- Comprobaciones básicas de los datos recibidos.
  if p_pedido_id is null
     or p_pago_id is null
     or p_session_id is null
     or p_session_id not like 'cs_test_%'
     or p_payment_intent is null
     or p_payment_intent not like 'pi_%'
     or p_evento_id is null
     or p_evento_id not like 'evt_%'
     or p_importe_centimos is null
     or p_importe_centimos <= 0
     or p_moneda is distinct from 'eur' then
    raise exception 'Datos de confirmación de Stripe no válidos';
  end if;

  -- Mismo orden de bloqueo que aplicar_cambio_estado():
  -- primero el pedido y después su pago.
  select *
  into v_pedido
  from public.pedidos
  where id = p_pedido_id
  for update;

  if not found then
    raise exception 'Pedido no encontrado';
  end if;

  select *
  into v_pago
  from public.pagos
  where id = p_pago_id
    and pedido_id = p_pedido_id
  for update;

  if not found then
    raise exception 'Pago no encontrado para este pedido';
  end if;

  select id
  into v_ultimo_pago_id
  from public.pagos
  where pedido_id = p_pedido_id
  order by id desc
  limit 1;

  if v_ultimo_pago_id is distinct from p_pago_id then
    raise exception 'La confirmación no corresponde al último pago';
  end if;

  if v_pago.proveedor is distinct from 'stripe_test'
     or v_pago.metodo is distinct from 'tarjeta' then
    raise exception 'El pago no corresponde a Stripe en pruebas';
  end if;

  -- referencia_externa conserva el identificador de la sesión.
  -- El PaymentIntent se guarda en los datos del evento.
  if v_pago.referencia_externa is distinct from p_session_id then
    raise exception 'La sesión de Stripe no coincide con el pago';
  end if;

  if round(v_pedido.total * 100)::bigint
       is distinct from p_importe_centimos
     or round(v_pago.importe * 100)::bigint
       is distinct from p_importe_centimos then
    raise exception 'El importe confirmado no coincide con el pedido';
  end if;

  -- Evita repetir el evento de negocio para una sesión ya procesada.
  -- El bloqueo del pedido serializa las llamadas de esta función
  -- sobre el mismo pedido.
  select *
  into v_evento
  from public.eventos
  where pedido_id = p_pedido_id
    and tipo = 'payment.simulated'
    and datos ->> 'proveedor' = 'stripe_test'
    and datos ->> 'stripe_session_id' = p_session_id
  order by id
  limit 1;

  if found then
    if v_evento.datos ->> 'stripe_payment_intent'
         is distinct from p_payment_intent then
      raise exception 'El PaymentIntent no coincide con el registrado';
    end if;

    if v_pago.resultado is distinct from 'aceptado' then
      raise exception 'El pago registrado tiene un resultado incoherente';
    end if;

    return jsonb_build_object(
      'accion', 'ya_procesado',
      'pedido_id', v_pedido.id,
      'codigo', v_pedido.codigo,
      'estado', v_pedido.estado
    );
  end if;

  -- Cancelar y confirmar compiten por el mismo bloqueo del pedido.
  -- Si la cancelación ganó, no intentamos reabrir el pedido.
  if v_pedido.estado = 'cancelado' then
    return jsonb_build_object(
      'accion', 'reembolsar',
      'pedido_id', v_pedido.id,
      'pago_id', v_pago.id,
      'codigo', v_pedido.codigo,
      'stripe_session_id', p_session_id,
      'stripe_payment_intent', p_payment_intent
    );
  end if;

  -- Una situación distinta requiere revisión, no una actualización
  -- directa que se salte las transiciones del proyecto.
  if v_pedido.estado is distinct from 'creado'
     or v_pago.resultado is distinct from 'pendiente' then
    raise exception
      'No se puede confirmar automáticamente: estado %, resultado %',
      v_pedido.estado,
      v_pago.resultado;
  end if;

  -- PRIMERO se actualiza el estado y se acepta el pago.
  perform public.aplicar_cambio_estado(
    p_pedido_id,
    'pagado',
    true
  );

  -- DESPUÉS se inserta el evento que consume la integración.
  insert into public.eventos (
    tipo,
    usuario_id,
    pedido_id,
    datos
  )
  values (
    'payment.simulated',
    v_pedido.usuario_id,
    v_pedido.id,
    jsonb_build_object(
      'proveedor', 'stripe_test',
      'metodo', 'tarjeta',
      'resultado', 'aceptado',
      'importe', v_pago.importe,
      'ultimos4', v_pago.ultimos4,
      'stripe_session_id', p_session_id,
      'stripe_payment_intent', p_payment_intent,
      'stripe_evento_id', p_evento_id
    )
  );

  return jsonb_build_object(
    'accion', 'confirmado',
    'pedido_id', v_pedido.id,
    'codigo', v_pedido.codigo,
    'estado', 'pagado'
  );
end;
$$;

-- No puede ejecutarse desde el navegador, ni siquiera con login.
revoke execute on function public.confirmar_pago_stripe(
  bigint, bigint, text, text, text, bigint, text
) from public, anon, authenticated;

-- La utilizará el webhook con el cliente de servidor.
grant execute on function public.confirmar_pago_stripe(
  bigint, bigint, text, text, text, bigint, text
) to service_role;

commit;
