"""Trip Wallet maths: splits, balances, settling up, amounts, invite codes.

Pure functions only (app/services/trip_wallet.py); no database.
"""
import pytest

from app.services import trip_wallet as tw


def test_split_equal_gives_leftover_to_first():
    assert tw.split_equal(100, ["a", "b", "c"]) == {"a": 34, "b": 33, "c": 33}
    assert sum(tw.split_equal(2_200_000, list("ABCDEF")).values()) == 2_200_000


def test_split_equal_needs_people_once():
    with pytest.raises(ValueError):
        tw.split_equal(100, [])
    with pytest.raises(ValueError):
        tw.split_equal(100, ["a", "a"])


def test_check_exact():
    assert tw.check_exact(1000, {"a": 600, "b": 400, "c": 0}) == {"a": 600, "b": 400}
    with pytest.raises(ValueError):
        tw.check_exact(1000, {"a": 600, "b": 300})
    with pytest.raises(ValueError):
        tw.check_exact(1000, {"a": 1100, "b": -100})
    with pytest.raises(ValueError):
        tw.check_exact(0, {"a": 0})


def _tl_example():
    """TL's six friends: hotel, taxi, food, activities, all split by six."""
    people = list("ABCDEF")
    expenses = [
        ("A", 1_200_000, tw.split_equal(1_200_000, people)),
        ("B", 400_000, tw.split_equal(400_000, people)),
        ("C", 300_000, tw.split_equal(300_000, people)),
        ("D", 300_000, tw.split_equal(300_000, people)),
    ]
    return people, expenses


def test_balances_add_up_to_zero():
    people, expenses = _tl_example()
    rows = tw.balances(people, expenses)
    assert sum(r["net"] for r in rows.values()) == 0
    assert rows["A"]["paid"] == 1_200_000
    assert rows["E"]["paid"] == 0
    assert rows["E"]["net"] < 0


def test_tl_example_settles_in_five_payments():
    people, expenses = _tl_example()
    nets = {m: r["net"] for m, r in tw.balances(people, expenses).items()}
    payments = tw.settle_up(nets, people)
    assert len(payments) == 5  # at most people − 1
    after = dict(nets)
    for frm, to, amount in payments:
        assert amount > 0
        after[frm] += amount
        after[to] -= amount
    assert all(v == 0 for v in after.values())
    # Everyone who owes pays; nobody who is owed pays.
    assert {p[0] for p in payments} == {"C", "D", "E", "F"}


def test_settlements_move_balances():
    people = ["A", "B"]
    expenses = [("A", 1000, {"A": 500, "B": 500})]
    nets = {m: r["net"] for m, r in tw.balances(people, expenses).items()}
    assert tw.settle_up(nets, people) == [("B", "A", 500)]
    rows = tw.balances(people, expenses, [("B", "A", 500)])
    assert rows["A"]["net"] == 0 and rows["B"]["net"] == 0
    assert tw.settle_up({m: r["net"] for m, r in rows.items()}, people) == []


def test_settle_up_is_stable_on_ties():
    nets = {"a": 100, "b": -50, "c": -50}
    assert tw.settle_up(nets, ["a", "b", "c"]) == [("b", "a", 50), ("c", "a", 50)]


@pytest.mark.parametrize("amount,currency,minor", [
    ("4000", "INR", 400000),
    ("4,000.50", "inr", 400050),
    (12.5, "USD", 1250),
    ("1500", "JPY", 1500),
    ("1.234", "KWD", 1234),
])
def test_to_minor(amount, currency, minor):
    assert tw.to_minor(amount, currency) == minor


@pytest.mark.parametrize("amount,currency", [
    ("0", "INR"), ("-5", "INR"), ("abc", "INR"), ("1.234", "USD"), ("1.5", "JPY"),
    ("nan", "USD"), ("1e20", "USD"),
])
def test_to_minor_rejects(amount, currency):
    with pytest.raises(ValueError):
        tw.to_minor(amount, currency)


def test_format_amount():
    assert tw.format_amount(400000, "INR") == "INR 4,000"
    assert tw.format_amount(400050, "INR") == "INR 4,000.50"
    assert tw.format_amount(1500, "JPY") == "JPY 1,500"


def test_invite_code():
    for _ in range(50):
        code = tw.make_invite_code()
        assert len(code) == tw.INVITE_LENGTH
        assert set(code) <= set(tw.INVITE_ALPHABET)
        assert not set(code) & set("01OIL")
    assert tw.normalise_code(" ab-c2 d3 ") == "ABC2D3"
