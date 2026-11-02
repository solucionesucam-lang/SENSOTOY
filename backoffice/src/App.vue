<script setup>
import { ref, onMounted } from 'vue'
import { supabase } from './supabase.js'
import Login from './views/Login.vue'
import Panel from './views/Panel.vue'
import Pedidos from './views/Pedidos.vue'
import Tickets from './views/Tickets.vue'
import Agente from './views/Agente.vue'

const sesion = ref(null)
const vista = ref('panel')
const vistas = { panel: Panel, pedidos: Pedidos, tickets: Tickets, agente: Agente }
const nombres = { panel: 'Cuadro de mando', pedidos: 'Pedidos', tickets: 'Tickets', agente: 'Agente' }

onMounted(async () => {
  const { data } = await supabase.auth.getSession()
  sesion.value = data.session
  supabase.auth.onAuthStateChange((_evento, s) => { sesion.value = s })
})

async function salir() {
  await supabase.auth.signOut()
}
</script>

<template>
  <p class="aviso">Prototipo académico UCAM · Back-office de pruebas · Datos ficticios</p>
  <Login v-if="!sesion" />
  <div v-else>
    <header class="cabecera">
      <h1>Sensotoys · Back-office</h1>
      <nav aria-label="Secciones">
        <button
          v-for="(nombre, clave) in nombres"
          :key="clave"
          :class="{ activo: vista === clave }"
          :aria-current="vista === clave ? 'page' : null"
          @click="vista = clave"
        >{{ nombre }}</button>
      </nav>
      <button class="salir" @click="salir">Salir</button>
    </header>
    <main>
      <component :is="vistas[vista]" />
    </main>
  </div>
</template>