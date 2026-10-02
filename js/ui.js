// =====================================================================
// ui.js — PIEZAS DE INTERFAZ COMUNES A TODAS LAS PÁGINAS
// Cabecera, pie, formato de números, mensajes y carrito del navegador.
// =====================================================================
import { usuarioActual, cerrarSesion } from './datos.js';

export const ENVIO = 3.95, ENVIO_GRATIS = 45, MAX_POR_PRODUCTO = 3;

export const ESTADOS = {
  creado:      ['Creado',                    '#EDE7F4', '#463A66'],
  pagado:      ['Pagado',                    '#DCEBE5', '#1F5247'],
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

function fusionarCarritoInvitado() {
  try {
    const invitado = JSON.parse(localStorage.getItem('sensotoys_carrito_invitado')) || [];
    if (invitado.length) {
      const propio = leerCarrito();
      for (const l of invitado) {
        const existente = propio.find((x) => x.variante_id === l.variante_id);
        if (existente) existente.cantidad = Math.min(MAX_POR_PRODUCTO, existente.cantidad + l.cantidad);
        else propio.push({ variante_id: l.variante_id, cantidad: Math.min(MAX_POR_PRODUCTO, l.cantidad) });
      }
      localStorage.setItem(claveCarrito(), JSON.stringify(propio));
    }
    localStorage.removeItem('sensotoys_carrito_invitado');
  } catch {
    localStorage.removeItem('sensotoys_carrito_invitado');
  }
}

// ---------- Cabecera y pie ----------
function pintarContadorCarrito() {
  const el = document.getElementById('contador-carrito');
  if (el) el.textContent = unidadesEnCarrito();
}

export async function pintarMarco() {
  let usuario = null;
  try { usuario = await usuarioActual(); } catch (e) { console.warn(e.message); }
      if (usuario) {
        localStorage.setItem('sensotoys_usuario_id', usuario.id);
        fusionarCarritoInvitado();
      } else {
        localStorage.removeItem('sensotoys_usuario_id');
      }

  // NUEVO: da un id al <main> de la página si no lo tiene, para que el
  // enlace "Saltar al contenido" tenga un destino al que ir.
  const principal = document.querySelector('main');
    if (principal && !principal.id) principal.id = 'contenido-principal';

  document.body.insertAdjacentHTML('afterbegin', `
    <a class="saltar-enlace" href="#contenido-principal">Saltar al contenido</a>
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

export function colorSlug(color) {
  let c = color.replace(/\s*Aurora$/i, '').trim();
  if (c.includes('/')) {
    return c.split('/').map((s) => s.trim().toLowerCase()).join('-');
  }
  return c.split(' ')[0].toLowerCase();
}

// Tarjeta de producto para catálogo e inicio
export function tarjetaProducto(p) {
  const v = p.variantes;
  const desde = Math.min(...v.map((x) => x.precio));
  const stock = v.reduce((a, x) => a + x.stock, 0);
  const precios = new Set(v.map((x) => x.precio)).size;
  const rutaImagen = `img/productos/${p.slug}-${colorSlug(v[0].color)}.webp`;

  return `<a class="card" href="producto.html?slug=${encodeURIComponent(p.slug)}">
    <div class="photo" style="height:160px;background:${v[0]?.color_hex || '#eee'}">
      <img src="${rutaImagen}" alt="${esc(p.descripcion)}" loading="lazy"
           style="width:100%;height:100%;object-fit:contain"
           onerror="this.onerror=function(){this.replaceWith(Object.assign(document.createElement('span'),{textContent:'[Foto]'}))};this.src='img/productos/${p.slug}.webp'">
    </div>
    <div class="row"><span class="tag">${esc(p.categorias.nombre)}</span>${p.es_edicion_limitada ? '<span class="badge">Limitada</span>' : ''}</div>
    <div class="pname">${esc(p.nombre)}</div>
    <div class="row"><span>${precios > 1 ? 'desde ' : ''}${euros(desde)}</span>
      <span class="small muted">${p.es_edicion_limitada ? `Quedan ${stock} de ${p.unidades_edicion}` : `${stock} uds.`}</span></div>
  </a>`;
}



