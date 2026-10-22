"""Read-only grpcurl checks for balancing and anonymous access restrictions."""
import json
import re
import subprocess


def invoke(contract, method, payload, expectedError=None, verbose=False):
    arguments = ["docker", "compose", "run", "--rm", "-T", "grpcurl", "-plaintext", "-max-time", "8", "-import-path", "/proto", "-proto", f"penguin/v1/{contract}.proto", "-d", json.dumps(payload)]
    if verbose:
        arguments.append("-v")
    arguments.extend(["gateway:9090", "penguin.v1." + method])
    response = subprocess.run(arguments, capture_output=True, text=True, timeout=30)
    if expectedError:
        assert response.returncode != 0 and f"Code: {expectedError}" in response.stderr, response.stdout + response.stderr
        return None
    assert response.returncode == 0, response.stdout + response.stderr
    if verbose:
        return response.stdout
    return json.loads(response.stdout)


def main():
    instances = set()
    for attempt in range(6):
        output = invoke("store", "Store/ListProducts", {}, verbose=True)
        match = re.search(r"(?im)^x-instance-name:\s*(\S+)", output)
        assert match, "Falta metadata de instancia"
        instances.add(match.group(1))
    assert instances == {"tienda-service-1", "tienda-service-2"}
    print("PASS grpcurl balancea el catálogo público entre dos instancias", flush=True)
    invoke("players", "Players/GetPlayer", {"id": 1}, expectedError="Unauthenticated")
    invoke("store", "Store/UpdateStock", {"id": 1, "stock": 999}, expectedError="Unauthenticated")
    invoke("cafeteria", "Cafeteria/CreateOrder", {"product": "Café", "quantity": 1}, expectedError="Unauthenticated")
    invoke("auth", "Auth/GetSession", {}, expectedError="Unauthenticated")
    print("PASS los tres backends exigen sesión también por gRPC directo", flush=True)
    print("GRPC_VALIDATION failures=0", flush=True)


if __name__ == "__main__":
    main()
