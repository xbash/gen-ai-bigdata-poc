from __future__ import annotations

import hashlib
import json
import logging
import os
import sys
import time
from dataclasses import asdict, dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any
from urllib.parse import quote

import requests

from adaptadores.base import AdaptadorBaseDatos
from adaptadores.fabrica import crear_adaptador


TABLAS: dict[str, str] = {
    "sucursales": "sucursal_id",
    "clientes": "cliente_id",
    "productos": "producto_id",
    "ventas": "venta_id",
    "detalle_ventas": "detalle_id",
}

DIRECTORIO_STAGING = Path("/app/data/staging")
DIRECTORIO_MANIFIESTOS = Path("/app/manifests")

TIEMPO_ESPERA_SEGUNDOS = 120
INTERVALO_REINTENTO_SEGUNDOS = 5


@dataclass
class ResultadoTabla:
    tabla: str
    clave_ordenamiento: str
    filas_origen: int
    filas_exportadas: int
    columnas: list[str]
    archivo_local: str
    archivo_hdfs: str
    tamano_bytes: int
    sha256: str
    estado: str
    duracion_segundos: float
    error: str | None = None


def configurar_logging() -> None:
    logging.basicConfig(
        level=logging.INFO,
        format=(
            "%(asctime)s | %(levelname)s | "
            "%(name)s | %(message)s"
        ),
        datefmt="%Y-%m-%dT%H:%M:%S",
    )


def obtener_variable(nombre: str) -> str:
    valor = os.getenv(nombre)

    if not valor:
        raise RuntimeError(
            f"La variable obligatoria '{nombre}' no está definida."
        )

    return valor


def construir_configuracion() -> dict[str, Any]:
    return {
        "motor": obtener_variable("MOTOR_ORIGEN").lower(),
        "base_datos": {
            "host": obtener_variable("DB_HOST"),
            "puerto": int(obtener_variable("DB_PORT")),
            "base": obtener_variable("DB_NAME"),
            "usuario": obtener_variable("DB_USER"),
            "contrasena": obtener_variable("DB_PASSWORD"),
        },
        "webhdfs_url": obtener_variable(
            "WEBHDFS_URL"
        ).rstrip("/"),
        "usuario_hdfs": os.getenv("HDFS_USER", "root"),
    }


def esperar_motor(
    adaptador: AdaptadorBaseDatos,
) -> None:
    logger = logging.getLogger("esperar_motor")
    limite = time.monotonic() + TIEMPO_ESPERA_SEGUNDOS

    while time.monotonic() < limite:
        try:
            adaptador.conectar()
            adaptador.probar_conexion()

            logger.info(
                "%s está disponible.",
                adaptador.nombre_motor,
            )
            return

        except Exception as error:
            adaptador.cerrar()

            logger.warning(
                "%s aún no está disponible: %s",
                adaptador.nombre_motor,
                error,
            )

            time.sleep(INTERVALO_REINTENTO_SEGUNDOS)

    raise TimeoutError(
        f"{adaptador.nombre_motor} no estuvo disponible "
        "dentro del tiempo esperado."
    )


def construir_url_webhdfs(
    configuracion: dict[str, Any],
    ruta_hdfs: str,
    operacion: str,
    **parametros: str,
) -> str:
    ruta_codificada = quote(ruta_hdfs, safe="/")

    argumentos = {
        "op": operacion,
        "user.name": configuracion["usuario_hdfs"],
        **parametros,
    }

    consulta = "&".join(
        f"{quote(str(clave))}={quote(str(valor))}"
        for clave, valor in argumentos.items()
    )

    return (
        f"{configuracion['webhdfs_url']}"
        f"/webhdfs/v1{ruta_codificada}?{consulta}"
    )


def crear_directorio_hdfs(
    configuracion: dict[str, Any],
    ruta_hdfs: str,
) -> None:
    respuesta = requests.put(
        construir_url_webhdfs(
            configuracion,
            ruta_hdfs,
            "MKDIRS",
        ),
        timeout=30,
    )

    respuesta.raise_for_status()

    if not respuesta.json().get("boolean", False):
        raise RuntimeError(
            f"No se pudo crear el directorio HDFS {ruta_hdfs}"
        )


