-- =====================================================================
-- SENSOTOYS · Prototipo académico SIE
-- pruebas.sql — Pruebas de la lógica de negocio (no dejan datos)
--
-- Ejecutar DESPUÉS de todos los scripts (01 a 16) y con los usuarios de
-- prueba creados. En Supabase > SQL Editor, SELECCIONA UN BLOQUE cada vez
-- (de "do $$" a "$$;") y pulsa Run: cada bloque termina siempre con un
-- "raise exception", que deshace todo lo que haya hecho, y el mensaje del
-- error es el resultado:
--     PRUEBA n · OK: ...      -> la prueba pasa
--     PRUEBA n · FALLO: ...   -> hay un fallo en la lógica
-- Cada bloque se hace pasar por un usuario con request.jwt.claims (lo mismo
-- que lee auth.uid()) y crea su propio producto de prueba, así que no
-- depende de los datos del catálogo.
-- =====================================================================


-- @prueba 1 · Transiciones de estado prohibidas
do $$
declare
  v_admin uuid := (select id from auth.users where email = 'admin@sensotoys-demo.test');
  v_c1    uuid := (select id from auth.users where email = 'cliente1@sensotoys-demo.test');
  v_envio jsonb := '{"nombre":"Prueba","direccion":"Calle Prueba 1","cp":"28001","ciudad":"Madrid","provincia":"Madrid"}';
  v_prod bigint; v_var bigint; v_r jsonb; v_ped bigint; v_msg text; v_estado text;
begin
  insert into public.productos (categoria_id, nombre, slug, descripcion, material, edad_minima)
    select id, 'Prueba', 'zz-prueba-1', 'x', 'x', 6 from public.categorias limit 1 returning id into v_prod;
  insert into public.variantes (producto_id, sku, color, color_hex, textura, talla, precio, stock)
    values (v_prod, 'ZZ-1', 'Rojo', '#FF0000', 'lisa', 'Única', 25, 20) returning id into v_var;

  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_c1, 'role', 'authenticated')::text, true);
  v_r := public.crear_pedido(jsonb_build_array(jsonb_build_object('variante_id', v_var, 'cantidad', 1)),
                             v_envio, 'contrareembolso');
  select id into v_ped from public.pedidos where codigo = v_r ->> 'codigo';

  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  begin
    perform public.cambiar_estado_pedido(v_ped, 'enviado');   -- creado -> enviado no existe
    raise exception 'PRUEBA 1 · FALLO: se permitió creado -> enviado';
  exception when others then
    v_msg := sqlerrm;
    if v_msg like 'PRUEBA 1%' then raise; end if;
  end;
  if v_msg not like 'No se puede pasar un pedido de "creado" a "enviado"%' then
    raise exception 'PRUEBA 1 · FALLO: mensaje inesperado: %', v_msg;
  end if;

  perform public.cambiar_estado_pedido(v_ped, 'cancelado');
  begin
    perform public.cambiar_estado_pedido(v_ped, 'pagado');    -- cancelado es un estado final
    raise exception 'PRUEBA 1 · FALLO: se reabrió un pedido cancelado';
  exception when others then
    if sqlerrm like 'PRUEBA 1%' then raise; end if;
  end;

  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_c1, 'role', 'authenticated')::text, true);
  begin
    perform public.cambiar_estado_pedido(v_ped, 'pagado');    -- un cliente no puede cambiar estados
    raise exception 'PRUEBA 1 · FALLO: un cliente cambió un estado';
  exception when others then
    if sqlerrm like 'PRUEBA 1%' then raise; end if;
  end;

  select estado into v_estado from public.pedidos where id = v_ped;
  raise exception 'PRUEBA 1 · OK: creado->enviado rechazado, cancelado->pagado rechazado, cliente sin permiso (estado final: %)', v_estado;
end $$;


-- @prueba 2 · Incidencia: solo defectuoso y retraso cambian el pedido
do $$
declare
  v_c1    uuid := (select id from auth.users where email = 'cliente1@sensotoys-demo.test');
  v_envio jsonb := '{"nombre":"Prueba","direccion":"Calle Prueba 1","cp":"28001","ciudad":"Madrid","provincia":"Madrid"}';
  v_prod bigint; v_var bigint; v_r jsonb; v_ped bigint; v_ped2 bigint; v_estado text; v_eventos int;
