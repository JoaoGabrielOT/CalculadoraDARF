"""Referências do preço-alvo e da projeção de venda (metas.py:42-111).

Funções (campo `funcao` de cada caso):
- preco_alvo: entrada {lote, qtd, lucro, day_trade, corretagem}; saída é o resultado de calcular_preco_alvo
  ou {"erro": mensagem}. qtd e lucro não finitos vêm como texto ("inf", "-inf", "nan").
- centavo: entrada {valores}; saída {"teto": [...], "piso": [...]}.
"""
import random

from . import base

mt = base.mt
nc = base.nc

QTDS = [1, 7, 100, 333, 100000]
LUCROS = [-200, 0, 0.01, 1000, 12345.67, 1e6]
PRECOS = [0.37, 10.0, 33.33]
CORRETAGENS = [0.0, 2.5]
FIXOS = [21.7743, 21.77, 21.770000000001, 5.999999999, 5.989, 5.981]


def _lote(preco):
    return {"id": "L1", "ticker": "PETR4", "tipo": "Ação", "data_compra": "2026-10-01", "qtd": 100,
            "preco": preco, "vendas": [], "mod": 0}


def _numero(v):
    return float(v) if isinstance(v, str) else v


def _calcular(entrada):
    antes = nc.CORRETAGEM_POR_ORDEM
    nc.CORRETAGEM_POR_ORDEM = entrada["corretagem"]
    try:
        return mt.calcular_preco_alvo(entrada["lote"], _numero(entrada["qtd"]), _numero(entrada["lucro"]),
                                      entrada["day_trade"])
    except ValueError as e:
        return {"erro": str(e)}
    finally:
        nc.CORRETAGEM_POR_ORDEM = antes


def _precos():
    out = []
    for qtd in QTDS:
        for lucro in LUCROS:
            for day_trade in (False, True):
                for preco in PRECOS:
                    for corretagem in CORRETAGENS:
                        entrada = {"lote": _lote(preco), "qtd": qtd, "lucro": lucro, "day_trade": day_trade,
                                   "corretagem": corretagem}
                        nome = f"q{qtd}_l{lucro}_{'dt' if day_trade else 'sw'}_p{preco}_c{corretagem}"
                        out.append(base.caso(nome, "preco_alvo", entrada, _calcular(entrada)))
    return out


def _erros():
    out = []
    lote = _lote(10.0)
    for nome, qtd, lucro in (("qtd_zero", 0, 1000), ("qtd_negativa", -5, 1000), ("qtd_inf", "inf", 1000),
                             ("qtd_nan", "nan", 1000), ("lucro_inf", 100, "inf"), ("lucro_nan", 100, "nan"),
                             ("lucro_menos_inf", 100, "-inf"), ("preco_negativo", 100, -5000),
                             ("lucro_gigante", 100, 1.7e308), ("qtd_minuscula", 1e-320, 1000),
                             ("qtd_gigante", 1e308, 1e308), ("qtd_fracionaria", 0.5, 100)):
        entrada = {"lote": lote, "qtd": qtd, "lucro": lucro, "day_trade": False, "corretagem": 0.0}
        out.append(base.caso(f"erro_{nome}", "preco_alvo", entrada, _calcular(entrada)))
    return out


def _centavos():
    rnd = random.Random(16)
    valores = list(FIXOS) + [0.0, -0.0, 0.005, -0.001, -0.5, 0.01, 1e-9, 1234567.891, 1e15]
    while len(valores) < 500:
        c = rnd.random()
        if c < 0.4:
            valores.append(rnd.uniform(0, 500))
        elif c < 0.7:
            valores.append(rnd.randint(1, 100000) / 100 + rnd.choice([0.0, 1e-9, -1e-9, 1e-7, 4e-7]))
        else:
            valores.append(round(rnd.uniform(0.01, 300), 3))
    return [base.caso("teto_e_piso", "centavo", {"valores": valores},
                      {"teto": [mt.teto_centavo(v) for v in valores], "piso": [mt.piso_centavo(v) for v in valores]})]


def casos():
    return _precos() + _erros() + _centavos()
