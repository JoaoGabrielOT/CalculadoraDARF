"""Referências da apuração do mês e das regras de compra e venda (nucleo.py:259-375, 444-452, 459-485, 520-524).

Cada caso de `apurar` traz o mês, a corretagem por ordem usada e, na saída, a apuração (com `ops`), `info_darf` e
`mensagem_fechamento` do mês seguinte.
"""
import copy
import random

from . import base

nc = base.nc

ACOES = ["PETR4", "VALE3", "ITUB4", "TAEE11", "BBAS3", "WEGE3", "MGLU3", "ABEV3"]
BDRS = ["AAPL34", "T1TW34", "MSFT34", "NVDC34"]


class _Fabrica:
    """Ids sequenciais e montagem de meses sintéticos."""

    def __init__(self):
        self.n = 0

    def id(self, prefixo):
        self.n += 1
        return f"{prefixo}{self.n:04d}"

    def venda(self, data, qtd, preco):
        return {"id": self.id("v"), "data": data, "qtd": qtd, "preco": preco, "mod": 0}

    def lote(self, ticker, data, qtd, preco, vendas=(), tipo=None):
        return {"id": self.id("l"), "ticker": ticker, "tipo": tipo or nc.tipo_por_ticker(ticker),
                "data_compra": data, "qtd": qtd, "preco": preco, "vendas": list(vendas), "mod": 0}

    def mes(self, mes, lotes, darf_anterior=0.0):
        return {"mes": mes, "fechado": False, "darf_anterior": darf_anterior, "lotes": list(lotes),
                "excluidos": {}, "mod": 0}


def _dia(mes, d):
    return f"{mes}-{d:02d}"


def _mes_aleatorio(rnd, f, mes):
    """Compras com preços float quaisquer; parte das vendas no dia da compra (day trade)."""
    lotes = []
    for _ in range(rnd.randint(1, 6)):
        ticker = rnd.choice(ACOES + BDRS)
        dia = rnd.randint(1, 20)
        qtd = rnd.choice([1, 3, 10, 100, 250, 1000, rnd.randint(1, 3000)])
        preco = rnd.uniform(2, 400)
        if rnd.random() < 0.3:
            preco = round(preco, 2)
        restante = qtd
        vendas = []
        for _ in range(rnd.randint(0, 3)):
            if restante <= 0:
                break
            q = restante if rnd.random() < 0.4 else rnd.randint(1, restante)
            restante -= q
            d_venda = dia if rnd.random() < 0.35 else rnd.randint(dia, 28)
            vendas.append(f.venda(_dia(mes, d_venda), q, preco * rnd.uniform(0.85, 1.2)))
        lotes.append(f.lote(ticker, _dia(mes, dia), qtd, preco, vendas))
    return lotes


def _meses_especiais(f):
    """Fronteira da isenção, IRRF, prejuízo, várias vendas no mesmo dia e tipo desconhecido."""
    out = []
    m = "2026-03"
    # vendas de ações no swing de exatamente 20000.0 (isento) e 20000.01 (tributa)
    out.append(f.mes(m, [f.lote("PETR4", _dia(m, 2), 100, 150.0, [f.venda(_dia(m, 9), 100, 200.0)])]))
    out.append(f.mes(m, [f.lote("PETR4", _dia(m, 2), 100, 150.0, [f.venda(_dia(m, 9), 100, 200.0001)])]))
    out.append(f.mes(m, [f.lote("PETR4", _dia(m, 2), 100, 150.0, [f.venda(_dia(m, 9), 100, 199.9999)])]))
    # swing com IRRF acima de R$ 1 num dia (venda > 20000) e várias vendas no mesmo dia
    out.append(f.mes(m, [
        f.lote("VALE3", _dia(m, 3), 500, 60.5, [f.venda(_dia(m, 12), 200, 75.3), f.venda(_dia(m, 12), 300, 76.1)]),
        f.lote("ITUB4", _dia(m, 4), 400, 30.25, [f.venda(_dia(m, 12), 400, 36.7)]),
    ], darf_anterior=2.5))
    # swing de BDR com lucro (sempre tributa) e ação isenta com prejuízo
    out.append(f.mes(m, [
        f.lote("AAPL34", _dia(m, 3), 100, 45.1, [f.venda(_dia(m, 20), 100, 52.9)]),
        f.lote("PETR4", _dia(m, 3), 100, 38.0, [f.venda(_dia(m, 20), 100, 30.2)]),
    ]))
    # day trade com IRRF acima de R$ 1 (lucro do dia > 100) e dois day trades no mesmo dia
    out.append(f.mes(m, [
        f.lote("PETR4", _dia(m, 5), 1000, 30.0, [f.venda(_dia(m, 5), 1000, 31.4)]),
        f.lote("VALE3", _dia(m, 5), 200, 60.0, [f.venda(_dia(m, 5), 120, 60.9), f.venda(_dia(m, 5), 80, 60.2)]),
    ]))
    # mês de prejuízo: day trade e swing negativos
    out.append(f.mes(m, [
        f.lote("BBAS3", _dia(m, 6), 300, 27.0, [f.venda(_dia(m, 6), 300, 26.1)]),
        f.lote("MGLU3", _dia(m, 6), 3000, 8.0, [f.venda(_dia(m, 18), 3000, 6.5)]),
        f.lote("MSFT34", _dia(m, 6), 50, 70.0, [f.venda(_dia(m, 18), 50, 64.0)]),
    ]))
    # lucro pequeno: DARF abaixo de R$ 10 acumula
    out.append(f.mes(m, [f.lote("MSFT34", _dia(m, 6), 10, 100.0, [f.venda(_dia(m, 18), 10, 103.0)])],
                     darf_anterior=1.25))
    # sem vendas, mês vazio e tipo que não é Ação nem BDR
    out.append(f.mes(m, [f.lote("PETR4", _dia(m, 6), 10, 30.0)]))
    out.append(f.mes(m, []))
    out.append(f.mes(m, [f.lote("HGLG11", _dia(m, 2), 100, 150.0, [f.venda(_dia(m, 9), 100, 170.0)],
                                tipo="FII")]))
    return out


