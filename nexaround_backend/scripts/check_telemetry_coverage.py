#!/usr/bin/env python3
"""Fail the build if an outbound HTTP call is made outside a telemetry block.

The inventory of instrumented call sites is only useful if it cannot silently
shrink. This script is that guarantee: it finds every outbound request in the
backend and checks each one sits inside an `async with telemetry.track(...)`.

Run it directly:

    python scripts/check_telemetry_coverage.py

Exit codes: 0 clean, 1 violations found.

Adding a genuinely exempt call site means adding it to ALLOWLIST below, with a
reason. That is deliberately a visible, reviewable edit rather than something
that can happen by omission.
"""
from __future__ import annotations

import ast
import sys
from pathlib import Path

BACKEND_ROOT = Path(__file__).resolve().parent.parent
APP_DIR = BACKEND_ROOT / "app"

# Attribute calls that reach the network.
NETWORK_CALLS = {"get", "post", "put", "patch", "delete", "request", "send", "stream"}

# Modules whose call surface is HTTP.
HTTP_MODULES = {"httpx", "requests", "aiohttp"}

# Constructors that produce an HTTP client. A name bound to one of these is
# tracked per-scope, so `session.delete(...)` on a SQLAlchemy session and
# `resp.json().get(...)` on a dict are not mistaken for network calls — which a
# name-substring heuristic gets wrong constantly.
CLIENT_CTORS = {"AsyncClient", "Client", "ClientSession", "Session"}

# One-off maintenance and seeding scripts. They are run by hand, not by the
# service, and are out of scope for request-path telemetry.
SKIP_DIRS = {"scripts", "__pycache__"}
SKIP_FILE_PREFIXES = ("check_", "run_", "find_", "update_", "test_", "_")

# (relative path, function name) → reason for exemption.
ALLOWLIST: dict[tuple[str, str], str] = {
    ("services/telemetry.py", "*"):
        "The telemetry module itself; instrumenting it would recurse.",
    ("services/auth_service.py", "_fetch_apple_jwks"):
        "Apple public-key fetch on the login path. Free, cached in process, and "
        "telemetry must never sit between a user and authentication.",
}


def _ctor_module(node: ast.AST) -> bool:
    """True if the expression constructs an HTTP client, e.g. httpx.AsyncClient()."""
    if not isinstance(node, ast.Call):
        return False
    func = node.func
    if isinstance(func, ast.Attribute) and func.attr in CLIENT_CTORS:
        base = func.value
        return isinstance(base, ast.Name) and base.id in HTTP_MODULES
    # Bare `AsyncClient()` after `from httpx import AsyncClient`
    return isinstance(func, ast.Name) and func.id in CLIENT_CTORS


def _target_name(node: ast.AST) -> str | None:
    """Render an assignment target as a comparable name: `x` or `self._client`."""
    if isinstance(node, ast.Name):
        return node.id
    if isinstance(node, ast.Attribute) and isinstance(node.value, ast.Name):
        return f"{node.value.id}.{node.attr}"
    return None


TRACK_NAMES = {"track", "track_sync"}


def _is_track_call(node: ast.Call) -> bool:
    func = node.func
    if isinstance(func, ast.Attribute) and func.attr in TRACK_NAMES:
        return True
    return isinstance(func, ast.Name) and func.id in TRACK_NAMES


