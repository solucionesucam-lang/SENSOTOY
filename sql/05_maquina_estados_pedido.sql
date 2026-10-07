-- =====================================================================
-- SENSOTOYS · Prototipo académico SIE
-- 05_maquina_estados_pedido.sql — Qué cambios de estado están permitidos


-- La función cambiar_estado_pedido() de 04 dejaba poner CUALQUIER
-- estado a un pedido (por ejemplo, pasar uno "enviado" otra vez a
-- "creado"). Esta tabla dice explícitamente qué saltos tienen sentido
-- de negocio, y la función los comprueba antes de guardar el cambio.
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1. Tabla con los saltos de estado permitidos
-- Guardarlo como datos (una fila = un salto válido) en vez de como una
-- cadena de "if" en el código hace más fácil leer y defender las
-- reglas: para saber qué está permitido, basta con hacer un select.
-- ---------------------------------------------------------------------
create table public.transiciones_pedido (
  estado_desde text not null check (estado_desde in
    ('creado','pagado','preparacion','enviado','cancelado','incidencia')),
  estado_hasta text not null check (estado_hasta in
    ('creado','pagado','preparacion','enviado','cancelado','incidencia')),
  primary key (estado_desde, estado_hasta)
);
alter table public.transiciones_pedido enable row level security;
-- Nadie desde la web necesita leer esta tabla directamente: la
-- consulta la propia función (security definer), no el navegador.

insert into public.transiciones_pedido (estado_desde, estado_hasta) values
  ('creado',      'pagado'),        -- pago con tarjeta aceptado
  ('creado',      'preparacion'),   -- contra reembolso: se prepara sin esperar al cobro
  ('creado',      'cancelado'),     -- el cliente cancela antes de pagar
  ('creado',      'incidencia'),    -- pago con tarjeta rechazado
  ('pagado',      'preparacion'),
  ('pagado',      'incidencia'),    -- algo falla ya cobrado (ej. sin stock real)
  ('preparacion', 'enviado'),
  ('preparacion', 'incidencia'),
  ('enviado',     'incidencia'),    -- el paquete se pierde o llega dañado
  ('incidencia',  'pagado'),        -- incidencia resuelta: el pago queda validado
  ('incidencia',  'preparacion'),   -- incidencia resuelta: se retoma la preparación
  ('incidencia',  'cancelado');     -- incidencia sin solución: se cancela
  -- 'cancelado' no aparece nunca en estado_desde: es un estado final.
  -- 'enviado' -> 'preparacion' tampoco existe: un envío no puede "desenviarse".


-- ---------------------------------------------------------------------
-- 2. Sustituir cambiar_estado_pedido() por una versión que sí valida
-- Mismo nombre, mismos parámetros (bigint, text) → conserva
-- automáticamente los permisos que ya le dio 04 con "grant execute".
-- ---------------------------------------------------------------------
create or replace function public.cambiar_estado_pedido(p_pedido_id bigint, p_estado text)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_estado_actual text;
begin
  if not public.es_admin() then
    raise exception 'Solo un administrador puede cambiar estados';
  end if;

  select estado into v_estado_actual from public.pedidos where id = p_pedido_id;
  if not found then
    raise exception 'Pedido no encontrado';
  end if;

  if v_estado_actual = p_estado then
    raise exception 'El pedido ya está en el estado "%"', p_estado;
  end if;

  if not exists (
    select 1 from public.transiciones_pedido
    where estado_desde = v_estado_actual and estado_hasta = p_estado
  ) then
    raise exception 'No se puede pasar un pedido de "%" a "%"', v_estado_actual, p_estado;
  end if;

  update public.pedidos set estado = p_estado where id = p_pedido_id;
end;
$$;
