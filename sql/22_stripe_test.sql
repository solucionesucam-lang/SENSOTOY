-- SENSOTOYS · Integración de Stripe en entorno de pruebas
-- PROPUESTA PENDIENTE DE REVISIÓN.
-- No ejecutar en Supabase #1 sin revisión del responsable.
--
-- Objetivo:
-- Crear pedidos con tarjeta pendientes de pago,
-- conservando el contrato de eventos de integración.

-- ---------------------------------------------------------------------
-- 1. Permitir pagos pendientes de Stripe sin ultimos4.
--
-- REVISAR ANTES DE EJECUTAR:
-- Se espera que la restricción original se llame pagos_check.
-- Confirmar su nombre en Supabase #1.
-- ---------------------------------------------------------------------

begin;

alter table public.pagos
  drop constraint pagos_check;

alter table public.pagos
  add constraint pagos_tarjeta_ultimos4_check
  check (
    metodo <> 'tarjeta'
    or ultimos4 is not null
    or (
      proveedor = 'stripe_test'
      and resultado = 'pendiente'
    )
  );

commit;
