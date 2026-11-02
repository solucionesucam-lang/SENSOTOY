import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'

// base: ruta donde vive el back-office en GitHub Pages
export default defineConfig({
  base: '/SENSOTOY/backoffice/',
  plugins: [vue()],
})
