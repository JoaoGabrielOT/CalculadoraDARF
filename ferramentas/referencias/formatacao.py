"""Referências de formatação de moeda/percentual e leitura de valores digitados (nucleo.py, mercado.py, sugestoes.py)."""
import random

from . import base

nc, mk, sg = base.nc, base.mk, base.sg

FIXOS_BRL = [-0.004, -0.005, 0.125, 1.125, 1234567.891, -1234.5]
TEXTOS = ["10.000,50", "-250", "R$ 0", "1.234", "10.000", "12,5", " R$ 1.234,56 ", "inf", "nan", "abc", "0", "",
          "-0", "--5", "1.234.567", "1.23", "-1.234", "1e3", "-inf", "R$-10,5", "0,0", "1.234,5.6"]
TEXTOS_NUM = TEXTOS + ["5", "-5", "0,001", "R$ 1.000,00"]


def _erro(fn, *args):
    try:
        return fn(*args)
    except Exception as e:  # noqa: BLE001 - o nome da exceção é a referência
        return {"erro": type(e).__name__}


def _texto_float(r):
    """float não finito não cabe em JSON: a referência de float é o repr do resultado."""
    return r if isinstance(r, dict) else repr(r)


def casos():
    out = []
    rnd = random.Random(20261031)
    aleatorios = []
    for i in range(500):
        mag = rnd.choice([1, 10, 100, 1000, 100000, 10000000])
        v = rnd.uniform(-1, 1) * mag
        if i % 5 == 0:
            v = round(v, rnd.choice([2, 3]))  # perto do meio do centavo
        aleatorios.append(v)
    for i, v in enumerate(aleatorios):
        out.append(base.caso(f"brl aleatório {i}", "brl", {"v": v}, nc.brl(v)))
    for i, v in enumerate(FIXOS_BRL):
        out.append(base.caso(f"empate_centavo {i}", "brl", {"v": v}, nc.brl(v)))
    for i, v in enumerate([0.0, -0.0, 0.004, -0.0041, 999.995, 0.005, 1e9]):
        out.append(base.caso(f"brl borda {i}", "brl", {"v": v}, nc.brl(v)))
    for i, s in enumerate(TEXTOS_NUM):
        out.append(base.caso(f"parse_num {i}", "parse_num", {"s": s}, _texto_float(_erro(nc.parse_num, s))))
    for i, s in enumerate(TEXTOS + [None]):
        out.append(base.caso(f"parse_valor {i}", "parse_valor", {"s": s}, _texto_float(_erro(nc.parse_valor, s))))
    for i, v in enumerate([32.5, 1e-9, 123.456789012, 0.0, 10.0, 1234.5, 0.005, 100.0, 5e-9, -3.25]):
        out.append(base.caso(f"fmt_num {i}", "fmt_num", {"v": v}, nc.fmt_num(v)))
    for i, s in enumerate(["100", "1.000", " 5 ", "0", "-3", "abc", "", "1,5", "10.000.000", "1_0", "007"]):
        out.append(base.caso(f"parse_qtd {i}", "parse_qtd", {"s": s}, _erro(nc.parse_qtd, s)))
    for i, v in enumerate([0.0, 1.0, 1.125, 2.675, 32.5, 1234.567, -0.0, -3.5, 0.005]):
        out.append(base.caso(f"preco_texto {i}", "preco_texto", {"v": v}, nc.preco_texto(v)))
    for i, res in enumerate([None, (10.0, 2.5), (-0.003, -0.01), (0.004, 0.0), (0.005, 0.125), (-1234.5, -12.345),
                             (1234567.891, 99.995)]):
        out.append(base.caso(f"fmt_resultado {i}", "fmt_resultado", {"res": res}, nc.fmt_resultado(res)))
    for i, v in enumerate([None, 0.004, -0.004, 12.345, 0.0, -0.0, 0.005, 100.0, -12.345]):
        for sinal in (True, False):
            out.append(base.caso(f"fmt_pct {i} sinal={sinal}", "fmt_pct", {"v": v, "sinal": sinal},
                                 mk.fmt_pct(v, sinal)))
    for i, v in enumerate([None, 0, 999, 1000, 1.5e6, 2.3e9, 999999.9, 0.0, 1e12, 5.5, -5, 1999.9, 1e9, 999.99]):
        out.append(base.caso(f"fmt_volume {i}", "fmt_volume", {"v": v}, mk.fmt_volume(v)))
    for i, (v, casas) in enumerate([(1.25, 1), (1.25, 2), (0.05, 1), (2.675, 2), (-0.04, 1), (10.0, 0), (3.14159, 3),
                                    (0.0, 1), (1234.5678, 2)]):
        out.append(base.caso(f"fmt_dec {i}", "fmt_dec", {"v": v, "casas": casas}, sg._fmt_dec(v, casas)))
        if casas == 1:
            out.append(base.caso(f"fmt_dec padrão {i}", "fmt_dec", {"v": v}, sg._fmt_dec(v)))
    return out
