CREATE TABLE IF NOT EXISTS productos (
    id SERIAL PRIMARY KEY,
    nombre VARCHAR(100) NOT NULL,
    precio NUMERIC(10,2) NOT NULL,
    stock INT NOT NULL DEFAULT 0
);

INSERT INTO productos (nombre, precio, stock) VALUES
    ('Gorro de lana', 80.00, 20),
    ('Bufanda', 60.00, 25)
ON CONFLICT DO NOTHING;
