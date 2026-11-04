-- =====================================================================
-- SENSOTOYS · Prototipo académico SIE (sin actividad comercial real)
-- 26_reenvio_y_pruebas.sql — Carga inicial por la integración y
-- pruebas de duplicado y de error (Supabase #1, la TIENDA)
--
-- OJO: se ejecuta en el proyecto de la TIENDA (Supabase #1).
-- Requisitos: sql/19 ejecutado, URL y secreto de n8n en el Vault y el
-- workflow de n8n activo. Abrir antes la URL de n8n en el navegador para
-- despertar Render (se duerme a los 15 min sin uso).
-- Cada apartado se ejecuta por separado.
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1. CARGA INICIAL: reenviar los pedidos que ya existían en la tienda
--    Se reenvía el order.created de cada pedido. El payload se construye
--    en el momento del envío, así que lleva el estado ACTUAL del pedido:
--    no hace falta reenviar sus pagos ni sus cambios de estado.
--    Pasan por el flujo real (n8n → integrar_evento): no se copia nada
--    a mano entre sistemas.
--
--    Va en LOTES DE 10 para no saturar n8n (Render gratis tiene poca
--    memoria). Ejecutar, esperar ~30 s y repetir hasta que devuelva
--    0 filas. Solo coge los que aún no se han reenviado hoy.
-- ---------------------------------------------------------------------
select e.id as evento_id, e.pedido_id, public.enviar_evento_n8n(e.id) as request_id
from public.eventos e
where e.tipo = 'order.created'
  and e.pedido_id is not null
  and not exists (select 1 from public.envios_webhook w
                  where w.evento_id = e.id
                    and w.request_id is not null
                    and w.creado_en >= current_date)
order by e.id
limit 10;

-- Seguimiento: cuántos han respondido bien y cuántos no
select status_code, count(*)
from public.v_envios_webhook
where creado_en >= current_date
group by status_code
order by status_code;


-- ---------------------------------------------------------------------
-- 2. PRUEBA DE DUPLICADO (idempotencia)
--    Reenvía un order.created que ya se integró. n8n lo recibe (200),
--    pero integrar_evento responde "duplicado" y no crea nada:
--    se ve en log_integracion (Supabase #2) con resultado = duplicado.
-- ---------------------------------------------------------------------
select public.enviar_evento_n8n(
  (select max(id) from public.eventos where tipo = 'order.created')
);


-- ---------------------------------------------------------------------
-- 3. PRUEBA DE ERROR (payload incompleto)
--    Envía a n8n un evento sin cliente ni pedido, con el secreto bueno.
--    El nodo "Validar" lo rechaza y queda en log_integracion con
--    resultado = error y el motivo ("falta cliente; falta pedido...").
--    evento_id 999999 no existe en la tienda: es una prueba.
-- ---------------------------------------------------------------------
select net.http_post(
  url     := (select decrypted_secret from vault.decrypted_secrets where name = 'n8n_webhook_url'),
  body    := '{"version": 1, "origen": "prueba-error", "evento_id": 999999, "tipo": "order.created"}'::jsonb,
  headers := jsonb_build_object(
               'Content-Type', 'application/json',
               'x-sensotoys-secret',
               (select decrypted_secret from vault.decrypted_secrets where name = 'n8n_webhook_secret'))
) as request_id;


-- ---------------------------------------------------------------------
-- 4. PRUEBA DE SEGURIDAD (secreto incorrecto)
--    Misma llamada con un secreto falso: n8n debe responder 403 y no
--    ejecutar el flujo. Se comprueba en net._http_response.
-- ---------------------------------------------------------------------
select net.http_post(
  url     := (select decrypted_secret from vault.decrypted_secrets where name = 'n8n_webhook_url'),
  body    := '{"tipo": "order.created", "evento_id": 999998}'::jsonb,
  headers := '{"Content-Type": "application/json", "x-sensotoys-secret": "secreto-falso"}'::jsonb
) as request_id;

-- Respuesta de las dos últimas llamadas directas (esperado: 200 y 403)
select id, status_code, left(content, 120) as respuesta
from net._http_response
order by id desc
limit 2;
