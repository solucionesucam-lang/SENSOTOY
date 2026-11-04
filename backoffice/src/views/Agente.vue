<script setup>
import { ref, computed, onMounted } from 'vue'
import { supabase } from '../supabase.js'
import { fecha } from '../formato.js'

const cargando = ref(true)
const error = ref('')
const propuestas = ref([])
const filtro = ref('')

// Mismos valores que el check de aprobaciones_agente.estado en sql/17
const estados = {
  aprobado: 'Aprobado',
  pendiente_revision: 'Pendiente de revisión',
  rechazado: 'Rechazado',
  simulado: 'Ejecutado en modo simulado',
}
const motivos = {
  pago_rechazado: 'Pago rechazado',
  retraso_envio: 'Retraso de envío',
  producto_defectuoso: 'Producto defectuoso',
  otro: 'Otro',
}

const visibles = computed(() =>
  filtro.value ? propuestas.value.filter((p) => p.estado === filtro.value) : propuestas.value
)

async function cargar() {
  cargando.value = true
  error.value = ''
  const { data, error: e } = await supabase
    .from('aprobaciones_agente')
    .select(
      'id, tipo_caso, datos_consultados, accion_propuesta, mensaje_cliente, justificacion, prioridad, confianza, riesgos, estado, revisor, decidido_en, creado_en, tickets(id, motivo, clientes(nombre))'
    )
    .order('creado_en', { ascending: false })
    .limit(50)
  cargando.value = false
  if (e) {
    error.value = 'No se pudieron cargar las propuestas: ' + e.message
    return
  }
  propuestas.value = data
}

onMounted(cargar)
</script>

<template>
  <section>
    <div class="titulo">
      <h2>Agente</h2>
      <div class="acciones">
        <label for="filtro-agente">Estado</label>
        <select id="filtro-agente" v-model="filtro">
          <option value="">Todos</option>
          <option v-for="(nombre, clave) in estados" :key="clave" :value="clave">{{ nombre }}</option>
        </select>
        <button @click="cargar" :disabled="cargando">{{ cargando ? 'Actualizando…' : 'Actualizar' }}</button>
      </div>
    </div>
    <p>
      Propuestas del agente de IA. El agente nunca envía nada al cliente por sí solo:
      una persona del equipo aprueba o rechaza cada propuesta por Telegram.
    </p>

    <p v-if="error" role="alert" class="error">{{ error }}</p>
    <p v-else-if="cargando && propuestas.length === 0">Cargando propuestas…</p>
    <p v-else-if="visibles.length === 0">{{ filtro ? 'No hay propuestas del agente con ese estado.' : 'Todavía no hay propuestas del agente.' }}</p>

    <article v-for="p in visibles" :key="p.id" class="propuesta">
      <h3>
        Propuesta {{ p.id }} · Ticket {{ p.tickets?.id }}
        <span v-if="p.tickets">({{ motivos[p.tickets.motivo] || p.tickets.motivo }}, {{ p.tickets.clientes?.nombre }})</span>
        <span class="estado" :class="'estado-' + p.estado">{{ estados[p.estado] || p.estado }}</span>
      </h3>
      <dl>
        <dt>Tipo de caso</dt><dd>{{ p.tipo_caso }}</dd>
        <dt>Acción propuesta</dt><dd>{{ p.accion_propuesta }}</dd>
        <dt>Justificación</dt><dd>{{ p.justificacion }}</dd>
        <dt>Prioridad</dt><dd>{{ p.prioridad }}</dd>
        <dt>Confianza</dt><dd>{{ p.confianza === null ? 'No indicada' : Math.round(p.confianza * 100) + ' %' }}</dd>
        <dt>Riesgos</dt><dd>{{ p.riesgos || 'No indicados' }}</dd>
        <dt>Mensaje al cliente</dt><dd>{{ p.mensaje_cliente || 'Sin mensaje' }}</dd>
        <dt>Decisión humana</dt>
        <dd v-if="p.revisor">{{ estados[p.estado] }} por {{ p.revisor }} el {{ fecha(p.decidido_en) }}</dd>
        <dd v-else>Todavía sin decisión humana</dd>
      </dl>
      <details>
        <summary>Datos que consultó el agente</summary>
        <pre>{{ JSON.stringify(p.datos_consultados, null, 2) }}</pre>
      </details>
    </article>
  </section>
</template>