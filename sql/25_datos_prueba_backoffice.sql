-- =====================================================================
-- SENSOTOYS · Prototipo académico SIE (sin actividad comercial real)
-- 25_datos_prueba_backoffice.sql — Preparar el back-office para las
-- pruebas y la demo (Supabase #2)
--
-- OJO: se ejecuta en el proyecto del BACK-OFFICE (Supabase #2).
-- NO es un script para ejecutar entero de una vez: cada apartado se
-- ejecuta por separado y en el orden del guion:
--
--   1. VACIADO .......... antes de la demo → captura "back-office ANTES"
--   (en Supabase #1: sql/26 reenvía los pedidos por la integración)
--   2. TELEGRAM ......... cuando el cliente de prueba ya exista aquí
--   3. COMPROBACIONES ... captura "back-office DESPUÉS"
--
-- Aquí NO se inventa ningún pedido: todos los datos del back-office
-- entran por la integración real (tienda → trigger → n8n →
-- integrar_evento). Así las métricas proceden de datos del sistema.
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1. VACIADO (irreversible: borra TODO el back-office)
--    Deja las tablas vacías y los id empezando otra vez en 1.
--    Si se ejecuta por error en la tienda (Supabase #1), falla porque
--    allí no existen estas tablas: no borra nada de la tienda.
-- ---------------------------------------------------------------------
truncate public.aprobaciones_agente,
         public.tickets,
         public.lineas_bo,
         public.pedidos_bo,
         public.clientes,
         public.log_integracion
  restart identity;

-- Comprobación: todo a 0
select (select count(*) from public.clientes)            as clientes,
       (select count(*) from public.pedidos_bo)          as pedidos,
       (select count(*) from public.tickets)             as tickets,
       (select count(*) from public.log_integracion)     as log,
       (select count(*) from public.aprobaciones_agente) as aprobaciones;


-- ---------------------------------------------------------------------
-- 2. TELEGRAM DEL CLIENTE DE PRUEBA
--    El cliente se crea solo cuando llega su primer pedido por la
--    integración; ejecutar esto DESPUÉS del reenvío (sql/26).
--    Sustituir los dos valores SOLO en el editor de Supabase; en el
--    repositorio se quedan con CAMBIAR_... (el chat_id identifica una
--    cuenta de Telegram: no se sube).
-- ---------------------------------------------------------------------
update public.clientes
   set telegram_chat_id = 'CAMBIAR_CHAT_ID'
 where email = 'CAMBIAR_EMAIL_CLIENTE_PRUEBA'
returning id, email, nombre, telegram_chat_id;
-- Si devuelve 0 filas: ese cliente aún no ha llegado al back-office
-- (haz antes una compra con esa cuenta o reenvía uno de sus pedidos).


-- ---------------------------------------------------------------------
-- 3. COMPROBACIONES (para la captura "DESPUÉS")
-- ---------------------------------------------------------------------
select * from public.v_metricas_resumen;
select * from public.v_pedidos_por_dia order by dia;
select * from public.v_integraciones_por_resultado order by orden;

-- Últimas ejecuciones registradas (trazabilidad)
select id, evento_id, tipo_evento, resultado, mensaje, ejecucion_n8n, creado_en
from public.log_integracion
order by id desc
limit 15;
