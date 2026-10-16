"""Job tracker: the small line-of-business app being migrated."""
import os
import uuid
from pathlib import Path

from flask import Flask, Response, abort, jsonify, redirect, render_template_string, request

import db
import storage

app = Flask(__name__)
app.config["MAX_CONTENT_LENGTH"] = 5 * 1024 * 1024
store = storage.from_env()
SITE = os.environ.get("SITE_NAME", "company server")


def ensure_schema():
    """Create the tables on a new, empty database; harmless when they already exist."""
    try:
        with db.connect() as conn:
            conn.execute((Path(__file__).parent / "schema.sql").read_text())
    except Exception:  # database not reachable yet; /health will report it
        pass


ensure_schema()

PAGE = """<!doctype html><meta charset="utf-8"><title>Jobs</title>
<style>body{font:15px system-ui,sans-serif;margin:32px;color:#16191f}table{border-collapse:collapse}
td,th{padding:4px 10px;border-bottom:1px solid #e3e6ea;text-align:left}small{color:#5f6b7a}</style>
<h1>Jobs</h1><p><small>Served from {{ site }}. {{ count }} jobs.</small></p>
<form method="post" action="/jobs" enctype="multipart/form-data">
<input name="customer" placeholder="Customer" required> <input name="site" placeholder="Site" required>
<input name="description" placeholder="Work" required> <input type="file" name="attachment">
<button>Add job</button></form>
<table><tr><th>#</th><th>Customer</th><th>Site</th><th>Work</th><th>Status</th><th>File</th></tr>
{% for j in jobs %}<tr><td>{{ j[0] }}</td><td>{{ j[1] }}</td><td>{{ j[2] }}</td><td>{{ j[3] }}</td>
<td>{{ j[4] }}</td><td>{% if j[5] %}<a href="/files/{{ j[5] }}">{{ j[5].split('/')[-1] }}</a>{% endif %}</td></tr>
{% endfor %}</table>"""


@app.get("/")
def index():
    with db.connect() as conn:
        count = conn.execute("SELECT count(*) FROM jobs").fetchone()[0]
        jobs = conn.execute(
            "SELECT id, customer, site, description, status, attachment FROM jobs ORDER BY id DESC LIMIT 50"
        ).fetchall()
    return render_template_string(PAGE, jobs=jobs, count=count, site=SITE)


@app.post("/jobs")
def create_job():
    form = request.form
    if not all(form.get(f, "").strip() for f in ("customer", "site", "description")):
        abort(400)
    key = None
    upload = request.files.get("attachment")
    if upload and upload.filename:
        key = f"{uuid.uuid4().hex[:8]}/{storage.safe_filename(upload.filename)}"
        store.put(key, upload.read())
    with db.connect() as conn:
        conn.execute(
            "INSERT INTO jobs (customer, site, description, attachment) VALUES (%s, %s, %s, %s)",
            (form["customer"].strip(), form["site"].strip(), form["description"].strip(), key),
        )
    return redirect("/", code=303)


@app.get("/files/<path:key>")
def file(key):
    if ".." in key.split("/"):
        abort(404)
    try:
        data = store.get(key)
    except Exception:
        abort(404)
    return Response(data, mimetype="application/octet-stream",
                    headers={"Content-Disposition": f"attachment; filename={key.split('/')[-1]}"})


@app.post("/heartbeat")
def heartbeat():
    with db.connect() as conn:
        row = conn.execute("INSERT INTO heartbeat DEFAULT VALUES RETURNING id, written_at").fetchone()
    return jsonify(id=row[0], written_at=row[1].isoformat())


@app.get("/health")
def health():
    with db.connect() as conn:
        jobs = conn.execute("SELECT count(*) FROM jobs").fetchone()[0]
        last = conn.execute("SELECT max(written_at) FROM heartbeat").fetchone()[0]
    return jsonify(status="ok", site=SITE, jobs=jobs, last_heartbeat=last.isoformat() if last else None)
