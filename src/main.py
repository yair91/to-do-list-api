import logging
import os
from datetime import datetime, timezone

from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field

from db import Database, DatabaseError
from metrics import Metricas

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s %(message)s")


class NuevaTarea(BaseModel):
    title: str = Field(min_length=1, max_length=200)
    done: bool = False


def version():
    return os.environ.get("APP_VERSION", "dev")


def create_app(db=None, metricas=None):
    app = FastAPI(title="to-do-list-api")
    app.state.db = db or Database()
    app.state.metricas = metricas or Metricas()

    @app.get("/tasks")
    def listar(request: Request):
        try:
            return request.app.state.db.listar()
        except DatabaseError:
            request.app.state.metricas.error_db("read")
            raise HTTPException(503, "No se pudo leer de la base de datos")

    @app.post("/tasks", status_code=201)
    def crear(tarea: NuevaTarea, request: Request):
        try:
            creada = request.app.state.db.crear(tarea.title.strip(), tarea.done)
        except DatabaseError:
            request.app.state.metricas.error_db("write")
            raise HTTPException(503, "No se pudo escribir en la base de datos")
        request.app.state.metricas.tarea_creada()
        return creada

    @app.get("/version")
    def get_version():
        return {"version": version()}

    @app.get("/health")
    def health(request: Request):
        try:
            request.app.state.db.ping()
            estado_db = "OK"
        except DatabaseError:
            request.app.state.metricas.error_db("health")
            estado_db = "FAIL"
        cuerpo = {
            "status": "ok" if estado_db == "OK" else "fail",
            "database": estado_db,
            "version": version(),
            "timestamp": datetime.now(timezone.utc).isoformat(),
        }
        return JSONResponse(cuerpo, status_code=200 if estado_db == "OK" else 503)

    return app


app = create_app()
