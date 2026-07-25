SET NAMES utf8mb4;
SET time_zone = '+00:00';

CREATE TABLE sucursales (
    sucursal_id INT NOT NULL,
    nombre VARCHAR(100) NOT NULL,
    ciudad VARCHAR(100) NOT NULL,
    activa BOOLEAN NOT NULL DEFAULT TRUE,

    CONSTRAINT pk_sucursales
        PRIMARY KEY (sucursal_id)
) ENGINE=InnoDB;


CREATE TABLE clientes (
    cliente_id INT NOT NULL,
    nombre VARCHAR(150) NOT NULL,
    correo VARCHAR(150) NOT NULL,
    fecha_registro DATE NOT NULL,
    estado VARCHAR(20) NOT NULL,

    CONSTRAINT pk_clientes
        PRIMARY KEY (cliente_id),

    CONSTRAINT uk_clientes_correo
        UNIQUE (correo),

    CONSTRAINT chk_clientes_estado
        CHECK (
            estado IN (
                'ACTIVO',
                'INACTIVO',
                'SUSPENDIDO'
            )
        )
) ENGINE=InnoDB;


CREATE TABLE productos (
    producto_id INT NOT NULL,
    nombre VARCHAR(150) NOT NULL,
    categoria VARCHAR(100) NOT NULL,
    precio DECIMAL(12,2) NOT NULL,
    stock INT NOT NULL,
    activo BOOLEAN NOT NULL DEFAULT TRUE,

    CONSTRAINT pk_productos
        PRIMARY KEY (producto_id),

    CONSTRAINT chk_productos_precio
        CHECK (precio >= 0),

    CONSTRAINT chk_productos_stock
        CHECK (stock >= 0)
) ENGINE=InnoDB;


CREATE TABLE ventas (
    venta_id BIGINT NOT NULL,
    cliente_id INT NOT NULL,
    sucursal_id INT NOT NULL,
    fecha_venta DATETIME NOT NULL,
    estado VARCHAR(20) NOT NULL,
    total DECIMAL(14,2) NOT NULL,

    CONSTRAINT pk_ventas
        PRIMARY KEY (venta_id),

    CONSTRAINT fk_ventas_cliente
        FOREIGN KEY (cliente_id)
        REFERENCES clientes(cliente_id),

    CONSTRAINT fk_ventas_sucursal
        FOREIGN KEY (sucursal_id)
        REFERENCES sucursales(sucursal_id),

    CONSTRAINT chk_ventas_estado
        CHECK (
            estado IN (
                'CREADA',
                'PAGADA',
                'ANULADA'
            )
        ),

    CONSTRAINT chk_ventas_total
        CHECK (total >= 0)
) ENGINE=InnoDB;


CREATE TABLE detalle_ventas (
    detalle_id BIGINT NOT NULL,
    venta_id BIGINT NOT NULL,
    producto_id INT NOT NULL,
    cantidad INT NOT NULL,
    precio_unitario DECIMAL(12,2) NOT NULL,
    subtotal DECIMAL(14,2) NOT NULL,

    CONSTRAINT pk_detalle_ventas
        PRIMARY KEY (detalle_id),

    CONSTRAINT fk_detalle_venta
        FOREIGN KEY (venta_id)
        REFERENCES ventas(venta_id),

    CONSTRAINT fk_detalle_producto
        FOREIGN KEY (producto_id)
        REFERENCES productos(producto_id),

    CONSTRAINT chk_detalle_cantidad
        CHECK (cantidad > 0),

    CONSTRAINT chk_detalle_precio
        CHECK (precio_unitario >= 0),

    CONSTRAINT chk_detalle_subtotal
        CHECK (subtotal >= 0)
) ENGINE=InnoDB;


CREATE INDEX idx_ventas_cliente
    ON ventas(cliente_id);

CREATE INDEX idx_ventas_fecha
    ON ventas(fecha_venta);

CREATE INDEX idx_detalle_venta
    ON detalle_ventas(venta_id);