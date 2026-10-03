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
let revelarPendiente = new Set();
new MutationObserver((cambios) => {
  for (const c of cambios) {
    for (const n of c.addedNodes) {
      if (n.nodeType !== 1) continue;
      aplicarColores(n);
      if (n.matches?.('[data-revelar]') || n.querySelector?.('[data-revelar]')) revelarPendiente.add(n);
    }
  }
  // Los nodos [data-revelar] añadidos después se revelan solos (en lote, en el siguiente fotograma)
  if (revelarPendiente.size) requestAnimationFrame(() => {
    const lote = revelarPendiente; revelarPendiente = new Set();
    for (const n of lote) if (n.isConnected) revelar(n);
  });
}).observe(document.documentElement, { childList: true, subtree: true });

// ---------- Preferencias de movimiento ----------
const consultaQuieta = window.matchMedia?.('(prefers-reduced-motion: reduce)');
const sinMovimiento = () => !!consultaQuieta?.matches;
const punteroFino = () => !!window.matchMedia?.('(hover: hover) and (pointer: fine)').matches;

// ---------- Aparición al hacer scroll ----------
// El CSS solo oculta [data-revelar] cuando <html> tiene .js-revelar. Sin
// IntersectionObserver o con movimiento reducido no se añade la clase y todo
// se ve directamente.
const haySoloIO = 'IntersectionObserver' in window;
if (haySoloIO && !sinMovimiento()) document.documentElement.classList.add('js-revelar');

let observadorRevelar = null;
const yaRevelado = new WeakSet(); // idempotencia: un nodo se observa una sola vez

export function revelar(raiz = document) {
  if (!raiz) return;
  const nodos = [];
  if (raiz.matches?.('[data-revelar]')) nodos.push(raiz);
  nodos.push(...(raiz.querySelectorAll?.('[data-revelar]') || []));
  const nuevos = nodos.filter((n) => !yaRevelado.has(n));
  if (!nuevos.length) return;

  // --orden: índice dentro de su contenedor (módulo 8 para que el escalonado no se alargue)
  const contador = new Map();
  for (const n of nuevos) {
    yaRevelado.add(n);
    const i = contador.get(n.parentElement) || 0;
    contador.set(n.parentElement, i + 1);
    n.style.setProperty('--orden', i % 8);
  }

  if (!haySoloIO || sinMovimiento()) {
    for (const n of nuevos) n.classList.add('visible');
    return;
  }
  observadorRevelar ||= new IntersectionObserver((entradas) => {
    for (const e of entradas) {
      if (!e.isIntersecting) continue;
      e.target.classList.add('visible');
      observadorRevelar.unobserve(e.target);
    }
  }, { threshold: 0.12, rootMargin: '0px 0px -5% 0px' });
  for (const n of nuevos) observadorRevelar.observe(n);
}

// ---------- Imagen de producto (única) ----------
export function colorSlug(color) {
  const c = color.replace(/\s*Aurora$/i, '').trim();
  if (c.includes('/')) return c.split('/').map((s) => s.trim().toLowerCase()).join('-');
  return c.split(' ')[0].toLowerCase();
}

// Ficheros que existen de verdad en img/productos (sin extensión), para no
// pedir rutas que den 404. Si se añade una foto nueva, hay que añadirla aquí.
const FOTOS = new Set([
  'anillos-magneticos-trio-azul', 'anillos-magneticos-trio-azul-4x5',
  'anillos-magneticos-trio-plata', 'anillos-magneticos-trio-plata-4x5',
  'cubo-infinito-mate-gris', 'cubo-infinito-mate-gris-4x5',
  'cubo-infinito-mate-verde', 'cubo-infinito-mate-verde-4x5',
  'nube-mochi-aurora-lavanda', 'nube-mochi-aurora-lavanda-4x5',
  'nube-mochi-aurora-menta', 'nube-mochi-aurora-menta-4x5',
  'nube-mochi-aurora-rosa', 'nube-mochi-aurora-rosa-4x5',
  'nube-mochi-celeste', 'nube-mochi-crema', 'nube-mochi-rosa',
  'pan-de-leche-xl', 'pan-de-leche-xl-4x5',
  'pop-it-hexagono-azul', 'pop-it-hexagono-azul-4x5',
  'pop-it-hexagono-rosa', 'pop-it-hexagono-rosa-4x5',
  'pop-it-hexagono-verde', 'pop-it-hexagono-verde-4x5',
  'pulpo-reversible-rosa-azul', 'pulpo-reversible-verde-amarillo',
  'set-calma-nocturna', 'set-calma-nocturna-4x5',
  'tubo-sensorial-glitter'
]);

