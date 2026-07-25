SET SESSION cte_max_recursion_depth = 20000;


INSERT INTO sucursales (
    sucursal_id,
    nombre,
    ciudad,
    activa
)
WITH RECURSIVE numeros AS (
    SELECT 1 AS numero

    UNION ALL

    SELECT numero + 1
    FROM numeros
    WHERE numero < 10
)
SELECT
    numero,
    CONCAT('Sucursal ', numero),
    CASE
        WHEN numero <= 3 THEN 'Santiago'
        WHEN numero <= 5 THEN 'Valparaíso'
        WHEN numero <= 7 THEN 'Concepción'
        ELSE 'Rancagua'
    END,
    TRUE
FROM numeros;


INSERT INTO clientes (
    cliente_id,
    nombre,
    correo,
    fecha_registro,
    estado
)
WITH RECURSIVE numeros AS (
    SELECT 1 AS numero

    UNION ALL

    SELECT numero + 1
    FROM numeros
    WHERE numero < 500
)
SELECT
    numero,
    CONCAT('Cliente ', numero),
    CONCAT('cliente', numero, '@poc.local'),
    DATE_ADD(
        DATE('2024-01-01'),
        INTERVAL MOD(numero - 1, 730) DAY
    ),
    CASE
        WHEN MOD(numero, 20) = 0 THEN 'SUSPENDIDO'
        WHEN MOD(numero, 10) = 0 THEN 'INACTIVO'
        ELSE 'ACTIVO'
    END
FROM numeros;


INSERT INTO productos (
    producto_id,
    nombre,
    categoria,
    precio,
    stock,
    activo
)
WITH RECURSIVE numeros AS (
    SELECT 1 AS numero

    UNION ALL

    SELECT numero + 1
    FROM numeros
    WHERE numero < 100
)
SELECT
    numero,
    CONCAT('Producto ', numero),
    CASE MOD(numero, 4)
        WHEN 0 THEN 'Computación'
        WHEN 1 THEN 'Electrónica'
        WHEN 2 THEN 'Accesorios'
        ELSE 'Oficina'
    END,
    ROUND(1000 + numero * 137.25, 2),
    10 + MOD(numero * 7, 200),
    TRUE
FROM numeros;


INSERT INTO ventas (
    venta_id,
    cliente_id,
    sucursal_id,
    fecha_venta,
    estado,
    total
)
WITH RECURSIVE numeros AS (
    SELECT 1 AS numero

    UNION ALL

    SELECT numero + 1
    FROM numeros
    WHERE numero < 5000
)
SELECT
    numero,
    MOD(numero - 1, 500) + 1,
    MOD(numero - 1, 10) + 1,
    DATE_ADD(
        TIMESTAMP('2025-01-01 08:00:00'),
        INTERVAL (numero - 1) * 10 MINUTE
    ),
    CASE
        WHEN MOD(numero, 30) = 0 THEN 'ANULADA'
        WHEN MOD(numero, 5) = 0 THEN 'CREADA'
        ELSE 'PAGADA'
    END,
    0
FROM numeros;


INSERT INTO detalle_ventas (
    detalle_id,
    venta_id,
    producto_id,
    cantidad,
    precio_unitario,
    subtotal
)
WITH RECURSIVE numeros AS (
    SELECT 1 AS numero

    UNION ALL

    SELECT numero + 1
    FROM numeros
    WHERE numero < 15000
)
SELECT
    n.numero,
    MOD(n.numero - 1, 5000) + 1,
    MOD(n.numero - 1, 100) + 1,
    MOD(n.numero - 1, 4) + 1,
    p.precio,
    ROUND(
        (MOD(n.numero - 1, 4) + 1) * p.precio,
        2
    )
FROM numeros n
JOIN productos p
    ON p.producto_id = MOD(n.numero - 1, 100) + 1;


UPDATE ventas v
JOIN (
    SELECT
        venta_id,
        SUM(subtotal) AS total
    FROM detalle_ventas
    GROUP BY venta_id
) totales
    ON totales.venta_id = v.venta_id
SET v.total = totales.total;