begin
  insert into public.productos (categoria_id, nombre, slug, descripcion, material, edad_minima)
    select id, 'Prueba', 'zz-prueba-2', 'x', 'x', 6 from public.categorias limit 1 returning id into v_prod;
  insert into public.variantes (producto_id, sku, color, color_hex, textura, talla, precio, stock)
    values (v_prod, 'ZZ-2', 'Rojo', '#FF0000', 'lisa', 'Única', 25, 20) returning id into v_var;

  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_c1, 'role', 'authenticated')::text, true);
  v_r := public.crear_pedido(jsonb_build_array(jsonb_build_object('variante_id', v_var, 'cantidad', 1)),
                             v_envio, 'tarjeta', '4242 4242 4242 4242');
  select id into v_ped from public.pedidos where codigo = v_r ->> 'codigo';

  perform public.crear_incidencia('otro', 'Tengo una duda sobre mi pedido', v_ped);
  select estado into v_estado from public.pedidos where id = v_ped;
  if v_estado <> 'pagado' then
    raise exception 'PRUEBA 2 · FALLO: el motivo "otro" cambió el pedido a %', v_estado;
  end if;

  perform public.crear_incidencia('pago_rechazado', 'El banco dice que el pago falló', v_ped);
  select estado into v_estado from public.pedidos where id = v_ped;
  if v_estado <> 'pagado' then
    raise exception 'PRUEBA 2 · FALLO: el motivo "pago_rechazado" cambió el pedido a %', v_estado;
  end if;

  if (select count(*) from public.incidencias where pedido_id = v_ped) <> 2 then
    raise exception 'PRUEBA 2 · FALLO: las incidencias no se registraron';
  end if;

  perform public.crear_incidencia('retraso_envio', 'Mi pedido tarda demasiado en llegar', v_ped);
  select estado into v_estado from public.pedidos where id = v_ped;
  if v_estado <> 'incidencia' then
    raise exception 'PRUEBA 2 · FALLO: "retraso_envio" dejó el pedido en %', v_estado;
  end if;

  v_r := public.crear_pedido(jsonb_build_array(jsonb_build_object('variante_id', v_var, 'cantidad', 1)),
                             v_envio, 'contrareembolso');
  select id into v_ped2 from public.pedidos where codigo = v_r ->> 'codigo';
  perform public.crear_incidencia('producto_defectuoso', 'El producto llegó roto de fábrica', v_ped2);
  select estado into v_estado from public.pedidos where id = v_ped2;
  if v_estado <> 'incidencia' then
    raise exception 'PRUEBA 2 · FALLO: "producto_defectuoso" dejó el pedido en %', v_estado;
  end if;

  select count(*) into v_eventos from public.eventos
  where pedido_id in (v_ped, v_ped2) and tipo = 'order.status_changed' and datos ->> 'a' = 'incidencia';
  raise exception 'PRUEBA 2 · OK: otro y pago_rechazado no tocan el pedido; retraso_envio y producto_defectuoso sí (eventos order.status_changed: %)', v_eventos;
end $$;


-- @prueba 3 · Reponer stock: límites, tirada y evento
do $$
declare
  v_admin uuid := (select id from auth.users where email = 'admin@sensotoys-demo.test');
  v_c1    uuid := (select id from auth.users where email = 'cliente1@sensotoys-demo.test');
  v_envio jsonb := '{"nombre":"Prueba","direccion":"Calle Prueba 1","cp":"28001","ciudad":"Madrid","provincia":"Madrid"}';
  v_prod bigint; v_var bigint; v_r jsonb; v_msg text; v_stock int; v_eventos int;
