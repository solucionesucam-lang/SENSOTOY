alter table public.cupones add column if not exists un_uso_por_cliente boolean not null default false;
update public.cupones set un_uso_por_cliente = true where codigo = 'BIENVENIDA10';


create index if not exists eventos_usuario_id_idx on public.eventos (usuario_id);
create index if not exists eventos_pedido_id_idx on public.eventos (pedido_id);
create index if not exists incidencias_usuario_id_idx on public.incidencias (usuario_id);
create index if not exists incidencias_pedido_id_idx on public.incidencias (pedido_id);
create index if not exists lineas_pedido_variante_id_idx on public.lineas_pedido (variante_id);
create index if not exists pedidos_cupon_codigo_idx on public.pedidos (cupon_codigo);
