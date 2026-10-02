alter table public.cupones add column if not exists un_uso_por_cliente boolean not null default false;
update public.cupones set un_uso_por_cliente = true where codigo = 'BIENVENIDA10';


create index if not exists eventos_usuario_id_idx on public.eventos (usuario_id);
create index if not exists eventos_pedido_id_idx on public.eventos (pedido_id);
create index if not exists incidencias_usuario_id_idx on public.incidencias (usuario_id);
create index if not exists incidencias_pedido_id_idx on public.incidencias (pedido_id);
create index if not exists lineas_pedido_variante_id_idx on public.lineas_pedido (variante_id);
create index if not exists pedidos_cupon_codigo_idx on public.pedidos (cupon_codigo);


drop policy if exists "perfiles: el propio o admin" on public.perfiles;
create policy "perfiles: el propio o admin" on public.perfiles
  for select to authenticated
  using (id = (select auth.uid()) or (select public.es_admin()));

drop policy if exists "pedidos: los propios o admin" on public.pedidos;
create policy "pedidos: los propios o admin" on public.pedidos
  for select to authenticated
  using (usuario_id = (select auth.uid()) or (select public.es_admin()));

drop policy if exists "lineas: las de mis pedidos o admin" on public.lineas_pedido;
create policy "lineas: las de mis pedidos o admin" on public.lineas_pedido
  for select to authenticated using (
    exists (select 1 from public.pedidos p where p.id = lineas_pedido.pedido_id
            and (p.usuario_id = (select auth.uid()) or (select public.es_admin()))));

drop policy if exists "pagos: los de mis pedidos o admin" on public.pagos;
create policy "pagos: los de mis pedidos o admin" on public.pagos
  for select to authenticated using (
    exists (select 1 from public.pedidos p where p.id = pagos.pedido_id
            and (p.usuario_id = (select auth.uid()) or (select public.es_admin()))));

drop policy if exists "incidencias: las propias o admin" on public.incidencias;
create policy "incidencias: las propias o admin" on public.incidencias
  for select to authenticated
  using (usuario_id = (select auth.uid()) or (select public.es_admin()));

drop policy if exists "eventos: solo admin" on public.eventos;
create policy "eventos: solo admin" on public.eventos
  for select to authenticated using ((select public.es_admin()));

grant select on public.transiciones_pedido to authenticated;
drop policy if exists "transiciones: solo admin" on public.transiciones_pedido;
create policy "transiciones: solo admin" on public.transiciones_pedido
  for select to authenticated using ((select public.es_admin()));


create or replace function public.cupon_ya_usado(p_codigo text, p_usuario uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (select 1 from public.pedidos
                 where usuario_id = p_usuario and cupon_codigo = p_codigo
                   and estado <> 'cancelado');
$$;

revoke execute on function public.cupon_ya_usado(text, uuid) from public, anon, authenticated;
