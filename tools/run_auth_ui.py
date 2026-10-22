"""Runs Godot auth tests and cleans only the generated account; no secrets in logs."""
import json
from pathlib import Path
import subprocess
import sys
from verify_discovery import compose, waitFor
from verify_auth import request, sql


def main():
    render = "--render-auth" in sys.argv
    Path(".tools").mkdir(exist_ok=True)
    fixture = Path(".tools/godot-auth-fixture.json")
    fixture.unlink(missing_ok=True)
    Path("docs/fase4/ui").mkdir(parents=True, exist_ok=True)
    arguments = ["godot"] + ([] if render else ["--headless"]) + ["--path", ".", "--script", "res://tools/verify_auth_ui.gd", "--"] + (["--render-auth"] if render else [])
    try:
        result = subprocess.run(arguments, text=True, capture_output=True, timeout=100)
        Path("docs/fase4/godot-auth.log").write_text(result.stdout + result.stderr)
        print(result.stdout, end="", flush=True)
        assert result.returncode == 0 and "AUTH_UI_VALIDATION failures=0" in result.stdout and "SCRIPT ERROR" not in result.stderr, "La prueba Godot falló; revisar docs/fase4/godot-auth.log"
    finally:
        if fixture.exists():
            name = json.loads(fixture.read_text())["username"]
            assert name.startswith("gd_") and len(name) == 19 and all(character in "0123456789abcdef" for character in name[3:])
            ids = sql(f"SELECT player_id FROM accounts WHERE username_key='{name}'")
            for rawId in ids.splitlines():
                playerId = int(rawId)
                sql(f"BEGIN; DELETE FROM accounts WHERE player_id={playerId}; DELETE FROM jugadores WHERE id={playerId}; COMMIT;")
    fixture.unlink(missing_ok=True)
    print("PASS limpieza de la cuenta exclusiva de Godot", flush=True)
    try:
        compose("stop", "jugadores-service")
        offlineArguments = ["godot"] + ([] if render else ["--headless"]) + ["--path", ".", "--script", "res://tools/verify_auth_ui.gd", "--", "--offline-auth"] + (["--render-auth"] if render else [])
        result = subprocess.run(offlineArguments, text=True, capture_output=True, timeout=50)
        Path("docs/fase4/godot-offline.log").write_text(result.stdout + result.stderr)
        print(result.stdout, end="", flush=True)
        assert result.returncode == 0 and "AUTH_UI_OFFLINE failures=0" in result.stdout and "SCRIPT ERROR" not in result.stderr, "La prueba sin servicio falló; revisar docs/fase4/godot-offline.log"
    finally:
        compose("start", "jugadores-service")
    waitFor(lambda: request("POST", "/auth/login", {"username": "offline_test", "password": "not-a-real-account"})[0] == 401, "servicio de cuentas recuperado")


if __name__ == "__main__":
    main()
