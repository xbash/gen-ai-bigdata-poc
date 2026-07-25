from __future__ import annotations

from abc import ABC, abstractmethod
from pathlib import Path
from typing import Any, Iterator


class AdaptadorBaseDatos(ABC):
    """
    Contrato mínimo requerido por el motor común de ingesta.
    """

    def __init__(self, configuracion: dict[str, Any]) -> None:
        self.configuracion = configuracion
        self.conexion: Any | None = None

    @property
    @abstractmethod
    def nombre_motor(self) -> str:
        """Nombre estable utilizado en rutas y manifiestos."""

    @abstractmethod
    def conectar(self) -> None:
        """Abre la conexión con el motor."""

    @abstractmethod
    def cerrar(self) -> None:
        """Cierra la conexión si está abierta."""

    @abstractmethod
    def probar_conexion(self) -> None:
        """Ejecuta una consulta mínima de validación."""

    @abstractmethod
    def contar_filas(self, tabla: str) -> int:
        """Retorna la cantidad de registros de una tabla."""

    @abstractmethod
    def exportar_csv(
        self,
        tabla: str,
        clave_ordenamiento: str,
        ruta_csv: Path,
    ) -> tuple[int, list[str]]:
        """
        Exporta una tabla ordenada a CSV.

        Retorna:
            cantidad de filas exportadas;
            nombres de columnas.
        """

    def __enter__(self) -> "AdaptadorBaseDatos":
        self.conectar()
        return self

    def __exit__(
        self,
        tipo_excepcion: type[BaseException] | None,
        excepcion: BaseException | None,
        traceback: Any,
    ) -> None:
        self.cerrar()