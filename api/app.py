import os
from contextlib import contextmanager

import psycopg2
from fastapi import FastAPI, HTTPException
from psycopg2 import pool

app = FastAPI(title="Records API", version="1.0.0")

DB_HOST = os.environ["DB_HOST"]
DB_PORT = os.environ.get("DB_PORT", "5432")
DB_NAME = os.environ["DB_NAME"]
DB_USER = os.environ["DB_USER"]
DB_PASSWORD = os.environ["DB_PASSWORD"]

connection_pool: pool.ThreadedConnectionPool | None = None


@app.on_event("startup")
def startup() -> None:
    global connection_pool
    connection_pool = pool.ThreadedConnectionPool(
        minconn=1,
        maxconn=10,
        host=DB_HOST,
        port=DB_PORT,
        dbname=DB_NAME,
        user=DB_USER,
        password=DB_PASSWORD,
    )


@app.on_event("shutdown")
def shutdown() -> None:
    if connection_pool is not None:
        connection_pool.closeall()


@contextmanager
def get_db_connection():
    if connection_pool is None:
        raise HTTPException(status_code=503, detail="Database pool not initialized")
    conn = connection_pool.getconn()
    try:
        yield conn
    finally:
        connection_pool.putconn(conn)


@app.get("/health")
def health():
    return {"status": "healthy"}


@app.get("/")
def root():
    return {
        "message": "Records API",
        "endpoints": {
            "health": "/health",
            "records": "/api/records",
        },
    }


@app.get("/api/records")
def get_records():
    try:
        with get_db_connection() as conn:
            with conn.cursor() as cursor:
                cursor.execute(
                    "SELECT id, name, category, value FROM records ORDER BY id"
                )
                rows = cursor.fetchall()
        return {
            "count": len(rows),
            "records": [
                {"id": r[0], "name": r[1], "category": r[2], "value": r[3]}
                for r in rows
            ],
        }
    except psycopg2.Error as exc:
        raise HTTPException(status_code=503, detail="Database unavailable") from exc
