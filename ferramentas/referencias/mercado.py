"""Referências dos indicadores de mercado e do radar (mercado.py:6-102, 514-548; nucleo.py:231-254).

Funções (campo `funcao` de cada caso):
- indicadores: entrada {barras: [{alta, baixa, fech}]}; saída {atr14, atr22, chandelier, chandelier_5_2, serie,
  serie_5_2} (None quando faltam barras).
- pivos: entrada {alta, baixa, fech}; saída {pp, r1, s1}.
- risco: entrada {valores}; saída {"<índice>": [rótulo, fundo, texto]} (índice do valor na lista).
- variacao: entrada {pares: [[preco, anterior]]}; saída {"resultados": [[var, var_pct]]}.
- anterior_de: entrada {pares: [[data, fech]], dia}; saída {"anterior"}.
- ordenar_radar: entrada {radar: [{ticker, pos?}]}; saída {"tickers"}.
- adicionar_radar: entrada {radar, ticker, nome}; saída {"item", "radar"} (ticker, nome, desde, pos).
- reordenar_radar: entrada {radar, tickers}; saída {"radar"} (ticker, nome, desde, pos).
- filtrar_ordenar: entrada {itens, dados, custodia}; saída {"<filtro>|<ordem>": [tickers]}.
- resumo_dia: entrada {tickers, dados}; saída {"resumo": [alta, queda, média]}.
"""
import copy
import random

from . import base

mk = base.mk
nc = base.nc


def _serie(rng, n, passo=0.03):
    fech = rng.uniform(5, 50)
    out = []
    for _ in range(n):
        fech = max(0.5, fech * (1 + rng.uniform(-passo, passo)))
        alta = fech * (1 + rng.uniform(0, passo))
        baixa = fech * (1 - rng.uniform(0, passo))
        out.append({"alta": alta, "baixa": baixa, "fech": fech})
    return out


def _indicadores(nome, barras):
    h, l, c = [b["alta"] for b in barras], [b["baixa"] for b in barras], [b["fech"] for b in barras]
    saida = {
        "atr14": mk.calcular_atr(h, l, c, 14), "atr22": mk.calcular_atr(h, l, c, 22),
        "chandelier": mk.calcular_chandelier(barras), "chandelier_5_2": mk.calcular_chandelier(barras, 5, 2),
        "serie": mk.serie_chandelier(barras), "serie_5_2": mk.serie_chandelier(barras, 5, 2),
    }
    return base.caso(nome, "indicadores", {"barras": barras}, saida)


def _casos_indicadores():
    rng = random.Random(3)
    out = []
    for n in list(range(0, 31)) + list(range(35, 121, 5)):
        out.append(_indicadores(f"barras_{n}", _serie(rng, n)))
    out.append(_indicadores("planas_40", [{"alta": 11.0, "baixa": 9.0, "fech": 10.0}] * 40))
    out.append(_indicadores("sem_amplitude_40", [{"alta": 10.0, "baixa": 10.0, "fech": 10.0}] * 40))
    gaps = [{"alta": 10.0 + (i % 2) * 5, "baixa": 9.0 + (i % 2) * 5, "fech": 9.5 + (i % 2) * 5} for i in range(40)]
    out.append(_indicadores("gaps_40", gaps))
    return out


def _pivos():
    entradas = [(12, 9, 10.5), (10.0, 10.0, 10.0), (11.37, 9.81, 10.02), (0.0, 0.0, 0.0), (100, 90, 95),
                (3.3, 1.1, 2.2)]
    return [base.caso(f"pivos_{i}", "pivos", {"alta": a, "baixa": b, "fech": f}, mk.calcular_pivos(a, b, f))
            for i, (a, b, f) in enumerate(entradas)]


def _risco():
    valores = [round(i / 10, 1) for i in range(0, 61)] + [
        2.2, 3.0, 4.5, 2.1999999999999997, 2.2000000000000006, 2.9999999999999996, 3.0000000000000004,
        4.499999999999999, 4.500000000000001, -1.0, 1e-9, 100.0, 0]
    saida = {str(i): list(mk.classificar_risco(v)) for i, v in enumerate(valores)}
    return [base.caso("grade", "risco", {"valores": valores}, saida)]


