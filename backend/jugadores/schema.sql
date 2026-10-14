CREATE TABLE IF NOT EXISTS jugadores (
    id SERIAL PRIMARY KEY,
    nombre VARCHAR(100) NOT NULL,
    monedas INT NOT NULL DEFAULT 0
);

INSERT INTO jugadores (nombre, monedas) VALUES
    ('Pingu', 100),
    ('Nieve', 50)
ON CONFLICT DO NOTHING;
