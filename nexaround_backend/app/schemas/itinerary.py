from pydantic import BaseModel, ConfigDict, Field
from typing import List, Optional
from uuid import UUID
from datetime import datetime, date

class ItineraryItem(BaseModel):
    # `extra="allow"` + optional attraction_id lets a single Itinerary row hold
    # either a classic saved-attraction item (with attraction_id) OR a free-form
    # AI "Odyssey" block (a meta header or a day's activities) whose shape the
    # backend never needs to understand — it's stored verbatim in the JSON
    # `items` column and round-tripped to the app. Keeps the existing itinerary
    # flow working with zero DB migration.
    model_config = ConfigDict(extra="allow")

    attraction_id: Optional[UUID] = None
    time: Optional[str] = None
    note: Optional[str] = None

class ItineraryBase(BaseModel):
    title: str
    trip_date: Optional[date] = None
    items: List[ItineraryItem] = []
    status: str = "draft"

class ItineraryCreate(ItineraryBase):
    pass

class ItineraryUpdate(BaseModel):
    title: Optional[str] = None
    trip_date: Optional[date] = None
    items: Optional[List[ItineraryItem]] = None
    status: Optional[str] = None

# The bounds a generation request must satisfy, named so the retry endpoint can
# clamp to the same numbers. It replays parameters stored on an existing trip
# and never passes through this model, so without a shared source of truth a
# plan saved before a bound existed walks straight round it: one stored trip
# carries travelers=110, another days=31.
TRAVELERS_RANGE = (1, 20)
DAYS_RANGE = (1, 14)
BUDGET_RANGE = (0.0, 1_000_000_000.0)
DESTINATION_MAX = 200
MOOD_MAX = 60


class OdysseyRouteLeg(BaseModel):
    """One city the trip sleeps in, as the planner describes it."""
    city: str = Field(min_length=1, max_length=DESTINATION_MAX)
    country: str = Field(default="", max_length=64)
    start_day: int = Field(ge=1, le=DAYS_RANGE[1])
    end_day: int = Field(ge=1, le=DAYS_RANGE[1])
    nights: Optional[int] = Field(default=None, ge=0, le=DAYS_RANGE[1])
    latitude: Optional[float] = Field(default=None, ge=-90, le=90)
    longitude: Optional[float] = Field(default=None, ge=-180, le=180)
    arrive_by: str = Field(default="", max_length=16)
    from_previous_km: float = Field(default=0, ge=0, le=40_000)


class OdysseyRouteAirport(BaseModel):
    iata: str = Field(default="", max_length=3)
    city: str = Field(default="", max_length=DESTINATION_MAX)
    name: str = Field(default="", max_length=DESTINATION_MAX)


class OdysseyRoute(BaseModel):
    """A whole route, in the shape the route planner both emits and re-reads."""
    # Capped at the trip length: one leg per day is already more moving than
    # any plan should do, and an unbounded list is a free hotel search per
    # entry on a paid API.
    legs: List[OdysseyRouteLeg] = Field(default_factory=list, max_length=DAYS_RANGE[1])
    arrival_airport: Optional[OdysseyRouteAirport] = None
    departure_airport: Optional[OdysseyRouteAirport] = None
    region: str = Field(default="", max_length=128)
    source: str = Field(default="", max_length=16)


