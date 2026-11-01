"""Referências de sugestões de alvo e stop, patrimônio e textos dos cartões (sugestoes.py:20-284).

Funções (campo `funcao` de cada caso):
- grade_sugestoes: entrada {series: {nome: [barra]}, entradas: [{serie, lote, qtd, preco, hoje, patrimonio}]};
  saída {resultados: [...]}, um por entrada: ou {excecao, mensagem} (tipo da exceção do Python) ou
  {item, linhas} com o item de montar_item (sem o lote) e as linhas de linhas_card.
- erros_item: entrada {entradas: [{lote, qtd, tipo, valor}]}; saída {resultados: [{erro, linhas}]}.
- alerta_risco: entrada {resultados, patrimonios}; saída {"<i>|<j>": {pct, limite, excede}}.
- patrimonio: entrada {arquivos, cenarios: [{hoje, caixa, cotacoes}]}; saída {cenarios: [...]}.
- rodape: entrada {patrimonios, resultados}; saída {"<i>|<j>": [linhas]}.
"""
import random
from datetime import date, timedelta

from . import base
from . import fechamento as fe

mk, mt, nc, sg = base.mk, base.mt, base.nc, base.sg

FIM = date(2026, 10, 28)


def _barra(d, abre, alta, baixa, fech):
    return {"data": d.isoformat(), "abre": abre, "alta": alta, "baixa": baixa, "fech": fech}


def _serie(rnd, n, tipo, preco=10.0, fim=FIM):
    barras, fech = [], preco
    for i in range(n):
        d = fim - timedelta(days=n - 1 - i)
        if tipo == "volatil":
            fech = fech * (1 + rnd.uniform(-0.05, 0.05))
            alta, baixa = fech * (1 + rnd.uniform(0, 0.04)), fech * (1 - rnd.uniform(0, 0.04))
        elif tipo == "muito_volatil":
            fech = fech * (1 + rnd.uniform(-0.3, 0.3))
            alta, baixa = fech * (1 + rnd.uniform(0, 0.5)), fech * (1 - rnd.uniform(0, 0.5))
        elif tipo == "plana":
            alta = baixa = fech = preco
        elif tipo == "padrao":
            alta, baixa, fech = 11.0, 9.0, 10.0
        else:  # extrema: estoura o ATR para infinito
            alta, baixa, fech = 1.7e308, 1.0, 1.0
        barras.append(_barra(d, fech if i % 7 else None, alta, baixa, fech))
    return barras


def _lote(i, preco, data):
    return {"id": f"L{i}", "ticker": "PETR4", "tipo": "Ação", "data_compra": data, "qtd": 100, "preco": preco,
            "vendas": []}


def _d(iso):
    return date.fromisoformat(iso) if iso else None


def _executar(series, e):
    barras = [dict(b, data=_d(b["data"])) for b in series[e["serie"]]]
    diarias = {"barras": barras, "hoje": FIM, "preco": e["preco"], "fonte": "Yahoo Finance"}
    pat = None if e["patrimonio"] is None else {"valor": e["patrimonio"]}
    try:
        item = sg.montar_item(e["lote"], e["qtd"], diarias, pat, hoje=_d(e["hoje"]))
        linhas = sg.linhas_card(item)
    except Exception as ex:  # noqa: BLE001 - o tipo da exceção entra na referência
        return {"excecao": type(ex).__name__, "mensagem": str(ex)}
    item = {k: v for k, v in item.items() if k != "lote"}
    return {"item": item, "linhas": linhas}


def _grade():
    rnd = random.Random(5)
    series = {}
    for n in (0, 1, 5, 14, 15, 16, 22, 23, 24, 30, 60):
        series[f"volatil_{n}"] = _serie(rnd, n, "volatil")
    series["volatil_30_fim_27"] = _serie(rnd, 30, "volatil", fim=FIM - timedelta(days=1))
    series["muito_volatil_30"] = _serie(rnd, 30, "muito_volatil")
    series["muito_volatil_60"] = _serie(rnd, 60, "muito_volatil", preco=0.5)
    series["plana_30"] = _serie(rnd, 30, "plana")
    series["plana_16"] = _serie(rnd, 16, "plana")
    series["padrao_30"] = _serie(rnd, 30, "padrao")
    series["padrao_18"] = _serie(rnd, 18, "padrao")
    series["extrema_30"] = _serie(rnd, 30, "extrema")
    entradas, k = [], 0
    for nome in series:
        for preco in (10.0, 11.5, 40.0, 0.05):
            for data in ("2026-10-28", "2026-10-01"):
                k += 1
                lote = _lote(k, preco, data)
                cots = [None, 0.0, preco]
                try:
                    barras = [dict(b, data=_d(b["data"])) for b in series[nome]]
                    s = sg.sugerir(lote, barras, FIM, None)
                    cots += [s["stop"] * 0.9, s["alvo"] * 1.1, s["stop"], s["alvo"]]
                except Exception:  # noqa: BLE001
                    pass
                cots += [preco / 4, preco * 4]
                for cot in cots:
                    entradas.append({"serie": nome, "lote": lote, "qtd": rnd.choice([1, 100]), "preco": cot,
                                     "hoje": rnd.choice(["2026-10-28", "2026-10-29", None]),
                                     "patrimonio": rnd.choice([None, 0.0, 500.0, 11000.0, 1e6])})
    with base.congelar():
        resultados = [_executar(series, e) for e in entradas]
    return base.caso("grade_sugestoes", "grade_sugestoes", {"series": series, "entradas": entradas},
                     {"resultados": resultados})


