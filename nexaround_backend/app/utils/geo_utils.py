from geoalchemy2.elements import WKTElement
from geoalchemy2.shape import to_shape

def create_point(latitude: float, longitude: float) -> WKTElement:
    """Create a WKTElement POINT from latitude and longitude."""
    # Note: PostGIS uses (longitude, latitude) order for coordinates
    return WKTElement(f"POINT({longitude} {latitude})", srid=4326)

def get_lat_lng(location):
    """Extract (latitude, longitude) from a Geometry element."""
    if location is None:
        return None, None
    shape = to_shape(location)
    return shape.y, shape.x


def point_or_none(latitude, longitude):
    """A POINT, or None when either coordinate is missing."""
    if latitude is None or longitude is None:
        return None
    return create_point(latitude, longitude)
