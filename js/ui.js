// =====================================================================
// ui.js — PIEZAS DE INTERFAZ COMUNES A TODAS LAS PÁGINAS
// Cabecera, pie, formato de números, mensajes, carrito del navegador y
// pasillo de compra. Las constantes de negocio no se escriben aquí:
// se leen de la base de datos (tabla configuracion, sql/11).
// =====================================================================
import { usuarioActual, cerrarSesion, configuracion, variantesPorId } from './datos.js';

// Se rellena en pintarMarco(): maxPorProducto, envioGratis, gastosEnvio
export const CONFIG = {};
export const configLista = () => CONFIG.maxPorProducto !== undefined;

async function cargarConfiguracion() {
  try {
    const c = await configuracion();
    CONFIG.maxPorProducto = Number(c.max_por_producto);
    CONFIG.envioGratis = Number(c.envio_gratis_desde);
    CONFIG.gastosEnvio = Number(c.gastos_envio);
  } catch (e) {
    console.warn('No se pudo leer la configuración de la tienda:', e.message);
  }
}

export const ESTADOS = {
  creado: 'Creado',
  pagado: 'Pagado',
  preparacion: 'Pendiente de preparación',
  enviado: 'Enviado',
  cancelado: 'Cancelado',
  incidencia: 'Con incidencia'
};

