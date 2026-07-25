from __future__ import annotations

from typing import Any

from adaptadores.base import AdaptadorBaseDatos
from adaptadores.mysql import AdaptadorMySQL
from adaptadores.postgresql import AdaptadorPostgreSQL


def crear_adaptador(
    motor: str,
    configuracion: dict[str, Any],
) -> AdaptadorBaseDatos:
    motor_normalizado = motor.strip().lower()

    adaptadores = {
        "postgresql": AdaptadorPostgreSQL,
        "mysql": AdaptadorMySQL,
    }

    clase_adaptador = adaptadores.get(motor_normalizado)

    if clase_adaptador is None:
        motores_soportados = ", ".join(
            sorted(adaptadores.keys())
        )

        raise ValueError(
            f"Motor no soportado: {motor}. "
            f"Motores disponibles: {motores_soportados}"
        )

    return clase_adaptador(configuracion)