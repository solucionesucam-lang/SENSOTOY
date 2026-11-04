-- =====================================================================
-- SENSOTOYS · Integración de Stripe en entorno de pruebas
-- 29_registrar_reembolso_stripe.sql
--
-- PROPUESTA PENDIENTE DE REVISIÓN Y PRUEBAS.
-- Guardar en GitHub. NO ejecutar todavía en Supabase.
--
-- Objetivo:
-- Registrar un reembolso confirmado por Stripe cuando el pedido
-- ya estaba cancelado antes de procesar la confirmación del pago.
--
-- Requiere:
--   · Tablas pedidos y pagos.
--   · Flujo Stripe de sql/22 y sql/28.
--
-- IMPORTANTE:
-- Esta función NO realiza el reembolso en Stripe.
-- El webhook lo solicita y comprueba que su estado sea "succeeded"
-- ANTES de llamar a esta función.
--
-- No modifica:
--   · El estado del pedido.
--   · El stock.
--   · El cupón.
--   · El resultado del pago.
--
-- El esquema actual de pagos no admite el resultado "reembolsado".
-- La devolución queda registrada por separado en stripe_reembolsos.
-- No se emite un nuevo tipo de evento de integración.
-- =====================================================================

begin;


-- ---------------------------------------------------------------------
-- 1. Registro de reembolsos completos de este flujo
-- ---------------------------------------------------------------------

create table if not exists public.stripe_reembolsos (
  id bigint generated always as identity primary key,

  pedido_id bigint not null
    references public.pedidos(id),

  pago_id bigint not null unique
    references public.pagos(id),

  stripe_session_id text not null unique
    check (stripe_session_id ~ '^cs_test_'),

  stripe_payment_intent text not null unique
    check (stripe_payment_intent ~ '^pi_'),

  stripe_reembolso_id text not null unique
    check (stripe_reembolso_id ~ '^re_'),

  stripe_evento_id text not null
    check (stripe_evento_id ~ '^evt_'),

  importe_centimos bigint not null
    check (importe_centimos > 0),

  moneda text not null
    check (moneda = 'eur'),

  motivo text not null
    default 'pedido_cancelado_antes_de_confirmar'
    check (motivo = 'pedido_cancelado_antes_de_confirmar'),

  creado_en timestamptz not null default now()
);

create index if not exists stripe_reembolsos_pedido_idx
  on public.stripe_reembolsos (pedido_id);

-- No se expone este registro al navegador.
alter table public.stripe_reembolsos
  enable row level security;

revoke all privileges
  on table public.stripe_reembolsos
  from public, anon, authenticated;


-- ---------------------------------------------------------------------
-- 2. Registro transaccional e idempotente
-- ---------------------------------------------------------------------

create or replace function public.registrar_reembolso_stripe(
  p_pedido_id bigint,
  p_pago_id bigint,
  p_session_id text,
  p_payment_intent text,
  p_reembolso_id text,
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
  v_registro public.stripe_reembolsos%rowtype;
  v_registro_id bigint;
begin
  -- Datos obligatorios.
  if p_pedido_id is null
     or p_pago_id is null
     or p_session_id is null
     or p_session_id !~ '^cs_test_'
     or p_payment_intent is null
     or p_payment_intent !~ '^pi_'
     or p_reembolso_id is null
     or p_reembolso_id !~ '^re_'
     or p_evento_id is null
     or p_evento_id !~ '^evt_'
     or p_importe_centimos is null
     or p_importe_centimos <= 0
     or p_moneda is distinct from 'eur' then
    raise exception 'Datos de reembolso de Stripe no válidos';
  end if;

  -- Mismo orden de bloqueo que las funciones de cambio de estado:
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

  if v_pago.proveedor is distinct from 'stripe_test'
     or v_pago.metodo is distinct from 'tarjeta' then
    raise exception 'El pago no corresponde a Stripe en pruebas';
  end if;

  if v_pago.referencia_externa is distinct from p_session_id then
    raise exception 'La sesión de Stripe no coincide con el pago';
  end if;

  if round(v_pedido.total * 100)::bigint
       is distinct from p_importe_centimos
     or round(v_pago.importe * 100)::bigint
       is distinct from p_importe_centimos then
    raise exception 'El importe del reembolso no coincide con el pedido';
  end if;

  if v_pedido.estado is distinct from 'cancelado' then
    raise exception
      'Este registro solo admite pedidos cancelados; estado actual: %',
      v_pedido.estado;
  end if;

  -- El bloqueo del pedido serializa los registros del mismo pedido.
  -- Si llega de nuevo el webhook, devolvemos el registro existente.
  select *
  into v_registro
  from public.stripe_reembolsos
  where pago_id = p_pago_id;

  if found then
    if v_registro.pedido_id is distinct from p_pedido_id
       or v_registro.stripe_session_id
            is distinct from p_session_id
       or v_registro.stripe_payment_intent
            is distinct from p_payment_intent
       or v_registro.stripe_reembolso_id
            is distinct from p_reembolso_id
       or v_registro.importe_centimos
            is distinct from p_importe_centimos
       or v_registro.moneda
            is distinct from p_moneda then
      raise exception
        'El reembolso recibido no coincide con el registrado';
    end if;

    return jsonb_build_object(
      'accion', 'ya_registrado',
      'registro_id', v_registro.id,
      'pedido_id', v_pedido.id,
      'codigo', v_pedido.codigo,
      'stripe_reembolso_id', v_registro.stripe_reembolso_id
    );
  end if;

  insert into public.stripe_reembolsos (
    pedido_id,
    pago_id,
    stripe_session_id,
    stripe_payment_intent,
    stripe_reembolso_id,
    stripe_evento_id,
    importe_centimos,
    moneda
  )
  values (
    p_pedido_id,
    p_pago_id,
    p_session_id,
    p_payment_intent,
    p_reembolso_id,
    p_evento_id,
    p_importe_centimos,
    p_moneda
  )
  returning id into v_registro_id;

  return jsonb_build_object(
    'accion', 'registrado',
    'registro_id', v_registro_id,
    'pedido_id', v_pedido.id,
    'codigo', v_pedido.codigo,
    'stripe_reembolso_id', p_reembolso_id
  );
end;
$$;


-- ---------------------------------------------------------------------
-- 3. Permisos: solo la llamada de servidor del webhook
-- ---------------------------------------------------------------------

revoke execute on function public.registrar_reembolso_stripe(
  bigint, bigint, text, text, text, text, bigint, text
) from public, anon, authenticated;

grant execute on function public.registrar_reembolso_stripe(
  bigint, bigint, text, text, text, text, bigint, text
) to service_role;

commit;
