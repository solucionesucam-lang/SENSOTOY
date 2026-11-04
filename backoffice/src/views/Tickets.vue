<script setup>
import { ref, computed, onMounted } from 'vue'
import { supabase } from '../supabase.js'
import { fecha } from '../formato.js'

const cargando = ref(true)
const error = ref('')
const tickets = ref([])
const filtro = ref('')

// Mismos valores que los check de la tabla tickets en sql/17
const estadosTicket = ['abierta', 'en_curso', 'resuelta']
const motivos = {
  pago_rechazado: 'Pago rechazado',
  retraso_envio: 'Retraso de envío',
  producto_defectuoso: 'Producto defectuoso',
  otro: 'Otro',
}

const visibles = computed(() =>
  filtro.value ? tickets.value.filter((t) => t.estado === filtro.value) : tickets.value
)

async function cargar() {
  cargando.value = true
  error.value = ''
  const { data, error: e } = await supabase
    .from('tickets')
    .select('id, motivo, mensaje, prioridad, estado, abierto_en, resuelto_en, clientes(nombre), pedidos_bo(codigo_tienda)')
    .order('abierto_en', { ascending: false })
    .limit(100)
  cargando.value = false
  if (e) {
    error.value = 'No se pudieron cargar los tickets: ' + e.message
    return
  }
  tickets.value = data
}

onMounted(cargar)
</script>

<template>
  <section>
    <div class="titulo">
      <h2>Tickets</h2>
      <div class="acciones">
        <label for="filtro-ticket">Estado</label>
        <select id="filtro-ticket" v-model="filtro">
          <option value="">Todos</option>
          <option v-for="e in estadosTicket" :key="e" :value="e">{{ e }}</option>
        </select>
        <button @click="cargar" :disabled="cargando">{{ cargando ? 'Actualizando…' : 'Actualizar' }}</button>
      </div>
    </div>

    <p v-if="error" role="alert" class="error">{{ error }}</p>
    <p v-else-if="cargando && tickets.length === 0">Cargando tickets…</p>
    <p v-else-if="visibles.length === 0">{{ filtro ? 'No hay tickets con ese estado.' : 'Todavía no hay tickets.' }}</p>

    <div v-if="visibles.length > 0" class="tabla-ancha">
      <table>
        <caption>Incidencias de postventa ({{ visibles.length }})</caption>
        <thead>
          <tr>
            <th scope="col">Nº</th><th scope="col">Abierto</th><th scope="col">Cliente</th>
            <th scope="col">Pedido</th><th scope="col">Motivo y mensaje</th><th scope="col">Prioridad</th>
            <th scope="col">Estado</th><th scope="col">Resuelto</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="t in visibles" :key="t.id">
            <td>{{ t.id }}</td>
            <td>{{ fecha(t.abierto_en) }}</td>
            <td>{{ t.clientes?.nombre }}</td>
            <td>{{ t.pedidos_bo?.codigo_tienda || 'Sin pedido' }}</td>
            <td><strong>{{ motivos[t.motivo] || t.motivo }}</strong><br />{{ t.mensaje }}</td>
            <td>{{ t.prioridad || 'Sin asignar' }}</td>
            <td><span class="estado" :class="'estado-' + t.estado">{{ t.estado }}</span></td>
            <td>{{ fecha(t.resuelto_en) }}</td>
          </tr>
        </tbody>
      </table>
    </div>
  </section>
</template>