// Punto focal (object-position) por fichero, solo donde NO es el centro.
// Las fotos cuadradas se recortan con cover a 4/5 (se pierde ~10 % por lado):
// en las nubes, la silueta ocupa casi todo el ancho, así que se desplaza el
// encuadre para que el recorte caiga del lado con menos protagonista.
const ENCUADRE = {
  'nube-mochi-crema': '42% 50%',
  'nube-mochi-rosa': '55% 50%'
};

function ficheroFoto(slug, color) {
  const c = colorSlug(color);
  return [`${slug}-${c}-4x5`, `${slug}-4x5`, `${slug}-${c}`, slug].find((f) => FOTOS.has(f)) || null;
}

// Foto 4:5 del color o del producto; si no, el original del color; si no, la
// genérica; si no hay ninguna, el marcador "[Foto]". El listener de error
// queda como red de seguridad por si un fichero del manifiesto desaparece.
export function imgProducto(slug, color, nombre, clase = '') {
  const f = ficheroFoto(slug, color);
  if (!f) return '<span class="sin-foto">[Foto]</span>';
  const es45 = f.endsWith('-4x5');
  const enc = ENCUADRE[f];
  return `<img class="${esc(`foto-img ${clase}`.trim())}" src="img/productos/${f}.webp"
    data-slug="${esc(slug)}" alt="${esc(nombre)} · ${esc(color)}" loading="lazy" decoding="async"
    width="800" height="${es45 ? 1000 : 800}"${enc ? ` style="--encuadre: ${enc}"` : ''}>`;
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

// ---------- Formas orgánicas decorativas ----------
const FORMAS = [
  "M174.5 123.1C167.1 147.6 141.4 183.2 120 187.8C98.5 192.3 63.7 169.4 45.7 150.3C27.7 131.1 5.9 93.5 12.1 72.8C18.3 52.1 57.7 31.3 83.1 25.9C108.6 20.5 149.3 24 164.6 40.2C179.8 56.4 181.9 98.5 174.5 123.1Z",
  "M142.9 172.2C119.1 181.8 68 164.1 46.5 145.8C25 127.5 3.2 79.8 13.9 62.4C24.7 45 81.7 37.1 110.9 41.3C140.1 45.6 183.9 66.1 189.2 87.9C194.5 109.7 166.6 162.5 142.9 172.2Z",
  "M166 145.2C156 164.2 126.7 193.1 106.9 193.7C87.1 194.4 63.1 166.8 47.1 148.9C31.2 131 8.5 105.6 11 86.4C13.5 67.3 41.5 46.6 62.1 34.1C82.7 21.7 117.4 4.1 134.8 11.6C152.3 19.2 161.7 57.2 166.9 79.5C172.1 101.7 176 126.1 166 145.2Z",
  "M161.3 163.1C143.1 180.8 64.9 175.9 44 154.3C23.1 132.8 17.7 51.7 35.9 34C54.1 16.4 132.2 26.9 153.1 48.4C174 70 179.5 145.5 161.3 163.1Z",
  "M192.1 118.7C188.6 136.2 160.5 151.1 142 163.3C123.5 175.6 98.9 195.7 81.3 192.1C63.8 188.6 48.9 160.5 36.7 142C24.4 123.5 4.3 98.9 7.9 81.3C11.4 63.8 39.5 48.9 58 36.7C76.5 24.4 101.1 4.3 118.7 7.9C136.2 11.4 151.1 39.5 163.3 58C175.6 76.5 195.7 101.1 192.1 118.7Z",
  "M58.7 168.6C32.7 159.2 10.5 116 14.2 92.5C17.9 69 55.8 31 80.8 27.7C105.7 24.3 149.1 52.4 164 72.6C178.8 92.8 187.5 132.8 170 148.8C152.4 164.8 84.6 178 58.7 168.6Z"
];

export function formaSVG(n, clase = '') {
  const i = ((Math.round(Number(n)) || 1) - 1 + FORMAS.length * 10) % FORMAS.length;
  const cls = ['forma', `forma-${i + 1}`, clase].filter(Boolean).join(' ');
  return `<svg class="${esc(cls)}" viewBox="0 0 200 200" aria-hidden="true" focusable="false"><path fill="currentColor" d="${FORMAS[i]}"/></svg>`;
}

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
let ultimoContador = null;
const textoCarrito = (n) => `Carrito, ${n} ${n === 1 ? 'artículo' : 'artículos'}`;

// Actualiza número y aria-label; la clase .cambia (rebote) solo se reinicia
// cuando el número es distinto del anterior (no en la primera pintura).
function pintarContadorCarrito() {
  const el = document.getElementById('contador-carrito');
  if (!el) return;
  const n = unidadesEnCarrito();
  el.textContent = n;
  document.getElementById('boton-carrito')?.setAttribute('aria-label', textoCarrito(n));
  if (ultimoContador !== null && n !== ultimoContador && !sinMovimiento()) {
    el.classList.remove('cambia');
    void el.offsetWidth;
    el.classList.add('cambia');
  }
  ultimoContador = n;
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

  // Enlace del menú que corresponde a la página actual (aria-current="page")
  const archivo = location.pathname.split('/').pop() || 'index.html';
  const categoriaActual = param('categoria');
  const actual = (href) => {
    const [ruta, consulta = ''] = href.split('?');
    if (ruta !== archivo) return false;
    const cat = new URLSearchParams(consulta).get('categoria');
    return ruta === 'catalogo.html' ? (cat ? cat === categoriaActual : categoriaActual !== 'limitadas') : true;
  };
  const enlaceMenu = (href, texto) =>
    `<a href="${href}"${actual(href) ? ' aria-current="page"' : ''}>${texto}</a>`;

  const nCarrito = unidadesEnCarrito();
  ultimoContador = nCarrito;

  document.body.insertAdjacentHTML('afterbegin', `
    <a class="saltar-enlace" href="#${destinoSalto}">Saltar al contenido</a>
    <div class="banner aviso-prototipo">Prototipo académico UCAM · Sin actividad comercial real · No introduzcas datos personales ni medios de pago reales</div>
    <header class="top cabecera"><div class="wrap cabecera-in">
      <a class="logo" href="index.html" aria-label="Sensotoys, inicio">
        <svg class="logo-forma" viewBox="0 0 200 200" aria-hidden="true" focusable="false"><path fill="currentColor" d="${FORMAS[2]}"/></svg>
        <span class="logo-texto">senso<em>toys</em></span>
      </a>
      <button class="menu-toggle" type="button" aria-expanded="false" aria-controls="menu-principal">
        <span class="menu-toggle-raya" aria-hidden="true"></span><span class="visualmente-oculto">Menú</span>
      </button>
      <nav class="main menu" id="menu-principal" aria-label="Principal">
        ${enlaceMenu('catalogo.html', 'Catálogo')}
        ${enlaceMenu('catalogo.html?categoria=limitadas', 'Ediciones limitadas')}
        ${enlaceMenu('soporte.html', 'Ayuda y postventa')}
        ${usuario ? enlaceMenu('pedido.html', 'Mis pedidos') : ''}
        ${usuario?.rol === 'admin' ? enlaceMenu('admin.html', 'Back-office') : ''}
      </nav>
      <div class="right cabecera-acciones">
        ${usuario
          ? `<span class="small muted">${esc(usuario.email)}</span><button class="link-btn" id="salir">Salir</button>`
          : `<a class="btn btn-ghost" href="login.html">Entrar</a>`}
        <a class="boton-carrito" id="boton-carrito" href="carrito.html" aria-label="${textoCarrito(nCarrito)}"${archivo === 'carrito.html' ? ' aria-current="page"' : ''}>
          <svg viewBox="0 0 24 24" width="22" height="22" aria-hidden="true" focusable="false" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M5.5 8.5h13l-1 11a1.5 1.5 0 0 1-1.5 1.4H8a1.5 1.5 0 0 1-1.5-1.4l-1-11z"/><path d="M8.8 8.5V7a3.2 3.2 0 0 1 6.4 0v1.5"/></svg>
          <span class="contador" id="contador-carrito">${nCarrito}</span></a>
      </div>
    </div></header>`);

  document.body.insertAdjacentHTML('beforeend', `
    <footer class="foot pie">
      <div class="wrap pie-in">
        <p class="pie-lema">Aprieta, respira, <em>repite</em>.</p>
        <div class="pie-columnas">
          <nav aria-label="Tienda"><h2 class="pie-titulo">Tienda</h2><ul>
            <li><a href="catalogo.html">Todo el catálogo</a></li>
            <li><a href="catalogo.html?categoria=squishies">Squishies</a></li>
            <li><a href="catalogo.html?categoria=fidgets">Fidgets</a></li>
            <li><a href="catalogo.html?categoria=sets">Sets sensoriales</a></li>
            <li><a href="catalogo.html?categoria=limitadas">Ediciones limitadas</a></li>
          </ul></nav>
          <nav aria-label="Ayuda"><h2 class="pie-titulo">Ayuda</h2><ul>
            <li><a href="soporte.html">Ayuda y postventa</a></li>
            <li><a href="pedido.html">Mis pedidos</a></li>
            ${usuario ? '' : '<li><a href="login.html">Entrar</a></li>'}
          </ul></nav>
          <div class="pie-nota"><h2 class="pie-titulo">Sobre este proyecto</h2>
            <p>Prototipo académico para Soluciones Informáticas para la Empresa (UCAM). Datos y pagos simulados.</p></div>
        </div>
        <p class="pie-marca" aria-hidden="true">sensotoys</p>
      </div>
      ${formaSVG(5, 'pie-forma')}
    </footer>`);

  activarMenuMovil();
  activarCabeceraScroll();
  pintarContadorCarrito();
  pintarBannerCookies();
  document.getElementById('salir')?.addEventListener('click', async () => {
    await cerrarSesion();
    location.href = 'index.html';
  });
  revelar();
  return usuario;
}

// Menú móvil: botón con aria-expanded; Escape, clic fuera, clic en un enlace
// y volver con el historial lo cierran.
function activarMenuMovil() {
  const cabecera = document.querySelector('header.cabecera');
  const boton = cabecera?.querySelector('.menu-toggle');
  if (!cabecera || !boton) return;
  const poner = (abierto) => {
    cabecera.classList.toggle('abierta', abierto);
    boton.setAttribute('aria-expanded', String(abierto));
  };
  boton.addEventListener('click', () => poner(boton.getAttribute('aria-expanded') !== 'true'));
  document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape' && boton.getAttribute('aria-expanded') === 'true') {
      poner(false);
      boton.focus();
    }
  });
  document.addEventListener('click', (e) => {
    if (boton.getAttribute('aria-expanded') !== 'true') return;
    if (e.target.closest('.menu a') || !e.target.closest('header.cabecera')) poner(false);
  });
  window.addEventListener('pageshow', () => poner(false));
  window.matchMedia?.('(min-width: 860px)').addEventListener?.('change', (e) => { if (e.matches) poner(false); });
}

