[CmdletBinding()]
param(
    [string]$DirectorioProyecto = (Get-Location).Path,
    [string[]]$Motores = @("postgresql", "mysql"),
    [switch]$SoloHdfs
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ContenedorNameNode = "bigdata-hdfs-namenode"
$ContenedorPostgreSQL = "bigdata-postgresql"
$ContenedorMySQL = "bigdata-mysql"

$TablasEsperadas = [ordered]@{
    "sucursales"     = 10
    "clientes"       = 500
    "productos"      = 100
    "ventas"         = 5000
    "detalle_ventas" = 15000
}

function Obtener-VariablesEnv {
    param([string]$RutaEnv)

    $resultado = @{}

    foreach ($linea in Get-Content -LiteralPath $RutaEnv) {
        $lineaLimpia = $linea.Trim()

        if (
            [string]::IsNullOrWhiteSpace($lineaLimpia) -or
            $lineaLimpia.StartsWith("#") -or
            -not $lineaLimpia.Contains("=")
        ) {
            continue
        }

        $partes = $lineaLimpia.Split("=", 2)
        $resultado[$partes[0].Trim()] = $partes[1].Trim()
    }

    return $resultado
}

function Probar-Contenedor {
    param([string]$Nombre)

    $estado = podman inspect $Nombre --format "{{.State.Running}}" 2>$null

    if ($LASTEXITCODE -ne 0 -or $estado.Trim() -ne "true") {
        throw "El contenedor '$Nombre' no está ejecutándose."
    }
}

function Obtener-ConteosPostgreSQL {
    $consulta = @"
SELECT 'sucursales', COUNT(*) FROM sucursales
UNION ALL
SELECT 'clientes', COUNT(*) FROM clientes
UNION ALL
SELECT 'productos', COUNT(*) FROM productos
UNION ALL
SELECT 'ventas', COUNT(*) FROM ventas
UNION ALL
SELECT 'detalle_ventas', COUNT(*) FROM detalle_ventas;
"@

    $salida = podman exec $ContenedorPostgreSQL `
        psql -U bigdata -d ventas -At -F "|" -c $consulta

    if ($LASTEXITCODE -ne 0) {
        throw "Falló la consulta de conteos en PostgreSQL."
    }

    $conteos = @{}

    foreach ($linea in $salida) {
        if ($linea -match '^([^|]+)\|(\d+)$') {
            $conteos[$Matches[1]] = [int64]$Matches[2]
        }
    }

    return $conteos
}

function Obtener-ConteosMySQL {
    param([hashtable]$VariablesEnv)

    $consulta = @"
SELECT 'sucursales', COUNT(*) FROM sucursales
UNION ALL
SELECT 'clientes', COUNT(*) FROM clientes
UNION ALL
SELECT 'productos', COUNT(*) FROM productos
UNION ALL
SELECT 'ventas', COUNT(*) FROM ventas
UNION ALL
SELECT 'detalle_ventas', COUNT(*) FROM detalle_ventas;
"@

    $salida = podman exec `
        --env "MYSQL_PWD=$($VariablesEnv['MYSQL_PASSWORD'])" `
        $ContenedorMySQL `
        mysql -u bigdata -D ventas -N -B -e $consulta

    if ($LASTEXITCODE -ne 0) {
        throw "Falló la consulta de conteos en MySQL."
    }

    $conteos = @{}

    foreach ($linea in $salida) {
        $columnas = $linea -split "`t"

        if ($columnas.Count -eq 2 -and $columnas[1] -match '^\d+$') {
            $conteos[$columnas[0]] = [int64]$columnas[1]
        }
    }

    return $conteos
}

function Obtener-UltimoArchivoHdfs {
    param(
        [string]$Motor,
        [string]$Tabla
    )

    $rutaBase = "/data/raw/batch/$Motor/$Tabla"
    $salida = podman exec $ContenedorNameNode hdfs dfs -ls -R $rutaBase 2>$null

    if ($LASTEXITCODE -ne 0) {
        return $null
    }

    $patron = "/$([regex]::Escape($Tabla))\.csv$"

    $linea = $salida |
        Where-Object { $_ -match $patron } |
        Select-Object -Last 1

    if (-not $linea) {
        return $null
    }

    return (($linea -split '\s+')[-1])
}

function Contar-RegistrosCsvHdfs {
    param([string]$RutaHdfs)

    $lineas = @(podman exec $ContenedorNameNode hdfs dfs -cat $RutaHdfs)

    if ($LASTEXITCODE -ne 0) {
        throw "No se pudo leer el archivo HDFS: $RutaHdfs"
    }

    return [Math]::Max(0, $lineas.Count - 1)
}

function Validar-ManifiestoHdfs {
    param([string]$Motor)

    $ruta = "/data/manifests/batch/$Motor"
    $salida = podman exec $ContenedorNameNode hdfs dfs -ls -R $ruta 2>$null

    if ($LASTEXITCODE -ne 0) {
        return $false
    }

    return [bool]($salida | Where-Object { $_ -match 'manifiesto_\d{8}T\d{6}Z\.json$' })
}

$RutaEnv = Join-Path $DirectorioProyecto ".env"

if (-not (Test-Path -LiteralPath $RutaEnv)) {
    throw "No se encontró el archivo .env en: $RutaEnv"
}

$VariablesEnv = Obtener-VariablesEnv -RutaEnv $RutaEnv
Probar-Contenedor -Nombre $ContenedorNameNode

$resultados = New-Object System.Collections.Generic.List[object]

foreach ($motor in $Motores) {
    Write-Host ""
    Write-Host "Validando motor: $motor" -ForegroundColor Cyan

    $conteosOrigen = @{}

    if (-not $SoloHdfs) {
        switch ($motor.ToLowerInvariant()) {
            "postgresql" {
                Probar-Contenedor -Nombre $ContenedorPostgreSQL
                $conteosOrigen = Obtener-ConteosPostgreSQL
            }
            "mysql" {
                Probar-Contenedor -Nombre $ContenedorMySQL
                $conteosOrigen = Obtener-ConteosMySQL -VariablesEnv $VariablesEnv
            }
            default {
                throw "Motor no soportado: $motor"
            }
        }
    }

    foreach ($tabla in $TablasEsperadas.Keys) {
        $rutaArchivo = Obtener-UltimoArchivoHdfs -Motor $motor -Tabla $tabla

        if (-not $rutaArchivo) {
            $resultados.Add([PSCustomObject]@{
                Motor       = $motor
                Tabla       = $tabla
                Estado      = "ERROR"
                FilasOrigen = 0
                FilasHDFS   = 0
                Coincide    = $false
                RutaHDFS    = ""
                Detalle     = "Archivo CSV no encontrado"
            })
            continue
        }

        $filasHdfs = Contar-RegistrosCsvHdfs -RutaHdfs $rutaArchivo

        if ($SoloHdfs) {
            $filasOrigen = [int64]$TablasEsperadas[$tabla]
        }
        elseif ($conteosOrigen.ContainsKey($tabla)) {
            $filasOrigen = [int64]$conteosOrigen[$tabla]
        }
        else {
            $filasOrigen = 0
        }

        $estado = if ($filasOrigen -eq $filasHdfs) { "OK" } else { "ERROR" }

        $resultados.Add([PSCustomObject]@{
            Motor       = $motor
            Tabla       = $tabla
            Estado      = $estado
            FilasOrigen = $filasOrigen
            FilasHDFS   = $filasHdfs
            Coincide    = ($filasOrigen -eq $filasHdfs)
            RutaHDFS    = $rutaArchivo
            Detalle     = ""
        })
    }

    $manifiestoOk = Validar-ManifiestoHdfs -Motor $motor
    Write-Host "Manifiesto HDFS: $(if ($manifiestoOk) { 'OK' } else { 'NO ENCONTRADO' })"
}

Write-Host ""
Write-Host "Resumen de validación" -ForegroundColor Cyan

$resultados |
    Format-Table Motor, Tabla, Estado, FilasOrigen, FilasHDFS, Coincide, RutaHDFS -AutoSize

$errores = @($resultados | Where-Object { $_.Estado -ne "OK" })

Write-Host ""

if ($errores.Count -eq 0) {
    Write-Host "VALIDACIÓN COMPLETADA: todos los conteos coinciden." -ForegroundColor Green
    exit 0
}

Write-Host "VALIDACIÓN CON ERRORES: se detectaron $($errores.Count) diferencias." -ForegroundColor Red
$errores | Format-Table Motor, Tabla, Detalle -AutoSize
exit 1