def _variacao():
    pares = [[10.0, 9.0], [None, 9.0], [10.0, None], [None, None], [0, 9.0], [10.0, 0], [-1.0, 9.0], [10.0, -9.0],
             [1.125, 1.0], [100.0, 100.0], [10, 8], [9.0, 10.0], [0.1, 0.3], [5.5, 5.5000001], [1e-9, 1.0]]
    saida = {"resultados": [list(mk.variacao(p, a)) for p, a in pares]}
    return [base.caso("pares", "variacao", {"pares": pares}, saida)]


def _anterior_de():
    casos = {
        "basico": ([["2026-10-20", 10.0], ["2026-10-21", 11.0], ["2026-10-22", 12.0]], "2026-10-22"),
        "desordenado": ([["2026-10-22", 12.0], ["2026-10-20", 10.0], ["2026-10-21", 11.0]], "2026-10-22"),
        "sem_anterior": ([["2026-10-22", 12.0]], "2026-10-22"),
        "vazio": ([], "2026-10-22"),
        "dia_depois_de_tudo": ([["2026-10-20", 10.0], ["2026-10-21", 11.0]], "2026-11-01"),
        "mesma_data_fechamentos_diferentes": ([["2026-10-20", 13.0], ["2026-10-20", 10.0], ["2026-10-22", 1.0]],
                                              "2026-10-21"),
    }
    return [base.caso(nome, "anterior_de", {"pares": p, "dia": d},
                      {"anterior": mk.anterior_de([tuple(x) for x in p], d)})
            for nome, (p, d) in casos.items()]


def _radar(*itens):
    """itens: (ticker, pos|None)."""
    return [{"ticker": t, "nome": f"Nome {t}", "desde": "2026-01-02", **({} if p is None else {"pos": p})}
            for t, p in itens]


def _ordenar():
    cenarios = {
        "sem_pos": _radar(("A", None), ("B", None), ("C", None)),
        "com_pos": _radar(("A", 2), ("B", 0), ("C", 1)),
        "misto": _radar(("A", None), ("B", 0), ("C", None), ("D", 1)),
        "pos_repetida": _radar(("A", 1), ("B", 1), ("C", 0), ("D", 1)),
        "pos_e_indice_empatam": _radar(("A", 2), ("B", None), ("C", 1), ("D", None)),
        "vazio": [],
    }
    return [base.caso(nome, "ordenar_radar", {"radar": r}, {"tickers": [x["ticker"] for x in nc.ordenar_radar(r)]})
            for nome, r in cenarios.items()]


def _projetar(radar):
    return [{"ticker": r["ticker"], "nome": r["nome"], "desde": r["desde"], "pos": r.get("pos")} for r in radar]


def _adicionar():
    out = []
    cenarios = {
        "vazio": (_radar(), "PETR4", "Petrobras"),
        "sem_pos": (_radar(("A", None), ("B", None)), "C", ""),
        "com_pos": (_radar(("A", 5), ("B", 2)), "C", "Nome C"),
        "misto": (_radar(("A", None), ("B", 7), ("C", None)), "D", "D"),
        "repetido": (_radar(("A", 0), ("B", 1)), "B", "outro"),
    }
    for nome, (radar, ticker, nm) in cenarios.items():
        cfg = {"radar": copy.deepcopy(radar)}
        with base.congelar():
            item = nc.adicionar_radar(cfg, ticker, nm)
        saida = {"item": None if item is None else _projetar([item])[0], "radar": _projetar(cfg["radar"])}
        out.append(base.caso(nome, "adicionar_radar", {"radar": radar, "ticker": ticker, "nome": nm}, saida))
    return out


def _reordenar():
    out = []
    radar = _radar(("A", None), ("B", None), ("C", None), ("D", None))
    cenarios = {
        "completa": (radar, ["D", "C", "B", "A"]),
        "parcial": (radar, ["C", "A"]),
        "desconhecido": (radar, ["Z", "B"]),
        "repetido": (radar, ["B", "B", "A"]),
        "vazia": (radar, []),
        "com_pos_antiga": (_radar(("A", 3), ("B", 0), ("C", 2), ("D", 1)), ["C"]),
    }
    for nome, (r, tickers) in cenarios.items():
        cfg = {"radar": copy.deepcopy(r)}
        nc.reordenar_radar(cfg, tickers)
        out.append(base.caso(nome, "reordenar_radar", {"radar": r, "tickers": tickers},
                             {"radar": _projetar(cfg["radar"])}))
    return out


