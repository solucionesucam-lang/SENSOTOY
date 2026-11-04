import { createClient } from "npm:@supabase/supabase-js@2";
import { corsHeaders } from "npm:@supabase/supabase-js@2/cors";

class ErrorPublico extends Error {
  constructor(
    mensaje: string,
    public estado = 400,
  ) {
    super(mensaje);
  }
}

function responder(datos: unknown, estado = 200) {
  return new Response(JSON.stringify(datos), {
    status: estado,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json",
      "Cache-Control": "no-store",
    },
  });
}

function exigir(
  condicion: unknown,
  mensaje: string,
  estado = 400,
): asserts condicion {
  if (!condicion) {
    throw new ErrorPublico(mensaje, estado);
  }
}

// Los importes de la base de datos tienen dos decimales.
function centimos(valor: unknown): number {
  const numero = Number(valor);
  const importe = Math.round(numero * 100);

  exigir(
    Number.isFinite(numero) &&
      Number.isSafeInteger(importe) &&
      importe > 0,
    "El importe del pedido no es válido.",
    409,
  );

  return importe;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return responder({ error: "Método no permitido." }, 405);
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const claveAnonima = Deno.env.get("SUPABASE_ANON_KEY");
    const claveServidor = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const claveStripe = Deno.env.get("STRIPE_SECRET_KEY");
    const direccionTienda = Deno.env.get("SITE_URL");

    exigir(
      supabaseUrl &&
        claveAnonima &&
        claveServidor &&
        direccionTienda,
      "Falta configuración de la función de pago.",
      500,
    );

    exigir(
      claveStripe?.startsWith("sk_test_"),
      "Falta una clave secreta de pruebas de Stripe válida.",
      500,
    );

    const base = new URL(direccionTienda);

    exigir(
      base.protocol === "https:" &&
        !base.username &&
        !base.password &&
        !base.search &&
        !base.hash &&
        base.pathname.endsWith("/"),
      "La dirección de la tienda no está bien configurada.",
      500,
    );

    const autorizacion = req.headers.get("Authorization");

    exigir(
      autorizacion?.startsWith("Bearer "),
      "Tienes que iniciar sesión.",
      401,
    );

    const opciones = {
      auth: {
        persistSession: false,
        autoRefreshToken: false,
      },
    };

    const clienteAuth = createClient(
      supabaseUrl,
      claveAnonima,
      opciones,
    );

    const token = autorizacion.slice("Bearer ".length);

    const { data: autenticacion, error: errorAuth } =
      await clienteAuth.auth.getUser(token);

    exigir(
      !errorAuth && autenticacion.user,
      "La sesión no es válida. Vuelve a iniciar sesión.",
      401,
    );

    let cuerpo;

    try {
      cuerpo = await req.json();
    } catch {
      throw new ErrorPublico(
        "La solicitud no contiene un JSON válido.",
      );
    }

    const codigo = cuerpo?.codigo_pedido;

    exigir(
      typeof codigo === "string" &&
        codigo.trim().length > 0 &&
        codigo.length <= 100,
      "Falta un código de pedido válido.",
    );

    // Este cliente privilegiado solo existe en el servidor.
    // El pedido se busca comprobando expresamente su propietario.
    const admin = createClient(
      supabaseUrl,
      claveServidor,
      opciones,
    );

    const { data: pedido, error: errorPedido } = await admin
      .from("pedidos")
      .select("id, codigo, usuario_id, estado, total, creado_en")
      .eq("codigo", codigo.trim())
      .eq("usuario_id", autenticacion.user.id)
      .maybeSingle();

    if (errorPedido) {
      throw new ErrorPublico(
        "No se pudo consultar el pedido.",
        500,
      );
    }

    exigir(pedido, "Pedido no encontrado.", 404);

    exigir(
      pedido.estado === "creado",
      "Este pedido ya no está pendiente de pago.",
      409,
    );

    const { data: pago, error: errorPago } = await admin
      .from("pagos")
      .select(
        "id, proveedor, metodo, importe, resultado, referencia_externa",
      )
      .eq("pedido_id", pedido.id)
      .order("id", { ascending: false })
      .limit(1)
      .maybeSingle();

    if (errorPago) {
      throw new ErrorPublico(
        "No se pudo consultar el pago.",
        500,
      );
    }

    exigir(
      pago &&
        pago.proveedor === "stripe_test" &&
        pago.metodo === "tarjeta" &&
        pago.resultado === "pendiente",
      "El pedido no tiene un pago pendiente de Stripe.",
      409,
    );

    const importe = centimos(pedido.total);

    exigir(
      centimos(pago.importe) === importe,
      "El importe del pago no coincide con el pedido.",
      409,
    );

    async function stripe(
      ruta: string,
      parametros?: URLSearchParams,
      idempotencia?: string,
    ) {
      const headers: Record<string, string> = {
        Authorization: `Bearer ${claveStripe}`,
      };

      if (parametros) {
        headers["Content-Type"] =
          "application/x-www-form-urlencoded";
      }

      if (idempotencia) {
        headers["Idempotency-Key"] = idempotencia;
      }

      const respuesta = await fetch(
        `https://api.stripe.com/v1${ruta}`,
        {
          method: parametros ? "POST" : "GET",
          headers,
          body: parametros?.toString(),
          signal: AbortSignal.timeout(15000),
        },
      );

      const datos = await respuesta.json();

      if (!respuesta.ok) {
        console.error("Error de Stripe:", {
          estado: respuesta.status,
          tipo: datos?.error?.type,
          codigo: datos?.error?.code,
        });

        throw new ErrorPublico(
          "No se pudo preparar el pago con Stripe. Si persiste, contacta con la tienda.",
          502,
        );
      }

      return datos;
    }

    let referencia: string | null = pago.referencia_externa;
    let sesion;

    if (referencia?.startsWith("cs_test_")) {
      // Si ya existe una sesión, recuperamos esa misma.
      sesion = await stripe(
        `/checkout/sessions/${encodeURIComponent(referencia)}`,
      );
    } else {
      // Solo iniciamos el pago durante los primeros 20 minutos.
      // La sesión dura unos 35 minutos desde la marca inicial:
      // termina antes de los 60 minutos previstos para cancelar.
      const creado = Date.parse(pedido.creado_en);
      const antiguedad = Date.now() - creado;

      exigir(
        Number.isFinite(creado) &&
          antiguedad >= 0 &&
          antiguedad < 20 * 60 * 1000,
        "El pedido es demasiado antiguo para iniciar el pago. Cancélalo desde tus pedidos antes de volver a comprar.",
        409,
      );

      // Reservamos una marca temporal antes de llamar a Stripe.
      // Los reintentos conservan los mismos parámetros y
      // la misma clave de idempotencia.
      if (!referencia) {
        const marca =
          `stripe_init:${Math.floor(Date.now() / 1000)}`;

        const { data: reserva, error: errorReserva } = await admin
          .from("pagos")
          .update({ referencia_externa: marca })
          .eq("id", pago.id)
          .eq("resultado", "pendiente")
          .is("referencia_externa", null)
          .select("referencia_externa")
          .maybeSingle();

        if (errorReserva) {
          throw new ErrorPublico(
            "No se pudo preparar el registro del pago.",
            500,
          );
        }

        if (reserva) {
          referencia = reserva.referencia_externa;
        } else {
          const { data: actual, error: errorActual } = await admin
            .from("pagos")
            .select("referencia_externa")
            .eq("id", pago.id)
            .maybeSingle();

          if (errorActual) {
            throw new ErrorPublico(
              "No se pudo recuperar el registro del pago.",
              500,
            );
          }

          referencia = actual?.referencia_externa ?? null;
        }
      }

      if (referencia?.startsWith("cs_test_")) {
        // Otra solicitud puede haber creado y guardado la sesión.
        sesion = await stripe(
          `/checkout/sessions/${encodeURIComponent(referencia)}`,
        );
      } else {
        exigir(
          referencia && /^stripe_init:\d+$/.test(referencia),
          "El pago tiene una referencia que debe revisar la tienda.",
          409,
        );

        const inicio = Number(referencia.split(":")[1]);
        const ahora = Math.floor(Date.now() / 1000);

        // Fecha fija para conservar los mismos parámetros
        // cuando se reintenta una solicitud a Stripe.
        const caduca = inicio + 35 * 60 + 5;

        // Permitimos reintentos de creación durante 4 minutos.
        // Queda más de un minuto de margen sobre el mínimo
        // de 30 minutos que exige Stripe.
        exigir(
          Number.isSafeInteger(inicio) &&
            inicio <= ahora &&
            ahora - inicio <= 4 * 60,
          "No se pudo recuperar la sesión a tiempo. No crees otro pedido: contacta con la tienda indicando el código de este pedido.",
          409,
        );

        const retorno = new URL("pedido.html", base);
        retorno.searchParams.set("codigo", pedido.codigo);

        const exito = new URL(retorno);
        exito.searchParams.set("stripe", "retorno");

        const cancelacion = new URL(retorno);
        cancelacion.searchParams.set("stripe", "cancelado");

        const parametros = new URLSearchParams({
          mode: "payment",
          "payment_method_types[0]": "card",

          success_url: exito.href,
          cancel_url: cancelacion.href,

          client_reference_id: String(pedido.id),

          "metadata[pedido_id]": String(pedido.id),
          "metadata[codigo_pedido]": pedido.codigo,
          "metadata[pago_id]": String(pago.id),

          "payment_intent_data[metadata][pedido_id]":
            String(pedido.id),
          "payment_intent_data[metadata][pago_id]":
            String(pago.id),

          "line_items[0][price_data][currency]": "eur",
          "line_items[0][price_data][product_data][name]":
            `Pedido ${pedido.codigo}`,
          "line_items[0][price_data][unit_amount]":
            String(importe),
          "line_items[0][quantity]": "1",

          expires_at: String(caduca),
        });

        sesion = await stripe(
          "/checkout/sessions",
          parametros,
          `sensotoys-checkout-v1-${pago.id}`,
        );
      }
    }

    exigir(
      sesion.livemode === false &&
        sesion.metadata?.pedido_id === String(pedido.id) &&
        sesion.metadata?.pago_id === String(pago.id) &&
        sesion.amount_total === importe &&
        sesion.currency === "eur",
      "La sesión de Stripe no coincide con el pedido.",
      409,
    );

    const { data: guardado, error: errorGuardar } = await admin
      .from("pagos")
      .update({ referencia_externa: sesion.id })
      .eq("id", pago.id)
      .eq("resultado", "pendiente")
      .eq("referencia_externa", referencia)
      .select("id")
      .maybeSingle();

    if (errorGuardar) {
      throw new ErrorPublico(
        "No se pudo guardar la sesión. No vuelvas a crear el pedido; reintenta el pago de este mismo pedido.",
        500,
      );
    }

    if (!guardado) {
      // Otra solicitud puede haber guardado ya esta misma sesión.
      const { data: pagoActual, error: errorPagoActual } = await admin
        .from("pagos")
        .select("referencia_externa, resultado")
        .eq("id", pago.id)
        .eq("pedido_id", pedido.id)
        .maybeSingle();

      if (errorPagoActual) {
        throw new ErrorPublico(
          "No se pudo comprobar la sesión guardada.",
          500,
        );
      }

      exigir(
        pagoActual?.referencia_externa === sesion.id &&
          pagoActual?.resultado === "pendiente",
        "El pago ha cambiado mientras se preparaba la sesión. Consulta el estado de tu pedido antes de reintentar.",
        409,
      );
    }

    // Volvemos a comprobar el estado por si se canceló
    // durante la llamada a Stripe.
    const { data: estadoActual, error: errorEstado } = await admin
      .from("pedidos")
      .select("estado")
      .eq("id", pedido.id)
      .eq("usuario_id", autenticacion.user.id)
      .maybeSingle();

    if (errorEstado) {
      throw new ErrorPublico(
        "No se pudo comprobar el estado del pedido.",
        500,
      );
    }

    if (estadoActual?.estado !== "creado") {
      if (sesion.status === "open") {
        await stripe(
          `/checkout/sessions/${encodeURIComponent(sesion.id)}/expire`,
          new URLSearchParams(),
          `sensotoys-expire-v1-${pago.id}`,
        );
      }

      throw new ErrorPublico(
        "El pedido ya no está disponible para pagar.",
        409,
      );
    }

    exigir(
      sesion.status === "open" &&
        sesion.payment_status === "unpaid" &&
        typeof sesion.url === "string",
      "La sesión ya ha finalizado o ha caducado. Consulta el estado en tus pedidos.",
      409,
    );

    const urlPago = new URL(sesion.url);

    exigir(
      urlPago.protocol === "https:" &&
        urlPago.hostname === "checkout.stripe.com",
      "El enlace de pago recibido no es válido.",
      502,
    );

    return responder({
      ok: true,
      url: urlPago.href,
      codigo_pedido: pedido.codigo,
      modo_pruebas: true,
    });
  } catch (error) {
    if (error instanceof ErrorPublico) {
      return responder(
        { error: error.message },
        error.estado,
      );
    }

    console.error(
      "Error inesperado en crear-sesion-pago:",
      error instanceof Error ? error.name : "desconocido",
    );

    return responder(
      { error: "No se pudo preparar el pago. Inténtalo de nuevo." },
      500,
    );
  }
});
