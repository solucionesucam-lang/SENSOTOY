<script setup>
import { ref, onMounted, onBeforeUnmount, nextTick } from 'vue'
import Chart from 'chart.js/auto'
import { supabase } from '../supabase.js'

const cargando = ref(true)
const error = ref('')
const resumen = ref(null)
const porEstado = ref([])
const integraciones = ref([])
const agente = ref([])
const porDia = ref([])

const lienzo = ref(null)
let grafico = null

const euros = new Intl.NumberFormat('es-ES', { style: 'currency', currency: 'EUR' })

// "2026-11-04" -> "04/11"
function etiqueta(dia) {
  const d = String(dia)
  return d.slice(8, 10) + '/' + d.slice(5, 7)
}

async function cargar() {
  cargando.value = true
  error.value = ''
  const [r, e, i, a, d] = await Promise.all([
    supabase.from('v_metricas_resumen').select('*').single(),
    supabase.from('v_pedidos_por_estado').select('*').order('orden'),
    supabase.from('v_integraciones_por_resultado').select('*').order('orden'),
    supabase.from('v_agente_por_estado').select('*').order('orden'),
    supabase.from('v_pedidos_por_dia').select('*').order('dia'),
  ])
  const fallo = [r, e, i, a, d].find((x) => x.error)
  if (fallo) {
    error.value = 'No se pudieron cargar los datos: ' + fallo.error.message
    cargando.value = false
    return
  }
  resumen.value = r.data
  porEstado.value = e.data
  integraciones.value = i.data
  agente.value = a.data
  porDia.value = d.data
  cargando.value = false
  await nextTick()
  dibujar()
}

function dibujar() {
  if (!lienzo.value) return
  if (grafico) grafico.destroy()
  grafico = new Chart(lienzo.value, {
    type: 'bar',
    data: {
      labels: porDia.value.map((f) => etiqueta(f.dia)),
      datasets: [{
        label: 'Pedidos',
        data: porDia.value.map((f) => f.pedidos),
        backgroundColor: '#7a1f4d',
      }],
    },
    options: {
      responsive: true,
      plugins: { legend: { display: false } },
      scales: {
        x: { title: { display: true, text: 'Día' } },
        y: { beginAtZero: true, ticks: { precision: 0 }, title: { display: true, text: 'Pedidos' } },
      },
    },
  })
}

onMounted(cargar)
onBeforeUnmount(() => { if (grafico) grafico.destroy() })
</script>

<template>
  <section>
    <div class="titulo">
      <h2>Cuadro de mando</h2>
      <button @click="cargar" :disabled="cargando">{{ cargando ? 'Actualizando…' : 'Actualizar' }}</button>
    </div>

    <p v-if="error" role="alert" class="error">{{ error }}</p>
    <p v-else-if="cargando && !resumen">Cargando datos…</p>

    <div v-if="resumen">
      <ul class="tarjetas">
        <li><span class="valor">{{ resumen.pedidos_totales }}</span><span class="nombre">Pedidos totales</span></li>
        <li><span class="valor">{{ euros.format(Number(resumen.importe_total)) }}</span><span class="nombre">Importe total</span></li>
        <li><span class="valor">{{ euros.format(Number(resumen.importe_medio)) }}</span><span class="nombre">Importe medio</span></li>
        <li><span class="valor">{{ resumen.tickets_abiertos }}</span><span class="nombre">Tickets abiertos</span></li>
        <li><span class="valor">{{ resumen.propuestas_agente }}</span><span class="nombre">Propuestas del agente</span></li>
        <li><span class="valor">{{ resumen.propuestas_aprobadas }}</span><span class="nombre">Propuestas aprobadas</span></li>
      </ul>

      <div class="tablas">
        <table>
          <caption>Pedidos por estado</caption>
          <thead><tr><th scope="col">Estado</th><th scope="col">Pedidos</th></tr></thead>
          <tbody>
            <tr v-for="f in porEstado" :key="f.estado"><td>{{ f.estado }}</td><td>{{ f.pedidos }}</td></tr>
          </tbody>
        </table>

        <table>
          <caption>Integraciones por resultado</caption>
          <thead><tr><th scope="col">Resultado</th><th scope="col">Ejecuciones</th></tr></thead>
          <tbody>
            <tr v-for="f in integraciones" :key="f.resultado"><td>{{ f.resultado }}</td><td>{{ f.ejecuciones }}</td></tr>
          </tbody>
        </table>

        <table>
          <caption>Propuestas del agente por estado</caption>
          <thead><tr><th scope="col">Estado</th><th scope="col">Propuestas</th></tr></thead>
          <tbody>
            <tr v-for="f in agente" :key="f.estado"><td>{{ f.estado }}</td><td>{{ f.propuestas }}</td></tr>
          </tbody>
        </table>
      </div>

      <h3>Pedidos por día</h3>
      <p v-if="porDia.length === 0">Todavía no hay pedidos que mostrar.</p>
      <div v-else>
        <canvas ref="lienzo" role="img" aria-label="Gráfico de barras con el número de pedidos de cada día"></canvas>
        <details>
          <summary>Ver los datos del gráfico en una tabla</summary>
          <table>
            <thead><tr><th scope="col">Día</th><th scope="col">Pedidos</th><th scope="col">Importe</th></tr></thead>
            <tbody>
              <tr v-for="f in porDia" :key="f.dia">
                <td>{{ etiqueta(f.dia) }}</td><td>{{ f.pedidos }}</td><td>{{ euros.format(Number(f.importe)) }}</td>
              </tr>
            </tbody>
          </table>
        </details>
      </div>
    </div>
  </section>
</template>

<style scoped>
.titulo { display: flex; flex-wrap: wrap; gap: 1rem; align-items: center; justify-content: space-between; }
.tarjetas { list-style: none; padding: 0; margin: 1rem 0; display: grid; gap: .75rem; grid-template-columns: repeat(auto-fit, minmax(170px, 1fr)); }
.tarjetas li { border: 1px solid var(--borde); border-radius: 10px; padding: .75rem 1rem; background: #fff; display: flex; flex-direction: column; }
.valor { font-size: 1.6rem; font-weight: 700; }
.nombre { font-size: .9rem; }
.tablas { display: grid; gap: 1rem; grid-template-columns: repeat(auto-fit, minmax(240px, 1fr)); margin-bottom: 1.5rem; }
table { border-collapse: collapse; width: 100%; background: #fff; }
caption { text-align: left; font-weight: 700; padding-bottom: .25rem; }
th, td { border: 1px solid var(--borde); padding: .4rem .6rem; text-align: left; }
details { margin-top: 1rem; }
summary { cursor: pointer; }
</style>