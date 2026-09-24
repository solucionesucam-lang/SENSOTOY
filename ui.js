// =====================================================================
// ui.js — PIEZAS DE INTERFAZ COMUNES A TODAS LAS PÁGINAS
// Cabecera, pie, formato de números, mensajes y carrito del navegador.
// =====================================================================
import { usuarioActual, cerrarSesion } from './datos.js';

export const ENVIO = 3.95, ENVIO_GRATIS = 45, MAX_POR_PRODUCTO = 3;

export const ESTADOS = {
  creado:      ['Creado',                    '#EDE7F4', '#463A66'],
  pagado:      ['Pagado (simulado)',         '#DCEBE5', '#1F5247'],
  preparacion: ['Pendiente de preparación',  '#F6E6C8', '#6B4C12'],
  enviado:     ['Enviado',                   '#DCE7F4', '#25456B'],
  cancelado:   ['Cancelado',                 '#E8E2DB', '#4A4039'],
  incidencia:  ['Con incidencia',            '#F7DED6', '#8A3318']
};

// ---------- Formato ----------
export const euros = (n) => Number(n).toLocaleString('es-ES', { style: 'currency', currency: 'EUR' });
export const fecha = (iso) => new Date(iso).toLocaleString('es-ES', { dateStyle: 'short', timeStyle: 'short' });
export const esc = (s) => String(s ?? '').replace(/[&<>"']/g,
  (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
export const param = (nombre) => new URLSearchParams(location.search).get(nombre);
export const estadoBadge = (e) => {
  const [txt, bg, fg] = ESTADOS[e] || [e, '#eee', '#333'];
  return `<span class="st" style="background:${bg};color:${fg}">${txt}</span>`;
};

export function aviso(msg) {
  let t = document.getElementById('toast');
  if (!t) {
    t = document.createElement('div');
    t.id = 'toast'; t.className = 'toast'; t.setAttribute('role', 'status');
    document.body.append(t);
  }
  t.textContent = msg; t.style.display = 'block';
  clearTimeout(t._h); t._h = setTimeout(() => (t.style.display = 'none'), 3000);
}

// ---------- Carrito (vive en el navegador hasta que se compra) ----------
// Solo guarda qué variante y cuántas: el precio siempre se lee de la BD.
export function leerCarrito() {
  try { return JSON.parse(localStorage.getItem('sensotoys_carrito')) || []; }
  catch { return []; }
}
export function guardarCarrito(lineas) {
  localStorage.setItem('sensotoys_carrito', JSON.stringify(lineas));
  pintarContadorCarrito();
}
export function unidadesEnCarrito() {
  return leerCarrito().reduce((a, l) => a + l.cantidad, 0);
}

// Resumen orientativo para mostrar. El importe que vale es el que
// calcula crear_pedido() en la base de datos.
export function resumenImportes(subtotal) {
  const envio = subtotal === 0 ? 0 : (subtotal >= ENVIO_GRATIS ? 0 : ENVIO);
  const base = Math.round((subtotal / 1.21) * 100) / 100;
  return { subtotal, base, iva: subtotal - base, envio, total: subtotal + envio };
}

// ---------- Cabecera y pie ----------
function pintarContadorCarrito() {
  const el = document.getElementById('contador-carrito');
  if (el) el.textContent = unidadesEnCarrito();
}

export async function pintarMarco() {
  let usuario = null;
  try { usuario = await usuarioActual(); } catch (e) { console.warn(e.message); }

  document.body.insertAdjacentHTML('afterbegin', `
    <div class="banner">Prototipo académico UCAM · Sin actividad comercial real · No introduzcas datos personales ni medios de pago reales</div>
    <header class="top"><div class="wrap">
      <a class="logo" href="index.html">SENSOTOYS</a>
      <nav class="main" aria-label="Principal">
        <a href="catalogo.html">Catálogo</a>
        <a href="catalogo.html?categoria=limitadas">Ediciones limitadas</a>
        <a href="soporte.html">Ayuda y postventa</a>
        ${usuario ? '<a href="pedido.html">Mis pedidos</a>' : ''}
        ${usuario?.rol === 'admin' ? '<a href="admin.html">Back-office</a>' : ''}
      </nav>
      <div class="right">
        ${usuario
          ? `<span class="small muted">${esc(usuario.email)}</span><button class="link-btn" id="salir">Salir</button>`
          : `<a class="btn btn-ghost" href="login.html">Entrar</a>`}
        <a class="btn btn-primary" href="carrito.html">Carrito · <span id="contador-carrito">0</span></a>
      </div>
    </div></header>`);

  document.body.insertAdjacentHTML('beforeend', `
    <footer class="foot"><div class="wrap">
      <div>Sensotoys · Prototipo académico para Soluciones Informáticas para la Empresa (UCAM)</div>
      <div>Datos y pagos simulados</div>
    </div></footer>`);

  pintarContadorCarrito();
  document.getElementById('salir')?.addEventListener('click', async () => {
    await cerrarSesion();
    location.href = 'index.html';
  });
  return usuario;
}

// Para páginas que exigen sesión: si no hay, manda al login y vuelve después
export function exigirSesion(usuario) {
  if (!usuario) {
    location.href = 'login.html?volver=' + encodeURIComponent(location.pathname.split('/').pop() + location.search);
    return false;
  }
  return true;
}

// Tarjeta de producto para catálogo e inicio
export function tarjetaProducto(p) {
  const v = p.variantes;
  const desde = Math.min(...v.map((x) => x.precio));
  const stock = v.reduce((a, x) => a + x.stock, 0);
  const precios = new Set(v.map((x) => x.precio)).size;
  return `<a class="card" href="producto.html?slug=${encodeURIComponent(p.slug)}">
    <div class="photo" style="height:160px;background:${v[0]?.color_hex || '#eee'}">[Foto]</div>
    <div class="row"><span class="tag">${esc(p.categorias.nombre)}</span>${p.es_edicion_limitada ? '<span class="badge">Limitada</span>' : ''}</div>
    <div class="pname">${esc(p.nombre)}</div>
    <div class="row"><span>${precios > 1 ? 'desde ' : ''}${euros(desde)}</span>
      <span class="small muted">${p.es_edicion_limitada ? `Quedan ${stock} de ${p.unidades_edicion}` : `${stock} uds.`}</span></div>
  </a>`;
}
