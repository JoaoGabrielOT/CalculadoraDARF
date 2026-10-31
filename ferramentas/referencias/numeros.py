"""Referências da aritmética do Python: round, format, repr, sum, max e min."""
import random

from . import base

FIXOS = [0.125, 0.375, 1.125, 2.5, -0.125, 2.675, 1.005, 0.005, -0.001, -0.0, 1e-05, 0.0001, 1e16,
         123456789.125, 5e-324]


def _valores():
    rng = random.Random(1)
    vals = list(FIXOS)
    for _ in range(2000):
        v = rng.uniform(1, 10) * 10 ** rng.randint(-10, 17)
        vals.append(-v if rng.random() < 0.4 else v)
    return vals


def casos():
    rng = random.Random(2)
    vals = _valores()
    out = []
    for i, x in enumerate(vals):
        for n in (0, 2, 3, 4, 6):
            out.append(base.caso(f"round {i} n={n}", "round", {"x": x, "casas": n}, round(x, n)))
        for n in (1, 2, 8):
            out.append(base.caso(f"format {i} .{n}f", "format",
                                 {"x": x, "casas": n, "sinal": False, "milhar": False}, format(x, f".{n}f")))
        out.append(base.caso(f"format {i} +.2f", "format",
                             {"x": x, "casas": 2, "sinal": True, "milhar": False}, format(x, "+.2f")))
        out.append(base.caso(f"format {i} ,.2f", "format",
                             {"x": x, "casas": 2, "sinal": False, "milhar": True}, format(x, ",.2f")))
        out.append(base.caso(f"repr {i}", "repr", {"x": x}, repr(x)))
    listas = [[0.1] * 10]
    for _ in range(500):
        listas.append([rng.choice(vals) if rng.random() < 0.3 else rng.uniform(-1000, 1000) * 10 ** rng.randint(-3, 3)
                       for _ in range(rng.randint(0, 60))])
    for i, lista in enumerate(listas):
        out.append(base.caso(f"sum {i}", "sum", {"valores": lista}, sum(lista)))
    pares = [(0.0, -0.0), (-0.0, 0.0), (0, -0.0), (-0.0, 0), (1.5, 1.5), (1.0, 2.0), (2.0, 1.0), (-1.0, -2.0)]
    for _ in range(100):
        pares.append((rng.choice(vals), rng.choice(vals)))
    for i, (a, b) in enumerate(pares):
        out.append(base.caso(f"max {i}", "max", {"a": a, "b": b}, max(a, b)))
        out.append(base.caso(f"min {i}", "min", {"a": a, "b": b}, min(a, b)))
    return out