class OdysseyGenerateRequest(BaseModel):
    """Request body for kicking off a server-side AI Odyssey generation."""
    # Both are interpolated into the Gemini prompt, so their length is billed
    # tokens. Generous caps, but caps: a place name is not four kilobytes.
    destination: str = Field(min_length=1, max_length=DESTINATION_MAX)
    mood: str = Field(default="Adventurous", max_length=MOOD_MAX)
    # A negative budget flowed straight through to the waterfall, and an
    # enormous one to a quote in the hundreds of millions. The app has no
    # bound on either field, so this is the only place that can hold the line.
    budget: float = Field(default=50000, ge=BUDGET_RANGE[0], le=BUDGET_RANGE[1])
    # Capped at 14: the single-shot Gemini generation call produces the whole
    # plan (header + every day) in one response, with an output budget that
    # scales per day (see odyssey_ai_service._itinerary_token_budget). Longer
    # trips than this are better served as two Odysseys than as one response
    # the size of a novella. The app's date picker enforces this too; this
    # is the server-side backstop.
    days: int = Field(default=3, ge=DAYS_RANGE[0], le=DAYS_RANGE[1])
    currency: str = Field(default="USD", min_length=1, max_length=8)
    # The app's own field rejects zero and below but has no ceiling, so a typed
    # "99999" reached the planner: 99,999 hotel rooms and a budget in the
    # hundreds of millions. Zero was worse - it stored a trip for nobody.
    travelers: int = Field(default=1, ge=TRAVELERS_RANGE[0], le=TRAVELERS_RANGE[1])
    include_flights: bool = False
    departure_city: str = ""
    departure_country: str = ""
    nationality: str = ""
    has_visa: bool = False
    flight_start_date: Optional[str] = None
    flight_end_date: Optional[str] = None
    include_hotels: bool = False
    hotel_check_in_date: Optional[str] = None
    hotel_check_out_date: Optional[str] = None
    start_date: Optional[str] = None
    end_date: Optional[str] = None
    # What the app's place picker already knew when the user tapped the
    # destination, and used to throw away. All optional: the backend resolves
    # the destination on its own, so older builds and free-text stay correct —
    # these only let it skip a lookup and disambiguate a name Google would
    # otherwise have to guess at.
    # Where the traveller wants the trip to begin and end inside the
    # destination country. Optional and independent: either may be given alone.
    # The app only enables these once a country is chosen and restricts their
    # search to it, so a city from elsewhere should never arrive - but the
    # planner treats them as a request rather than a guarantee either way.
    entry_city: str = Field(default="", max_length=DESTINATION_MAX)
    exit_city: str = Field(default="", max_length=DESTINATION_MAX)
    # The traveller asked to stay in the entry city rather than tour the
    # country. Only meaningful alongside an entry city, and the planner checks
    # for one before honouring it. Defaults False so app builds that predate
    # the question behave exactly as they do today; these models do not set
    # extra="allow", so without this field the key would be dropped in silence.
    only_this_city: bool = False
    # Where those two places actually are. The app picks them from Google, so
    # it knows to the metre; without these the route planner has to guess from
    # the name, and its guess becomes the leg coordinates that the hotel search
    # and every distance check downstream then use.
    entry_latitude: Optional[float] = Field(default=None, ge=-90, le=90)
    entry_longitude: Optional[float] = Field(default=None, ge=-180, le=180)
    exit_latitude: Optional[float] = Field(default=None, ge=-90, le=90)
    exit_longitude: Optional[float] = Field(default=None, ge=-180, le=180)
    destination_place_id: str = ""
    destination_latitude: Optional[float] = None
    destination_longitude: Optional[float] = None
    destination_address: str = ""
    # Where the traveller is flying FROM. The app derives departure_city by
    # reverse-geocoding these, and when that fails it sends the literal word
    # "Nearby" — which the airport resolver then asked a model about, quoting a
    # traveller in Trincomalee a flight from Chennai. Carrying the raw point
    # lets the backend recover the country when the name is unusable.
    departure_latitude: Optional[float] = None
    departure_longitude: Optional[float] = None
    # The route the traveller was shown by /odyssey/route-preview and accepted.
    # Optional: an app that does not preview still generates exactly as before,
    # and a route that fails the planner's own coherence checks is discarded
    # server-side rather than believed — see `plan_route(preset=...)`.
    preset_route: Optional[OdysseyRoute] = None


class OdysseyRoutePreviewRequest(BaseModel):
    """What the route preview needs: the trip's shape, not its money.

    A subset of `OdysseyGenerateRequest` — budget and currency are absent
    because the route is decided before anything is priced, and asking for
    them would imply the preview honours them.
    """
    destination: str = Field(min_length=1, max_length=DESTINATION_MAX)
    mood: str = Field(default="Adventurous", max_length=MOOD_MAX)
    days: int = Field(default=3, ge=DAYS_RANGE[0], le=DAYS_RANGE[1])
    travelers: int = Field(default=1, ge=TRAVELERS_RANGE[0], le=TRAVELERS_RANGE[1])
    include_flights: bool = False
    departure_city: str = ""
    departure_country: str = ""
    departure_latitude: Optional[float] = None
    departure_longitude: Optional[float] = None
    start_date: Optional[str] = None
    hotel_check_in_date: Optional[str] = None
    entry_city: str = Field(default="", max_length=DESTINATION_MAX)
    exit_city: str = Field(default="", max_length=DESTINATION_MAX)
    # The traveller asked to stay in the entry city rather than tour the
    # country. Only meaningful alongside an entry city, and the planner checks
    # for one before honouring it. Defaults False so app builds that predate
    # the question behave exactly as they do today; these models do not set
    # extra="allow", so without this field the key would be dropped in silence.
    only_this_city: bool = False
    entry_latitude: Optional[float] = Field(default=None, ge=-90, le=90)
    entry_longitude: Optional[float] = Field(default=None, ge=-180, le=180)
    exit_latitude: Optional[float] = Field(default=None, ge=-90, le=90)
    exit_longitude: Optional[float] = Field(default=None, ge=-180, le=180)
    destination_place_id: str = ""
    destination_latitude: Optional[float] = None
    destination_longitude: Optional[float] = None
    destination_address: str = ""
    # "Show me a different region." The cities already offered, sent back so
    # the planner can avoid them. Capped for the same reason as `legs`: this
    # text is interpolated into a billed prompt.
    exclude_cities: List[str] = Field(default_factory=list, max_length=24)


class OdysseyRoutePreviewResponse(BaseModel):
    """The route to show before a plan is paid for.

    `route` is handed back to /odyssey/generate untouched as `preset_route`
    when the traveller accepts it.
    """
    route: OdysseyRoute
    notice: str = ""


class OdysseySwapRequest(BaseModel):
    """Request body for swapping a single activity in a saved Odyssey for an
    AI-suggested alternative. `day_index` and `activity_index` are zero-based
    positions within the plan (day position, then activity within that day)."""
    day_index: int
    activity_index: int
    reason: str = ""

class OdysseyPartnerSwapRequest(BaseModel):
    """Request body for swapping a single booking partner in a saved Odyssey."""
    partner_name: str
    reason: str = ""

class OdysseyRideAppsResponse(BaseModel):
    """Ride apps for the itinerary's display-only chips under transport stops.
    `country` is the ISO code the apps are for, empty when none was usable."""
    country: str = ""
    apps: List[str] = Field(default_factory=list)

class ItineraryResponse(ItineraryBase):
    id: UUID
    user_id: UUID
    created_at: datetime

    class Config:
        from_attributes = True