class Visitor(ast.NodeVisitor):
    """Walks a module tracking whether we are inside a `track()` block."""

    def __init__(self, relpath: str) -> None:
        self.relpath = relpath
        self.violations: list[tuple[int, str, str]] = []
        self._func_stack: list[str] = []
        self._track_depth = 0
        # Names currently bound to an HTTP client, module-wide. Scoping this
        # per-function would miss `self._client` set in __init__ and used in a
        # method, which is how google_lens_service is written.
        self._clients: set[str] = set()

    # -- client binding ------------------------------------------------------

    def visit_Assign(self, node: ast.Assign) -> None:
        if _ctor_module(node.value):
            for target in node.targets:
                name = _target_name(target)
                if name:
                    self._clients.add(name)
        self.generic_visit(node)

    def visit_AnnAssign(self, node: ast.AnnAssign) -> None:
        if node.value is not None and _ctor_module(node.value):
            name = _target_name(node.target)
            if name:
                self._clients.add(name)
        self.generic_visit(node)

    def _is_network_call(self, node: ast.Call) -> bool:
        func = node.func
        if not isinstance(func, ast.Attribute) or func.attr not in NETWORK_CALLS:
            return False
        value = func.value
        # httpx.get(...) / requests.post(...)
        if isinstance(value, ast.Name) and value.id in HTTP_MODULES:
            return True
        # httpx.AsyncClient().get(...) — constructed inline
        if _ctor_module(value):
            return True
        name = _target_name(value)
        return name is not None and name in self._clients

    # -- context tracking ----------------------------------------------------

    def _visit_func(self, node) -> None:
        self._func_stack.append(node.name)
        self.generic_visit(node)
        self._func_stack.pop()

    visit_FunctionDef = _visit_func
    visit_AsyncFunctionDef = _visit_func

    def visit_AsyncWith(self, node: ast.AsyncWith) -> None:
        opened = 0
        for item in node.items:
            expr = item.context_expr
            if isinstance(expr, ast.Call) and _is_track_call(expr):
                opened += 1
            # `async with httpx.AsyncClient() as client:` binds a client name.
            elif _ctor_module(expr) and item.optional_vars is not None:
                name = _target_name(item.optional_vars)
                if name:
                    self._clients.add(name)
        self._track_depth += opened
        self.generic_visit(node)
        self._track_depth -= opened

    def visit_With(self, node: ast.With) -> None:
        opened = 0
        for item in node.items:
            expr = item.context_expr
            if isinstance(expr, ast.Call) and _is_track_call(expr):
                opened += 1
            elif _ctor_module(expr) and item.optional_vars is not None:
                name = _target_name(item.optional_vars)
                if name:
                    self._clients.add(name)
        self._track_depth += opened
        self.generic_visit(node)
        self._track_depth -= opened

    # -- the check -----------------------------------------------------------

    def visit_Call(self, node: ast.Call) -> None:
        if self._track_depth == 0 and self._is_network_call(node):
            func_name = self._func_stack[-1] if self._func_stack else "<module>"
            if not self._allowed(func_name):
                self.violations.append((node.lineno, func_name, ast.unparse(node.func)))
        self.generic_visit(node)

    def _allowed(self, func_name: str) -> bool:
        return (
            (self.relpath, func_name) in ALLOWLIST
            or (self.relpath, "*") in ALLOWLIST
        )


def main() -> int:
    violations: list[str] = []
    scanned = 0

    for path in sorted(APP_DIR.rglob("*.py")):
        if SKIP_DIRS & set(path.parts):
            continue
        if path.name.startswith(SKIP_FILE_PREFIXES):
            continue
        relpath = str(path.relative_to(APP_DIR))
        try:
            tree = ast.parse(path.read_text(encoding="utf-8"))
        except SyntaxError as e:
            print(f"  ! could not parse {relpath}: {e}", file=sys.stderr)
            continue
        scanned += 1
        visitor = Visitor(relpath)
        visitor.visit(tree)
        for lineno, func, call in visitor.violations:
            violations.append(f"  app/{relpath}:{lineno}  in {func}()  →  {call}(...)")

    print(f"telemetry coverage: scanned {scanned} modules")

    if violations:
        print(
            f"\nFAIL — {len(violations)} outbound call(s) not wrapped in "
            f"telemetry.track():\n"
        )
        print("\n".join(violations))
        print(
            "\nWrap each in `async with telemetry.track(provider, operation, ...)`\n"
            "and mark the outcome with t.hit(source) or t.upstream(response).\n"
            "If the call is genuinely exempt, add it to ALLOWLIST in this script\n"
            "with a reason.\n"
        )
        return 1

    print("PASS — every outbound call is instrumented")
    return 0


if __name__ == "__main__":
    sys.exit(main())
