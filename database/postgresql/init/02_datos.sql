INSERT INTO sucursales (
    sucursal_id,
    nombre,
    ciudad,
    activa
)
SELECT
    numero,
    'Sucursal ' || numero,
    CASE
        WHEN numero <= 3 THEN 'Santiago'
        WHEN numero <= 5 THEN 'Valparaíso'
        WHEN numero <= 7 THEN 'Concepción'
        ELSE 'Rancagua'
    END,
    TRUE
FROM generate_series(1, 10) AS numero;


INSERT INTO clientes (
    cliente_id,
    nombre,
    correo,
    fecha_registro,
    estado
)
SELECT
    numero,
    'Cliente ' || numero,
    'cliente' || numero || '@poc.local',
    DATE '2024-01-01' + ((numero - 1) % 730),
    CASE
        WHEN numero % 20 = 0 THEN 'SUSPENDIDO'
        WHEN numero % 10 = 0 THEN 'INACTIVO'
        ELSE 'ACTIVO'
    END
FROM generate_series(1, 500) AS numero;


INSERT INTO productos (
    producto_id,
    nombre,
    categoria,
    precio,
    stock,
    activo
)
SELECT
    numero,
    'Producto ' || numero,
    CASE
        WHEN numero % 4 = 0 THEN 'Computación'
        WHEN numero % 4 = 1 THEN 'Electrónica'
        WHEN numero % 4 = 2 THEN 'Accesorios'
        ELSE 'Oficina'
    END,
    ROUND((1000 + numero * 137.25)::NUMERIC, 2),
    10 + ((numero * 7) % 200),
    TRUE
FROM generate_series(1, 100) AS numero;


INSERT INTO ventas (
    venta_id,
    cliente_id,
    sucursal_id,
    fecha_venta,
    estado,
    total
)
SELECT
    numero,
    ((numero - 1) % 500) + 1,
    ((numero - 1) % 10) + 1,
    TIMESTAMP '2025-01-01 08:00:00'
        + ((numero - 1) * INTERVAL '10 minutes'),
    CASE
        WHEN numero % 30 = 0 THEN 'ANULADA'
        WHEN numero % 5 = 0 THEN 'CREADA'
        ELSE 'PAGADA'
    END,
    0
FROM generate_series(1, 5000) AS numero;


INSERT INTO detalle_ventas (
    detalle_id,
    venta_id,
    producto_id,
    cantidad,
    precio_unitario,
    subtotal
)
SELECT
    numero,
    ((numero - 1) % 5000) + 1,
    ((numero - 1) % 100) + 1,
    ((numero - 1) % 4) + 1,
    p.precio,
    ROUND(
        (
            (((numero - 1) % 4) + 1)
            * p.precio
        )::NUMERIC,
        2
    )
FROM generate_series(1, 15000) AS numero
JOIN productos p
    ON p.producto_id = ((numero - 1) % 100) + 1;


UPDATE ventas v
SET total = totales.total
FROM (
    SELECT
        venta_id,
        SUM(subtotal) AS total
    FROM detalle_ventas
    GROUP BY venta_id
) AS totales
WHERE v.venta_id = totales.venta_id;