def subir_archivo_hdfs(
    configuracion: dict[str, Any],
    ruta_local: Path,
    ruta_hdfs: str,
) -> None:
    respuesta_inicial = requests.put(
        construir_url_webhdfs(
            configuracion,
            ruta_hdfs,
            "CREATE",
            overwrite="false",
        ),
        allow_redirects=False,
        timeout=30,
    )

    if respuesta_inicial.status_code != 307:
        raise RuntimeError(
            "WebHDFS no devolvió HTTP 307. "
            f"HTTP={respuesta_inicial.status_code}; "
            f"respuesta={respuesta_inicial.text[:300]}"
        )

    ubicacion = respuesta_inicial.headers.get("Location")

    if not ubicacion:
        raise RuntimeError(
            "WebHDFS no informó el DataNode de destino."
        )

    with ruta_local.open("rb") as archivo:
        respuesta_carga = requests.put(
            ubicacion,
            data=archivo,
            timeout=300,
        )

    respuesta_carga.raise_for_status()


def calcular_sha256(ruta_archivo: Path) -> str:
    digest = hashlib.sha256()

    with ruta_archivo.open("rb") as archivo:
        for bloque in iter(
            lambda: archivo.read(1024 * 1024),
            b"",
        ):
            digest.update(bloque)

    return digest.hexdigest()


def procesar_tabla(
    adaptador: AdaptadorBaseDatos,
    configuracion: dict[str, Any],
    tabla: str,
    clave: str,
    id_ejecucion: str,
    fecha_carga: str,
    directorio_ejecucion: Path,
) -> ResultadoTabla:
    logger = logging.getLogger(f"tabla.{tabla}")
    inicio = time.monotonic()

    motor = adaptador.nombre_motor
    ruta_local = directorio_ejecucion / f"{tabla}.csv"

    directorio_hdfs = (
        f"/data/raw/batch/{motor}/{tabla}"
        f"/fecha_carga={fecha_carga}"
        f"/id_ejecucion={id_ejecucion}"
    )

    archivo_hdfs = f"{directorio_hdfs}/{tabla}.csv"

    try:
        filas_origen = adaptador.contar_filas(tabla)

        filas_exportadas, columnas = adaptador.exportar_csv(
            tabla=tabla,
            clave_ordenamiento=clave,
            ruta_csv=ruta_local,
        )

        if filas_origen != filas_exportadas:
            raise RuntimeError(
                "Diferencia de conteo: "
                f"origen={filas_origen}, "
                f"exportadas={filas_exportadas}"
            )

        sha256 = calcular_sha256(ruta_local)
        tamano = ruta_local.stat().st_size

        crear_directorio_hdfs(
            configuracion,
            directorio_hdfs,
        )

        subir_archivo_hdfs(
            configuracion,
            ruta_local,
            archivo_hdfs,
        )

        duracion = round(
            time.monotonic() - inicio,
            3,
        )

        logger.info(
            "motor=%s tabla=%s filas=%d bytes=%d",
            motor,
            tabla,
            filas_exportadas,
            tamano,
        )

        return ResultadoTabla(
            tabla=tabla,
            clave_ordenamiento=clave,
            filas_origen=filas_origen,
            filas_exportadas=filas_exportadas,
            columnas=columnas,
            archivo_local=str(ruta_local),
            archivo_hdfs=archivo_hdfs,
            tamano_bytes=tamano,
            sha256=sha256,
            estado="OK",
            duracion_segundos=duracion,
        )

    except Exception as error:
        logger.exception(
            "Falló la tabla %s del motor %s.",
            tabla,
            motor,
        )

        return ResultadoTabla(
            tabla=tabla,
            clave_ordenamiento=clave,
            filas_origen=0,
            filas_exportadas=0,
            columnas=[],
            archivo_local=str(ruta_local),
            archivo_hdfs=archivo_hdfs,
            tamano_bytes=0,
            sha256="",
            estado="ERROR",
            duracion_segundos=round(
                time.monotonic() - inicio,
                3,
            ),
            error=str(error),
        )


