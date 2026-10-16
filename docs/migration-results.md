# Migration results

Recorded by `scripts/migrate.sh` on 2026-10-16T15:29:49Z.

| Check | Company server | AWS (eu-west-2) | Result |
|---|---|---|---|
| Jobs table (row count, MD5 of every row) | `501 1b42bb3ec4ce20cb9d04cfa20854390e` | `501 1b42bb3ec4ce20cb9d04cfa20854390e` | match |
| Uploaded files (SHA-256 each) | 61 files | 61 files | 0 mismatched |

Write freeze to validated cutover: **94 seconds**.