begin
  -- Edición limitada de 10 unidades: 4 en stock, se venden 2 -> stock 2, vendidas 2
  insert into public.productos (categoria_id, nombre, slug, descripcion, material, edad_minima, es_edicion_limitada, unidades_edicion)
    select id, 'Prueba limitada', 'zz-prueba-3', 'x', 'x', 6, true, 10 from public.categorias limit 1 returning id into v_prod;
  insert into public.variantes (producto_id, sku, color, color_hex, textura, talla, precio, stock)
    values (v_prod, 'ZZ-3', 'Rojo', '#FF0000', 'lisa', 'Única', 25, 4) returning id into v_var;

  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_c1, 'role', 'authenticated')::text, true);
  v_r := public.crear_pedido(jsonb_build_array(jsonb_build_object('variante_id', v_var, 'cantidad', 2)),
                             v_envio, 'tarjeta', '4242 4242 4242 4242');
  begin
    perform public.reponer_stock(v_var, 1);
    raise exception 'PRUEBA 3 · FALLO: un cliente repuso stock';
  exception when others then
    if sqlerrm like 'PRUEBA 3%' then raise; end if;
  end;

  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  foreach v_stock in array array[0, 501, -3] loop
    begin
      perform public.reponer_stock(v_var, v_stock);
      raise exception 'PRUEBA 3 · FALLO: se aceptó la cantidad %', v_stock;
    exception when others then
      if sqlerrm like 'PRUEBA 3%' then raise; end if;
    end;
  end loop;

  begin
    perform public.reponer_stock(v_var, 7);                    -- 2 + 2 + 7 = 11 > 10
    raise exception 'PRUEBA 3 · FALLO: se superó la tirada';
  exception when others then
    v_msg := sqlerrm;
    if v_msg like 'PRUEBA 3%' then raise; end if;
  end;
  if v_msg not like 'Se superaría la tirada%' then
    raise exception 'PRUEBA 3 · FALLO: mensaje inesperado: %', v_msg;
  end if;

  v_stock := public.reponer_stock(v_var, 6);                   -- 2 + 2 + 6 = 10: justo la tirada
  if v_stock <> 8 then
    raise exception 'PRUEBA 3 · FALLO: stock esperado 8, hay %', v_stock;
  end if;
  begin
    perform public.reponer_stock(v_var, 1);
    raise exception 'PRUEBA 3 · FALLO: se superó la tirada por 1 unidad';
  exception when others then
    if sqlerrm like 'PRUEBA 3%' then raise; end if;
  end;

  select count(*) into v_eventos from public.eventos where tipo = 'stock.replenished' and datos ->> 'sku' = 'ZZ-3';
  if v_eventos <> 1 then
    raise exception 'PRUEBA 3 · FALLO: eventos stock.replenished = %', v_eventos;
  end if;
  raise exception 'PRUEBA 3 · OK: cantidad 1..500, solo admin, tirada respetada (stock final %), evento registrado', v_stock;
end $$;


-- @prueba 4 · Cupón de un solo uso por cliente
do $$
declare
  v_c1    uuid := (select id from auth.users where email = 'cliente1@sensotoys-demo.test');
  v_c2    uuid := (select id from auth.users where email = 'cliente2@sensotoys-demo.test');
  v_envio jsonb := '{"nombre":"Prueba","direccion":"Calle Prueba 1","cp":"28001","ciudad":"Madrid","provincia":"Madrid"}';
  v_prod bigint; v_var bigint; v_r jsonb; v_msg text; v_v jsonb; v_lineas jsonb;
