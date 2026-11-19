import sys
from datetime import datetime, timezone
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "src"))

from db import DatabaseError  # noqa: E402
from main import create_app  # noqa: E402


class DbFalsa:
    def __init__(self):
        self.tareas = []
        self.caida = False

    def _revisar(self):
        if self.caida:
            raise DatabaseError("connection refused")

    def listar(self):
        self._revisar()
        return list(self.tareas)

    def crear(self, title, done):
        self._revisar()
        tarea = {
            "id": len(self.tareas) + 1,
            "title": title,
            "done": done,
            "created_at": datetime.now(timezone.utc).isoformat(),
        }
        self.tareas.append(tarea)
        return tarea

    def ping(self):
        self._revisar()


class MetricasFalsas:
    def __init__(self):
        self.publicadas = []

    def error_db(self, operacion):
        self.publicadas.append(("DbErrors", operacion))

    def tarea_creada(self):
        self.publicadas.append(("TasksCreated", None))


@pytest.fixture
def ctx(monkeypatch):
    monkeypatch.setenv("APP_VERSION", "v1.2.3")
    db, metricas = DbFalsa(), MetricasFalsas()
    return TestClient(create_app(db=db, metricas=metricas)), db, metricas


def test_crear_y_listar_tareas(ctx):
    client, _, metricas = ctx
    res = client.post("/tasks", json={"title": "estudiar para el examen", "done": False})
    assert res.status_code == 201
    assert res.json()["title"] == "estudiar para el examen"

    res = client.get("/tasks")
    assert res.status_code == 200
    assert [t["title"] for t in res.json()] == ["estudiar para el examen"]
    assert ("TasksCreated", None) in metricas.publicadas


def test_crear_tarea_sin_titulo_es_invalido(ctx):
    client, db, _ = ctx
    assert client.post("/tasks", json={"done": True}).status_code == 422
    assert client.post("/tasks", json={"title": ""}).status_code == 422
    assert db.tareas == []


def test_version_viene_de_variable_de_ambiente(ctx):
    client, _, _ = ctx
    assert client.get("/version").json() == {"version": "v9.9.9"}


def test_health_ok(ctx):
    client, _, _ = ctx
    res = client.get("/health")
    body = res.json()
    assert res.status_code == 200
    assert body["database"] == "OK"
    assert body["version"] == "v1.2.3"
    datetime.fromisoformat(body["timestamp"])


def test_health_fail_si_la_base_esta_caida(ctx):
    client, db, metricas = ctx
    db.caida = True
    res = client.get("/health")
    assert res.status_code == 503
    assert res.json()["database"] == "FAIL"
    assert ("DbErrors", "health") in metricas.publicadas


def test_errores_de_lectura_y_escritura_publican_metrica(ctx):
    client, db, metricas = ctx
    db.caida = True
    assert client.get("/tasks").status_code == 503
    assert client.post("/tasks", json={"title": "x"}).status_code == 503
    assert ("DbErrors", "read") in metricas.publicadas
    assert ("DbErrors", "write") in metricas.publicadas
    assert ("TasksCreated", None) not in metricas.publicadas
