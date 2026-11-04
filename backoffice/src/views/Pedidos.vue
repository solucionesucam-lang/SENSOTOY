<script setup>
import { ref, computed, onMounted } from 'vue'
import { supabase } from '../supabase.js'
import { euros, fecha, estadosPedido } from '../formato.js'

const cargando = ref(true)
const error = ref('')
const pedidos = ref([])
const filtro = ref('')
const abierto = ref(null) // id del pedido cuyas líneas se muestran

const visibles = computed(() =>
  filtro.value ? pedidos.value.filter((p) => p.estado === filtro.value) : pedidos.value
)
const seleccionado = computed(() => pedidos.value.find((p) => p.id === abierto.value) || null)

async function cargar() {
  cargando.value = true
  error.value = ''
  // Una sola consulta: el pedido, su cliente y sus líneas
  const { data, error: e } = await supabase
    .from('pedidos_bo')
    .select(
      'id, codigo_tienda, importe, estado, fecha_pedido, clientes(nombre, email), lineas_bo(sku, nombre_producto, descripcion_variante, precio_unitario, cantidad, importe)'
    )
    .order('fecha_pedido', { ascending: false })
    .limit(100)
  cargando.value = false
  if (e) {
    error.value = 'No se pudieron cargar los pedidos: ' + e.message
    return
  }
  pedidos.value = data
}

function alternar(id) {
  abierto.value = abierto.value === id ? null : id
}

onMounted(cargar)
</script>

<template>
  <section>
    <div class="titulo">
      <h2>Pedidos</h2>
      <div class="acciones">
        <label for="filtro-estado">Estado</label>
        <select id="filtro-estado" v-model="filtro">
          <option value="">Todos</option>
          <option v-for="e in estadosPedido" :key="e" :value="e">{{ e }}</option>
        </select>
        <button @click="cargar" :disabled="cargando">{{ cargando ? 'Actualizando…' : 'Actualizar' }}</button>
      </div>
    </div>

    <p v-if="error" role="alert" class="error">{{ error }}</p>
    <p v-else-if="cargando && pedidos.length === 0">Cargando pedidos…</p>
    <p v-else-if="visibles.length === 0">{{ filtro ? 'No hay pedidos con ese estado.' : 'Todavía no hay pedidos.' }}</p>

    <div v-if="seleccionado" class="detalle">
      <h3>Líneas del pedido {{ seleccionado.codigo_tienda }}</h3>
      <p>Cliente: {{ seleccionado.clientes?.nombre }} ({{ seleccionado.clientes?.email }})</p>
      <div class="tabla-ancha">
        <table>
          <thead>
            <tr><th scope="col">Producto</th><th scope="col">SKU</th><th scope="col">Precio</th><th scope="col">Cantidad</th><th scope="col">Importe</th></tr>
          </thead>
          <tbody>
            <tr v-for="l in seleccionado.lineas_bo" :key="l.sku">
              <td>{{ l.nombre_producto }}<span v-if="l.descripcion_variante"> · {{ l.descripcion_variante }}</span></td>
              <td>{{ l.sku }}</td>
              <td>{{ euros(l.precio_unitario) }}</td>
              <td>{{ l.cantidad }}</td>
              <td>{{ euros(l.importe) }}</td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>

    <div v-if="visibles.length > 0" class="tabla-ancha">
      <table>
        <caption>Pedidos integrados desde la tienda ({{ visibles.length }})</caption>
        <thead>
          <tr>
            <th scope="col">Código</th><th scope="col">Fecha</th><th scope="col">Cliente</th>
            <th scope="col">Importe</th><th scope="col">Estado</th><th scope="col">Líneas</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="p in visibles" :key="p.id">
            <td>{{ p.codigo_tienda }}</td>
            <td>{{ fecha(p.fecha_pedido) }}</td>
            <td>{{ p.clientes?.nombre }}</td>
            <td>{{ euros(p.importe) }}</td>
            <td><span class="estado" :class="'estado-' + p.estado">{{ p.estado }}</span></td>
            <td>
              <button class="pequeno" :aria-expanded="abierto === p.id" @click="alternar(p.id)">
                {{ abierto === p.id ? 'Ocultar' : 'Ver líneas' }}
              </button>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
  </section>
</template>