from __future__ import annotations

import csv
from pathlib import Path
from typing import Any

import psycopg
from psycopg import sql

from adaptadores.base import AdaptadorBaseDatos


class AdaptadorPostgreSQL(AdaptadorBaseDatos):

    @property
    def nombre_motor(self) -> str:
        return "postgresql"

    def conectar(self) -> None:
        self.conexion = psycopg.connect(
            host=self.configuracion["host"],
            port=self.configuracion["puerto"],
            dbname=self.configuracion["base"],
            user=self.configuracion["usuario"],
            password=self.configuracion["contrasena"],
            connect_timeout=5,
        )

    def cerrar(self) -> None:
        if self.conexion is not None:
            self.conexion.close()
            self.conexion = None

    def probar_conexion(self) -> None:
        if self.conexion is None:
            raise RuntimeError("La conexión PostgreSQL no está abierta.")

        with self.conexion.cursor() as cursor:
            cursor.execute("SELECT 1")
            cursor.fetchone()

    def contar_filas(self, tabla: str) -> int:
        if self.conexion is None:
            raise RuntimeError("La conexión PostgreSQL no está abierta.")

        consulta = sql.SQL(
            "SELECT COUNT(*) FROM {}"
        ).format(
            sql.Identifier(tabla)
        )

        with self.conexion.cursor() as cursor:
            cursor.execute(consulta)
            resultado = cursor.fetchone()

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
            raise RuntimeError("La conexión PostgreSQL no está abierta.")

        consulta = sql.SQL(
            "SELECT * FROM {} ORDER BY {}"
        ).format(
            sql.Identifier(tabla),
            sql.Identifier(clave_ordenamiento),
        )

        filas_exportadas = 0

        with self.conexion.cursor(
            name=f"cursor_batch_{tabla}"
        ) as cursor:
            cursor.itersize = 1000
            cursor.execute(consulta)

            columnas = [
                descripcion.name
                for descripcion in cursor.description or []
            ]

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

        return filas_exportadas, columnas