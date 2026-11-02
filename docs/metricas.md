# Métricas del cuadro de mando

Todas las métricas del cuadro de mando se calculan con datos reales del back-office (Supabase #2), a partir de las tablas y vistas SQL del propio sistema. Ninguna cifra está escrita a mano.

Los datos del prototipo son de prueba, así que los valores que se ven no son conclusiones de negocio. Lo que se justifica en este documento es **qué se mide y por qué**. Las fuentes son referencias generales de la industria: respaldan la elección de cada métrica, no validan nuestras cifras. Fuentes consultadas el 2 de noviembre de 2026.

## 1. Resumen

| # | Métrica | Dato de origen | Fuente |
|---|---------|----------------|--------|
| M1 | Pedidos totales | Número de filas de `pedidos_bo` | [1] |
| M2 | Importe total | Suma del importe de `pedidos_bo` | [1] |
| M3 | Pedidos por estado | `pedidos_bo` agrupado por estado | [1] |
| M4 | Tickets abiertos | `tickets` con estado abierto | [2] |
| M5 | Integraciones correctas vs. fallidas | `log_integracion`, resultado ok / error | [3], [4] |
| M6 | Propuestas del agente vs. aprobadas | `aprobaciones_agente`, estado final | [5], [6] |
| G1 | Gráfico: pedidos por día (barras) | `pedidos_bo` agrupado por fecha | [1], [7] |

## 2. Justificación de cada métrica

**M1. Pedidos totales.** Cuenta cuántos pedidos ha integrado la tienda en el back-office. Shopify incluye el número de transacciones entre los indicadores básicos de una tienda online y recomienda leerlo junto con los ingresos y el valor medio del pedido, porque el recuento solo no dice si el negocio va bien [1]. En nuestro caso sirve además para comprobar que la integración está llevando los pedidos de la tienda al back-office.

**M2. Importe total.** Suma el importe de los pedidos. Es la métrica de ventas, que [1] lista como indicador de seguimiento por hora, día, semana, mes o año. Se muestra junto a M1 para poder calcular el valor medio de un pedido (ingresos divididos entre número de pedidos), que [1] también define.

**M3. Pedidos por estado.** Muestra cuántos pedidos hay en cada fase (por ejemplo, creado, pagado o enviado). Es una vista operativa de la gestión de pedidos: [1] trata el cumplimiento del pedido como un indicador propio, con la tasa de cumplimiento (pedidos enviados sobre pedidos recibidos). Aquí no calculamos esa tasa, pero el desglose por estado es el dato del que se obtiene.

**M4. Tickets abiertos.** Cuenta las incidencias de postventa que siguen sin resolver. Zendesk define el *backlog* como los tickets abiertos menos los resueltos en un periodo, y explica que sirve para medir la capacidad del equipo y detectar si se está quedando atrás [2]. El mismo artículo propone comparar tickets abiertos y resueltos como "balance de tickets". Elegimos mostrar los abiertos porque son los que requieren acción humana.

**M5. Integraciones correctas vs. fallidas.** Cuenta cuántas ejecuciones de n8n terminaron en `ok` y cuántas en `error`, según `log_integracion`. El libro de Google sobre ingeniería de fiabilidad (SRE) incluye los errores entre las cuatro señales básicas para vigilar un sistema, y los define como la frecuencia con la que fallan las peticiones [3]. Además, la documentación de n8n indica que se consultan las ejecuciones fallidas en su vista de ejecuciones y que se puede asignar un flujo de error que reaccione cuando una ejecución falla [4]. Nuestra métrica traslada esa idea al cuadro de mando: ver de un vistazo si la integración funciona.

**M6. Propuestas del agente vs. aprobadas.** Cuenta cuántas propuestas ha hecho el agente de IA y cuántas ha aprobado una persona (el resto están rechazadas o pendientes). Esta métrica es la evidencia de la supervisión humana. El Marco de Gestión de Riesgos de IA del NIST sugiere recoger datos sobre con qué frecuencia y por qué las personas corrigen o rechazan la salida de una IA en sistemas reales, y pide definir con claridad el papel de la persona que supervisa [5]. El artículo de Anthropic sobre agentes describe el patrón de que el agente se detenga en puntos de control para recibir la opinión de una persona [6], que es lo que hace nuestro flujo con la aprobación por Telegram.

## 3. Gráfico: pedidos por día

El gráfico G1 es de **barras**, con un grupo de barras por día y la altura igual al número de pedidos de ese día. Se eligen barras porque permiten comparar valores día a día; la documentación de Chart.js, la librería que usamos, describe el gráfico de barras como una forma de comparar varios conjuntos de datos lado a lado [7]. Los ingresos por periodo (en este caso, por día) son además un seguimiento habitual en el comercio electrónico [1].

## 4. Fuentes

1. Shopify. *Essential Ecommerce KPIs to Track*. https://www.shopify.com/blog/7365564-32-key-performance-indicators-kpis-for-ecommerce
2. Zendesk. *17 help desk and service desk metrics to measure support performance*. https://www.zendesk.com/blog/top-10-help-desk-metrics
3. Google. *Site Reliability Engineering*, capítulo 6, "Monitoring Distributed Systems". https://sre.google/sre-book/monitoring-distributed-systems/
4. n8n. Documentación: *Handle errors gracefully* (gestión de errores y vistas de ejecuciones). https://docs.n8n.io/flow-logic/error-handling/
5. NIST. *AI Risk Management Framework (AI RMF 1.0)*, 2023, Appendix C: "AI Risk Management and Human-AI Interaction". https://airc.nist.gov/airmf-resources/airmf/appendices/app-c-ai-risk-management-and-human-ai-interaction
6. Anthropic (E. S. y B. Zhang). *Building effective agents*, 19 de diciembre de 2024. https://www.anthropic.com/research/building-effective-agents
7. Chart.js. Documentación: *Bar Chart*. https://www.chartjs.org/docs/latest/charts/bar.html

## 5. Límites

- Los datos son de prueba y de poco volumen; las métricas demuestran el funcionamiento del sistema, no el rendimiento de un negocio real.
- Las fuentes citadas son guías generales (blogs de empresas del sector, documentación técnica y marcos de referencia). Respaldan por qué se mide cada cosa, pero no establecen valores objetivo para esta tienda.
- No se calculan métricas que exigirían datos que el sistema no tiene, como tasa de conversión o tiempos de resolución de tickets.
