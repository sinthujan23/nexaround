"""Free map data for free users: Overture Maps places (downloaded one area at a
time), Geoapify (OpenStreetMap) for areas not downloaded yet, our own score.

Pure rules live in `sections` and `score`; `overture_import` downloads; the
importer loop is `app.open_data_worker`; serving is `open_places_service`.
"""
