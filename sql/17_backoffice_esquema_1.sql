-- =====================================================================
-- SENSOTOYS · Prototipo académico SIE (sin actividad comercial real)
-- 17_backoffice_esquema.sql — Esquema del BACK-OFFICE (Supabase #2)
--
-- OJO: este script se ejecuta en el SEGUNDO proyecto de Supabase
-- (back-office), NO en el de la tienda. Son dos sistemas distintos:
-- otra base de datos, otros usuarios, otras claves.
--
-- Ejecutar UNA vez en: Supabase #2 > SQL Editor > New query > Run
--
-- Por qué no hay claves foráneas hacia la tienda: la tienda vive en otra
-- base de datos y PostgreSQL no puede relacionar tablas de dos bases
-- distintas. Guardamos el identificador de la tienda como dato
-- (codigo_tienda, pedido_tienda_id...) y los UNIQUE sobre esos campos
-- son los que dan la idempotencia: el mismo pedido no puede entrar dos veces.
-- =====================================================================


-- ---------------------------------------------------------------------
-- 0. Función auxiliar: actualiza "actualizado_en" en cada UPDATE
-- ---------------------------------------------------------------------
create or replace function public.tocar_actualizado_en()
returns trigger
language plpgsql set search_path = ''
as $$
begin
  new.actualizado_en := now();
  return new;
end;
$$;


-- ---------------------------------------------------------------------
-- 1. CLIENTES — copia del cliente de la tienda
-- ---------------------------------------------------------------------
create table public.clientes (
  id                bigint generated always as identity primary key,
  usuario_tienda_id uuid not null unique,      -- perfiles.id de la tienda (sin FK: otra BD)
  email             text not null unique check (email ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
  nombre            text not null,
  telegram_chat_id  text,                       -- chat de PRUEBA; texto porque puede ser negativo/largo
  creado_en         timestamptz not null default now(),
  actualizado_en    timestamptz not null default now()
);

create trigger clientes_actualizado_en
  before update on public.clientes
  for each row execute function public.tocar_actualizado_en();


-- ---------------------------------------------------------------------
-- 2. PEDIDOS_BO — el pedido tal como lo ve el back-office
-- ---------------------------------------------------------------------
create table public.pedidos_bo (
  id               bigint generated always as identity primary key,
  codigo_tienda    text   not null unique,      -- PED-2026-000001 → IDEMPOTENCIA
  pedido_tienda_id bigint not null unique,      -- pedidos.id de la tienda (los eventos traen este)
  cliente_id       bigint not null references public.clientes(id),
  importe          numeric(10,2) not null check (importe >= 0),
  estado           text not null
                   check (estado in ('creado', 'pagado', 'preparacion',
                                     'enviado', 'cancelado', 'incidencia')),
  fecha_pedido     timestamptz not null,        -- cuándo se hizo en la tienda
  recibido_en      timestamptz not null default now(),  -- cuándo llegó al back-office
  actualizado_en   timestamptz not null default now()
);

create index on public.pedidos_bo (cliente_id);
create index on public.pedidos_bo (estado);
create index on public.pedidos_bo (fecha_pedido);

create trigger pedidos_bo_actualizado_en
  before update on public.pedidos_bo
  for each row execute function public.tocar_actualizado_en();


-- ---------------------------------------------------------------------
-- 3. LINEAS_BO — líneas de cada pedido
-- ---------------------------------------------------------------------
create table public.lineas_bo (
  id                   bigint generated always as identity primary key,
  pedido_id            bigint not null references public.pedidos_bo(id) on delete cascade,
  sku                  text not null,
  nombre_producto      text not null,
  descripcion_variante text,
  precio_unitario      numeric(10,2) not null check (precio_unitario > 0),
  cantidad             int not null check (cantidad > 0),
  importe              numeric(10,2) generated always as (precio_unitario * cantidad) stored,
  unique (pedido_id, sku)                       -- la misma línea no se duplica
);

create index on public.lineas_bo (pedido_id);


-- ---------------------------------------------------------------------
-- 4. TICKETS — incidencias postventa
-- ---------------------------------------------------------------------
create table public.tickets (
  id                   bigint generated always as identity primary key,
  incidencia_tienda_id bigint not null unique,  -- incidencias.id de la tienda → IDEMPOTENCIA
  cliente_id           bigint not null references public.clientes(id),
  pedido_id            bigint references public.pedidos_bo(id),   -- puede no tener pedido
  motivo               text not null
                       check (motivo in ('pago_rechazado', 'retraso_envio',
                                         'producto_defectuoso', 'otro')),
  mensaje              text not null,
  prioridad            text check (prioridad in ('baja', 'media', 'alta')),
  estado               text not null default 'abierta'
                       check (estado in ('abierta', 'en_curso', 'resuelta')),
  abierto_en           timestamptz not null,    -- fecha de la incidencia en la tienda
  resuelto_en          timestamptz,
  actualizado_en       timestamptz not null default now(),
  -- resuelta  <=> tiene fecha de resolución (si no, el tiempo medio sale mal)
  check ((estado = 'resuelta') = (resuelto_en is not null)),
  check (resuelto_en is null or resuelto_en >= abierto_en)
);

create index on public.tickets (cliente_id);
create index on public.tickets (estado);

create trigger tickets_actualizado_en
  before update on public.tickets
  for each row execute function public.tocar_actualizado_en();


-- ---------------------------------------------------------------------
-- 5. LOG_INTEGRACION — una fila por cada ejecución del flujo (trazabilidad)
-- evento_id NO es unique a propósito: si un evento falla y se reintenta,
-- queremos ver los dos intentos.
-- ---------------------------------------------------------------------
create table public.log_integracion (
  id           bigint generated always as identity primary key,
  evento_id    bigint,                          -- eventos.id de la tienda (null si el payload ni lo trae)
  tipo_evento  text,                            -- order.created, support.requested...
  resultado    text not null check (resultado in ('ok', 'error', 'duplicado')),
  mensaje      text,                            -- qué pasó / por qué falló
  payload      jsonb not null default '{}',     -- lo que llegó tal cual
  ejecucion_n8n text,                           -- id de ejecución de n8n (para buscarla)
  creado_en    timestamptz not null default now()
);

create index on public.log_integracion (evento_id);
create index on public.log_integracion (resultado, creado_en);


-- ---------------------------------------------------------------------
-- 6. APROBACIONES_AGENTE — salida estructurada del agente + decisión humana
-- ---------------------------------------------------------------------
create table public.aprobaciones_agente (
  id                bigint generated always as identity primary key,
  ticket_id         bigint not null references public.tickets(id) on delete cascade,
  tipo_caso         text not null,              -- p. ej. retraso_envio, defecto...
  datos_consultados jsonb not null default '{}',-- lo que el agente leyó con sus herramientas
  accion_propuesta  text not null,
  mensaje_cliente   text,                       -- texto que se enviaría por Telegram
  justificacion     text not null,
  prioridad         text not null check (prioridad in ('baja', 'media', 'alta')),
  confianza         numeric(3,2) check (confianza between 0 and 1),
  riesgos           text,
  estado            text not null default 'pendiente_revision'
                    check (estado in ('aprobado', 'pendiente_revision',
                                      'rechazado', 'simulado')),
  revisor           text,                       -- quién aprobó/rechazó (cuenta de prueba)
  decidido_en       timestamptz,
  creado_en         timestamptz not null default now(),
  -- Si un humano decidió, tiene que constar quién y cuándo
  check (estado not in ('aprobado', 'rechazado')
         or (revisor is not null and decidido_en is not null))
);

create index on public.aprobaciones_agente (ticket_id);
create index on public.aprobaciones_agente (estado);


-- ---------------------------------------------------------------------
-- 7. BLOQUEO INICIAL DE SEGURIDAD (igual que en la tienda, sql/01)
-- RLS activado y sin políticas = la clave pública no ve nada.
-- n8n usará la clave secreta (service_role), que se salta RLS.
-- Las políticas de solo lectura para el back-office van en el paso 5.
-- ---------------------------------------------------------------------
alter table public.clientes            enable row level security;
alter table public.pedidos_bo          enable row level security;
alter table public.lineas_bo           enable row level security;
alter table public.tickets             enable row level security;
alter table public.log_integracion     enable row level security;
alter table public.aprobaciones_agente enable row level security;
