3D NAVIGATION MARKERS
=====================

Put two PNG images in THIS folder to use real 3D car / person markers during
Google Maps navigation:

    car_3d.png    -> shown while DRIVING
    walk_3d.png   -> shown while WALKING

Requirements for best results:
  - Top-down (bird's-eye) view, the vehicle/person pointing STRAIGHT UP.
  - Transparent background (PNG with alpha).
  - Square image, around 200 x 200 px.

Where to get free ones:
  - https://www.flaticon.com  (search: "3d car top view", "3d walking person top view")
  - https://www.freepik.com
  - or any 3D asset you already have.

After adding the files:
  1. Run:  flutter pub get
  2. Rebuild the app.

That's it — the app automatically uses these images as the markers. If the
files are missing, it falls back to the built-in glossy badge marker.