begin
  insert into public.productos (categoria_id, nombre, slug, descripcion, material, edad_minima)
    select id, 'Prueba', 'zz-prueba-4', 'x', 'x', 6 from public.categorias limit 1 returning id into v_prod;
  insert into public.variantes (producto_id, sku, color, color_hex, textura, talla, precio, stock)
    values (v_prod, 'ZZ-4', 'Rojo', '#FF0000', 'lisa', 'Única', 25, 20) returning id into v_var;
  v_lineas := jsonb_build_array(jsonb_build_object('variante_id', v_var, 'cantidad', 1));

  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_c1, 'role', 'authenticated')::text, true);
  v_r := public.crear_pedido(v_lineas, v_envio, 'contrareembolso', null, 'BIENVENIDA10');
  if (select descuento from public.pedidos where codigo = v_r ->> 'codigo') <> 2.50 then
    raise exception 'PRUEBA 4 · FALLO: el descuento del 10 %% de 25 € debería ser 2,50';
  end if;

  v_v := public.validar_cupon('BIENVENIDA10', 25);
  if (v_v ->> 'valido')::boolean then
    raise exception 'PRUEBA 4 · FALLO: validar_cupon acepta un cupón ya usado';
  end if;

  begin
    perform public.crear_pedido(v_lineas, v_envio, 'contrareembolso', null, 'BIENVENIDA10');
    raise exception 'PRUEBA 4 · FALLO: se usó el cupón dos veces';
  exception when others then
    v_msg := sqlerrm;
    if v_msg like 'PRUEBA 4%' then raise; end if;
  end;
  if v_msg <> 'Ya has usado este cupón' then
    raise exception 'PRUEBA 4 · FALLO: mensaje inesperado: %', v_msg;
  end if;

  -- Cancelar el pedido libera el cupón
  perform public.cancelar_mi_pedido(v_r ->> 'codigo');
  v_r := public.crear_pedido(v_lineas, v_envio, 'contrareembolso', null, 'BIENVENIDA10');

  -- Otro cliente sí puede usarlo
  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_c2, 'role', 'authenticated')::text, true);
  v_r := public.crear_pedido(v_lineas, v_envio, 'contrareembolso', null, 'BIENVENIDA10');
  raise exception 'PRUEBA 4 · OK: segundo uso rechazado ("%"), cupón libre tras cancelar, otro cliente puede usarlo', v_msg;
end $$;


-- @prueba 5 · Avance automático cada 5 horas
do $$
declare
  v_c1    uuid := (select id from auth.users where email = 'cliente1@sensotoys-demo.test');
  v_envio jsonb := '{"nombre":"Prueba","direccion":"Calle Prueba 1","cp":"28001","ciudad":"Madrid","provincia":"Madrid"}';
  v_prod bigint; v_var bigint; v_lineas jsonb;
  v_r jsonb; v_pagado bigint; v_contra bigint; v_rechazado bigint; v_reciente bigint; v_n int; v_eventos int; v_resultado text;
