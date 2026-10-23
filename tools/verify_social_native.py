import json
import os
from pathlib import Path
import secrets
import subprocess
import urllib.request

root = Path(__file__).resolve().parent.parent
os.chdir(root)
username = "native_" + secrets.token_hex(5)
body = json.dumps({"username": username, "password": secrets.token_hex(16)}).encode()
request = urllib.request.Request("http://localhost:8000/auth/register", data=body, headers={"Content-Type": "application/json"})
with urllib.request.urlopen(request, timeout=15) as response:
    session = json.load(response)
try:
    env = os.environ.copy()
    env["SOCIAL_TEST_SESSION"] = json.dumps(session)
    result = subprocess.run(["godot", "--headless", "--path", ".", "--script", "res://tools/verify_social_native.gd"], env=env, capture_output=True, text=True, timeout=45)
    print(result.stdout, end="")
    print(result.stderr, end="")
    if result.returncode or "SOCIAL_NATIVE_VALIDATION failures=0" not in result.stdout or "SCRIPT ERROR" in result.stderr:
        raise SystemExit(1)
finally:
    sql = f"BEGIN; DELETE FROM accounts WHERE username='{username}'; DELETE FROM jugadores WHERE id={int(session['jugador']['id'])} AND nombre='{username}'; COMMIT;"
    subprocess.run(["docker", "compose", "exec", "-T", "db-jugadores", "psql", "-U", "jugadoresapp", "-d", "jugadoresdb", "-v", "ON_ERROR_STOP=1", "-c", sql], check=True, capture_output=True)
    print("PASS cuenta temporal nativa eliminada")
