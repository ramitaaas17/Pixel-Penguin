"""Prueba local con Docker ya iniciado. No cambia los valores del juego."""
import subprocess
import sys
import shutil
import time


if shutil.which('docker') is None:
    sys.exit('No se encontró Docker. Instálalo antes de ejecutar la prueba.')

try:
    docker = subprocess.run(
        ['docker', 'info'], capture_output=True, text=True, timeout=15,
    )
except subprocess.TimeoutExpired:
    sys.exit('Docker no respondió. Revisa el servicio antes de ejecutar la prueba.')
if docker.returncode != 0:
    sys.exit(
        'No se puede conectar con Docker.\n'
        'Si el servicio está detenido ejecuta: sudo systemctl start docker\n'
        'Luego comprueba: docker info\n'
        'Cuando funcione inicia el proyecto con: docker compose up -d --build --wait\n'
        'Si aparece permission denied revisa los permisos de tu usuario en Docker.'
    )


def sql(service, statement):
    return subprocess.check_output([
        'docker', 'compose', 'exec', '-T', 'db-' + service, 'sh', '-c',
        'psql -v ON_ERROR_STOP=1 -Atq -U "$POSTGRES_USER" -d "$POSTGRES_DB"',
    ], input=statement, text=True).strip()


for service, table in [('jugadores', 'jugadores'), ('tienda', 'productos'), ('cafeteria', 'pedidos')]:
    # A temporary row works even when the domain table is empty.
    insert = {
        'jugadores': "INSERT INTO jugadores(nombre,monedas) VALUES ('prueba kafka',0) RETURNING id",
        'tienda': "INSERT INTO productos(nombre,precio,stock) VALUES ('prueba kafka',0,0) RETURNING id",
        'cafeteria': "INSERT INTO pedidos(producto,cantidad) VALUES ('prueba kafka',1) RETURNING id",
    }[service]
    # Rollback must also remove the pending message.
    rollback_id = sql(service, f"BEGIN; {insert}; SELECT currval('message_outbox_id_seq'); ROLLBACK;").splitlines()[-1]
    assert sql(service, f'SELECT count(*) FROM message_outbox WHERE id={int(rollback_id)};') == '0'
    lines = sql(service, f"BEGIN; {insert}; SELECT currval('message_outbox_id_seq'); COMMIT;").splitlines()
    row_id, event_id = map(int, lines[-2:])
    try:
        deadline = time.monotonic() + 90
        while time.monotonic() < deadline:
            if sql(service, f"SELECT count(*) FROM message_inbox WHERE event_id='{service}-{event_id}';") == '1':
                break
            time.sleep(1)
        else:
            pending = sql(service, f'SELECT count(*) FROM message_outbox WHERE id={event_id};')
            print(f'{service}: mensaje {event_id} pendiente de envío: {pending}', file=sys.stderr)
            subprocess.run(['docker', 'compose', 'logs', '--tail', '30', service + '-service' if service != 'tienda' else 'tienda-service-1', 'kafka-rest'])
            raise AssertionError('No llegó el mensaje de ' + service)
        print(service + ': mensaje recibido y guardado')
    finally:
        sql(service, f'DELETE FROM {table} WHERE id={row_id};')
