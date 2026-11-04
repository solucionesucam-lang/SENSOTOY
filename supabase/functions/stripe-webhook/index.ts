import Stripe from "npm:stripe@18";
import { createClient } from "npm:@supabase/supabase-js@2";

// BORRADOR PENDIENTE DE REVISIÓN Y PRUEBAS.
//
// Requiere:
//   · SQL 28: confirmar_pago_stripe().
//   · SQL 29: registrar_reembolso_stripe(), pendiente de preparar.
//
// No desplegar hasta tener ambas funciones SQL revisadas.
//
// El webhook no utiliza la sesión del navegador.
// Verifica la firma de Stripe sobre el cuerpo original.

function responder(datos: unknown, estado = 200) {
  return new Response(JSON.stringify(datos), {
    status: estado,
    headers: {
      "Content-Type": "application/json",
      "Cache-Control": "no-store",
    },
  });
}

function comprobar(
  condicion: unknown,
  mensaje: string,
): asserts condicion {
  if (!condicion) {
    throw new Error(mensaje);
  }
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") {
    return responder({ error: "Método no permitido." }, 405);
  }

  const claveStripe = Deno.env.get("STRIPE_SECRET_KEY");
  const secretoFirma = Deno.env.get("STRIPE_WEBHOOK_SECRET");
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const claveServidor = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

  if (
    !claveStripe?.startsWith("sk_test_") ||
    !secretoFirma?.startsWith("whsec_") ||
    !supabaseUrl ||
    !claveServidor
  ) {
    console.error("Falta configuración del webhook.");

    return responder(
      { error: "Webhook no configurado." },
      500,
    );
  }

  const firma = req.headers.get("stripe-signature");

  if (!firma) {
    return responder(
      { error: "Falta la firma de Stripe." },
      400,
    );
  }

  const stripe = new Stripe(claveStripe, {
    httpClient: Stripe.createFetchHttpClient(),
    maxNetworkRetries: 2,
    timeout: 10000,
  });

  const cryptoProvider = Stripe.createSubtleCryptoProvider();

  let evento: Stripe.Event;

  try {
    // No utilizar req.json() antes de verificar la firma.
    const cuerpoOriginal = await req.text();

    evento = await stripe.webhooks.constructEventAsync(
      cuerpoOriginal,
      firma,
      secretoFirma,
      undefined,
      cryptoProvider,
    );
  } catch {
    console.warn("Firma de webhook no válida.");

    return responder(
      { error: "Firma no válida." },
      400,
    );
  }

  if (evento.livemode !== false) {
    return responder(
      { error: "Solo se admiten eventos de pruebas." },
      400,
    );
  }

  if (evento.type !== "checkout.session.completed") {
    return responder({
      recibido: true,
      ignorado: true,
    });
  }

  const admin = createClient(
    supabaseUrl,
    claveServidor,
    {
      auth: {
        persistSession: false,
        autoRefreshToken: false,
      },
    },
  );

  try {
    const avisoSesion =
      evento.data.object as Stripe.Checkout.Session;

    comprobar(
      avisoSesion.id.startsWith("cs_test_"),
      "La sesión no corresponde a pruebas.",
    );

    // Recuperamos la sesión directamente de Stripe.
    const sesion = await stripe.checkout.sessions.retrieve(
      avisoSesion.id,
      {
        expand: ["payment_intent"],
      },
    );

    const pedidoId = sesion.metadata?.pedido_id;
    const pagoId = sesion.metadata?.pago_id;

    // Esta cuenta podría tener otras integraciones.
    // Ignoramos sesiones que no llevan ninguna de nuestras marcas.
    if (!pedidoId && !pagoId) {
      return responder({
        recibido: true,
        ignorado: true,
      });
    }

    comprobar(
      typeof pedidoId === "string" &&
        /^[1-9][0-9]*$/.test(pedidoId) &&
        typeof pagoId === "string" &&
        /^[1-9][0-9]*$/.test(pagoId),
      "Faltan identificadores válidos del pedido o del pago.",
    );

    comprobar(
      sesion.livemode === false &&
        sesion.mode === "payment" &&
        sesion.status === "complete" &&
        sesion.payment_status === "paid" &&
        sesion.currency === "eur" &&
        sesion.client_reference_id === pedidoId,
      "La sesión no cumple las condiciones del pago.",
    );

    comprobar(
      sesion.payment_method_types.length === 1 &&
        sesion.payment_method_types[0] === "card",
      "El método de pago no corresponde al flujo de tarjeta.",
    );

    const importe = sesion.amount_total;

    comprobar(
      typeof importe === "number" &&
        Number.isSafeInteger(importe) &&
        importe > 0,
      "El importe de Stripe no es válido.",
    );

    const intent = sesion.payment_intent;

    comprobar(
      intent &&
        typeof intent !== "string",
      "No se pudo recuperar el PaymentIntent.",
    );

    comprobar(
      intent.livemode === false &&
        intent.status === "succeeded" &&
        intent.currency === "eur" &&
        intent.amount === importe &&
        intent.amount_received === importe &&
        intent.metadata.pedido_id === pedidoId &&
        intent.metadata.pago_id === pagoId,
      "El PaymentIntent no coincide con el pedido.",
    );

    // La función SQL bloquea el pedido, valida sus importes
    // y confirma estado + evento en una sola transacción.
    const { data: resultado, error: errorConfirmacion } =
      await admin.rpc("confirmar_pago_stripe", {
        p_pedido_id: pedidoId,
        p_pago_id: pagoId,
        p_session_id: sesion.id,
        p_payment_intent: intent.id,
        p_evento_id: evento.id,
        p_importe_centimos: importe,
        p_moneda: sesion.currency,
      });

    if (errorConfirmacion) {
      console.error("Error al confirmar el pago:", {
        evento: evento.id,
        codigo: errorConfirmacion.code,
      });

      throw new Error(
        "No se pudo registrar la confirmación del pago.",
      );
    }

    comprobar(
      resultado &&
        typeof resultado.accion === "string",
      "La confirmación no devolvió una acción válida.",
    );

    if (
      resultado.accion === "confirmado" ||
      resultado.accion === "ya_procesado"
    ) {
      return responder({
        recibido: true,
        accion: resultado.accion,
      });
    }

    comprobar(
      resultado.accion === "reembolsar",
      "La confirmación devolvió una acción desconocida.",
    );

    // El pedido ya estaba cancelado.
    // Buscamos primero un reembolso de esta integración para
    // recuperar operaciones cuya respuesta pudiera haberse perdido.
    let reembolso: Stripe.Refund | null = null;

    await stripe.refunds.list({
      payment_intent: intent.id,
      limit: 100,
    }).autoPagingEach((existente) => {
      if (
        existente.metadata?.sensotoys_pago_id === pagoId &&
        existente.metadata?.sensotoys_session_id === sesion.id
      ) {
        reembolso = existente;
        return false;
      }

      return true;
    });

    if (!reembolso) {
      reembolso = await stripe.refunds.create(
        {
          payment_intent: intent.id,
          amount: importe,
          metadata: {
            sensotoys_pedido_id: pedidoId,
            sensotoys_pago_id: pagoId,
            sensotoys_session_id: sesion.id,
            motivo: "pedido_cancelado_antes_de_confirmar",
          },
        },
        {
          idempotencyKey:
            `sensotoys-refund-v1-${intent.id}`,
        },
      );
    }

    // Recuperamos el estado actual del reembolso.
    const devolucion = await stripe.refunds.retrieve(
      reembolso.id,
    );

    const intentReembolso =
      typeof devolucion.payment_intent === "string"
        ? devolucion.payment_intent
        : devolucion.payment_intent?.id;

    comprobar(
      intentReembolso === intent.id &&
        devolucion.amount === importe &&
        devolucion.currency === "eur",
      "El reembolso no coincide con el pago.",
    );

    // No damos el caso por terminado si el reembolso
    // sigue pendiente, ha fallado o requiere intervención.
    comprobar(
      devolucion.status === "succeeded",
      "El reembolso todavía no consta como completado.",
    );

    // Esta función se añadirá en el SQL 29.
    // Debe registrar la devolución sin reabrir el pedido
    // y sin volver a modificar el stock.
    const { error: errorRegistro } = await admin.rpc(
      "registrar_reembolso_stripe",
      {
        p_pedido_id: pedidoId,
        p_pago_id: pagoId,
        p_session_id: sesion.id,
        p_payment_intent: intent.id,
        p_reembolso_id: devolucion.id,
        p_evento_id: evento.id,
        p_importe_centimos: importe,
        p_moneda: devolucion.currency,
      },
    );

    if (errorRegistro) {
      console.error("Error al registrar el reembolso:", {
        evento: evento.id,
        codigo: errorRegistro.code,
        reembolso: devolucion.id,
      });

      throw new Error(
        "El reembolso se realizó, pero falta registrarlo.",
      );
    }

    return responder({
      recibido: true,
      accion: "reembolsado",
    });
  } catch (error) {
    console.error("Webhook pendiente de resolver:", {
      evento: evento.id,
      mensaje: error instanceof Error
        ? error.message
        : "Error desconocido",
    });

    // No respondemos 200 cuando falta completar o registrar
    // una operación. El fallo debe quedar visible en Stripe.
    return responder(
      { error: "No se pudo completar el procesamiento del evento." },
      500,
    );
  }
});