begin
  insert into public.productos (categoria_id, nombre, slug, descripcion, material, edad_minima)
    select id, 'Prueba', 'zz-prueba-5', 'x', 'x', 6 from public.categorias limit 1 returning id into v_prod;
  insert into public.variantes (producto_id, sku, color, color_hex, textura, talla, precio, stock)
    values (v_prod, 'ZZ-5', 'Rojo', '#FF0000', 'lisa', 'Única', 25, 20) returning id into v_var;
  v_lineas := jsonb_build_array(jsonb_build_object('variante_id', v_var, 'cantidad', 1));

  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_c1, 'role', 'authenticated')::text, true);
  v_r := public.crear_pedido(v_lineas, v_envio, 'tarjeta', '4242424242424242');
  select id into v_pagado from public.pedidos where codigo = v_r ->> 'codigo';
  v_r := public.crear_pedido(v_lineas, v_envio, 'contrareembolso');
  select id into v_contra from public.pedidos where codigo = v_r ->> 'codigo';
  v_r := public.crear_pedido(v_lineas, v_envio, 'tarjeta', '1111222233330000');
  select id into v_rechazado from public.pedidos where codigo = v_r ->> 'codigo';
  v_r := public.crear_pedido(v_lineas, v_envio, 'tarjeta', '4242424242424242');
  select id into v_reciente from public.pedidos where codigo = v_r ->> 'codigo';

  if has_function_privilege('anon', 'public.avanzar_pedidos()', 'execute')
     or has_function_privilege('authenticated', 'public.avanzar_pedidos()', 'execute')
     or has_function_privilege('authenticated', 'public.aplicar_cambio_estado(bigint, text, boolean)', 'execute') then
    raise exception 'PRUEBA 5 · FALLO: la web puede ejecutar funciones internas';
  end if;

  -- Pasados 5 horas, salvo el pedido reciente (4 horas)
  update public.pedidos set estado_cambiado_en = now() - interval '6 hours' where id in (v_pagado, v_contra, v_rechazado);
  update public.pedidos set estado_cambiado_en = now() - interval '4 hours' where id = v_reciente;

  v_n := public.avanzar_pedidos();
  if v_n <> 2 then
    raise exception 'PRUEBA 5 · FALLO: primera pasada avanzó % pedidos (esperado 2)', v_n;
  end if;
  if (select estado from public.pedidos where id = v_pagado) <> 'preparacion'
     or (select estado from public.pedidos where id = v_contra) <> 'preparacion' then
    raise exception 'PRUEBA 5 · FALLO: pagado y contra reembolso debían pasar a preparacion';
  end if;
  if (select estado from public.pedidos where id = v_rechazado) <> 'incidencia'
     or (select estado from public.pedidos where id = v_reciente) <> 'pagado' then
    raise exception 'PRUEBA 5 · FALLO: se tocó un pedido con incidencia o demasiado reciente';
  end if;
  if public.avanzar_pedidos() <> 0 then
    raise exception 'PRUEBA 5 · FALLO: un pedido avanzó dos pasos seguidos';
  end if;

  update public.pedidos set estado_cambiado_en = now() - interval '5 hours' where id in (v_pagado, v_contra);
  v_n := public.avanzar_pedidos();
  if v_n <> 2 or (select estado from public.pedidos where id = v_pagado) <> 'enviado'
     or (select estado from public.pedidos where id = v_contra) <> 'enviado' then
    raise exception 'PRUEBA 5 · FALLO: segunda pasada incorrecta (avanzados %)', v_n;
  end if;
  select resultado into v_resultado from public.pagos where pedido_id = v_contra;
  if v_resultado <> 'aceptado' then
    raise exception 'PRUEBA 5 · FALLO: el pago contra reembolso enviado sigue %', v_resultado;
  end if;
  if not (select llego_a_enviarse from public.pedidos where id = v_pagado) then
    raise exception 'PRUEBA 5 · FALLO: llego_a_enviarse no se marcó';
  end if;

  select count(*) into v_eventos from public.eventos
  where pedido_id in (v_pagado, v_contra) and tipo = 'order.status_changed'
    and (datos ->> 'automatico')::boolean and datos ? 'de' and datos ? 'a';
  if v_eventos <> 4 then
    raise exception 'PRUEBA 5 · FALLO: eventos automáticos = % (esperados 4)', v_eventos;
  end if;

  update public.pedidos set estado_cambiado_en = now() - interval '9 hours' where id in (v_pagado, v_contra, v_rechazado, v_reciente);
  v_n := public.avanzar_pedidos();
  if v_n <> 1 or (select estado from public.pedidos where id = v_reciente) <> 'preparacion' then
    raise exception 'PRUEBA 5 · FALLO: tercera pasada: avanzados % (esperado 1), el pedido reciente está en %', v_n, (select estado from public.pedidos where id = v_reciente);
  end if;
  raise exception 'PRUEBA 5 · OK: pagado->preparacion->enviado y creado(contra reembolso)->preparacion; incidencia, enviado y pedidos recientes intactos; 4 eventos automáticos';
end $$;


-- @prueba 6 · El cliente cancela su pedido (solo en "creado") y recupera el stock
do $$
declare
  v_c1    uuid := (select id from auth.users where email = 'cliente1@sensotoys-demo.test');
  v_c2    uuid := (select id from auth.users where email = 'cliente2@sensotoys-demo.test');
  v_envio jsonb := '{"nombre":"Prueba","direccion":"Calle Prueba 1","cp":"28001","ciudad":"Madrid","provincia":"Madrid"}';
  v_prod bigint; v_var bigint; v_lineas jsonb; v_r jsonb; v_codigo text; v_pagado text; v_msg text;
