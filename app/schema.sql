CREATE TABLE IF NOT EXISTS jobs (
    id          bigserial PRIMARY KEY,
    customer    text        NOT NULL,
    site        text        NOT NULL,
    description text        NOT NULL,
    status      text        NOT NULL DEFAULT 'open'
                CHECK (status IN ('open', 'scheduled', 'done', 'invoiced')),
    attachment  text,
    created_at  timestamptz NOT NULL DEFAULT now()
);

-- One row per drill write; lets the DR drill measure how much data survived.
CREATE TABLE IF NOT EXISTS heartbeat (
    id         bigserial PRIMARY KEY,
    written_at timestamptz NOT NULL DEFAULT now()
);
