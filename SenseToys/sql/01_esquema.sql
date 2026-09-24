-- =====================================================================
-- SENSOTOYS · Prototipo académico SIE (sin actividad comercial real)
-- 01_esquema.sql — Tablas, relaciones y restricciones
-- Base de datos: Supabase (PostgreSQL)
-- Ejecutar UNA vez en: Supabase > SQL Editor > New query > Run
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1. DATOS MAESTROS: catálogo
-- ---------------------------------------------------------------------

create table categorias (
  id          bigint generated always as identity primary key,
  nombre      text not null unique,
  slug        text not null unique,          -- para la URL: ?categoria=squishies
  descripcion text,
  orden       int  not null default 0        -- orden en el menú
);

create table productos (
  id                  bigint generated always as identity primary key,
  categoria_id        bigint not null references categorias(id),
  nombre              text not null,
  slug                text not null unique,
  descripcion         text not null,
  material            text not null,
  edad_minima         int  not null check (edad_minima between 0 and 18),
  es_edicion_limitada boolean not null default false,
  unidades_edicion    int,                   -- tirada total (solo ediciones limitadas)
  activo              boolean not null default true,
  creado_en           timestamptz not null default now(),
  -- Si es edición limitada, tiene que tener tirada; si no, no.
  check ( (es_edicion_limitada and unidades_edicion > 0)
       or (not es_edicion_limitada and unidades_edicion is null) )
);

-- Cada combinación de color + talla es una variante con su precio y su stock.
create table variantes (
  id          bigint generated always as identity primary key,
  producto_id bigint not null references productos(id) on delete cascade,
  sku         text not null unique,          -- código interno de almacén
  color       text not null,
  color_hex   text not null check (color_hex ~ '^#[0-9A-Fa-f]{6}$'),
  textura     text not null,
  talla       text not null check (talla in ('S', 'M', 'L', 'Única')),
  medida_cm   int  check (medida_cm > 0),
  precio      numeric(10,2) not null check (precio > 0),  -- IVA incluido
  stock       int  not null check (stock >= 0),
  activo      boolean not null default true,
  unique (producto_id, color, talla)
);

create table cupones (
  codigo         text primary key check (codigo = upper(codigo)),
  descripcion    text not null,
  tipo           text not null check (tipo in ('porcentaje', 'importe')),
  valor          numeric(10,2) not null check (valor > 0),
  importe_minimo numeric(10,2) not null default 0,
  valido_hasta   date,
  activo         boolean not null default true,
  check (tipo <> 'porcentaje' or valor <= 100)
);


-- ---------------------------------------------------------------------
-- 2. USUARIOS
-- Supabase guarda el email y la contraseña (cifrada) en auth.users.
-- Aquí guardamos solo lo que necesita la tienda: nombre y rol.
-- ---------------------------------------------------------------------

create table perfiles (
  id        uuid primary key references auth.users(id) on delete cascade,
  email     text not null unique,
  nombre    text not null,
  rol       text not null default 'cliente' check (rol in ('cliente', 'admin')),
  creado_en timestamptz not null default now()
);

-- Cuando alguien se registra, se crea su perfil automáticamente.
create function crear_perfil_nuevo_usuario()
returns trigger
language plpgsql
security definer set search_path = ''
as $$
begin
  insert into public.perfiles (id, email, nombre)
  values (new.id, new.email,
          coalesce(new.raw_user_meta_data ->> 'nombre', new.email));
  return new;
end;
$$;

create trigger al_crear_usuario
  after insert on auth.users
  for each row execute function crear_perfil_nuevo_usuario();


-- ---------------------------------------------------------------------
-- 3. DATOS TRANSACCIONALES: pedidos, líneas y pagos
-- ---------------------------------------------------------------------

-- Genera el identificador único visible: PED-2026-000001
create sequence pedidos_codigo_seq;

create table pedidos (
  id              bigint generated always as identity primary key,
  codigo          text not null unique
                  default 'PED-' || to_char(now(), 'YYYY') || '-'
                          || lpad(nextval('pedidos_codigo_seq')::text, 6, '0'),
  usuario_id      uuid not null references perfiles(id),
  estado          text not null default 'creado'
                  check (estado in ('creado', 'pagado', 'preparacion',
                                    'enviado', 'cancelado', 'incidencia')),
  -- Importes (todos con 2 decimales). base_imponible, iva y total no se
  -- escriben nunca: la base de datos los calcula sola a partir del resto,
  -- así que no pueden llegar a estar mal.
  subtotal        numeric(10,2) not null check (subtotal >= 0),  -- suma de líneas, IVA incluido
  descuento       numeric(10,2) not null default 0 check (descuento >= 0 and descuento <= subtotal),
  gastos_envio    numeric(10,2) not null check (gastos_envio >= 0),
  base_imponible  numeric(10,2) generated always as (round((subtotal - descuento) / 1.21, 2)) stored,
  iva             numeric(10,2) generated always as ((subtotal - descuento) - round((subtotal - descuento) / 1.21, 2)) stored,
  total           numeric(10,2) generated always as (subtotal - descuento + gastos_envio) stored,
  cupon_codigo    text references cupones(codigo),
  -- Dirección de envío copiada en el momento de la compra
  envio_nombre    text not null,
  envio_direccion text not null,
  envio_cp        text not null check (envio_cp ~ '^[0-9]{5}$'),
  envio_ciudad    text not null,
  envio_provincia text not null,
  creado_en       timestamptz not null default now()
);

