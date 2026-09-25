-- =====================================================================
-- SENSOTOYS · Prototipo académico SIE
-- 02_datos_catalogo.sql — Categorías, productos, variantes y cupones
-- Ejecutar después de 01_esquema.sql
-- Todos los datos son ficticios.
-- =====================================================================

insert into categorias (nombre, slug, descripcion, orden) values
  ('Squishies',        'squishies', 'Espuma de recuperación lenta para apretar y relajarse.', 1),
  ('Fidgets',          'fidgets',   'Piezas para mantener las manos ocupadas en silencio.',   2),
  ('Sets sensoriales', 'sets',      'Combinaciones de texturas pensadas para un momento de calma.', 3);


-- Productos (la categoría se busca por su slug para no depender de ids)
insert into productos (categoria_id, nombre, slug, descripcion, material, edad_minima, es_edicion_limitada, unidades_edicion)
select c.id, p.nombre, p.slug, p.descripcion, p.material, p.edad, p.limitada, p.unidades
from (values
  ('squishies', 'Nube Mochi · Edición Aurora', 'nube-mochi-aurora',
   'Squishy de espuma de recuperación lenta con acabado mate y aroma neutro. Vuelve a su forma en unos 4 segundos. Fabricado en una única tirada de 150 unidades numeradas.',
   'Espuma de poliuretano', 6, true, 150),
  ('squishies', 'Nube Mochi', 'nube-mochi',
   'La versión permanente de nuestra nube: tacto suave, recuperación lenta y tres colores pastel.',
   'Espuma de poliuretano', 6, false, null),
  ('squishies', 'Pan de Leche XL', 'pan-de-leche-xl',
   'Squishy con forma de bollo y superficie rugosa que imita la corteza del pan. Ideal para apretar con toda la mano.',
   'Espuma de poliuretano', 6, false, null),
  ('squishies', 'Pulpo Reversible', 'pulpo-reversible',
   'Peluche de doble cara: dale la vuelta para cambiar de color y de expresión.',
   'Poliéster de pelo corto', 3, false, null),
  ('fidgets', 'Cubo Infinito Mate', 'cubo-infinito-mate',
   'Ocho cubos unidos por bisagras que se pliegan sin fin. Movimiento silencioso, apto para clase u oficina.',
   'Plástico ABS', 6, false, null),
  ('fidgets', 'Anillos Magnéticos Trío', 'anillos-magneticos-trio',
   'Tres anillos que giran y se separan con un clic magnético. Acabado satinado. Contiene imanes: no apto para menores de 14 años.',
   'Aleación de aluminio con imanes', 14, false, null),
  ('fidgets', 'Pop It Hexágono', 'pop-it-hexagono',
   'Plancha de burbujas de silicona que se presionan una a una. Se lava con agua y jabón.',
   'Silicona alimentaria', 3, false, null),
  ('sets', 'Set Calma Nocturna', 'set-calma-nocturna',
   'Caja de 4 piezas con texturas mixtas (lisa, rugosa, blanda y granulada) en tonos lavanda. Edición limitada de 80 cajas.',
   'Espuma, silicona y tela', 6, true, 80),
  ('sets', 'Tubo Sensorial Glitter', 'tubo-sensorial-glitter',
   'Tubo sellado con líquido espeso y purpurina que cae despacio. Ayuda a marcar un minuto de pausa.',
   'Plástico PET sellado', 3, false, null)
) as p(cat, nombre, slug, descripcion, material, edad, limitada, unidades)
join categorias c on c.slug = p.cat;


