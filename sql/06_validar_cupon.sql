-- =====================================================================
-- 06_validar_cupon.sql — Validación de cupones para el checkout
-- Solo lectura. Replica las reglas de cupón de crear_pedido() (sql/04),
-- que sigue siendo la validación que manda al confirmar el pedido.
-- =====================================================================

create or replace function public.validar_cupon(p_codigo text, p_subtotal numeric)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_codigo    text := upper(trim(coalesce(p_codigo, '')));
  v_subtotal  numeric := coalesce(p_subtotal, 0);
  v_cupon     public.cupones%rowtype;
  v_descuento numeric;
begin
  if v_codigo = '' then
    return jsonb_build_object('valido', false, 'mensaje', 'Introduce un cupón.',
                              'codigo', '', 'descuento', 0);
  end if;

  select * into v_cupon from public.cupones where codigo = v_codigo;
  if not found or not v_cupon.activo
     or (v_cupon.valido_hasta is not null and v_cupon.valido_hasta < current_date) then
    return jsonb_build_object('valido', false, 'mensaje', 'El cupón no existe o ha caducado',
                              'codigo', v_codigo, 'descuento', 0);
  end if;

  if v_subtotal < v_cupon.importe_minimo then
    return jsonb_build_object('valido', false,
                              'mensaje', format('El cupón exige un pedido mínimo de %s €', trim_scale(v_cupon.importe_minimo)),
                              'codigo', v_codigo, 'descuento', 0);
  end if;

  if v_cupon.tipo = 'porcentaje' then
    v_descuento := round(v_subtotal * v_cupon.valor / 100, 2);
  else
    v_descuento := least(v_cupon.valor, v_subtotal);
  end if;

  return jsonb_build_object('valido', true,
                            'mensaje', 'Cupón aplicado: -' || replace(to_char(v_descuento, 'FM999990.00'), '.', ',') || ' €',
                            'codigo', v_cupon.codigo, 'descuento', v_descuento);
end;
$$;

grant execute on function public.validar_cupon(text, numeric) to anon, authenticated;
