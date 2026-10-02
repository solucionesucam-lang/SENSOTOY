alter table public.cupones add column if not exists un_uso_por_cliente boolean not null default false;
update public.cupones set un_uso_por_cliente = true where codigo = 'BIENVENIDA10';