begin
  insert into public.productos (categoria_id, nombre, slug, descripcion, material, edad_minima)
    select id, 'Prueba', 'zz-prueba-6', 'x', 'x', 6 from public.categorias limit 1 returning id into v_prod;
  insert into public.variantes (producto_id, sku, color, color_hex, textura, talla, precio, stock)
    values (v_prod, 'ZZ-6', 'Rojo', '#FF0000', 'lisa', 'Única', 25, 20) returning id into v_var;
  v_lineas := jsonb_build_array(jsonb_build_object('variante_id', v_var, 'cantidad', 2));

  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_c1, 'role', 'authenticated')::text, true);
  v_codigo := public.crear_pedido(v_lineas, v_envio, 'contrareembolso') ->> 'codigo';
  v_pagado := public.crear_pedido(v_lineas, v_envio, 'tarjeta', '4242424242424242') ->> 'codigo';
  if (select stock from public.variantes where id = v_var) <> 16 then
    raise exception 'PRUEBA 6 · FALLO: tras dos pedidos de 2 uds. el stock debería ser 16';
  end if;

  -- Otro cliente no puede cancelar un pedido ajeno
  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_c2, 'role', 'authenticated')::text, true);
  begin
    perform public.cancelar_mi_pedido(v_codigo);
    raise exception 'PRUEBA 6 · FALLO: se canceló un pedido ajeno';
  exception when others then
    v_msg := sqlerrm;
    if v_msg like 'PRUEBA 6%' then raise; end if;
  end;
  if v_msg <> 'Pedido no encontrado' then
    raise exception 'PRUEBA 6 · FALLO: mensaje inesperado: %', v_msg;
  end if;

  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_c1, 'role', 'authenticated')::text, true);
  begin
    perform public.cancelar_mi_pedido(v_pagado);          -- ya pagado: no se puede
    raise exception 'PRUEBA 6 · FALLO: se canceló un pedido pagado';
  exception when others then
    if sqlerrm like 'PRUEBA 6%' then raise; end if;
  end;

  perform public.cancelar_mi_pedido(v_codigo);
  if (select estado from public.pedidos where codigo = v_codigo) <> 'cancelado'
     or (select stock from public.variantes where id = v_var) <> 18 then
    raise exception 'PRUEBA 6 · FALLO: el pedido no quedó cancelado o no se devolvió el stock (stock %)',
      (select stock from public.variantes where id = v_var);
  end if;
  begin
    perform public.cancelar_mi_pedido(v_codigo);          -- ya cancelado
    raise exception 'PRUEBA 6 · FALLO: se canceló dos veces';
  exception when others then
    if sqlerrm like 'PRUEBA 6%' then raise; end if;
  end;
  raise exception 'PRUEBA 6 · OK: cancelación solo del dueño y solo en "creado"; stock devuelto (16 -> 18)';
end $$;


-- @prueba 7 · Cancelar un pedido que ya se envió no devuelve el stock
do $$
declare
  v_admin uuid := (select id from auth.users where email = 'admin@sensotoys-demo.test');
  v_c1    uuid := (select id from auth.users where email = 'cliente1@sensotoys-demo.test');
  v_envio jsonb := '{"nombre":"Prueba","direccion":"Calle Prueba 1","cp":"28001","ciudad":"Madrid","provincia":"Madrid"}';
  v_prod bigint; v_var bigint; v_lineas jsonb; v_r jsonb; v_enviado bigint; v_noenviado bigint; v_stock int;
begin
  insert into public.productos (categoria_id, nombre, slug, descripcion, material, edad_minima)
    select id, 'Prueba', 'zz-prueba-7', 'x', 'x', 6 from public.categorias limit 1 returning id into v_prod;
  insert into public.variantes (producto_id, sku, color, color_hex, textura, talla, precio, stock)
    values (v_prod, 'ZZ-7', 'Rojo', '#FF0000', 'lisa', 'Única', 25, 20) returning id into v_var;
  v_lineas := jsonb_build_array(jsonb_build_object('variante_id', v_var, 'cantidad', 2));

  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_c1, 'role', 'authenticated')::text, true);
  v_r := public.crear_pedido(v_lineas, v_envio, 'tarjeta', '4242424242424242');
  select id into v_enviado from public.pedidos where codigo = v_r ->> 'codigo';
  v_r := public.crear_pedido(v_lineas, v_envio, 'tarjeta', '4242424242424242');
  select id into v_noenviado from public.pedidos where codigo = v_r ->> 'codigo';
  -- stock: 20 - 2 - 2 = 16

  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  perform public.cambiar_estado_pedido(v_enviado, 'preparacion');
  perform public.cambiar_estado_pedido(v_enviado, 'enviado');
  perform public.cambiar_estado_pedido(v_enviado, 'incidencia');
  perform public.cambiar_estado_pedido(v_enviado, 'cancelado');
  select stock into v_stock from public.variantes where id = v_var;
  if v_stock <> 16 then
    raise exception 'PRUEBA 7 · FALLO: un pedido enviado y cancelado devolvió stock (stock %)', v_stock;
  end if;

  perform public.cambiar_estado_pedido(v_noenviado, 'incidencia');
  perform public.cambiar_estado_pedido(v_noenviado, 'cancelado');
  select stock into v_stock from public.variantes where id = v_var;
  if v_stock <> 18 then
    raise exception 'PRUEBA 7 · FALLO: un pedido no enviado debía devolver 2 uds. (stock %)', v_stock;
  end if;
  raise exception 'PRUEBA 7 · OK: enviado->incidencia->cancelado no devuelve stock (16); sin enviar sí (18)';
