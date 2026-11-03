-- =====================================================================
-- SENSOTOYS · Prototipo académico SIE (sin actividad comercial real)
-- 18_n8n_esquema.sql — Almacenamiento interno de n8n (Supabase #2)
--
-- OJO: se ejecuta en el proyecto del BACK-OFFICE (Supabase #2).
--
-- Qué hace:
--   1. Crea un usuario de base de datos propio para n8n (n8n_svc), en vez
--      de darle el usuario "postgres", que puede con todo.
--   2. Crea el esquema "n8n" (vacío) cuyo dueño es n8n_svc. n8n creará
--      ahí sus tablas internas (workflows, ejecuciones, credenciales...)
--      la primera vez que arranque.
--   3. Comprueba que n8n_svc NO puede leer las tablas del back-office.
--      n8n escribirá en el back-office con OTRA credencial (la clave
--      secreta de la API), configurada dentro de n8n.
--
-- Conexión desde Render (Session pooler, puerto 5432):
--   usuario = n8n_svc.<ref-del-proyecto>   (NO postgres.<ref>)
--   contraseña = la de este rol, NO la "Database password" del proyecto
--
-- CONTRASEÑA: antes de ejecutar, cambia CAMBIAR_EN_EL_PANEL por una
-- contraseña larga SOLO en el editor de Supabase. En el repositorio este
-- fichero se queda con el texto CAMBIAR_EN_EL_PANEL. Nunca hagas commit
-- de la contraseña real.
--
-- HISTORIAL: el rol se creó primero como "n8n_app". Tras cambiarle la
-- contraseña, el pooler de Supabase (Supavisor) seguía rechazando la
-- conexión con "password authentication failed": guarda en caché las
-- credenciales durante un tiempo. Se renombró a "n8n_svc" (ver apartado 4)
-- para que el pooler leyera la contraseña nueva. Lección: no cambiar la
-- contraseña varias veces seguidas y esperar unos minutos tras cambiarla.
-- =====================================================================

-- 1. Usuario propio para n8n
create role n8n_svc with login password 'CAMBIAR_EN_EL_PANEL';

-- postgres necesita pertenecer al rol para poder hacerle dueño del esquema
grant n8n_svc to postgres;

-- 2. Esquema vacío, propiedad de n8n_svc
create schema n8n authorization n8n_svc;

-- Que n8n busque sus tablas en su esquema
alter role n8n_svc set search_path = n8n;


-- 3. Comprobación (debe devolver false en las dos columnas)
select
  has_table_privilege('n8n_svc', 'public.pedidos_bo', 'select') as n8n_lee_pedidos,
  has_table_privilege('n8n_svc', 'public.clientes',   'insert') as n8n_escribe_clientes;


-- ---------------------------------------------------------------------
-- 4. SOLO si ya existía el rol antiguo n8n_app (lo que pasó en nuestro
--    proyecto). NO ejecutar en una instalación nueva: en ese caso basta
--    con los apartados 1-3. El esquema "n8n" sigue siendo del rol, porque
--    PostgreSQL guarda el dueño por id interno, no por nombre.
-- ---------------------------------------------------------------------
-- alter role n8n_app rename to n8n_svc;
-- alter role n8n_svc with password 'CAMBIAR_EN_EL_PANEL';
-- select pg_get_userbyid(nspowner) as dueno from pg_namespace where nspname = 'n8n';  -- debe salir n8n_svc