-- Variantes: color + talla, con su precio (IVA incluido) y su stock
insert into variantes (producto_id, sku, color, color_hex, textura, talla, medida_cm, precio, stock)
select pr.id, v.sku, v.color, v.hex, v.textura, v.talla, v.cm, v.precio, v.stock
from (values
  -- Nube Mochi · Edición Aurora (stock total 37 de 150)
  ('nube-mochi-aurora', 'SNS-AUR-ROS-S', 'Rosa Aurora',    '#F2B8C6', 'Mate, tacto lento', 'S',  8, 19.90, 4),
  ('nube-mochi-aurora', 'SNS-AUR-ROS-M', 'Rosa Aurora',    '#F2B8C6', 'Mate, tacto lento', 'M', 12, 24.90, 6),
  ('nube-mochi-aurora', 'SNS-AUR-ROS-L', 'Rosa Aurora',    '#F2B8C6', 'Mate, tacto lento', 'L', 16, 31.50, 3),
  ('nube-mochi-aurora', 'SNS-AUR-MEN-S', 'Menta Aurora',   '#A9D8C8', 'Mate, tacto lento', 'S',  8, 19.90, 5),
  ('nube-mochi-aurora', 'SNS-AUR-MEN-M', 'Menta Aurora',   '#A9D8C8', 'Mate, tacto lento', 'M', 12, 24.90, 5),
  ('nube-mochi-aurora', 'SNS-AUR-MEN-L', 'Menta Aurora',   '#A9D8C8', 'Mate, tacto lento', 'L', 16, 31.50, 3),
  ('nube-mochi-aurora', 'SNS-AUR-LAV-S', 'Lavanda Aurora', '#C9BCE8', 'Mate, tacto lento', 'S',  8, 19.90, 4),
  ('nube-mochi-aurora', 'SNS-AUR-LAV-M', 'Lavanda Aurora', '#C9BCE8', 'Mate, tacto lento', 'M', 12, 24.90, 5),
  ('nube-mochi-aurora', 'SNS-AUR-LAV-L', 'Lavanda Aurora', '#C9BCE8', 'Mate, tacto lento', 'L', 16, 31.50, 2),
  -- Nube Mochi (stock total 58)
  ('nube-mochi', 'SNS-NUB-ROS-S', 'Rosa',    '#F7CBD5', 'Lisa, tacto lento', 'S',  8,  9.90, 7),
  ('nube-mochi', 'SNS-NUB-ROS-M', 'Rosa',    '#F7CBD5', 'Lisa, tacto lento', 'M', 12, 12.90, 8),
  ('nube-mochi', 'SNS-NUB-ROS-L', 'Rosa',    '#F7CBD5', 'Lisa, tacto lento', 'L', 16, 15.90, 5),
  ('nube-mochi', 'SNS-NUB-CRE-S', 'Crema',   '#F3E6CF', 'Lisa, tacto lento', 'S',  8,  9.90, 6),
  ('nube-mochi', 'SNS-NUB-CRE-M', 'Crema',   '#F3E6CF', 'Lisa, tacto lento', 'M', 12, 12.90, 7),
  ('nube-mochi', 'SNS-NUB-CRE-L', 'Crema',   '#F3E6CF', 'Lisa, tacto lento', 'L', 16, 15.90, 5),
  ('nube-mochi', 'SNS-NUB-CEL-S', 'Celeste', '#CFE3F2', 'Lisa, tacto lento', 'S',  8,  9.90, 7),
  ('nube-mochi', 'SNS-NUB-CEL-M', 'Celeste', '#CFE3F2', 'Lisa, tacto lento', 'M', 12, 12.90, 8),
  ('nube-mochi', 'SNS-NUB-CEL-L', 'Celeste', '#CFE3F2', 'Lisa, tacto lento', 'L', 16, 15.90, 5),
  -- Pan de Leche XL (24)
  ('pan-de-leche-xl', 'SNS-PAN-DOR-L', 'Dorado tostado', '#F6D9A8', 'Rugosa', 'L', 18, 18.50, 24),
  -- Pulpo Reversible (73)
  ('pulpo-reversible', 'SNS-PUL-ROA-S', 'Rosa / Azul',       '#EFC3E0', 'Pelo corto, doble cara', 'S', 10, 9.95, 40),
  ('pulpo-reversible', 'SNS-PUL-VEA-S', 'Verde / Amarillo',  '#C9E3A9', 'Pelo corto, doble cara', 'S', 10, 9.95, 33),
  -- Cubo Infinito Mate (41)
  ('cubo-infinito-mate', 'SNS-CUB-VER-S', 'Verde salvia', '#A9D8C8', 'Mate', 'S', 4, 14.00, 22),
  ('cubo-infinito-mate', 'SNS-CUB-GRI-S', 'Gris piedra',  '#D5D0C9', 'Mate', 'S', 4, 14.00, 19),
  -- Anillos Magnéticos Trío (65)
  ('anillos-magneticos-trio', 'SNS-ANI-AZU-U', 'Azul acero', '#B7D3E8', 'Satinada', 'Única', 3, 11.20, 35),
  ('anillos-magneticos-trio', 'SNS-ANI-PLA-U', 'Plata',      '#D9D9D9', 'Satinada', 'Única', 3, 11.20, 30),
  -- Pop It Hexágono (90)
  ('pop-it-hexagono', 'SNS-POP-VER-M', 'Verde lima',  '#C9E3A9', 'Silicona blanda', 'M', 13, 7.90, 30),
  ('pop-it-hexagono', 'SNS-POP-ROS-M', 'Rosa chicle', '#F4B6C8', 'Silicona blanda', 'M', 13, 7.90, 30),
  ('pop-it-hexagono', 'SNS-POP-AZU-M', 'Azul cielo',  '#B7D3E8', 'Silicona blanda', 'M', 13, 7.90, 30),
  -- Set Calma Nocturna (12 de 80)
  ('set-calma-nocturna', 'SNS-SET-LAV-U', 'Lavanda noche', '#C9BCE8', 'Mixta (4 texturas)', 'Única', null, 29.90, 12),
  -- Tubo Sensorial Glitter (36)
  ('tubo-sensorial-glitter', 'SNS-TUB-TUR-L', 'Turquesa', '#BFD8D2', 'Líquido lento', 'L', 20, 10.50, 18),
  ('tubo-sensorial-glitter', 'SNS-TUB-DOR-L', 'Dorado',   '#EAD9A6', 'Líquido lento', 'L', 20, 10.50, 18)
) as v(producto, sku, color, hex, textura, talla, cm, precio, stock)
join productos pr on pr.slug = v.producto;


-- Cupones de prueba (uno válido y uno caducado para probar la validación)
insert into cupones (codigo, descripcion, tipo, valor, importe_minimo, valido_hasta, activo) values
  ('BIENVENIDA10', '10 % de descuento en pedidos desde 20 €', 'porcentaje', 10,   20, null,         true),
  ('VERANO5',      '5 € de descuento (campaña terminada)',    'importe',     5,   30, '2026-08-31', true);


-- Comprobación: en ediciones limitadas, el stock no puede superar la tirada
select p.nombre, p.unidades_edicion as tirada, sum(v.stock) as quedan
from productos p join variantes v on v.producto_id = p.id
where p.es_edicion_limitada
group by p.id, p.nombre, p.unidades_edicion;
