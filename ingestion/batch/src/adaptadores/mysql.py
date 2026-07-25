from __future__ import annotations

import csv
from pathlib import Path
from typing import Any

import mysql.connector

from adaptadores.base import AdaptadorBaseDatos


class AdaptadorMySQL(AdaptadorBaseDatos):

    @property
    def nombre_motor(self) -> str:
        return "mysql"

    def conectar(self) -> None:
        self.conexion = mysql.connector.connect(
            host=self.configuracion["host"],
            port=self.configuracion["puerto"],
            database=self.configuracion["base"],
            user=self.configuracion["usuario"],
            password=self.configuracion["contrasena"],
            connection_timeout=5,
            charset="utf8mb4",
            use_unicode=True,
        )

    def cerrar(self) -> None:
        if self.conexion is not None:
            self.conexion.close()
            self.conexion = None

    def probar_conexion(self) -> None:
        if self.conexion is None:
            raise RuntimeError("La conexión MySQL no está abierta.")

        cursor = self.conexion.cursor()

        try:
            cursor.execute("SELECT 1")
            cursor.fetchone()
        finally:
            cursor.close()

    @staticmethod
    def escapar_identificador(identificador: str) -> str:
        if not identificador.replace("_", "").isalnum():
            raise ValueError(
                f"Identificador SQL inválido: {identificador}"
            )

        return f"`{identificador}`"

    def contar_filas(self, tabla: str) -> int:
        if self.conexion is None:
            raise RuntimeError("La conexión MySQL no está abierta.")

        tabla_sql = self.escapar_identificador(tabla)
        cursor = self.conexion.cursor()

        try:
            cursor.execute(
                f"SELECT COUNT(*) FROM {tabla_sql}"
            )
            resultado = cursor.fetchone()
        finally:
            cursor.close()

        if resultado is None:
            raise RuntimeError(
                f"No se pudo contar la tabla {tabla}."
            )

        return int(resultado[0])

    def exportar_csv(
        self,
        tabla: str,
        clave_ordenamiento: str,
        ruta_csv: Path,
    ) -> tuple[int, list[str]]:
        if self.conexion is None:
            raise RuntimeError("La conexión MySQL no está abierta.")

        tabla_sql = self.escapar_identificador(tabla)
        clave_sql = self.escapar_identificador(
            clave_ordenamiento
        )

        cursor = self.conexion.cursor(
            buffered=False,
            raw=False,
        )

        filas_exportadas = 0

        try:
            cursor.execute(
                f"SELECT * "
                f"FROM {tabla_sql} "
                f"ORDER BY {clave_sql}"
            )

            columnas = list(cursor.column_names)

            with ruta_csv.open(
                "w",
                encoding="utf-8",
                newline="",
            ) as archivo:
                escritor = csv.writer(
                    archivo,
                    lineterminator="\n",
                )

                escritor.writerow(columnas)

                for fila in cursor:
                    escritor.writerow(fila)
                    filas_exportadas += 1

        finally:
            cursor.close()

        return filas_exportadas, columnas