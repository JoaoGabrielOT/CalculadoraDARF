"""Referências de `_dados_api` com inteiros misturados a floats no chart do Yahoo (mercado.py:336-375).

Mesma rede falsa e mesmo congelamento de `yahoo.py`.

Funções (campo `funcao` de cada caso):
- dados_api: entrada {ticker, nome_conhecido, resposta}; saída = dict de `_dados_api` ou {"erro", "mensagem"}.
"""
import random

from . import yahoo


def _num(rng, x, p_int):
    """Valor `x` como int (arredondado, nunca 0) com probabilidade p_int; senão float."""
    if rng.random() < p_int:
        return max(1, round(x))
    return round(x, 4)


def _resposta(rng, n, p_int, meta_int):
    ts = [1758000000 + i * 86400 for i in range(n)]
    hi, lo, cl = [], [], []
    for _ in range(n):
        c = rng.uniform(5, 60)
        hi.append(_num(rng, c + rng.uniform(0.2, 2), p_int))
        lo.append(_num(rng, c - rng.uniform(0.2, 2), p_int))
        cl.append(_num(rng, c, p_int))
    preco = rng.randint(5, 60) if meta_int else round(rng.uniform(5, 60), 2)
    meta = {"gmtoffset": -10800, "regularMarketTime": ts[-1], "regularMarketPrice": preco,
            "longName": "Ativo sintético", "regularMarketDayHigh": rng.randint(5, 60),
            "regularMarketDayLow": rng.randint(1, 5), "fiftyTwoWeekHigh": rng.randint(60, 90),
            "fiftyTwoWeekLow": round(rng.uniform(1, 5), 2), "regularMarketVolume": rng.randint(1000, 10**7)}
    return {"meta": meta, "timestamp": ts, "indicators": {"quote": [{"high": hi, "low": lo, "close": cl}]}}


def casos():
    rng = random.Random(23)
    out = []
    for i in range(30):
        n = rng.choice([15, 16, 30, 60, 90, 127])
        p_int = [1.0, 0.5, 0.1, 0.9, 0.3][i % 5]
        out.append(yahoo._api(f"inteiros_{i}_p{p_int}", "PETR4", "", _resposta(rng, n, p_int, i % 2 == 0)))
    return out
