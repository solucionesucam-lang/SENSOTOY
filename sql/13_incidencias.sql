-- =====================================================================
-- SENSOTOYS · Prototipo académico SIE
-- 13_incidencias.sql — Postventa: motivos que afectan al pedido y gestión
-- Ejecutar DESPUÉS de 12. Se puede repetir sin problema.
--
-- Qué hace:
--   1. crear_incidencia() solo pasa el pedido a "incidencia" cuando el
--      motivo es 'producto_defectuoso' o 'retraso_envio'. Con 'otro' y
--      'pago_rechazado' la incidencia se registra y el pedido no cambia.
--   2. cambiar_estado_incidencia() deja al admin gestionar las
--      incidencias: abierta -> en_curso -> resuelta.
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1. Abrir una incidencia (formulario de ayuda y postventa)
-- ---------------------------------------------------------------------
create or replace function public.crear_incidencia(
  p_motivo text, p_mensaje text, p_pedido_id bigint default null, p_sesion text default null)
returns bigint
language plpgsql security definer set search_path = ''
as $$
declare
  v_usuario uuid := auth.uid();
  v_estado  text;
  v_id      bigint;
begin
  if v_usuario is null then
    raise exception 'Tienes que iniciar sesión para abrir una incidencia';
  end if;
  if coalesce(p_motivo, '') not in ('pago_rechazado', 'retraso_envio', 'producto_defectuoso', 'otro') then
    raise exception 'Elige un motivo válido';
  end if;
  if length(trim(coalesce(p_mensaje, ''))) not between 10 and 1000 then
    raise exception 'La descripción debe tener entre 10 y 1000 caracteres';
  end if;

  if p_pedido_id is not null then
    select estado into v_estado from public.pedidos
    where id = p_pedido_id and usuario_id = v_usuario for update;
    if not found then
      raise exception 'Ese pedido no es tuyo';
    end if;
  end if;

  insert into public.incidencias (usuario_id, pedido_id, motivo, mensaje)
  values (v_usuario, p_pedido_id, p_motivo, trim(p_mensaje))
  returning id into v_id;

  insert into public.eventos (tipo, usuario_id, sesion_id, pedido_id, datos)
  values ('support.requested', v_usuario, left(p_sesion, 60), p_pedido_id,
          jsonb_build_object('incidencia_id', v_id, 'motivo', p_motivo));

  -- Solo estos dos motivos ponen el pedido "con incidencia", y solo si el
  -- estado actual lo permite (un pedido cancelado, o ya con incidencia,
  -- se queda como está).
  if p_pedido_id is not null
     and p_motivo in ('producto_defectuoso', 'retraso_envio')
     and exists (select 1 from public.transiciones_pedido
                 where estado_desde = v_estado and estado_hasta = 'incidencia') then
    perform public.aplicar_cambio_estado(p_pedido_id, 'incidencia', false);
  end if;

  return v_id;
end;
$$;

revoke execute on function public.crear_incidencia(text, text, bigint, text) from public, anon, authenticated;
grant execute on function public.crear_incidencia(text, text, bigint, text) to authenticated;


-- ---------------------------------------------------------------------
-- 2. Gestionar una incidencia (solo admin): abierta -> en_curso -> resuelta
-- ---------------------------------------------------------------------
create or replace function public.cambiar_estado_incidencia(p_id bigint, p_estado text)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_actual text;
begin
  if not public.es_admin() then
    raise exception 'Solo un administrador puede gestionar incidencias';
  end if;

  select estado into v_actual from public.incidencias where id = p_id for update;
  if not found then
    raise exception 'Incidencia no encontrada';
  end if;

  if not ((v_actual = 'abierta' and p_estado = 'en_curso')
       or (v_actual = 'en_curso' and p_estado = 'resuelta')) then
    raise exception 'No se puede pasar una incidencia de "%" a "%"', v_actual, p_estado;
  end if;

  update public.incidencias set estado = p_estado where id = p_id;
end;
$$;

revoke execute on function public.cambiar_estado_incidencia(bigint, text) from public, anon, authenticated;
grant execute on function public.cambiar_estado_incidencia(bigint, text) to authenticated;
