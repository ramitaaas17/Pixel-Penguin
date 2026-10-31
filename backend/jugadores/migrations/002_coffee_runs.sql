CREATE TABLE IF NOT EXISTS coffee_runs (
    id VARCHAR(32) PRIMARY KEY,
    player_id INTEGER NOT NULL REFERENCES jugadores(id) ON DELETE CASCADE,
    started_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    state VARCHAR(12) NOT NULL DEFAULT 'playing' CHECK (state IN ('playing','abandoned','claimed')),
    plan JSONB NOT NULL,
    result JSONB,
    claimed_at TIMESTAMPTZ
);
CREATE UNIQUE INDEX IF NOT EXISTS coffee_one_active ON coffee_runs(player_id) WHERE state='playing';
