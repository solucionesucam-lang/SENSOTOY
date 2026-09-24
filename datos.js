// =====================================================================
// datos.js — CAPA DE PERSISTENCIA
// Todas las lecturas y escrituras a la base de datos pasan por aquí.
// Las páginas nunca hablan con Supabase directamente.
// =====================================================================
import { createClient } from 'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/+esm';
import { SUPABASE_URL, SUPABASE_KEY } from '../config.js';

export const supabase = createClient(SUPABASE_URL, SUPABASE_KEY);

// Identificador de la visita (para agrupar eventos aunque no haya login)
export function sesionId() {
  let id = localStorage.getItem('sensotoys_sesion');
  if (!id) {
    id = 'ses-' + crypto.randomUUID().slice(0, 13);
    localStorage.setItem('sensotoys_sesion', id);
  }
  return id;
}

// Si Supabase devuelve error, lo lanzamos con su mensaje para mostrarlo
function comprobar({ data, error }) {
  if (error) throw new Error(error.message);
  return data;
}

// ---------- Sesión y perfil ----------
export async function usuarioActual() {
  const { data } = await supabase.auth.getSession();
  const user = data.session?.user;
  if (!user) return null;
  const perfil = comprobar(await supabase.from('perfiles')
    .select('id, email, nombre, rol').eq('id', user.id).maybeSingle());
  return perfil;
}
export async function iniciarSesion(email, password) {
  comprobar(await supabase.auth.signInWithPassword({ email, password }));
}
export async function cerrarSesion() {
  await supabase.auth.signOut();
}

// ---------- Catálogo (lectura pública) ----------
export async function categorias() {
  return comprobar(await supabase.from('categorias')
    .select('id, nombre, slug, descripcion').order('orden'));
}

// Productos con su categoría y sus variantes, en una sola consulta
const CAMPOS_PRODUCTO = `id, nombre, slug, descripcion, material, edad_minima,
  es_edicion_limitada, unidades_edicion,
  categorias ( nombre, slug ),
  variantes ( id, sku, color, color_hex, textura, talla, medida_cm, precio, stock )`;

export async function productos() {
  return comprobar(await supabase.from('productos').select(CAMPOS_PRODUCTO).order('id'));
}
export async function productoPorSlug(slug) {
  return comprobar(await supabase.from('productos')
    .select(CAMPOS_PRODUCTO).eq('slug', slug).maybeSingle());
}
export async function variantesPorId(ids) {
  if (ids.length === 0) return [];
  return comprobar(await supabase.from('variantes')
    .select('id, color, color_hex, talla, precio, stock, productos ( nombre, slug, es_edicion_limitada )')
    .in('id', ids));
}

// ---------- Eventos de navegación ----------
// No bloquea la página: si falla, solo se avisa en la consola.
export async function registrarEvento(tipo, datos = {}) {
  const { error } = await supabase.rpc('registrar_evento',
    { p_tipo: tipo, p_sesion: sesionId(), p_datos: datos });
  if (error) console.warn('No se pudo registrar el evento', tipo, error.message);
}

// ---------- Compra ----------
// Solo enviamos QUÉ se compra; el precio lo pone la base de datos.
export async function crearPedido({ lineas, envio, metodo, tarjeta, cupon }) {
  return comprobar(await supabase.rpc('crear_pedido', {
    p_lineas: lineas, p_envio: envio, p_metodo: metodo,
    p_tarjeta: tarjeta || null, p_cupon: cupon || null, p_sesion: sesionId()
  }));
}

// ---------- Pedidos del cliente (RLS: solo ve los suyos) ----------
export async function misPedidos() {
  return comprobar(await supabase.from('pedidos')
    .select('id, codigo, estado, total, creado_en').order('creado_en', { ascending: false }));
}
export async function pedidoPorCodigo(codigo) {
  return comprobar(await supabase.from('pedidos')
    .select('*, lineas_pedido (*), pagos (*)').eq('codigo', codigo).maybeSingle());
}

// ---------- Postventa ----------
export async function crearIncidencia({ motivo, mensaje, pedidoId }) {
  return comprobar(await supabase.rpc('crear_incidencia', {
    p_motivo: motivo, p_mensaje: mensaje, p_pedido_id: pedidoId || null, p_sesion: sesionId()
  }));
}

// ---------- Back-office (RLS: solo el admin ve todo) ----------
export async function todosLosPedidos() {
  return comprobar(await supabase.from('pedidos')
    .select('*, perfiles ( nombre, email ), lineas_pedido (*), pagos (*)')
    .order('creado_en', { ascending: false }));
}
export async function eventos(limite = 200) {
  return comprobar(await supabase.from('eventos')
    .select('id, tipo, sesion_id, datos, creado_en, perfiles ( email ), pedidos ( codigo )')
    .order('creado_en', { ascending: false }).limit(limite));
}
export async function incidencias() {
  return comprobar(await supabase.from('incidencias')
    .select('*, perfiles ( email ), pedidos ( codigo )').order('creado_en', { ascending: false }));
}
export async function cambiarEstado(pedidoId, estado) {
  comprobar(await supabase.rpc('cambiar_estado_pedido', { p_pedido_id: pedidoId, p_estado: estado }));
}
