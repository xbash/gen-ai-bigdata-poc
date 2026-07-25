$RaizProyecto = "C:\rutinas-local\gen-ai-app\bigdata-poc"

New-Item -ItemType Directory -Path $RaizProyecto -Force |
    Out-Null

Set-Location $RaizProyecto

Get-Location

# --->

$Directorios = @(
    "config\hadoop",
    "database\postgresql",
    "database\mysql",
    "database\oracle",
    "ingestion\batch\src",
    "ingestion\realtime\src",
    "connectors\debezium",
    "scripts",
    "data\staging",
    "logs",
    "manifests"
)

foreach ($Directorio in $Directorios) {
    New-Item `
        -ItemType Directory `
        -Path (Join-Path $RaizProyecto $Directorio) `
        -Force |
        Out-Null
}

Get-ChildItem -Path $RaizProyecto -Recurse -Directory |
    Select-Object FullName

# --->

"prueba-montaje-$(Get-Date -Format 'yyyyMMdd-HHmmss')" |
    Set-Content -Path ".\data\staging\prueba.txt" `
        -Encoding UTF8

# --->

$RutaStaging = (Resolve-Path ".\data\staging").Path

podman run --rm `
    --volume "${RutaStaging}:/datos:ro" `
    docker.io/library/alpine:3.22 `
    sh -c "echo 'Contenido montado:'; ls -la /datos; cat /datos/prueba.txt"

# --->

podman version
podman machine list
podman compose version
podman machine inspect

# --->

podman run --rm docker.io/library/alpine:3.22 `
    sh -c "echo 'Podman operativo'; uname -a"

# --->

$RutaStaging = (Resolve-Path `
    "C:\rutinas-local\gen-ai-app\bigdata-poc\data\staging").Path

podman run --rm `
    --volume "${RutaStaging}:/datos:ro" `
    docker.io/library/alpine:3.22 `
    sh -c "ls -la /datos; cat /datos/prueba.txt"

# --->

$Directorios = @(
    "database\postgresql\init",
    "config\hadoop",
    "ingestion\batch\src",
    "ingestion\realtime\src",
    "scripts",
    "logs",
    "manifests"
)

foreach ($Directorio in $Directorios) {
    New-Item -ItemType Directory -Path $Directorio -Force |
        Out-Null
}

# --->

Set-Location "C:\rutinas-local\gen-ai-app\bigdata-poc"

podman compose stop namenode datanode1 datanode2
podman compose rm -f namenode datanode1 datanode2

# --->

podman volume ls |
    Select-String "bigdata_hdfs"

# --->

New-Item `
    -ItemType Directory `
    -Path ".\ingestion\batch\src" `
    -Force |
    Out-Null

New-Item `
    -ItemType Directory `
    -Path ".\data\staging" `
    -Force |
    Out-Null

New-Item `
    -ItemType Directory `
    -Path ".\manifests" `
    -Force |
    Out-Null
# --->

Get-ChildItem `
    -Path ".\data\staging" `
    -Recurse `
    -File |
    Select-Object `
        FullName,
        Length,
        LastWriteTime

# --->

Get-ChildItem `
    -Path ".\manifests" `
    -Filter "*.json" |
    Sort-Object LastWriteTime -Descending
# --->

$UltimoManifiesto = Get-ChildItem `
    -Path ".\manifests" `
    -Filter "*.json" |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

Get-Content $UltimoManifiesto.FullName -Raw |
    ConvertFrom-Json |
    Format-List

# --->

podman exec bigdata-hdfs-namenode `
    bash -c '
      ARCHIVO=$(hdfs dfs -ls -R /data/raw/batch/postgresql/clientes |
        awk "/clientes.csv$/ {print \$8}" |
        tail -1)

      echo "Archivo: ${ARCHIVO}"

      LINEAS=$(hdfs dfs -cat "${ARCHIVO}" | wc -l)

      echo "Líneas totales: ${LINEAS}"
      echo "Registros sin encabezado: $((LINEAS - 1))"
    '

# --->
Set-Location "C:\rutinas-local\gen-ai-app\bigdata-poc"

# --->
New-Item `
    -ItemType File `
    -Path ".\ingestion\batch\src\adaptadores\__init__.py" `
    -Force |
    Out-Null
# --->

Get-ChildItem .\manifests `
    -Filter "manifiesto_batch_postgresql_*.json" |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
# --->
$Motores = @(
    "postgresql",
    "mysql"
)

foreach ($Motor in $Motores) {
    Write-Host ""
    Write-Host "=== MOTOR: $Motor ==="

    $script = @"
      for TABLA in sucursales clientes productos ventas detalle_ventas
      do
        ARCHIVO=\$(hdfs dfs -ls -R /data/raw/batch/$Motor/\${TABLA} 2>/dev/null |
          awk -v tabla="\${TABLA}.csv" '\$NF ~ tabla"$" {print \$NF}' |
          tail -1)

        if [ -n "\${ARCHIVO}" ]; then
          LINEAS=\$(hdfs dfs -cat "\${ARCHIVO}" | wc -l)
          echo "\${TABLA}|\$((LINEAS - 1))"
        else
          echo "\${TABLA}|0 (No encontrado)"
        fi
      done
"@

    $script | podman exec -i bigdata-hdfs-namenode bash -s
}
# --->

$Motores = @(
    "postgresql",
    "mysql"
)

foreach ($Motor in $Motores) {
    Write-Host ""
    Write-Host "=== MOTOR: $Motor ==="

    $ScriptBash = @'
set -e

MOTOR="__MOTOR__"

for TABLA in sucursales clientes productos ventas detalle_ventas
do
    ARCHIVO=$(
        hdfs dfs -ls -R "/data/raw/batch/${MOTOR}/${TABLA}" 2>/dev/null |
        awk -v archivo="${TABLA}.csv" '$NF == archivo {print $NF}' |
        tail -n 1
    )

    if [ -n "${ARCHIVO}" ]; then
        LINEAS=$(hdfs dfs -cat "${ARCHIVO}" | wc -l)
        REGISTROS=$((LINEAS - 1))

        echo "${TABLA}|OK|${REGISTROS}|${ARCHIVO}"
    else
        echo "${TABLA}|ERROR|0|archivo no encontrado"
    fi
done
'@

    $ScriptBash = $ScriptBash.Replace(
        "__MOTOR__",
        $Motor
    )

    $ScriptBash |
        podman exec `
            -i `
            bigdata-hdfs-namenode `
            bash -s

    if ($LASTEXITCODE -ne 0) {
        Write-Error "Falló la validación HDFS para el motor '$Motor'."
        break
    }
}
# --->

# --->