create table lineas_pedido (
  id                   bigint generated always as identity primary key,
  pedido_id            bigint not null references pedidos(id) on delete cascade,
  variante_id          bigint not null references variantes(id),
  -- Copia de los datos en el momento de la compra (si luego cambia el
  -- precio o el nombre del producto, el pedido antiguo no cambia)
  nombre_producto      text not null,
  descripcion_variante text not null,
  precio_unitario      numeric(10,2) not null check (precio_unitario > 0),
  cantidad             int not null check (cantidad between 1 and 3),
  importe              numeric(10,2) not null,
  check (importe = precio_unitario * cantidad),
  unique (pedido_id, variante_id)
);

-- Preparada para las dos opciones de pago: simulado o Stripe en modo test.
create table pagos (
  id                 bigint generated always as identity primary key,
  pedido_id          bigint not null references pedidos(id) on delete cascade,
  proveedor          text not null check (proveedor in ('simulado', 'stripe_test')),
  metodo             text not null check (metodo in ('tarjeta', 'contrareembolso')),
  importe            numeric(10,2) not null check (importe > 0),
  resultado          text not null check (resultado in ('pendiente', 'aceptado', 'rechazado')),
  ultimos4           char(4) check (ultimos4 ~ '^[0-9]{4}$'),  -- NUNCA la tarjeta completa
  referencia_externa text,              -- p. ej. id de sesión de Stripe (si se usa)
  creado_en          timestamptz not null default now(),
  check (metodo <> 'tarjeta' or ultimos4 is not null)
);


-- ---------------------------------------------------------------------
-- 4. POSTVENTA Y EVENTOS
-- ---------------------------------------------------------------------

create table incidencias (
  id         bigint generated always as identity primary key,
  usuario_id uuid not null references perfiles(id),
  pedido_id  bigint references pedidos(id),     -- puede ser una consulta sin pedido
  motivo     text not null check (motivo in ('pago_rechazado', 'retraso_envio',
                                             'producto_defectuoso', 'otro')),
  mensaje    text not null check (length(mensaje) between 10 and 1000),
  estado     text not null default 'abierta'
             check (estado in ('abierta', 'en_curso', 'resuelta')),
  creado_en  timestamptz not null default now()
);

-- Registro de eventos de negocio (lo consumirá la Tarea 2).
create table eventos (
  id         bigint generated always as identity primary key,
  tipo       text not null check (tipo in ('product.viewed', 'cart.item_added',
                                           'checkout.started', 'order.created',
                                           'payment.simulated', 'support.requested')),
  usuario_id uuid references perfiles(id) on delete set null,  -- null = visitante anónimo
  sesion_id  text,              -- identifica la visita aunque no haya sesión iniciada
  pedido_id  bigint references pedidos(id) on delete set null,
  datos      jsonb not null default '{}',  -- detalle flexible de cada evento
  creado_en  timestamptz not null default now()
);


-- ---------------------------------------------------------------------
-- 5. ÍNDICES (búsquedas frecuentes)
-- ---------------------------------------------------------------------

create index on productos (categoria_id);
create index on variantes (producto_id);
create index on pedidos (usuario_id);
create index on pedidos (estado);
create index on lineas_pedido (pedido_id);
create index on pagos (pedido_id);
create index on eventos (tipo, creado_en);


-- ---------------------------------------------------------------------
-- 6. BLOQUEO INICIAL DE SEGURIDAD
-- La clave anónima de Supabase es pública. Sin esto, cualquiera podría
-- leer y modificar las tablas. Con RLS activado y sin políticas, la web
-- no puede acceder todavía: las políticas se añadirán en el siguiente paso.
-- ---------------------------------------------------------------------

alter table categorias    enable row level security;
alter table productos     enable row level security;
alter table variantes     enable row level security;
alter table cupones       enable row level security;
alter table perfiles      enable row level security;
alter table pedidos       enable row level security;
alter table lineas_pedido enable row level security;
alter table pagos         enable row level security;
alter table incidencias   enable row level security;
alter table eventos       enable row level security;
