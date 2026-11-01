"""Referências do `sum()` do Python 3.12 sobre números mistos (int e float).

Funções (campo `funcao` de cada caso):
- sum_misto: entrada {valores: [int | float]}; saída `sum(valores)` com o tipo do Python (int ou float).
"""
import random

from . import base


def _valor(rng):
    if rng.random() < 0.5:
        return rng.randint(-10**6, 10**6)
    if rng.random() < 0.4:
        return rng.choice([0.1, 0.2, 0.3, 1e-9, 1e16, -1e16, 1e-7, 2.5, 1e15 + 0.5])
    return rng.uniform(-1e6, 1e6)


def _caso(nome, valores):
    return base.caso(nome, "sum_misto", {"valores": valores}, sum(valores))


def casos():
    rng = random.Random(7)
    out = [_caso(f"aleatorio_{i}", [_valor(rng) for _ in range(rng.randint(0, 40))]) for i in range(400)]
    fixos = [("vazio", []), ("dois_inteiros", [30, 31]), ("dez_decimos", [0.1] * 10),
             ("int_e_floats", [1, 0.1, 0.2, 2, 0.3]), ("cancelamento", [0.1, 1, 1e16, 1, -1e16])]
    return out + [_caso(n, v) for n, v in fixos]
