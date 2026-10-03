-- =====================================================================
-- SENSOTOYS · Prototipo académico SIE
-- 14_stock.sql — Reponer stock desde el back-office
-- Ejecutar DESPUÉS de 12. Se puede repetir sin problema.
--
-- reponer_stock(p_variante_id, p_cantidad): solo admin, de 1 a 500
-- unidades. En ediciones limitadas no deja superar la tirada: el stock
-- de todas las variantes del producto, más lo ya vendido, tiene que ser
-- menor o igual que unidades_edicion. Lo "vendido" son las líneas de los
-- pedidos no cancelados y de los cancelados que llegaron a enviarse (esas
-- unidades salieron y no volvieron al almacén).
-- =====================================================================

create or replace function public.reponer_stock(p_variante_id bigint, p_cantidad int)
returns int
language plpgsql security definer set search_path = ''
as $$
declare
  v_producto_id bigint;
  v_producto    public.productos%rowtype;
  v_variante    public.variantes%rowtype;
  v_stock_total int;
  v_vendidas    int;
  v_nuevo       int;
begin
  if not public.es_admin() then
    raise exception 'Solo un administrador puede reponer stock';
  end if;
  if p_cantidad is null or p_cantidad not between 1 and 500 then
    raise exception 'La cantidad a reponer debe estar entre 1 y 500';
  end if;

  select producto_id into v_producto_id from public.variantes where id = p_variante_id;
  if not found then
    raise exception 'Variante no encontrada';
  end if;

  -- Se bloquea el producto y sus variantes (en orden de id, como
  -- crear_pedido) para que dos reposiciones no superen la tirada a la vez.
  select * into v_producto from public.productos where id = v_producto_id for update;
  perform 1 from public.variantes where producto_id = v_producto_id order by id for update;
  select * into v_variante from public.variantes where id = p_variante_id;

  if v_producto.es_edicion_limitada then
    select coalesce(sum(stock), 0) into v_stock_total
    from public.variantes where producto_id = v_producto_id;

    select coalesce(sum(lp.cantidad), 0) into v_vendidas
    from public.lineas_pedido lp
    join public.pedidos pe on pe.id = lp.pedido_id
    join public.variantes v on v.id = lp.variante_id
    where v.producto_id = v_producto_id
      and (pe.estado <> 'cancelado' or pe.llego_a_enviarse);

    if v_stock_total + v_vendidas + p_cantidad > v_producto.unidades_edicion then
      raise exception 'Se superaría la tirada de % unidades (stock %, vendidas %): como máximo puedes reponer %',
        v_producto.unidades_edicion, v_stock_total, v_vendidas,
        greatest(0, v_producto.unidades_edicion - v_stock_total - v_vendidas);
    end if;
  end if;

  update public.variantes set stock = stock + p_cantidad
  where id = p_variante_id
  returning stock into v_nuevo;

  insert into public.eventos (tipo, usuario_id, datos)
  values ('stock.replenished', auth.uid(),
          jsonb_build_object('variante_id', p_variante_id, 'sku', v_variante.sku,
                             'cantidad', p_cantidad,
                             'stock_antes', v_variante.stock, 'stock_despues', v_nuevo));
  return v_nuevo;
end;
$$;

revoke execute on function public.reponer_stock(bigint, int) from public, anon, authenticated;
grant execute on function public.reponer_stock(bigint, int) to authenticated;


-- ---------------------------------------------------------------------
-- Vista del back-office con todas las variantes y, en ediciones
-- limitadas, cuántas unidades se pueden reponer todavía.
-- security_invoker: las ventas solo las ve el admin (RLS de 04).
-- ---------------------------------------------------------------------
create or replace view public.v_stock_variantes
with (security_invoker = true) as
select
  v.id               as variante_id,
  pr.id              as producto_id,
  pr.nombre          as producto,
  v.sku,
  v.color,
  v.talla,
  v.stock,
  pr.es_edicion_limitada,
  pr.unidades_edicion,
  case when pr.es_edicion_limitada then
    greatest(0, pr.unidades_edicion
      - (select coalesce(sum(v2.stock), 0) from public.variantes v2 where v2.producto_id = pr.id)
      - (select coalesce(sum(lp.cantidad), 0)
         from public.lineas_pedido lp
         join public.pedidos pe on pe.id = lp.pedido_id
         join public.variantes v3 on v3.id = lp.variante_id
         where v3.producto_id = pr.id and (pe.estado <> 'cancelado' or pe.llego_a_enviarse)))
  end                as reponible_max
from public.variantes v
join public.productos pr on pr.id = v.producto_id
order by pr.nombre, v.id;

grant select on public.v_stock_variantes to authenticated;