// ---------- Formato ----------
export const euros = (n) => Number(n).toLocaleString('es-ES', { style: 'currency', currency: 'EUR' });
export const fecha = (iso) => new Date(iso).toLocaleString('es-ES', { dateStyle: 'short', timeStyle: 'short' });
export const esc = (s) => String(s ?? '').replace(/[&<>"']/g,
  (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
export const param = (nombre) => new URLSearchParams(location.search).get(nombre);
export const estadoBadge = (e) => ESTADOS[e]
  ? `<span class="st st-${e}">${ESTADOS[e]}</span>`
  : `<span class="st">${esc(e)}</span>`;

export function aviso(msg) {
  let t = document.getElementById('toast');
  if (!t) {
    t = document.createElement('div');
    t.id = 'toast'; t.className = 'toast'; t.hidden = true; t.setAttribute('role', 'status');
    document.body.append(t);
  }
  t.textContent = msg; t.hidden = false;
  clearTimeout(t._h); t._h = setTimeout(() => (t.hidden = true), 3000);
}

// ---------- Colores de variante ----------
// El color de cada variante viene de la base de datos, así que no puede ir
// en el CSS. Se marca con data-bg y se aplica por CSSOM (no hay atributos
// style en el HTML que escribimos). El observador cubre todo lo que se
// pinta después con innerHTML.
const HEX = /^#[0-9a-f]{6}$/i;
function aplicarColores(raiz) {
  const nodos = raiz.matches?.('[data-bg]') ? [raiz] : [];
  nodos.push(...(raiz.querySelectorAll?.('[data-bg]') || []));
  for (const n of nodos) {
    if (HEX.test(n.dataset.bg)) n.style.backgroundColor = n.dataset.bg;
    n.removeAttribute('data-bg');
  }
}
new MutationObserver((cambios) => {
  for (const c of cambios) for (const n of c.addedNodes) if (n.nodeType === 1) aplicarColores(n);
}).observe(document.documentElement, { childList: true, subtree: true });

// ---------- Imagen de producto (única) ----------
export function colorSlug(color) {
  const c = color.replace(/\s*Aurora$/i, '').trim();
  if (c.includes('/')) return c.split('/').map((s) => s.trim().toLowerCase()).join('-');
  return c.split(' ')[0].toLowerCase();
}

// Foto del color; si no existe, la genérica del producto; si tampoco, "[Foto]"
// (ese relevo lo hace el listener de abajo para todas las imágenes de producto).
export function imgProducto(slug, color, nombre, clase = '') {
  return `<img class="${clase}" src="img/productos/${esc(slug)}-${esc(colorSlug(color))}.webp"
    data-slug="${esc(slug)}" alt="${esc(nombre)} · ${esc(color)}" loading="lazy">`;
}
document.addEventListener('error', (e) => {
  const img = e.target;
  if (!(img instanceof HTMLImageElement) || !img.dataset.slug) return;
  if (!img.dataset.respaldo) {
    img.dataset.respaldo = '1';
    img.src = `img/productos/${img.dataset.slug}.webp`;
  } else {
    const hueco = document.createElement('span');
    hueco.className = 'sin-foto';
    hueco.textContent = '[Foto]';
    img.replaceWith(hueco);
  }
}, true);

// ---------- Carrito (localStorage) ----------
function claveCarrito() {
  const usuarioId = localStorage.getItem('sensotoys_usuario_id');
  return usuarioId ? `sensotoys_carrito_${usuarioId}` : 'sensotoys_carrito_invitado';
}

export function leerCarrito() {
  try {
    return JSON.parse(localStorage.getItem(claveCarrito())) || [];
  } catch {
    return [];
  }
}

export function guardarCarrito(lineas) {
  localStorage.setItem(claveCarrito(), JSON.stringify(lineas));
  pintarContadorCarrito();
}

export function lineasValidas(variantes) {
  const carrito = leerCarrito();
  const validas = carrito.filter((l) => variantes.some((v) => v.id === l.variante_id && v.productos));
  if (validas.length !== carrito.length) {
    guardarCarrito(validas);
    aviso('Hemos quitado del carrito productos que ya no están disponibles.');
  }
  return validas;
}

export function unidadesEnCarrito() {
  return leerCarrito().reduce((a, l) => a + l.cantidad, 0);
}

// Resumen orientativo para mostrar. El importe que vale es el que
// calcula crear_pedido() en la base de datos.
export function resumenImportes(subtotal) {
  const envio = subtotal === 0 || subtotal >= CONFIG.envioGratis ? 0 : CONFIG.gastosEnvio;
  const base = Math.round((subtotal / 1.21) * 100) / 100;
  return { subtotal, base, iva: subtotal - base, envio, total: subtotal + envio };
}

// Al iniciar sesión, el carrito de invitado se suma al de la cuenta
// respetando el máximo POR PRODUCTO (no por variante). Si algo falla, el
// carrito de invitado se conserva para intentarlo en la siguiente página.
async function fusionarCarritoInvitado() {
  let invitado;
  try { invitado = JSON.parse(localStorage.getItem('sensotoys_carrito_invitado')) || []; }
  catch { invitado = []; }
  if (!invitado.length) { localStorage.removeItem('sensotoys_carrito_invitado'); return; }
  if (!configLista()) return;

  try {
    const propio = leerCarrito();
    const ids = [...new Set([...invitado, ...propio].map((l) => l.variante_id))];
    const variantes = await variantesPorId(ids);
    const productoDe = (id) => variantes.find((v) => v.id === id)?.productos?.slug || `variante-${id}`;

    const porProducto = {};
    for (const l of propio) porProducto[productoDe(l.variante_id)] = (porProducto[productoDe(l.variante_id)] || 0) + l.cantidad;

    for (const l of invitado) {
      if (!variantes.some((v) => v.id === l.variante_id)) continue;
      const slug = productoDe(l.variante_id);
      const hueco = CONFIG.maxPorProducto - (porProducto[slug] || 0);
      if (hueco <= 0) continue;
      const cantidad = Math.min(l.cantidad, hueco);
      const existente = propio.find((x) => x.variante_id === l.variante_id);
      if (existente) existente.cantidad += cantidad;
      else propio.push({ variante_id: l.variante_id, cantidad });
      porProducto[slug] = (porProducto[slug] || 0) + cantidad;
    }
    localStorage.setItem(claveCarrito(), JSON.stringify(propio));
    localStorage.removeItem('sensotoys_carrito_invitado');
  } catch (e) {
    console.warn('No se pudo fusionar el carrito de invitado:', e.message);
  }
}

// ---------- Cabecera y pie ----------
function pintarContadorCarrito() {
  const el = document.getElementById('contador-carrito');
  if (el) el.textContent = unidadesEnCarrito();
}

// Pequeña animación del botón del carrito al añadir un producto
export function animarCarrito() {
  const boton = document.getElementById('boton-carrito');
  if (!boton) return;
  boton.classList.remove('bump');
  void boton.offsetWidth;
  boton.classList.add('bump');
}

export async function pintarMarco() {
  await cargarConfiguracion();
  let usuario = null;
  try { usuario = await usuarioActual(); } catch (e) { console.warn(e.message); }
  if (usuario) {
    localStorage.setItem('sensotoys_usuario_id', usuario.id);
    await fusionarCarritoInvitado();
  } else {
    localStorage.removeItem('sensotoys_usuario_id');
  }

  const principal = document.querySelector('main');
  if (principal && !principal.id) principal.id = 'contenido-principal';
  const destinoSalto = principal?.id || 'contenido-principal';

  document.body.insertAdjacentHTML('afterbegin', `
    <a class="saltar-enlace" href="#${destinoSalto}">Saltar al contenido</a>
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
        <a class="btn btn-primary" id="boton-carrito" href="carrito.html">Carrito · <span id="contador-carrito">0</span></a>
      </div>
    </div></header>`);

  document.body.insertAdjacentHTML('beforeend', `
    <footer class="foot"><div class="wrap">
      <div>Sensotoys · Prototipo académico para Soluciones Informáticas para la Empresa (UCAM)</div>
      <div>Datos y pagos simulados</div>
    </div></footer>`);

  pintarContadorCarrito();
  pintarBannerCookies();
  document.getElementById('salir')?.addEventListener('click', async () => {
    await cerrarSesion();
    location.href = 'index.html';
  });
  return usuario;
}

// Aviso de cookies: se muestra hasta que la persona lo acepta
function pintarBannerCookies() {
  try { if (localStorage.getItem('sensotoys_cookies_ok') === '1') return; } catch {}
  const div = document.createElement('div');
  div.id = 'cookies'; div.className = 'cookies'; div.setAttribute('role', 'region');
  div.setAttribute('aria-label', 'Aviso de cookies');
  div.innerHTML = '<span>Usamos almacenamiento local del navegador para recordar tu carrito y tu sesión.</span><button class="btn btn-primary" type="button">Aceptar</button>';
  div.querySelector('button').addEventListener('click', () => {
    try { localStorage.setItem('sensotoys_cookies_ok', '1'); } catch {}
    div.remove();
  });
  document.body.append(div);
}

// Para páginas que exigen sesión: si no hay, manda al login y vuelve después
export function exigirSesion(usuario) {
  if (!usuario) {
    location.href = 'login.html?volver=' + encodeURIComponent(location.pathname.split('/').pop() + location.search);
    return false;
  }
  return true;
}

// ---------- Tarjeta de producto (catálogo e inicio) ----------
export function tarjetaProducto(p) {
  const v = p.variantes;
  const desde = Math.min(...v.map((x) => x.precio));
  const stock = v.reduce((a, x) => a + x.stock, 0);
  const precios = new Set(v.map((x) => x.precio)).size;

  return `<a class="card card-producto" href="producto.html?slug=${encodeURIComponent(p.slug)}">
    <div class="photo photo-tarjeta" data-bg="${esc(v[0]?.color_hex || '#EEEEEE')}">
      ${imgProducto(p.slug, v[0].color, p.nombre)}
    </div>
    <div class="row"><span class="tag">${esc(p.categorias.nombre)}</span>${p.es_edicion_limitada ? '<span class="badge">Limitada</span>' : ''}</div>
    <div class="pname">${esc(p.nombre)}</div>
    <div class="row"><span>${precios > 1 ? 'desde ' : ''}${euros(desde)}</span>
      <span class="small muted">${p.es_edicion_limitada ? `Quedan ${stock} de ${p.unidades_edicion}` : `${stock} uds.`}</span></div>
  </a>`;
}

// ---------- Pasillo de compra (barra de progreso) ----------
// Catálogo 0 % → Producto → Carrito → Datos de envío → Pago → Pedido
// confirmado 100 %. Los pasos hechos son enlaces; los que faltan, no.
const PASOS = ['catalogo', 'producto', 'carrito', 'envio', 'pago', 'confirmado'];
const TEXTO_PASO = {
  catalogo: 'Catálogo', producto: 'Producto', carrito: 'Carrito',
  envio: 'Datos de envío', pago: 'Pago', confirmado: 'Pedido confirmado'
};

export function recordarProducto(slug) {
  try { sessionStorage.setItem('sensotoys_ultimo_producto', slug); } catch {}
}
function enlacePaso(paso) {
  if (paso === 'catalogo') return 'catalogo.html';
  if (paso === 'carrito') return 'carrito.html';
  if (paso === 'envio') return 'checkout.html';
  if (paso === 'producto') {
    try {
      const slug = sessionStorage.getItem('sensotoys_ultimo_producto');
      return slug ? `producto.html?slug=${encodeURIComponent(slug)}` : null;
    } catch { return null; }
  }
  return null;
}

// opciones.navegar(paso): si devuelve true, la página ya gestiona ese clic
// (en checkout, "Datos de envío" no recarga la página).
export function montarPasillo(contenedor, inicial, opciones = {}) {
  let actual = PASOS.indexOf(inicial);
  contenedor.className = 'pasillo';
  contenedor.innerHTML = `<nav aria-label="Pasos de la compra">
    <div class="pasillo-barra" role="progressbar" aria-label="Progreso de la compra" aria-valuemin="0" aria-valuemax="100">
      <div class="pasillo-relleno"></div></div>
    <ol class="pasillo-pasos"></ol></nav>`;
  const barra = contenedor.querySelector('.pasillo-barra');
  const lista = contenedor.querySelector('ol');

  function pintar() {
    const pct = Math.round((actual / (PASOS.length - 1)) * 100);
    barra.setAttribute('aria-valuenow', pct);
    barra.setAttribute('aria-valuetext', `Paso ${actual + 1} de ${PASOS.length}: ${TEXTO_PASO[PASOS[actual]]}`);
    contenedor.dataset.paso = actual;
    lista.innerHTML = PASOS.map((p, i) => {
      const estado = i < actual ? 'hecho' : i === actual ? 'actual' : 'futuro';
      const href = estado === 'hecho' && !opciones.sinEnlaces?.includes(p) ? enlacePaso(p) : null;
      const texto = `<span class="pasillo-num" aria-hidden="true">${i < actual ? '✓' : i + 1}</span><span class="pasillo-txt">${TEXTO_PASO[p]}</span>`;
      const contenido = href
        ? `<a href="${href}" data-paso="${p}">${texto}</a>`
        : `<span ${estado === 'futuro' ? 'aria-disabled="true"' : ''}>${texto}</span>`;
      return `<li class="pasillo-${estado}" ${estado === 'actual' ? 'aria-current="step"' : ''}>${contenido}</li>`;
    }).join('');
  }
  lista.addEventListener('click', (e) => {
    const a = e.target.closest('a[data-paso]');
    if (a && opciones.navegar?.(a.dataset.paso)) e.preventDefault();
  });
  pintar();
  // Al cargar, la barra crece desde 0 hasta su paso
  contenedor.dataset.paso = 0;
  requestAnimationFrame(() => requestAnimationFrame(() => { contenedor.dataset.paso = actual; }));

  return {
    ir(paso) {
      const i = PASOS.indexOf(paso);
      if (i === -1 || i === actual) return;
      actual = i;
      pintar();
    }
  };
}
