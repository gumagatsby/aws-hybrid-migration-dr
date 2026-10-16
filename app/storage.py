"""Where uploaded files live: a local folder on the company server, or S3 in AWS."""
import os
import re
from pathlib import Path

SAFE_NAME = re.compile(r"[^A-Za-z0-9._-]")


def safe_filename(name: str) -> str:
    """Strip anything that could escape the uploads folder or break an S3 key."""
    base = os.path.basename(name or "").strip()
    base = SAFE_NAME.sub("_", base).lstrip(".")
    return base[:120] or "file"


class LocalStore:
    def __init__(self, root: str):
        self.root = Path(root)
        self.root.mkdir(parents=True, exist_ok=True)

    def put(self, key: str, data: bytes) -> None:
        path = self.root / key
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)

    def get(self, key: str) -> bytes:
        return (self.root / key).read_bytes()


class S3Store:
    def __init__(self, bucket: str, prefix: str = "uploads/"):
        import boto3

        self.s3 = boto3.client("s3")
        self.bucket = bucket
        self.prefix = prefix

    def put(self, key: str, data: bytes) -> None:
        self.s3.put_object(Bucket=self.bucket, Key=self.prefix + key, Body=data)

    def get(self, key: str) -> bytes:
        return self.s3.get_object(Bucket=self.bucket, Key=self.prefix + key)["Body"].read()


def from_env():
    if os.environ.get("STORAGE", "local") == "s3":
        return S3Store(os.environ["BUCKET"])
    return LocalStore(os.environ.get("UPLOAD_DIR", "/data/uploads"))
