"""Authentication integration tests; never prints passwords or session tokens."""
import concurrent.futures
import hashlib
import json
import secrets
import subprocess
import urllib.error
import urllib.request
import uuid
import time
from verify_discovery import compose, waitFor


def request(method, path, body=None, token=None, expected=None):
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = "Bearer " + token
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request("http://localhost:8000" + path, data=data, headers=headers, method=method)
    try:
        response = urllib.request.urlopen(req, timeout=15)
    except urllib.error.HTTPError as error:
        response = error
    with response:
        code = response.status
        result = json.load(response)
    if expected is not None:
        assert code == expected, f"{method} {path}: HTTP {code}, expected {expected}"
    return code, result


def sql(query):
    return compose("exec", "-T", "db-jugadores", "sh", "-c", 'psql -qAt -U "$POSTGRES_USER" -d "$POSTGRES_DB" -v ON_ERROR_STOP=1 -c "$1"', "auth-test", query)


def orderSQL(query):
    return compose("exec", "-T", "db-cafeteria", "sh", "-c", 'psql -qAt -U "$POSTGRES_USER" -d "$POSTGRES_DB" -v ON_ERROR_STOP=1 -c "$1"', "auth-order-test", query)


def main():
    fixtureIds = []
    orderIds = []
    legacy = sql("SELECT COALESCE(json_agg(t),'[]') FROM (SELECT j.* FROM jugadores j LEFT JOIN accounts a ON a.player_id=j.id WHERE a.id IS NULL ORDER BY j.id) t")
    password = secrets.token_urlsafe(18)
    username = "ñauth_" + uuid.uuid4().hex[:8]
    try:
        _, first = request("POST", "/auth/register", {"username": username, "password": password}, expected=201)
        owner = int(first["jugador"]["id"])
        fixtureIds.append(owner)
        token = first["token"]
        assert first["jugador"]["monedas"] == 100
        assert abs(first["expires_at"] - time.time() - 43200) < 60
        assert "hash" not in json.dumps(first)
        print("PASS registro con jugador propio y monedas asignadas por servidor", flush=True)
        hashValue = sql(f"SELECT password_hash FROM accounts WHERE player_id={owner}")
        assert hashValue.startswith(("$2a$12$", "$2b$12$")) and hashValue != password
        tokenHash = hashlib.sha256(token.encode()).hexdigest()
        assert sql(f"SELECT count(*) FROM sessions WHERE token_hash=decode('{tokenHash}','hex')") == "1"
        print("PASS contraseña bcrypt coste 12 y token almacenado como SHA-256", flush=True)
        request("POST", "/auth/register", {"username": username.upper(), "password": password}, expected=409)
        request("POST", "/auth/register", {"username": "short", "password": "abc"}, expected=400)
        request("POST", "/auth/register", {"username": username + "x", "password": password, "monedas": 9999}, expected=400)
        print("PASS duplicado sin distinguir mayúsculas y entradas inválidas rechazados", flush=True)
        wrongCode, wrong = request("POST", "/auth/login", {"username": username, "password": "wrong-password"}, expected=401)
        _, missing = request("POST", "/auth/login", {"username": "missing_" + uuid.uuid4().hex[:8], "password": "wrong-password"}, expected=401)
        assert wrong["error"] == missing["error"]
        _, logged = request("POST", "/auth/login", {"username": username.upper(), "password": password}, expected=200)
        loginToken = logged["token"]
        assert logged["jugador"]["id"] == owner
        print("PASS login válido e inválido; errores sin revelar existencia de cuenta", flush=True)
        request("GET", "/auth/session", expected=401)
        request("GET", "/auth/session", token=secrets.token_urlsafe(32), expected=401)
        request("GET", "/cafeteria", expected=401)
        request("GET", f"/jugadores/{owner}", expected=401)
        _, current = request("GET", "/auth/session", token=token, expected=200)
        assert current["jugador"]["id"] == owner and "token" not in current
        _, ownOrders = request("GET", "/cafeteria", token=token, expected=200)
        assert ownOrders == []
        otherName = "auth_" + uuid.uuid4().hex[:10]
        _, other = request("POST", "/auth/register", {"username": otherName, "password": password}, expected=201)
        otherId = int(other["jugador"]["id"])
        fixtureIds.append(otherId)
        createdOrders = orderSQL(f"INSERT INTO pedidos(producto,cantidad,estado,jugador_id) VALUES('auth-fixture-owned',1,'pendiente',{owner}),('auth-fixture-other',1,'pendiente',{otherId}),('auth-fixture-legacy',1,'pendiente',NULL) RETURNING id")
        orderIds = [int(value) for value in createdOrders.splitlines()]
        _, visibleOrders = request("GET", f"/cafeteria?jugador_id={otherId}", token=token, expected=200)
        assert [record["id"] for record in visibleOrders] == [orderIds[0]]
        request("GET", f"/cafeteria/{orderIds[1]}", token=token, expected=404)
        request("GET", f"/cafeteria/{orderIds[2]}", token=token, expected=404)
        print("PASS pedidos filtrados por sesión: sin acceso a otro usuario ni a pedidos sin dueño", flush=True)
        request("GET", f"/jugadores/{otherId}", token=token, expected=403)
        request("GET", "/jugadores", token=token, expected=403)
        request("PUT", f"/jugadores/{owner}", {"monedas": 99999}, token=token, expected=403)
        request("PUT", "/tienda/1", {"stock": 99999}, token=token, expected=403)
        request("POST", "/cafeteria", {"producto": "Café", "cantidad": 1, "jugador_id": otherId}, token=token, expected=409)
        assert request("GET", f"/jugadores/{owner}", token=token, expected=200)[1]["monedas"] == 100
        print("PASS identidad derivada de sesión; datos ajenos y escrituras antiguas bloqueados", flush=True)
        raceName = "race_" + uuid.uuid4().hex[:10]
        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as executor:
            results = list(executor.map(lambda _: request("POST", "/auth/register", {"username": raceName, "password": password}), range(2)))
        for code, result in results:
            if code == 201:
                fixtureIds.append(int(result["jugador"]["id"]))
        assert sorted(code for code, _ in results) == [201, 409]
        assert sql(f"SELECT count(*) FROM jugadores WHERE nombre='{raceName}'") == "1"
        print("PASS registro concurrente: una cuenta y ningún jugador huérfano", flush=True)
        compose("restart", "jugadores-service")
        waitFor(lambda: request("GET", "/auth/session", token=token)[0] == 200, "sesión persistente después de reiniciar Jugadores")
        sql(f"UPDATE sessions SET expires_at=NOW()-INTERVAL '1 second' WHERE token_hash=decode('{tokenHash}','hex')")
        request("GET", "/auth/session", token=token, expected=401)
        request("GET", "/auth/session", token=loginToken, expected=200)
        print("PASS caducidad desde PostgreSQL sin invalidar otra sesión activa", flush=True)
        request("POST", "/auth/logout", token=loginToken, expected=200)
        request("GET", "/auth/session", token=loginToken, expected=401)
        request("POST", "/auth/logout", token=loginToken, expected=200)
        print("PASS logout revoca el token y su repetición es idempotente", flush=True)
        response = subprocess.run(["docker", "compose", "run", "--rm", "-T", "grpcurl", "-plaintext", "-import-path", "/proto", "-proto", "penguin/v1/players.proto", "-d", json.dumps({"id": owner}), "gateway:9090", "penguin.v1.Players/GetPlayer"], capture_output=True, text=True, timeout=30)
        assert response.returncode != 0 and "Code: Unauthenticated" in response.stderr
        print("PASS gRPC directo también exige sesión", flush=True)
        assert legacy == sql("SELECT COALESCE(json_agg(t),'[]') FROM (SELECT j.* FROM jugadores j LEFT JOIN accounts a ON a.player_id=j.id WHERE a.id IS NULL ORDER BY j.id) t")
        print("PASS jugadores anteriores conservados sin asignación de cuentas", flush=True)
    finally:
        for orderId in orderIds:
            orderSQL(f"DELETE FROM pedidos WHERE id={orderId}")
        for playerId in fixtureIds:
            sql(f"BEGIN; DELETE FROM accounts WHERE player_id={playerId}; DELETE FROM jugadores WHERE id={playerId}; COMMIT;")
    print("PASS limpieza exclusiva de cuentas, sesiones y jugadores de prueba", flush=True)
    print("AUTH_VALIDATION failures=0", flush=True)


if __name__ == "__main__":
    main()
