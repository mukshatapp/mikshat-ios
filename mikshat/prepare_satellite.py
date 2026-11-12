"""Validate the bundled source definition and derive its native XYZ configuration."""
from pathlib import Path
import hashlib
import json
import sqlite3
from urllib.parse import urlsplit


def configuration(path):
    # This bundled definition is immutable. Its WAL header must not make SQLite
    # require writable -wal/-shm sidecars in a clean CI checkout.
    with sqlite3.connect(path.resolve().as_uri() + "?mode=ro&immutable=1", uri=True) as connection:
        connection.row_factory = sqlite3.Row
        rows = connection.execute("SELECT * FROM info").fetchall()
        if len(rows) != 1:
            raise ValueError("Expected one satellite source")
        row = dict(rows[0])
        count = connection.execute("SELECT COUNT(*) FROM tiles").fetchone()[0]
    if row['tilenumbering'] != 'simple' or str(row['inverted_y']) != '0' or str(row['ellipsoid']) != '0':
        raise ValueError("Only non-inverted spherical XYZ is supported")
    minimum, maximum = int(row['minzoom']), int(row['maxzoom'])
    if not 0 <= minimum <= maximum <= 20:
        raise ValueError("Invalid source zoom range")
    url = row['url'].replace('{rnd}', '0').replace('{0}', '{z}').replace('{1}', '{x}').replace('{2}', '{y}')
    if url.startswith('http://'):
        url = 'https://' + url[7:]
    if urlsplit(url).hostname != 'mt0.google.com' or not all(token in url for token in ('{x}', '{y}', '{z}')):
        raise ValueError("Unexpected satellite endpoint")
    return dict(title=row['title'], url=url, minZoom=minimum, maxZoom=maximum,
                embeddedTileCount=count, sourceSHA256=hashlib.sha256(path.read_bytes()).hexdigest())


if __name__ == '__main__':
    directory = Path(__file__).resolve().parents[1] / 'iphone/Maps/Resources/Mikshat'
    value = configuration(directory / 'GOOGLE.sqlitedb')
    (directory / 'MikshatSatellite.json').write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n')
    print(f"Validated satellite definition: zoom {value['minZoom']}–{value['maxZoom']}, {value['embeddedTileCount']} embedded tiles")
