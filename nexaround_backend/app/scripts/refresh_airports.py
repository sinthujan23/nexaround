"""Regenerate app/data/airports.json from OurAirports (public domain).

Keeps only airports a traveller can actually fly to: type large or medium,
scheduled passenger service, and an IATA code. About 3,200 rows. Run from
nexaround_backend/ with plain Python (no app imports needed):

    python app/scripts/refresh_airports.py

Airports open and close slowly; refreshing once or twice a year is plenty.
"""
import csv
import io
import json
import pathlib
import urllib.request

SOURCE = "https://davidmegginson.github.io/ourairports-data/airports.csv"
OUT = pathlib.Path(__file__).resolve().parents[1] / "data" / "airports.json"
TYPES = {"large_airport": "L", "medium_airport": "M"}


def main() -> None:
    with urllib.request.urlopen(SOURCE, timeout=60) as resp:
        text = resp.read().decode("utf-8")
    rows = []
    seen = set()
    for r in csv.DictReader(io.StringIO(text)):
        iata = (r.get("iata_code") or "").strip().upper()
        kind = TYPES.get(r.get("type") or "")
        if not kind or r.get("scheduled_service") != "yes":
            continue
        if len(iata) != 3 or not iata.isalpha() or iata in seen:
            continue
        seen.add(iata)
        rows.append([
            iata,
            (r.get("name") or "").strip(),
            (r.get("municipality") or "").strip(),
            (r.get("iso_country") or "").strip().upper(),
            round(float(r["latitude_deg"]), 4),
            round(float(r["longitude_deg"]), 4),
            kind,
        ])
    rows.sort()
    OUT.parent.mkdir(parents=True, exist_ok=True)
    payload = {
        "source": SOURCE,
        "fields": ["iata", "name", "city", "country", "lat", "lng", "type"],
        "airports": rows,
    }
    OUT.write_text(json.dumps(payload, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    print(f"wrote {len(rows)} airports to {OUT}")


if __name__ == "__main__":
    main()