// .con-scroll en la cabecera cuando la página ha bajado un poco
function activarCabeceraScroll() {
  const cabecera = document.querySelector('header.cabecera');
  if (!cabecera) return;
  const ajustar = () => cabecera.classList.toggle('con-scroll', window.scrollY > 8);
  window.addEventListener('scroll', ajustar, { passive: true });
  ajustar();
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

  return `<a class="card card-producto tarjeta" href="producto.html?slug=${encodeURIComponent(p.slug)}" data-revelar>
    <div class="photo photo-tarjeta foto" data-bg="${esc(v[0]?.color_hex || '#EEEEEE')}">
      ${imgProducto(p.slug, v[0].color, p.nombre)}
    </div>
    <div class="tarjeta-cuerpo">
      <div class="row tarjeta-meta"><span class="tag etiqueta">${esc(p.categorias.nombre)}</span>${p.es_edicion_limitada ? '<span class="badge insignia">Limitada</span>' : ''}</div>
      <h3 class="pname tarjeta-nombre">${esc(p.nombre)}</h3>
      <div class="row tarjeta-pie"><span class="precio">${precios > 1 ? 'desde ' : ''}${euros(desde)}</span>
        <span class="small muted stock">${p.es_edicion_limitada ? `Quedan ${stock} de ${p.unidades_edicion}` : `${stock} uds.`}</span></div>
    </div>
    <span class="tarjeta-flecha" aria-hidden="true">→</span>
  </a>`;
}