FILTROS = mk.FILTROS_RADAR
ORDENS = [o for o, _ in mk.ORDENS_RADAR] + ["desconhecida"]


def _filtrar_caso(nome, itens, dados, custodia):
    saida = {}
    for f in FILTROS:
        for o in ORDENS:
            saida[f"{f}|{o}"] = [i["ticker"] for i in mk.filtrar_ordenar(itens, dados, f, o, set(custodia))]
    return base.caso(nome, "filtrar_ordenar", {"itens": itens, "dados": dados, "custodia": list(custodia)}, saida)


def _d(t, var=None, atr=None, media=None):
    return {"ticker": t, "var_pct": var, "atr_pct": atr, "vs_media_pct": media}


def _filtrar():
    itens = _radar(("PETR4", None), ("VALE3", None), ("ITUB4", None), ("BBAS3", None), ("WEGE3", None),
                   ("SEMCOT3", None), ("ABEV3", None), ("ÁGUA3", None), ("aaa3", None), ("MGLU3", None))
    dados = {
        "PETR4": _d("PETR4", 1.5, 2.0, -3.0), "VALE3": _d("VALE3", -2.5, 3.5, 4.0), "ITUB4": _d("ITUB4", 0.0, 1.5, 0.0),
        "BBAS3": _d("BBAS3", 1.5, 1.5, -10.5), "WEGE3": _d("WEGE3", None, None, None),
        "ABEV3": _d("ABEV3", -2.5, 5.0, 2.0), "ÁGUA3": _d("ÁGUA3", 0.25, 4.0, -1.0), "aaa3": _d("aaa3", -0.0, 2.0, 1.0),
        "MGLU3": {"ticker": "MGLU3", "nome": "x"},
    }
    custodia = ["PETR4", "WEGE3", "ABEV3", "SEMCOT3"]
    empate = _radar(("A1", None), ("B1", None), ("C1", None), ("D1", None), ("E1", None), ("F1", None))
    dados_e = {"A1": _d("A1", 1.0, 2.0, 1.0), "B1": _d("B1", 1.0, 2.0, 1.0), "C1": _d("C1", 2.0, 2.0, 1.0),
               "D1": _d("D1", 1.0, 2.0, 1.0), "E1": _d("E1", 2.0, 2.0, 1.0), "F1": _d("F1")}
    return [_filtrar_caso("completo", itens, dados, custodia),
            _filtrar_caso("empate_variacao", empate, dados_e, ["B1", "E1"]),
            _filtrar_caso("empate_variacao_invertido", list(reversed(empate)), dados_e, ["B1", "E1"]),
            _filtrar_caso("sem_cotacao", itens, {}, []),
            _filtrar_caso("vazio", [], dados, custodia)]


def _resumo():
    cenarios = {
        "vazio": ([], {}),
        "sem_cotacao": (["A", "B"], {}),
        "misto": (["A", "B", "C", "D", "E"], {"A": {"var_pct": 1.5}, "B": {"var_pct": -2.0}, "C": {"var_pct": 0.0},
                                              "D": {"var_pct": None}, "E": {}}),
        "neumaier": (["A", "B", "C", "D"], {"A": {"var_pct": 0.1}, "B": {"var_pct": 0.2}, "C": {"var_pct": 0.3},
                                            "D": {"var_pct": 1e16}}),
        "negativos": (["A", "B"], {"A": {"var_pct": -1.1}, "B": {"var_pct": -2.2}}),
        "inteiros": (["A", "B"], {"A": {"var_pct": 1}, "B": {"var_pct": -3}}),
    }
    return [base.caso(nome, "resumo_dia", {"tickers": t, "dados": d}, {"resumo": list(mk.resumo_dia(t, d))})
            for nome, (t, d) in cenarios.items()]


def casos():
    return (_casos_indicadores() + _pivos() + _risco() + _variacao() + _anterior_de() + _ordenar() + _adicionar()
            + _reordenar() + _filtrar() + _resumo())
