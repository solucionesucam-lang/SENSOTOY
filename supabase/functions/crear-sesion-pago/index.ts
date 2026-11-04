import { createClient } from "npm:@supabase/supabase-js@2";
import { corsHeaders } from "npm:@supabase/supabase-js@2/cors";

function responder(datos: unknown, estado = 200) {
  return new Response(JSON.stringify(datos), {
    status: estado,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json",
    },
  });
}

Deno.serve(async (req: Request) => {
  // Permite la comprobación previa que hace el navegador.
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return responder({ error: "Método no permitido." }, 405);
  }

  try {
    const autorizacion = req.headers.get("Authorization");

    if (!autorizacion?.startsWith("Bearer ")) {
      return responder({ error: "Tienes que iniciar sesión." }, 401);
    }

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      {
        auth: {
          persistSession: false,
          autoRefreshToken: false,
        },
      },
    );

    const token = autorizacion.slice("Bearer ".length);
    const { data, error } = await supabase.auth.getUser(token);

    if (error || !data.user) {
      return responder({ error: "La sesión no es válida." }, 401);
    }

    const claveStripe = Deno.env.get("STRIPE_SECRET_KEY");

    if (!claveStripe?.startsWith("sk_test_")) {
      return responder(
        { error: "Falta una clave secreta de pruebas de Stripe válida en la configuración." },
        500,
      );
    }

    // Consulta de solo lectura para comprobar la clave con Stripe.
    const respuestaStripe = await fetch(
      "https://api.stripe.com/v1/balance",
      {
        method: "GET",
        headers: {
          Authorization: `Bearer ${claveStripe}`,
        },
      },
    );

    if (!respuestaStripe.ok) {
      return responder(
        {
          error: "Stripe no ha aceptado la consulta.",
          estado_stripe: respuestaStripe.status,
        },
        502,
      );
    }

    const saldo = await respuestaStripe.json();

    if (saldo.livemode !== false) {
      return responder(
        { error: "La respuesta no corresponde al entorno de pruebas." },
        500,
      );
    }

    return responder({
      ok: true,
      mensaje: "Conexión con Stripe en pruebas verificada.",
      etapa: "conexion_stripe",
      modo_pruebas: true,
    });
  } catch {
    return responder({ error: "No se pudo completar la comprobación." }, 500);
  }
});
