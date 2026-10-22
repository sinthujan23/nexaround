"""A vendor reaches their own rows and no others.

The scoping is in the SQL rather than in the endpoint bodies, so these tests
compile the statements and read the WHERE clause. Crude, but it catches the
regression that actually threatens this design: someone "simplifying" a scoped
helper back to the unscoped `get_package()` and comparing the owner afterwards.
"""
import inspect
import uuid

import pytest

from app.api.v1 import partner as P
from app.repositories.experience_repository import ExperienceRepository

VENDOR = uuid.UUID("11111111-1111-1111-1111-111111111111")
OTHER = uuid.UUID("22222222-2222-2222-2222-222222222222")
ROW = uuid.UUID("33333333-3333-3333-3333-333333333333")


class _Capture:
    """Stands in for the session, keeping whatever statement was executed."""

    def __init__(self):
        self.statements = []

    async def execute(self, stmt):
        self.statements.append(stmt)

        class _R:
            def scalar_one_or_none(self_inner):
                return None

            def one(self_inner):
                class _Row:
                    total = live = new = recent = 0
                return _Row()
        return _R()


def _sql(stmt) -> str:
    return str(stmt.compile(compile_kwargs={"literal_binds": True}))


def _in_sql(value: uuid.UUID, sql: str) -> bool:
    """A bound UUID is rendered without its hyphens."""
    return str(value) in sql or value.hex in sql


def _details(func) -> list:
    """The `detail` strings a function raises, comments excluded."""
    import ast as _ast

    tree = _ast.parse(_ast.unparse(_ast.parse(inspect.getsource(func))))
    out = []
    for node in _ast.walk(tree):
        if isinstance(node, _ast.Call) and getattr(node.func, "id", "") == "HTTPException":
            for kw in node.keywords:
                if kw.arg == "detail" and isinstance(kw.value, _ast.Constant):
                    out.append(str(kw.value.value))
    return out


def _status_codes(func) -> set:
    """The HTTP status codes a function actually raises.

    Read from the syntax tree rather than the source text: a plain substring
    search also matches the comments explaining why 403 is NOT used, which is
    exactly the sort of false failure that teaches people to delete tests.
    """
    import ast as _ast

    tree = _ast.parse(_ast.unparse(_ast.parse(inspect.getsource(func))))
    found = set()
    for node in _ast.walk(tree):
        if isinstance(node, _ast.Call) and getattr(node.func, "id", "") == "HTTPException":
            for kw in node.keywords:
                if kw.arg == "status_code" and isinstance(kw.value, _ast.Constant):
                    found.add(kw.value.value)
    return found


@pytest.mark.parametrize("method,args", [
    ("get_package_for_vendor", (ROW, VENDOR)),
])
def test_a_scoped_lookup_filters_on_both_id_and_vendor(method, args):
    """Two predicates, not one.

    With only `id` the helper would happily return another vendor's row and the
    safety would rest on a comparison in the endpoint — the thing this design
    exists to avoid.
    """
    import asyncio

    cap = _Capture()
    repo = ExperienceRepository(cap)
    asyncio.run(getattr(repo, method)(*args))

    sql = _sql(cap.statements[-1])
    assert "vendor_id" in sql, f"{method} is not scoped to a vendor:\n{sql}"
    assert _in_sql(VENDOR, sql), f"the vendor is not bound into the query:\n{sql}"
    assert _in_sql(ROW, sql)


def test_stats_are_counted_per_vendor_not_platform_wide():
    import asyncio

    cap = _Capture()
    asyncio.run(ExperienceRepository(cap).vendor_stats(VENDOR))

    assert cap.statements, "no query ran"
    for stmt in cap.statements:
        sql = _sql(stmt)
        assert "vendor_id" in sql, f"an unscoped aggregate leaks other vendors:\n{sql}"
        assert _in_sql(VENDOR, sql)
        # Counting, not loading: rows are not pulled into memory to show a
        # number.
        assert "count(" in sql.lower()


def test_vendors_have_no_enquiry_endpoints():
    """Requests come only to Nexaround, which contacts both sides itself, so
    a vendor cannot reach a traveller around the platform's commission."""
    paths = [r.path for r in P.router.routes]
    assert not [p for p in paths if "enquir" in p], paths


def test_package_creation_cannot_be_filed_under_another_vendor():
    """`vendor_id` is taken from the principal, so the body cannot supply one."""
    from app.schemas.partner import PartnerPackageCreate

    assert "vendor_id" not in PartnerPackageCreate.model_fields
    source = inspect.getsource(P.create_partner_package)
    assert "vendor_id=principal.vendor.id" in source


@pytest.mark.parametrize("endpoint", [
    P.get_partner_package, P.update_partner_package, P.delete_partner_package,
])
def test_every_single_package_endpoint_uses_the_scoped_lookup(endpoint):
    source = inspect.getsource(endpoint)
    assert "get_package_for_vendor" in source, (
        f"{endpoint.__name__} does not use the scoped lookup"
    )
    assert "repo.get_package(" not in source, (
        f"{endpoint.__name__} uses the unscoped lookup"
    )


@pytest.mark.parametrize("endpoint", [
    P.get_partner_package, P.update_partner_package, P.delete_partner_package,
])
def test_a_miss_is_404_and_says_nothing_about_who_owns_it(endpoint):
    """403 would confirm the id exists and belongs to someone else.

    That is an enumeration oracle over the whole marketplace, so a row this
    vendor cannot see is indistinguishable from a row that does not exist.
    """
    codes = _status_codes(endpoint)
    assert 404 in codes, f"{endpoint.__name__} never 404s on a miss"
    # 403 is the one that must never appear on a lookup: it would confirm the
    # row exists and belongs to someone else. Other codes are fine: a 400 on
    # bad input says nothing about ownership.
    assert 403 not in codes, (
        f"{endpoint.__name__} raises 403; a row this vendor cannot see must be "
        f"indistinguishable from one that does not exist"
    )
    # And the message itself must not say whose row it is. Read from the AST,
    # not the source text — the comment explaining why 403 is avoided would
    # otherwise trip this and teach the next person to delete the test.
    for message in _details(endpoint):
        low = message.lower()
        for leak in ("belongs to", "another vendor", "not yours", "forbidden"):
            assert leak not in low, f"the 404 message leaks ownership: {message!r}"


def test_the_profile_update_cannot_move_the_vendor():
    """Where the business is is an admin's to set (a vendor could otherwise
    put a meeting place in front of travellers), so the vendor's save never
    touches the point, and so never has packages to drag along."""
    source = inspect.getsource(P.update_partner_profile)
    assert "location" not in source
    assert "apply_vendor_cascade" not in source
    assert "db.commit" in source