def _erros():
    lote = _lote(1, 10.0, "2026-10-01")
    entradas = [{"lote": lote, "qtd": 100, "tipo": "sem_dados", "valor": "Sem dados para PETR4 no Yahoo Finance."},
                {"lote": lote, "qtd": 100, "tipo": "texto", "valor": "Falha qualquer"}]
    resultados = []
    with base.congelar():
        for e in entradas:
            d = mk.SemDados(e["valor"]) if e["tipo"] == "sem_dados" else e["valor"]
            item = sg.montar_item(e["lote"], e["qtd"], d)
            resultados.append({"erro": item["erro"], "linhas": sg.linhas_card(item)})
    return base.caso("erros_item", "erros_item", {"entradas": entradas}, {"resultados": resultados})


RESULTADOS = [-1000.0, -400.48, -220.0, -0.01, -0.0, 0.0, 0.01, 400.0, -1, 0]
PATRIMONIOS = [None, 0, 0.0, -5.0, 1, 100.0, 1000, 11000.0, 30000.0, 1e9]


def _alertas():
    saida = {f"{i}|{j}": sg.alerta_risco(r, p if p is None else {"valor": p})
             for i, r in enumerate(RESULTADOS) for j, p in enumerate(PATRIMONIOS)}
    return base.caso("grade_alerta_risco", "alerta_risco", {"resultados": RESULTADOS, "patrimonios": PATRIMONIOS},
                     saida)


CAIXAS = [{}, {"saldo": 10000.0, "data": "2026-10-28"}, {"saldo": -250.75, "data": "2026-10-06"},
          {"saldo": 500.0, "data": "2026-11-15"}]
HOJES = ["2026-01-10", "2026-03-13", "2026-10-28"]
COTACOES = [{}, {"PETR4": 10.0}, {"PETR4": 31.5, "T1TW34": 9.9, "VALE3": 60.0, "AAPL34": 48.0, "ITUB4": 30.25},
            {"PETR4": 0.0, "ITUB4": 30.25}, {"ITUB4": 0.125}]


def _patrimonio(nome, arquivos):
    cenarios = [{"hoje": h, "caixa": c, "cotacoes": k} for h in HOJES for c in CAIXAS for k in COTACOES]
    saida = []
    with base.pasta_dados() as pasta, base.congelar():
        base.gravar_arquivos(pasta, arquivos)
        meses = mt._carregar_meses()
        for cen in cenarios:
            hoje = _d(cen["hoje"])
            cfg = {"caixa": dict(cen["caixa"])}
            pat = sg.patrimonio(cfg, cen["cotacoes"], hoje, meses)
            pat2, res = sg.resumo_patrimonio(cfg, cen["cotacoes"], hoje)
            saida.append({"patrimonio": pat, "resumo": [pat2, res],
                          "resultados": {m: sg.resultado_mes(meses, m) for m in list(meses) + ["2099-01"]}})
    return base.caso(nome, "patrimonio", {"arquivos": arquivos, "cenarios": cenarios}, {"cenarios": saida})


def _rodape():
    pats = [None] + [{"valor": v, "caixa": c, "posicoes": p, "caixa_definido": d, "sem_cotacao": s}
                     for v, c, p, d, s in ((11000.0, 10000.0, 1000.0, True, []),
                                           (1000.0, 0.0, 1000.0, False, ["PETR4", "VALE3"]),
                                           (0.0, 0.0, 0.0, True, []), (-50.0, -50.0, 0.0, True, ["ITUB4"]))]
    resultados = [-800.0, -660.0, -660.01, -100.0, -0.0, 0.0, 12.5, 660.5, 1e5]
    saida = {f"{i}|{j}": sg.linhas_rodape(p, r) for i, p in enumerate(pats) for j, r in enumerate(resultados)}
    return base.caso("rodape", "rodape", {"patrimonios": pats, "resultados": resultados}, saida)


def casos():
    return [_grade(), _erros(), _alertas(),
            _patrimonio("patrimonio_semestre", fe._semestre()),
            _patrimonio("patrimonio_sem_meses", {}),
            _patrimonio("patrimonio_empate", {"2026-10.json": fe._mes("2026-10", [
                fe._lote("A", "PETR4", "2026-10-05", 200, 30.0, [fe._venda("va1", "2026-10-05", 100, 35.0)]),
                fe._lote("B", "PETR4", "2026-09-01", 1000, 28.0, [fe._venda("vb1", "2026-10-05", 10, 31.0)])])}),
            _rodape()]
