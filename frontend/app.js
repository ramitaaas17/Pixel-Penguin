const middlewareUrl = "http://localhost:8000";

async function listarJugadores() {
    const response = await fetch(middlewareUrl + "/jugadores");
    const jugadores = await response.json();
    const lista = document.getElementById("listaJugadores");
    lista.innerHTML = "";
    jugadores.forEach(function (jugador) {
        const item = document.createElement("li");
        item.textContent = jugador.id + " - " + jugador.nombre + " (monedas: " + jugador.monedas + ")";
        lista.appendChild(item);
    });
}

async function crearJugador() {
    const jugadorNombre = document.getElementById("jugadorNombre").value;
    const jugadorMonedas = parseInt(document.getElementById("jugadorMonedas").value);
    await fetch(middlewareUrl + "/jugadores", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ nombre: jugadorNombre, monedas: jugadorMonedas })
    });
    listarJugadores();
}

async function listarProductos() {
    const response = await fetch(middlewareUrl + "/tienda");
    const productos = await response.json();
    const lista = document.getElementById("listaProductos");
    lista.innerHTML = "";
    productos.forEach(function (producto) {
        const item = document.createElement("li");
        item.textContent = producto.id + " - " + producto.nombre + " $" + producto.precio + " (stock: " + producto.stock + ")";
        lista.appendChild(item);
    });
}

async function crearProducto() {
    const productoNombre = document.getElementById("productoNombre").value;
    const productoPrecio = parseFloat(document.getElementById("productoPrecio").value);
    const productoStock = parseInt(document.getElementById("productoStock").value);
    await fetch(middlewareUrl + "/tienda", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ nombre: productoNombre, precio: productoPrecio, stock: productoStock })
    });
    listarProductos();
}

async function listarPedidos() {
    const response = await fetch(middlewareUrl + "/cafeteria");
    const pedidos = await response.json();
    const lista = document.getElementById("listaPedidos");
    lista.innerHTML = "";
    pedidos.forEach(function (pedido) {
        const item = document.createElement("li");
        item.textContent = pedido.id + " - " + pedido.producto + " x" + pedido.cantidad + " (" + pedido.estado + ")";
        lista.appendChild(item);
    });
}

async function crearPedido() {
    const pedidoProducto = document.getElementById("pedidoProducto").value;
    const pedidoCantidad = parseInt(document.getElementById("pedidoCantidad").value);
    await fetch(middlewareUrl + "/cafeteria", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ producto: pedidoProducto, cantidad: pedidoCantidad })
    });
    listarPedidos();
}
