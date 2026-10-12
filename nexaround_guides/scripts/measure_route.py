"""Measure a road route with Google Directions for a guide.

Prints every leg (km, minutes) as frontmatter-ready YAML and writes the
simplified route line(s) to src/data/routes/<name>.json for the map.

    GOOGLE_MAPS_API_KEY=... python3 scripts/measure_route.py route.json adelaide-perth

route.json holds named points and one or more sequences of them:

    {"points": {"Adelaide": [-34.9285, 138.6007], "Port Augusta": [-32.4937, 137.7744], ...},
     "lines": {"direct": ["Adelaide", "Port Augusta", ...], "coastal": [...]}}

Use exact coordinates (a roadhouse's own pin), not place names: Google
resolves a name like "Nullarbor Roadhouse" to a locality centre off the
highway, which added 76 km to one leg (87 km to the trip) when we tried it.
"""
import json
import os
import sys
import urllib.parse
import urllib.request

URL = "https://maps.googleapis.com/maps/api/directions/json"


def decode(s):
    pts, i, lat, lng = [], 0, 0, 0
    while i < len(s):
        for which in (0, 1):
            shift = res = 0
            while True:
                b = ord(s[i]) - 63
                i += 1
                res |= (b & 0x1F) << shift
                shift += 5
                if b < 0x20:
                    break
            d = ~(res >> 1) if res & 1 else res >> 1
            if which == 0:
                lat += d
            else:
                lng += d
        pts.append((lat / 1e5, lng / 1e5))
    return pts


def simplify(pts, eps=0.005):
    """Douglas-Peucker; eps in degrees (about 500 m)."""
    if len(pts) < 3:
        return pts
    if pts[0] == pts[-1]:
        # A closed loop has no baseline: split it at the point farthest from the start.
        far = max(range(len(pts)), key=lambda i: (pts[i][0] - pts[0][0]) ** 2 + (pts[i][1] - pts[0][1]) ** 2)
        return simplify(pts[: far + 1], eps)[:-1] + simplify(pts[far:], eps)
    (x1, y1), (x2, y2) = pts[0], pts[-1]
    dx, dy = x2 - x1, y2 - y1
    n = (dx * dx + dy * dy) ** 0.5 or 1e-12
    dmax, idx = 0, 0
    for i in range(1, len(pts) - 1):
        x, y = pts[i]
        d = abs(dy * x - dx * y + x2 * y1 - y2 * x1) / n
        if d > dmax:
            dmax, idx = d, i
    if dmax > eps:
        return simplify(pts[: idx + 1], eps)[:-1] + simplify(pts[idx:], eps)
    return [pts[0], pts[-1]]


def main():
    spec_path, name = sys.argv[1], sys.argv[2]
    key = os.environ["GOOGLE_MAPS_API_KEY"]
    spec = json.load(open(spec_path))
    pts = spec["points"]
    ll = lambda p: f"{pts[p][0]},{pts[p][1]}"
    lines = {}
    for line, seq in spec["lines"].items():
        q = {"origin": ll(seq[0]), "destination": ll(seq[-1]), "mode": "driving", "key": key}
        if len(seq) > 2:
            q["waypoints"] = "|".join(ll(p) for p in seq[1:-1])
        data = json.load(urllib.request.urlopen(f"{URL}?{urllib.parse.urlencode(q)}", timeout=30))
        if data.get("status") != "OK":
            sys.exit(f"{line}: Directions said {data.get('status')} {data.get('error_message', '')}")
        full, km_total, min_total = [], 0, 0
        print(f"# {line}")
        for i, leg in enumerate(data["routes"][0]["legs"]):
            km, mins = round(leg["distance"]["value"] / 1000), round(leg["duration"]["value"] / 60)
            km_total += km
            min_total += mins
            print(f"  - {{ from: {seq[i]}, to: {seq[i + 1]}, km: {km}, min: {mins} }}")
            for step in leg["steps"]:
                full += decode(step["polyline"]["points"])
        print(f"# total {km_total} km, {min_total // 60} h {min_total % 60:02d}\n")
        lines[line] = [[round(a, 4), round(b, 4)] for a, b in simplify(full)]
    out = os.path.join(os.path.dirname(__file__), "..", "src", "data", "routes", f"{name}.json")
    json.dump(lines, open(out, "w"), separators=(",", ":"))
    print(f"wrote {os.path.normpath(out)}")


if __name__ == "__main__":
    main()
