<script setup>
import { ref } from 'vue'
import { supabase } from '../supabase.js'

const email = ref('')
const clave = ref('')
const error = ref('')
const cargando = ref(false)

async function entrar() {
  error.value = ''
  cargando.value = true
  const { error: e } = await supabase.auth.signInWithPassword({
    email: email.value,
    password: clave.value,
  })
  cargando.value = false
  if (e) error.value = 'No se pudo entrar: revisa el correo y la contraseña.'
}
</script>

<template>
  <main class="login">
    <h1>Sensotoys · Back-office</h1>
    <p>Acceso solo para el equipo. Usa la cuenta de prueba.</p>
    <form @submit.prevent="entrar">
      <label for="email">Correo</label>
      <input id="email" type="email" v-model="email" autocomplete="username" required />
      <label for="clave">Contraseña</label>
      <input id="clave" type="password" v-model="clave" autocomplete="current-password" required />
      <button type="submit" :disabled="cargando">{{ cargando ? 'Entrando…' : 'Entrar' }}</button>
      <p v-if="error" role="alert" class="error">{{ error }}</p>
    </form>
  </main>
</template>