def _caso_apurar(nome, d, corretagem):
    nc.CORRETAGEM_POR_ORDEM = corretagem
    try:
        r = nc.apurar(copy.deepcopy(d))
        prox = nc.proximo_mes(d["mes"])
        saida = {"apuracao": r, "info_darf": nc.info_darf(r, d["mes"]),
                 "mensagem_fechamento": nc.mensagem_fechamento(r, prox)}
    finally:
        nc.CORRETAGEM_POR_ORDEM = 0.0
    return base.caso(nome, "apurar", {"mes": d, "corretagem": corretagem}, saida)


def casos():
    rnd = random.Random(2)
    f = _Fabrica()
    out = []

    meses = _meses_especiais(f)
    for i in range(60):
        mes = f"2026-{rnd.randint(1, 12):02d}"
        da = rnd.choice([0.0, 0.0, 3.75, 12.0, 0.01])
        meses.append(f.mes(mes, _mes_aleatorio(rnd, f, mes), da))

    for i, d in enumerate(meses):
        corretagem = rnd.choice([0.0, 0.0, 4.9, 2.5, 0.37])
        out.append(_caso_apurar(f"mês {i}", d, corretagem))

    # a fronteira da isenção é a esperada
    assert out[0]["saida"]["apuracao"]["vendas_acoes_st"] == 20000.0 and out[0]["saida"]["apuracao"]["isento"]
    assert not out[1]["saida"]["apuracao"]["isento"] and out[2]["saida"]["apuracao"]["isento"]
    infos = {c["saida"]["info_darf"][:6] for c in out}
    assert {"Código", "Abaixo", "Nada a"} <= infos, infos
    ops = [o for c in out for o in c["saida"]["apuracao"]["ops"]]
    assert any(o["regime"] == "Day trade" for o in ops) and any(o["regime"] == "Swing (isento)" for o in ops)
    assert any(c["saida"]["apuracao"]["irrf"] > 0 for c in out)
    assert any(c["entrada"]["corretagem"] > 0 for c in out)
    # swing com IRRF do dia entre 0 e R$ 1: rejeitado pelo filtro `> 1`
    def _dia_irrf_baixo(c):
        por_dia = {}
        for o in c["saida"]["apuracao"]["ops"]:
            if not o["dt"]:
                por_dia[o["data"]] = por_dia.get(o["data"], 0.0) + o["venda"] * nc.IRRF_SWING
        return any(0 < x <= 1 for x in por_dia.values())
    assert any(_dia_irrf_baixo(c) for c in out if c["funcao"] == "apurar")

    # calcular_venda, com e sem corretagem, day trade e swing, quantidade inteira e fracionária
    for i in range(80):
        qtd = rnd.choice([1, 7, 100, rnd.randint(1, 5000)])
        preco = rnd.uniform(1, 300)
        lote = f.lote(rnd.choice(ACOES), "2026-10-05", qtd, preco)
        q = rnd.randint(1, qtd)
        if i % 4 == 3:
            q = q + 0.5 if q < qtd else q - 0.5   # quantidade fracionária (metas.projetar)
            q = max(q, 0.5)
        data = "2026-10-05" if i % 2 == 0 else "2026-10-19"
        corretagem = rnd.choice([0.0, 4.9, 1.15])
        preco_venda = preco * rnd.uniform(0.8, 1.3)
        nc.CORRETAGEM_POR_ORDEM = corretagem
        try:
            c = nc.calcular_venda(lote, {"qtd": q, "preco": preco_venda, "data": data})
        finally:
            nc.CORRETAGEM_POR_ORDEM = 0.0
        out.append(base.caso(f"calcular_venda {i}", "calcular_venda",
                             {"lote": lote, "qtd": q, "preco": preco_venda, "data": data,
                              "corretagem": corretagem}, c))

    # vendido, restante, status_lote, sem_venda
    qtd_lote = 300
    for nome, vendas in [("sem vendas", []), ("parcial", [(100, "a")]), ("duas", [(100, "a"), (50, "b")]),
                         ("tudo", [(300, "a")]), ("tudo em duas", [(120, "a"), (180, "b")])]:
        lote = f.lote("PETR4", "2026-10-05", qtd_lote, 30.5,
                      [{"id": vid, "data": "2026-10-09", "qtd": q, "preco": 31.0, "mod": 0} for q, vid in vendas])
        out.append(base.caso(f"regras {nome}", "regras", {"lote": lote, "venda_id": "a"}, {
            "vendido": nc.vendido(lote), "restante": nc.restante(lote), "status": nc.status_lote(lote),
            "sem_venda": nc.sem_venda(lote, "a")}))
    lote_origem = f.lote("PETR4", "2026-10-05", 50, 30.5, [f.venda("2026-10-09", 20, 31.0)])
    lote_origem["origem"] = "x1"
    out.append(base.caso("regras com origem", "regras", {"lote": lote_origem, "venda_id": lote_origem["vendas"][0]["id"]},
                         {"vendido": 20, "restante": 30, "status": nc.status_lote(lote_origem),
                          "sem_venda": nc.sem_venda(lote_origem, lote_origem["vendas"][0]["id"])}))

    # erro_edicao_lote
    lote = f.lote("PETR4", "2026-10-05", 300, 30.5, [f.venda("2026-10-20", 100, 31.0), f.venda("2026-10-09", 50, 32.0)])
    sem = f.lote("PETR4", "2026-10-05", 300, 30.5)
    for nome, base_lote, mudancas in [
        ("qtd menor que a vendida", lote, {"qtd": 149}),
        ("qtd igual à vendida", lote, {"qtd": 150}),
        ("data depois da primeira venda", lote, {"data_compra": "2026-10-10"}),
        ("data no dia da primeira venda", lote, {"data_compra": "2026-10-09"}),
        ("sem vendas aceita qualquer data", sem, {"data_compra": "2026-12-31", "qtd": 1}),
    ]:
        novo = {**base_lote, **mudancas}
        out.append(base.caso(f"erro_edicao_lote {nome}", "erro_edicao_lote", {"lote": base_lote, "novo": novo},
                             nc.erro_edicao_lote(base_lote, novo)))

    # tipo_por_ticker
    for t in ["AAPL34", "T1TW34", "PETR4", "TAEE11", "PETR4F", "AAPL34F", "abcd34", "", None, " aapl34 ", "AAPL3F",
              "MSFT35", "XXXX39", "XXXX36", "XXX34", "XXXXX34", "ABCD31F", "ABCDE34F", "ıbm34", "ſſſſ34",
              "AAPL٣٤", "AAPL34\n", "F"]:
        out.append(base.caso(f"tipo_por_ticker {t!r}", "tipo_por_ticker", {"ticker": t}, nc.tipo_por_ticker(t)))

    # corrigir_tipos_mes
    errado = f.mes("2026-10", [f.lote("AAPL34", "2026-10-02", 10, 100.0, tipo="Ação"),
                               f.lote("PETR4", "2026-10-02", 10, 30.0, tipo="BDR"),
                               f.lote("VALE3", "2026-10-02", 10, 60.0)])
    certo = f.mes("2026-10", [f.lote("AAPL34", "2026-10-02", 10, 100.0), f.lote("PETR4", "2026-10-02", 10, 30.0)])
    for nome, d in [("com erros", errado), ("sem erros", certo), ("vazio", f.mes("2026-10", []))]:
        d2 = copy.deepcopy(d)
        mudou = nc.corrigir_tipos_mes(d2)
        out.append(base.caso(f"corrigir_tipos_mes {nome}", "corrigir_tipos_mes", {"mes": d},
                             {"mudou": mudou, "mes": d2}))

    # resultado_aberto
    lote = f.lote("PETR4", "2026-10-05", 300, 30.5, [f.venda("2026-10-09", 100, 31.0)])
    tudo = f.lote("PETR4", "2026-10-05", 100, 30.5, [f.venda("2026-10-09", 100, 31.0)])
    for nome, l, p in [("alta", lote, 33.1), ("queda", lote, 27.77), ("igual", lote, 30.5), ("zero", lote, 0),
                       ("zero float", lote, 0.0), ("nulo", lote, None), ("tudo vendido", tudo, 40.0),
                       ("sem vendas", f.lote("VALE3", "2026-10-05", 7, 61.235), 62.0)]:
        out.append(base.caso(f"resultado_aberto {nome}", "resultado_aberto", {"lote": l, "preco_atual": p},
                             nc.resultado_aberto(l, p)))
    for i in range(30):
        l = f.lote("PETR4", "2026-10-05", rnd.randint(1, 900), rnd.uniform(1, 200),
                   [f.venda("2026-10-09", 1, 1.0)])
        l["vendas"] = []
        p = rnd.uniform(0.5, 300)
        out.append(base.caso(f"resultado_aberto aleatório {i}", "resultado_aberto", {"lote": l, "preco_atual": p},
                             nc.resultado_aberto(l, p)))
    return out
