"""Fill the company server with sample jobs and attachments (fixed seed, so runs repeat)."""
import random
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

import db
import storage

CUSTOMERS = ["Northfield Lettings", "Ashby Dental", "Riverside Cafe", "Kestrel Print", "Holloway School",
             "Brook Vets", "Marlow Garage", "Oak Lane Surgery", "Quayside Hotel", "Fenwick Bakery"]
WORK = ["Replace consumer unit", "Fault-find lighting circuit", "Install EV charger", "Annual inspection",
        "Fit emergency lighting", "Rewire kitchen", "Add data points", "Repair door entry system"]
STATUSES = ["open", "scheduled", "done", "invoiced"]


def main(jobs: int = 500, attachments: int = 60) -> None:
    rng = random.Random(42)
    schema = (Path(__file__).parent / "schema.sql").read_text()
    store = storage.from_env()
    start = datetime(2025, 1, 6, tzinfo=timezone.utc)
    with db.connect() as conn:
        conn.execute(schema)
        if conn.execute("SELECT count(*) FROM jobs").fetchone()[0]:
            print("already seeded")
            return
        attach_rows = set(rng.sample(range(jobs), attachments))
        for i in range(jobs):
            customer = rng.choice(CUSTOMERS)
            work = rng.choice(WORK)
            key = None
            if i in attach_rows:
                key = f"seed{i:04d}/job-sheet-{i:04d}.txt"
                body = f"Job sheet {i}\nCustomer: {customer}\nWork: {work}\n" + "Notes. " * rng.randint(20, 400)
                store.put(key, body.encode())
            conn.execute(
                "INSERT INTO jobs (customer, site, description, status, attachment, created_at)"
                " VALUES (%s, %s, %s, %s, %s, %s)",
                (customer, f"Unit {rng.randint(1, 40)}", work, rng.choice(STATUSES), key,
                 start + timedelta(hours=7 * i)),
            )
    print(f"seeded {jobs} jobs, {attachments} attachments")


if __name__ == "__main__":
    main(*(int(a) for a in sys.argv[1:]))
