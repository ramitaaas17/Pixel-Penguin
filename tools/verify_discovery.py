"""Integration checks for the local Compose stack; restores each stopped service."""
import json
import re
import subprocess
import time
import urllib.error
import urllib.request


def compose(*arguments):
    result = subprocess.run(["docker", "compose", *arguments], check=True, text=True, capture_output=True, timeout=60)
    return result.stdout.strip()


def health(passing=False):
    query = "?passing=true&tag=grpc" if passing else ""
    return json.loads(compose("exec", "-T", "consul", "wget", "-qO-", "http://127.0.0.1:8500/v1/health/service/tienda" + query))


def serviceIds(passing=False):
    return {entry["Service"]["ID"] for entry in health(passing)}


def pool():
    config = compose("exec", "-T", "gateway", "cat", "/etc/nginx/nginx.conf")
    match = re.search(r"upstream tienda\s*\{([^}]+)\}", config)
    return match.group(1) if match else ""


def request():
    try:
        with urllib.request.urlopen("http://localhost:8000/tienda", timeout=5) as response:
            return response.status, response.headers.get("X-Instance-Name")
    except urllib.error.HTTPError as error:
        return error.code, None


def waitFor(predicate, message, timeout=40):
    deadline = time.monotonic() + timeout
    lastError = None
    while time.monotonic() < deadline:
        try:
            if predicate():
                print("PASS " + message, flush=True)
                return
        except (subprocess.SubprocessError, ValueError, OSError) as error:
            lastError = error
        time.sleep(1)
    raise AssertionError(f"Timeout: {message}; last error: {lastError}")


def restored():
    return serviceIds(True) == {"tienda-service-1", "tienda-service-2"} and {request()[1] for _ in range(6)} == {"tienda-service-1", "tienda-service-2"}


def main():
    waitFor(restored, "dos instancias saludables y balanceadas")
    original = next(entry["Service"] for entry in health(True) if entry["Service"]["ID"] == "tienda-service-1")
    endpoint = f"{original['Address']}:{original['Port']}"
    try:
        compose("stop", "tienda-service-1")
        waitFor(lambda: "tienda-service-1" not in serviceIds() and endpoint not in pool(), "baja normal elimina registro y destino de Nginx")
        assert {request()[1] for _ in range(6)} == {"tienda-service-2"}
        print("PASS seis consultas atendidas por la instancia restante", flush=True)
    finally:
        compose("start", "tienda-service-1")
    waitFor(restored, "instancia recuperada vuelve al balanceo")

    try:
        compose("kill", "-s", "SIGKILL", "tienda-service-1")
        waitFor(lambda: "tienda-service-1" not in serviceIds(True) and endpoint not in pool(), "caída abrupta excluye instancia no saludable del enrutamiento")
        waitFor(lambda: "tienda-service-1" not in serviceIds(), "Consul elimina registro crítico tras plazo de limpieza", timeout=130)
    finally:
        compose("start", "tienda-service-1")
    waitFor(restored, "registro automático después de caída abrupta")

    extraId = None
    try:
        extraId = compose("run", "--rm", "-d", "--no-deps", "-e", "INSTANCE_NAME=tienda-extra", "tienda-service-1")
        waitFor(lambda: "tienda-extra" in serviceIds(True), "nueva instancia se registra sin editar destinos")
        waitFor(lambda: "tienda-extra" in {request()[1] for _ in range(12)}, "Nginx enruta a la nueva instancia descubierta")
    finally:
        if extraId:
            subprocess.run(["docker", "stop", extraId], check=True, capture_output=True, timeout=30)
    waitFor(restored, "retirada de instancia adicional sin destinos residuales")

    try:
        compose("stop", "db-tienda")
        waitFor(lambda: not serviceIds(True) and "127.0.0.1:9" in pool() and request()[0] == 503, "base caída deja cero destinos saludables y devuelve 503")
    finally:
        compose("start", "db-tienda")
    waitFor(restored, "recuperación de base restaura salud y tráfico")

    try:
        compose("stop", "consul")
        waitFor(lambda: "127.0.0.1:9" in pool() and request()[0] == 503, "pérdida de Consul caduca destinos anteriores y devuelve 503")
    finally:
        compose("start", "consul")
    waitFor(restored, "recuperación de Consul restaura descubrimiento y balanceo")
    print("DISCOVERY_VALIDATION failures=0", flush=True)


if __name__ == "__main__":
    main()
