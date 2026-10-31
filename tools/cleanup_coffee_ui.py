"""Delete only the explicitly recorded, generated coffee UI test account."""
import json
from pathlib import Path
import re
import subprocess

root = Path(__file__).resolve().parents[1]
fixture = root / '.tools/coffee-ui-test.json'
if fixture.exists():
    data = json.loads(fixture.read_text())
    username = data['username']
    player_id = int(data['player_id'])
    if not re.fullmatch(r'cfui_[0-9a-f]{12}', username) or player_id <= 0:
        raise SystemExit('Invalid coffee UI cleanup fixture')
    statement = (
        f"BEGIN; DELETE FROM accounts WHERE player_id={player_id} AND username='{username}'; "
        f"DELETE FROM jugadores WHERE id={player_id} AND nombre='{username}'; COMMIT;"
    )
    subprocess.run(['docker', 'compose', 'exec', '-T', 'db-jugadores', 'psql', '-U', 'jugadoresapp', '-d', 'jugadoresdb', '-v', 'ON_ERROR_STOP=1', '-c', statement], cwd=root, check=True, capture_output=True)
    fixture.unlink()
    print('PASS cuenta temporal de recompensa eliminada')
