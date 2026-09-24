<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Tienda Online</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: Arial, sans-serif; background-color: #f5f5f5; }
        header { background-color: #333; color: white; padding: 20px; text-align: center; }
        .container { max-width: 1200px; margin: 0 auto; padding: 20px; }
        .productos { display: grid; grid-template-columns: repeat(auto-fit, minmax(250px, 1fr)); gap: 20px; }
        .producto { background: white; padding: 15px; border-radius: 8px; box-shadow: 0 2px 5px rgba(0,0,0,0.1); }
        .producto img { width: 100%; height: 200px; object-fit: cover; border-radius: 5px; }
        .precio { font-size: 1.5em; color: #e74c3c; font-weight: bold; margin: 10px 0; }
        button { background-color: #27ae60; color: white; border: none; padding: 10px 20px; border-radius: 5px; cursor: pointer; width: 100%; }
        button:hover { background-color: #229954; }
        .carrito { background: white; padding: 20px; margin-top: 30px; border-radius: 8px; box-shadow: 0 2px 5px rgba(0,0,0,0.1); }
        .carrito-item { display: flex; justify-content: space-between; padding: 10px 0; border-bottom: 1px solid #ddd; }
        .total { font-size: 1.3em; font-weight: bold; margin-top: 15px; text-align: right; }
    </style>
</head>
<body>
    <header>
        <h1>🛍️ Tienda Online</h1>
    </header>
    
    <div class="container">
        <div class="productos">
            <div class="producto">
                <img src="https://via.placeholder.com/250x200?text=Producto+1" alt="Producto 1">
                <h3>Producto 1</h3>
                <p>Descripción del producto 1</p>
                <div class="precio">$29.99</div>
                <button onclick="agregarCarrito('Producto 1', 29.99)">Agregar al carrito</button>
            </div>
            
            <div class="producto">
                <img src="https://via.placeholder.com/250x200?text=Producto+2" alt="Producto 2">
                <h3>Producto 2</h3>
                <p>Descripción del producto 2</p>
                <div class="precio">$39.99</div>
                <button onclick="agregarCarrito('Producto 2', 39.99)">Agregar al carrito</button>
            </div>
            
            <div class="producto">
                <img src="https://via.placeholder.com/250x200?text=Producto+3" alt="Producto 3">
                <h3>Producto 3</h3>
                <p>Descripción del producto 3</p>
                <div class="precio">$49.99</div>
                <button onclick="agregarCarrito('Producto 3', 49.99)">Agregar al carrito</button>
            </div>
        </div>
        
        <div class="carrito">
            <h2>🛒 Carrito de Compras</h2>
            <div id="carrito-items"></div>
            <div class="total">Total: $<span id="total">0.00</span></div>
            <button style="background-color: #3498db; margin-top: 15px;" onclick="comprar()">Comprar</button>
        </div>
    </div>
    
    <script>
        let carrito = [];
        
        function agregarCarrito(nombre, precio) {
            carrito.push({ nombre, precio });
            actualizarCarrito();
            alert(nombre + ' agregado al carrito');
        }
        
        function actualizarCarrito() {
            const carritoDiv = document.getElementById('carrito-items');
            carritoDiv.innerHTML = '';
            let total = 0;
            
            carrito.forEach((item, index) => {
                total += item.precio;
                carritoDiv.innerHTML += `
                    <div class="carrito-item">
                        <span>${item.nombre}</span>
                        <span>$${item.precio.toFixed(2)}</span>
                        <button style="width: 80px; background-color: #e74c3c;" onclick="eliminarCarrito(${index})">Eliminar</button>
                    </div>
                `;
            });
            
            document.getElementById('total').textContent = total.toFixed(2);
        }
        
        function eliminarCarrito(index) {
            carrito.splice(index, 1);
            actualizarCarrito();
        }
        
        function comprar() {
            if (carrito.length === 0) {
                alert('El carrito está vacío');
                return;
            }
            alert('¡Compra realizada! Total: $' + document.getElementById('total').textContent);
            carrito = [];
            actualizarCarrito();
        }
    </script>
</body>
</html>