end $$;


-- @prueba 8 · Gestión de incidencias: abierta -> en_curso -> resuelta
do $$
declare
  v_admin uuid := (select id from auth.users where email = 'admin@sensotoys-demo.test');
  v_c1    uuid := (select id from auth.users where email = 'cliente1@sensotoys-demo.test');
  v_id bigint;
begin
  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_c1, 'role', 'authenticated')::text, true);
  v_id := public.crear_incidencia('otro', 'Consulta general sin pedido');
  begin
    perform public.cambiar_estado_incidencia(v_id, 'en_curso');   -- un cliente no puede
    raise exception 'PRUEBA 8 · FALLO: un cliente gestionó una incidencia';
  exception when others then
    if sqlerrm like 'PRUEBA 8%' then raise; end if;
  end;

  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  begin
    perform public.cambiar_estado_incidencia(v_id, 'resuelta');   -- no se puede saltar en_curso
    raise exception 'PRUEBA 8 · FALLO: abierta -> resuelta permitido';
  exception when others then
    if sqlerrm like 'PRUEBA 8%' then raise; end if;
  end;
  perform public.cambiar_estado_incidencia(v_id, 'en_curso');
  perform public.cambiar_estado_incidencia(v_id, 'resuelta');
  begin
    perform public.cambiar_estado_incidencia(v_id, 'abierta');    -- no se reabre
    raise exception 'PRUEBA 8 · FALLO: resuelta -> abierta permitido';
  exception when others then
    if sqlerrm like 'PRUEBA 8%' then raise; end if;
  end;
  raise exception 'PRUEBA 8 · OK: solo admin, y solo abierta -> en_curso -> resuelta (estado final: %)',
    (select estado from public.incidencias where id = v_id);
end $$;


-- @prueba 9 · Configuración de negocio y porcentaje de rechazos
do $$
declare
  v_admin uuid := (select id from auth.users where email = 'admin@sensotoys-demo.test');
  v_c1    uuid := (select id from auth.users where email = 'cliente1@sensotoys-demo.test');
  v_envio jsonb := '{"nombre":"Prueba","direccion":"Calle Prueba 1","cp":"28001","ciudad":"Madrid","provincia":"Madrid"}';
  v_prod bigint; v_var bigint; v_r jsonb; v_ped bigint; v_msg text; v_antes numeric; v_despues numeric; v_cfg jsonb;
