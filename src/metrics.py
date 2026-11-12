import logging
import os

import boto3

log = logging.getLogger("todo.metrics")


class Metricas:
    """Publica metricas propias en CloudWatch con put_metric_data.
    Si falla CloudWatch no se rompe la peticion, solo se registra en el log."""

    def __init__(self, namespace=None, habilitadas=None, region=None):
        self.namespace = namespace or os.environ.get("METRICS_NAMESPACE", "TodoList")
        if habilitadas is None:
            habilitadas = os.environ.get("METRICS_ENABLED", "true").lower() == "true"
        self.habilitadas = habilitadas
        self._cliente = None
        self._region = region or os.environ.get("AWS_REGION", "us-east-1")

    def _cw(self):
        if self._cliente is None:
            self._cliente = boto3.client("cloudwatch", region_name=self._region)
        return self._cliente

    def publicar(self, nombre, valor=1, unidad="Count"):
        if not self.habilitadas:
            return
        try:
            self._cw().put_metric_data(
                Namespace=self.namespace,
                MetricData=[{"MetricName": nombre, "Value": valor, "Unit": unidad}],
            )
        except Exception:
            log.exception("no se pudo publicar la metrica %s", nombre)

    def error_db(self, operacion):
        log.warning("error de base de datos en %s", operacion)
        self.publicar("DbErrors")

    def tarea_creada(self):
        self.publicar("TasksCreated")
