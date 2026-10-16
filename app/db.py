"""Database connection: a plain URL on the company server, Secrets Manager in AWS."""
import json
import os

import psycopg
from psycopg.conninfo import make_conninfo

# Same query runs on both sides of the migration; equal results mean equal data.
FINGERPRINT_SQL = (
    "SELECT count(*), coalesce(md5(string_agg(j::text, '|' ORDER BY j.id)), '') FROM jobs j"
)


def conninfo() -> str:
    if url := os.environ.get("DATABASE_URL"):
        return url
    import boto3

    secret = boto3.client("secretsmanager").get_secret_value(SecretId=os.environ["DB_SECRET_ARN"])
    creds = json.loads(secret["SecretString"])
    return make_conninfo(
        host=os.environ["DB_HOST"],
        dbname=os.environ.get("DB_NAME", "jobs"),
        user=creds["username"],
        password=creds["password"],
        sslmode="require",
    )


def connect():
    return psycopg.connect(conninfo(), autocommit=True)


def fingerprint(conn) -> str:
    """Row count and a hash of every row, rendered the same way on any server."""
    conn.execute("SET TIME ZONE 'UTC'")
    count, digest = conn.execute(FINGERPRINT_SQL).fetchone()
    return f"{count} {digest}"


if __name__ == "__main__":
    import sys

    if sys.argv[1:] == ["fingerprint"]:
        print(fingerprint(connect()))
    elif sys.argv[1:] == ["conninfo"]:
        print(conninfo())
