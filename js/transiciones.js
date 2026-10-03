/* Transiciones entre documentos (View Transitions). Script clásico, sin dependencias,
   cargado en el <head> justo después de css/estilos.css en cada página.

   Por qué en el <head> y después de la hoja de estilos: un script clásico detiene el
   analizador hasta que la hoja está aplicada. Sin él, Chrome dispara «pagereveal» antes de
   que la regla @view-transition { navigation: auto } esté activa, descarta la transición
   («ViewTransition opt-in disabled») y rechaza sus promesas sin que nadie las recoja, lo
   que aparecía como InvalidStateError en consola al navegar con clic. */
(function () {
  'use strict';
  var quieta = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)');
  function nada() {}
  function recoger(t) {
    if (!t) return;
    ['ready', 'finished', 'updateCallbackDone'].forEach(function (k) { if (t[k] && t[k].catch) t[k].catch(nada); });
  }
  function alSalir(e) {
    if (quieta && quieta.matches && e.viewTransition) e.viewTransition.skipTransition();
    recoger(e.viewTransition);
  }
  addEventListener('pageswap', alSalir);
  addEventListener('pagereveal', alSalir);
  // Red de seguridad: una transición descartada por el navegador no debe contar como error de la página
  addEventListener('unhandledrejection', function (e) {
    var r = e.reason;
    if (r && r.name === 'InvalidStateError' && /ViewTransition/i.test(r.message || '')) e.preventDefault();
  });
})();
