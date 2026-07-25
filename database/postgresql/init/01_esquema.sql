CREATE TABLE sucursales (
    sucursal_id INTEGER PRIMARY KEY,
    nombre VARCHAR(100) NOT NULL,
    ciudad VARCHAR(100) NOT NULL,
    activa BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE clientes (
    cliente_id INTEGER PRIMARY KEY,
    nombre VARCHAR(150) NOT NULL,
    correo VARCHAR(150) NOT NULL UNIQUE,
    fecha_registro DATE NOT NULL,
    estado VARCHAR(20) NOT NULL
        CHECK (estado IN ('ACTIVO', 'INACTIVO', 'SUSPENDIDO'))
);

CREATE TABLE productos (
    producto_id INTEGER PRIMARY KEY,
    nombre VARCHAR(150) NOT NULL,
    categoria VARCHAR(100) NOT NULL,
    precio NUMERIC(12,2) NOT NULL CHECK (precio >= 0),
    stock INTEGER NOT NULL CHECK (stock >= 0),
    activo BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE ventas (
    venta_id BIGINT PRIMARY KEY,
    cliente_id INTEGER NOT NULL,
    sucursal_id INTEGER NOT NULL,
    fecha_venta TIMESTAMP NOT NULL,
    estado VARCHAR(20) NOT NULL
        CHECK (estado IN ('CREADA', 'PAGADA', 'ANULADA')),
    total NUMERIC(14,2) NOT NULL CHECK (total >= 0),

    CONSTRAINT fk_ventas_cliente
        FOREIGN KEY (cliente_id)
        REFERENCES clientes(cliente_id),

    CONSTRAINT fk_ventas_sucursal
        FOREIGN KEY (sucursal_id)
        REFERENCES sucursales(sucursal_id)
);

CREATE TABLE detalle_ventas (
    detalle_id BIGINT PRIMARY KEY,
    venta_id BIGINT NOT NULL,
    producto_id INTEGER NOT NULL,
    cantidad INTEGER NOT NULL CHECK (cantidad > 0),
    precio_unitario NUMERIC(12,2) NOT NULL CHECK (precio_unitario >= 0),
    subtotal NUMERIC(14,2) NOT NULL CHECK (subtotal >= 0),

    CONSTRAINT fk_detalle_venta
        FOREIGN KEY (venta_id)
        REFERENCES ventas(venta_id),

    CONSTRAINT fk_detalle_producto
        FOREIGN KEY (producto_id)
        REFERENCES productos(producto_id)
);

CREATE INDEX idx_ventas_cliente
    ON ventas(cliente_id);

CREATE INDEX idx_ventas_fecha
    ON ventas(fecha_venta);

CREATE INDEX idx_detalle_venta
    ON detalle_ventas(venta_id);