def guardar_manifiesto(
    configuracion: dict[str, Any],
    motor: str,
    manifiesto: dict[str, Any],
    id_ejecucion: str,
    fecha_carga: str,
) -> Path:
    ruta_local = (
        DIRECTORIO_MANIFIESTOS
        / f"manifiesto_batch_{motor}_{id_ejecucion}.json"
    )

    with ruta_local.open(
        "w",
        encoding="utf-8",
    ) as archivo:
        json.dump(
            manifiesto,
            archivo,
            ensure_ascii=False,
            indent=2,
        )

    directorio_hdfs = (
        f"/data/manifests/batch/{motor}"
        f"/fecha_carga={fecha_carga}"
    )

    archivo_hdfs = (
        f"{directorio_hdfs}/"
        f"manifiesto_{id_ejecucion}.json"
    )

    crear_directorio_hdfs(
        configuracion,
        directorio_hdfs,
    )

    subir_archivo_hdfs(
        configuracion,
        ruta_local,
        archivo_hdfs,
    )

    return ruta_local


def main() -> int:
    configurar_logging()
    logger = logging.getLogger("ingesta_batch")

    configuracion = construir_configuracion()
    motor = configuracion["motor"]

    fecha_inicio = datetime.now(timezone.utc)
    id_ejecucion = fecha_inicio.strftime("%Y%m%dT%H%M%SZ")
    fecha_carga = fecha_inicio.strftime("%Y-%m-%d")

    directorio_ejecucion = (
        DIRECTORIO_STAGING
        / motor
        / id_ejecucion
    )

    directorio_ejecucion.mkdir(
        parents=True,
        exist_ok=False,
    )

    adaptador = crear_adaptador(
        motor,
        configuracion["base_datos"],
    )

    resultados: list[ResultadoTabla] = []

    try:
        esperar_motor(adaptador)

        for tabla, clave in TABLAS.items():
            resultados.append(
                procesar_tabla(
                    adaptador=adaptador,
                    configuracion=configuracion,
                    tabla=tabla,
                    clave=clave,
                    id_ejecucion=id_ejecucion,
                    fecha_carga=fecha_carga,
                    directorio_ejecucion=directorio_ejecucion,
                )
            )

        fecha_fin = datetime.now(timezone.utc)

        tablas_error = [
            resultado.tabla
            for resultado in resultados
            if resultado.estado != "OK"
        ]

        estado = "OK" if not tablas_error else "ERROR"

        manifiesto = {
            "version_manifiesto": "1.1",
            "tipo_ingesta": "batch",
            "motor_origen": motor,
            "id_ejecucion": id_ejecucion,
            "fecha_inicio_utc": fecha_inicio.isoformat(),
            "fecha_fin_utc": fecha_fin.isoformat(),
            "estado": estado,
            "tablas_con_error": tablas_error,
            "cantidad_tablas": len(resultados),
            "filas_totales_origen": sum(
                resultado.filas_origen
                for resultado in resultados
            ),
            "filas_totales_exportadas": sum(
                resultado.filas_exportadas
                for resultado in resultados
            ),
            "resultados": [
                asdict(resultado)
                for resultado in resultados
            ],
        }

        ruta_manifiesto = guardar_manifiesto(
            configuracion=configuracion,
            motor=motor,
            manifiesto=manifiesto,
            id_ejecucion=id_ejecucion,
            fecha_carga=fecha_carga,
        )

        logger.info(
            "motor=%s estado=%s filas=%d manifiesto=%s",
            motor,
            estado,
            manifiesto["filas_totales_exportadas"],
            ruta_manifiesto,
        )

        return 0 if estado == "OK" else 1

    except Exception:
        logger.exception(
            "La ingesta batch de %s falló.",
            motor,
        )
        return 2

    finally:
        adaptador.cerrar()


if __name__ == "__main__":
    sys.exit(main())