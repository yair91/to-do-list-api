import json
import logging
import os

import boto3
import psycopg2
import psycopg2.extras

log = logging.getLogger("todo.db")

SCHEMA = """
CREATE TABLE IF NOT EXISTS tasks (
    id          SERIAL PRIMARY KEY,
    title       VARCHAR(200) NOT NULL,
    done        BOOLEAN      NOT NULL DEFAULT FALSE,
    created_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW()
)
"""


class DatabaseError(Exception):
    pass


def leer_credenciales():
    """Lee las credenciales de RDS desde Secrets Manager (DB_SECRET_ID).
    Sin DB_SECRET_ID usa variables DB_* (solo para desarrollo local)."""
    secret_id = os.environ.get("DB_SECRET_ID")
    if secret_id:
        client = boto3.client("secretsmanager", region_name=os.environ.get("AWS_REGION", "us-east-1"))
        secreto = json.loads(client.get_secret_value(SecretId=secret_id)["SecretString"])
        return {
            "host": secreto["host"],
            "port": int(secreto.get("port", 5432)),
            "dbname": secreto["dbname"],
            "user": secreto["username"],
            "password": secreto["password"],
        }
    return {
        "host": os.environ["DB_HOST"],
        "port": int(os.environ.get("DB_PORT", 5432)),
        "dbname": os.environ["DB_NAME"],
        "user": os.environ["DB_USER"],
        "password": os.environ["DB_PASSWORD"],
    }


class Database:
    def __init__(self, cargar_credenciales=leer_credenciales):
        self._cargar = cargar_credenciales
        self._credenciales = None
        self._esquema_listo = False

    def _conectar(self):
        try:
            if self._credenciales is None:
                self._credenciales = self._cargar()
            conn = psycopg2.connect(**self._credenciales, connect_timeout=3)
        except Exception as e:
            # si cambiaron las credenciales en Secrets Manager se vuelven a leer
            self._credenciales = None
            raise DatabaseError(str(e)) from e
        if not self._esquema_listo:
            try:
                with conn, conn.cursor() as cur:
                    cur.execute(SCHEMA)
                self._esquema_listo = True
            except psycopg2.Error as e:
                conn.close()
                raise DatabaseError(str(e)) from e
        return conn

    def _ejecutar(self, sql, params=None, uno=False):
        conn = self._conectar()
        try:
            with conn, conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
                cur.execute(sql, params)
                if cur.description is None:
                    return None
                return cur.fetchone() if uno else cur.fetchall()
        except psycopg2.Error as e:
            raise DatabaseError(str(e)) from e
        finally:
            conn.close()

    def listar(self):
        filas = self._ejecutar("SELECT id, title, done, created_at FROM tasks ORDER BY id")
        return [dict(f) for f in filas]

    def crear(self, title, done):
        fila = self._ejecutar(
            "INSERT INTO tasks (title, done) VALUES (%s, %s) RETURNING id, title, done, created_at",
            (title, done),
            uno=True,
        )
        return dict(fila)

    def ping(self):
        self._ejecutar("SELECT 1", uno=True)