// ---------- Transiciones de vista: la foto de la tarjeta "vuela" a la ficha ----------
const hayTransiciones = !!(window.CSS?.supports?.('view-transition-name', 'foto-producto'));
let fotoMarcada = null;

// La ficha llama a esto con su foto principal (el nombre debe ser único en la página)
export function marcarFotoTransicion(elemento) {
  if (!hayTransiciones || sinMovimiento() || !elemento) return;
  if (fotoMarcada && fotoMarcada !== elemento) fotoMarcada.style.viewTransitionName = '';
  elemento.style.viewTransitionName = 'foto-producto';
  fotoMarcada = elemento;
}
function limpiarFotoTransicion() {
  if (fotoMarcada) fotoMarcada.style.viewTransitionName = '';
  fotoMarcada = null;
}
if (hayTransiciones) {
  document.addEventListener('click', (e) => {
    const tarjeta = e.target.closest?.('a.tarjeta');
    const foto = tarjeta?.querySelector('.foto');
    if (foto) marcarFotoTransicion(foto);
  }, true);
  window.addEventListener('pageshow', (e) => { if (e.persisted) limpiarFotoTransicion(); });
}

// ---------- Microinteracciones ----------
// Efecto magnético sutil en .btn-grande: solo con puntero fino y sin reduced motion.
// Usa la propiedad `translate`, que no pisa el transform del CSS.
let botonMagnetico = null;
function soltarMagnetico() {
  if (!botonMagnetico) return;
  botonMagnetico.style.translate = '';
  botonMagnetico = null;
}
if (window.matchMedia && 'translate' in document.documentElement.style) {
  document.addEventListener('pointermove', (e) => {
    if (e.pointerType !== 'mouse' || sinMovimiento() || !punteroFino()) return soltarMagnetico();
    const b = e.target.closest?.('.btn-grande');
    if (!b || b.disabled || b.getAttribute('aria-disabled') === 'true') return soltarMagnetico();
    if (botonMagnetico && botonMagnetico !== b) soltarMagnetico();
    botonMagnetico = b;
    const r = b.getBoundingClientRect();
    const dx = (e.clientX - (r.left + r.width / 2)) / r.width;
    const dy = (e.clientY - (r.top + r.height / 2)) / r.height;
    b.style.translate = `${(dx * 8).toFixed(1)}px ${(dy * 6).toFixed(1)}px`;
  }, { passive: true });
  document.addEventListener('pointerleave', soltarMagnetico, true);
}

// Revelado inicial de lo que ya está en el HTML (las páginas lo repiten tras pintar contenido dinámico)
if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', () => revelar(), { once: true });
else revelar();

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