begin
  insert into public.productos (categoria_id, nombre, slug, descripcion, material, edad_minima)
    select id, 'Prueba', 'zz-prueba-9', 'x', 'x', 6 from public.categorias limit 1 returning id into v_prod;
  insert into public.variantes (producto_id, sku, color, color_hex, textura, talla, precio, stock)
    values (v_prod, 'ZZ-9', 'Rojo', '#FF0000', 'lisa', 'Única', 10, 50) returning id into v_var;

  v_cfg := public.obtener_configuracion();
  if (v_cfg ->> 'max_por_producto')::numeric <> 3 or (v_cfg ->> 'envio_gratis_desde')::numeric <> 45
     or (v_cfg ->> 'gastos_envio')::numeric <> 3.95 then
    raise exception 'PRUEBA 9 · FALLO: configuración por defecto inesperada: %', v_cfg;
  end if;

  -- crear_pedido obedece a la tabla: máximo 2 y envío de 5 €
  update public.configuracion set valor = 2 where clave = 'max_por_producto';
  update public.configuracion set valor = 5 where clave = 'gastos_envio';
  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_c1, 'role', 'authenticated')::text, true);
  begin
    perform public.crear_pedido(jsonb_build_array(jsonb_build_object('variante_id', v_var, 'cantidad', 3)),
                                v_envio, 'contrareembolso');
    raise exception 'PRUEBA 9 · FALLO: se aceptaron 3 uds. con el máximo en 2';
  exception when others then
    v_msg := sqlerrm;
    if v_msg like 'PRUEBA 9%' then raise; end if;
  end;
  v_r := public.crear_pedido(jsonb_build_array(jsonb_build_object('variante_id', v_var, 'cantidad', 2)),
                             v_envio, 'contrareembolso');
  if (select gastos_envio from public.pedidos where codigo = v_r ->> 'codigo') <> 5 then
    raise exception 'PRUEBA 9 · FALLO: el envío no sale de la configuración';
  end if;

  -- Un pago rechazado cuyo pedido acaba cancelado sigue contando en pct_rechazados
  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  select pct_rechazados into v_antes from public.v_resumen_ventas;
  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_c1, 'role', 'authenticated')::text, true);
  v_r := public.crear_pedido(jsonb_build_array(jsonb_build_object('variante_id', v_var, 'cantidad', 1)),
                             v_envio, 'tarjeta', '1111222233330000');
  select id into v_ped from public.pedidos where codigo = v_r ->> 'codigo';
  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  perform public.cambiar_estado_pedido(v_ped, 'cancelado');
  select pct_rechazados into v_despues from public.v_resumen_ventas;
  if v_despues <= v_antes then
    raise exception 'PRUEBA 9 · FALLO: el rechazo cancelado no cuenta (antes %, después %)', v_antes, v_despues;
  end if;
  raise exception 'PRUEBA 9 · OK: crear_pedido lee la configuración (rechazo: "%"); pct_rechazados %% pasa de % a % al cancelar un rechazo', v_msg, v_antes, v_despues;
end $$;


-- @prueba 10 · Destacados: ediciones limitadas primero y luego los más vendidos
do $$
declare
  v_prod_lim bigint; v_prod_top bigint; v_prod_otro bigint; v_orden bigint[];
  v_admin uuid := (select id from auth.users where email = 'admin@sensotoys-demo.test');
begin
  insert into public.productos (categoria_id, nombre, slug, descripcion, material, edad_minima, es_edicion_limitada, unidades_edicion)
    select id, 'Prueba limitada', 'zz-prueba-10a', 'x', 'x', 6, true, 10 from public.categorias limit 1 returning id into v_prod_lim;
  insert into public.productos (categoria_id, nombre, slug, descripcion, material, edad_minima)
    select id, 'Prueba top', 'zz-prueba-10b', 'x', 'x', 6 from public.categorias limit 1 returning id into v_prod_top;
  insert into public.productos (categoria_id, nombre, slug, descripcion, material, edad_minima)
    select id, 'Prueba otro', 'zz-prueba-10c', 'x', 'x', 6 from public.categorias limit 1 returning id into v_prod_otro;
  insert into public.variantes (producto_id, sku, color, color_hex, textura, talla, precio, stock)
    values (v_prod_lim, 'ZZ-10A', 'Rojo', '#FF0000', 'lisa', 'Única', 10, 5),
           (v_prod_top, 'ZZ-10B', 'Rojo', '#FF0000', 'lisa', 'Única', 10, 5),
           (v_prod_otro, 'ZZ-10C', 'Rojo', '#FF0000', 'lisa', 'Única', 10, 0);   -- sin stock: no sale

  select array_agg(producto_id order by ord) into v_orden
  from (select producto_id, row_number() over () as ord from public.productos_destacados(12)) d
  where producto_id in (v_prod_lim, v_prod_top, v_prod_otro);
  if v_orden is distinct from array[v_prod_lim, v_prod_top] then
    raise exception 'PRUEBA 10 · FALLO: orden de destacados inesperado: %', v_orden;
  end if;
  if has_function_privilege('anon', 'public.productos_destacados(integer)', 'execute') is not true then
    raise exception 'PRUEBA 10 · FALLO: los visitantes no pueden leer los destacados';
  end if;
  raise exception 'PRUEBA 10 · OK: la limitada va antes que el normal, y el producto sin stock no aparece (%)', v_orden;
end $$;
