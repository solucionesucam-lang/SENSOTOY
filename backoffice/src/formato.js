// Funciones de formato compartidas por las pantallas del back-office

const dinero = new Intl.NumberFormat('es-ES', { style: 'currency', currency: 'EUR' })

export function euros(valor) {
  return dinero.format(Number(valor))
}

export function fecha(valor) {
  if (!valor) return '—'
  return new Date(valor).toLocaleString('es-ES', { dateStyle: 'short', timeStyle: 'short' })
}

// Mismos valores que el check de pedidos_bo.estado en sql/17
export const estadosPedido = ['creado', 'pagado', 'preparacion', 'enviado', 'cancelado', 'incidencia']