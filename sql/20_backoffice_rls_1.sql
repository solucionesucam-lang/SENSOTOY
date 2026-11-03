-- =====================================================================
-- SENSOTOYS · Prototipo académico SIE (sin actividad comercial real)
-- 20_backoffice_rls.sql — Seguridad del BACK-OFFICE (Supabase #2)
--
-- OJO: se ejecuta en el proyecto del BACK-OFFICE (Supabase #2).
-- Ejecutar DESPUÉS de 17. Se puede repetir sin problema.
--
-- Quién puede hacer qué:
--   · anon (clave pública sin iniciar sesión) ...... nada
--   · authenticated (cuenta de prueba del back-office,
--     app Vue con sesión iniciada) ................. solo LEER
--   · n8n (clave secreta / service_role) ........... leer y escribir
--     (service_role se salta RLS: por eso esa clave SOLO vive en las
--     credenciales de n8n, nunca en la app Vue ni en el repositorio)
--
-- Dos capas:
--   1. Privilegios (GRANT/REVOKE): anon y authenticated no tienen
--      permiso de escribir aunque alguien cree una política por error.
--   2. RLS: authenticated solo ve filas mediante políticas de SELECT.
--
-- Requisito en el panel: Authentication > Sign In / Providers >
-- "Allow new users to sign up" DESACTIVADO. Así "authenticated" son solo
-- las cuentas creadas a mano por el grupo.
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1. Privilegios: quitar todo y dar solo lectura a authenticated
-- ---------------------------------------------------------------------
revoke all on public.clientes, public.pedidos_bo, public.lineas_bo,
              public.tickets, public.log_integracion, public.aprobaciones_agente
  from anon, authenticated;

grant select on public.clientes, public.pedidos_bo, public.lineas_bo,
                public.tickets, public.log_integracion, public.aprobaciones_agente
  to authenticated;

-- Las funciones de la base tampoco se pueden llamar desde la API
revoke execute on function public.tocar_actualizado_en() from public, anon, authenticated;


-- ---------------------------------------------------------------------
-- 2. RLS: políticas de solo lectura
-- (RLS ya está activado desde sql/17; se repite por si acaso)
-- ---------------------------------------------------------------------
alter table public.clientes            enable row level security;
alter table public.pedidos_bo          enable row level security;
alter table public.lineas_bo           enable row level security;
alter table public.tickets             enable row level security;
alter table public.log_integracion     enable row level security;
alter table public.aprobaciones_agente enable row level security;

drop policy if exists "backoffice lee clientes"     on public.clientes;
drop policy if exists "backoffice lee pedidos"      on public.pedidos_bo;
drop policy if exists "backoffice lee lineas"       on public.lineas_bo;
drop policy if exists "backoffice lee tickets"      on public.tickets;
drop policy if exists "backoffice lee log"          on public.log_integracion;
drop policy if exists "backoffice lee aprobaciones" on public.aprobaciones_agente;

create policy "backoffice lee clientes"     on public.clientes            for select to authenticated using (true);
create policy "backoffice lee pedidos"      on public.pedidos_bo          for select to authenticated using (true);
create policy "backoffice lee lineas"       on public.lineas_bo           for select to authenticated using (true);
create policy "backoffice lee tickets"      on public.tickets             for select to authenticated using (true);
create policy "backoffice lee log"          on public.log_integracion     for select to authenticated using (true);
create policy "backoffice lee aprobaciones" on public.aprobaciones_agente for select to authenticated using (true);

-- No hay políticas de INSERT/UPDATE/DELETE: nadie con la clave pública
-- puede escribir. Solo n8n, con la clave secreta.
