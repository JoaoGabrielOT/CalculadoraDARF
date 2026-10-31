"""Referências da interpretação do chart do Yahoo, sem rede (mercado.py:119-231, 336-375).

O `_get_chart` do Python é trocado por um falso que devolve JSON sintético; `time.time` é congelado em AGORA.

Funções (campo `funcao` de cada caso):
- historico_desde: entrada {ticker, desde, agora, respostas: {intervalo: resultado | {"__erro__": "sem_dados"|"limite"}}};
  saída {"chamadas": [params (valores em texto)], "barras": [{ts, dt, alta, baixa, abre}], "fonte", "intervalo"}
  ou {"erro", "mensagem", "chamadas"}.
- barras_diarias: entrada {resposta, passos: [{ticker, desde, agora}]}; saída {"passos": [resultado | erro],
  "chamadas": [params]} (o cache começa vazio).
- range_diarias: entrada {desde}; saída {"range"} (hoje = 2026-10-28).
- dados_api: entrada {ticker, nome_conhecido, resposta}; saída = dict de `_dados_api` ou {"erro", "mensagem"}.
"""
import contextlib
import sys
import types
from datetime import date, datetime, timezone
from unittest import mock

from . import base

mk = base.mk

if "requests" not in sys.modules:   # `_dados_api` importa requests; nenhuma chamada de rede é feita
    try:
        import requests  # noqa: F401
    except ImportError:
        sys.modules["requests"] = types.ModuleType("requests")


def _falso(respostas, chamadas):
    """_get_chart falso: registra os params (valores em texto) e devolve a resposta do intervalo (ou a única)."""
    def get_chart(ticker, params):
        chamadas.append({k: str(v) for k, v in params.items()})
        r = respostas.get(params.get("interval", "*"), respostas.get("*"))
        if r is None or r.get("__erro__") == "sem_dados":
            raise mk.SemDados(f"Sem dados para {ticker} no Yahoo Finance.")
        if r.get("__erro__") == "limite":
            raise RuntimeError("Too Many Requests")
        return r
    return get_chart


@contextlib.contextmanager
def _sem_rede(get_chart):
    original = mk._get_chart
    mk._get_chart = get_chart
    try:
        yield
    finally:
        mk._get_chart = original


def _erro(e):
    nome = "LimiteConsultas" if isinstance(e, RuntimeError) else type(e).__name__
    return {"erro": nome, "mensagem": str(e)}


def _barra(b):
    return {"ts": b["ts"], "dt": b["dt"].isoformat(), "alta": b["alta"], "baixa": b["baixa"], "abre": b["abre"]}


def _resultado_historico(h):
    return {"barras": [_barra(b) for b in h["barras"]], "fonte": h["fonte"], "intervalo": h["intervalo"]}


def _historico(nome, ticker, desde, agora, respostas):
    entrada = {"ticker": ticker, "desde": desde, "agora": agora, "respostas": respostas}
    chamadas = []
    with _sem_rede(_falso(respostas, chamadas)):
        try:
            saida = _resultado_historico(mk.historico_desde(ticker, datetime.fromisoformat(desde),
                                                            datetime.fromisoformat(agora)))
        except (mk.SemDados, RuntimeError) as e:
            saida = _erro(e)
    saida["chamadas"] = chamadas
    return base.caso(nome, "historico_desde", entrada, saida)


def _chart(timestamps, quote, meta=None):
    return {"meta": meta if meta is not None else {"gmtoffset": -10800}, "timestamp": timestamps,
            "indicators": {"quote": [quote]}}


def _casos_historico():
    desde, agora = "2026-10-20T11:00:00", "2026-10-22T12:00:00-03:00"
    ts = [1761051600, 1761055200, 1761058800, 1761062400]
    boa = _chart(ts, {"high": [21.5, None, 22.25, 0], "low": [20.9, 20.0, None, 19.0],
                      "open": [None, 21.0, 21.5, 20.0]})
    sem_barras = _chart([], {})
    sem = {"__erro__": "sem_dados"}
    return [
        _historico("fino_com_fuso", "PETR4", desde, agora, {"1m": sem, "5m": boa}),
        _historico("primeiro_intervalo", "PETR4", desde, agora, {"1m": boa}),
        _historico("sem_barras", "PETR4", desde, agora, {"*": sem_barras}),
        _historico("sem_dados_em_todos", "VALE3", desde, agora, {}),
        _historico("barras_vazias_depois_de_erro", "VALE3", desde, agora,
                   {"1m": sem, "5m": sem_barras, "15m": sem_barras, "1h": sem_barras, "1d": sem_barras}),
        _historico("limite_de_consultas", "VALE3", desde, agora, {"1m": {"__erro__": "limite"}}),
        _historico("baixa_ausente", "PETR4", desde, agora,
                   {"*": _chart([1761051600], {"high": [21.5]}, {})}),
        _historico("lista_curta", "PETR4", desde, agora,
                   {"*": _chart(ts, {"high": [21.5, 22.0, 23.0], "low": [20.0], "open": []})}),
        _historico("gmtoffset_zero_vira_brasilia", "PETR4", desde, agora,
                   {"*": _chart(ts[:2], {"high": [21.5, 22.0]}, {"gmtoffset": 0})}),
        _historico("gmtoffset_positivo", "PETR4", desde, agora,
                   {"*": _chart(ts[:2], {"high": [21.5, 22.0]}, {"gmtoffset": 19800})}),
        _historico("meta_nula", "PETR4", desde, agora,
                   {"*": {"meta": None, "timestamp": ts[:2], "indicators": {"quote": [{"high": [1.0, 2.0]}]}}}),
        _historico("sem_indicadores", "PETR4", desde, agora, {"*": {"meta": {}, "timestamp": ts}}),
        _historico("periodo_60_dias", "PETR4", "2026-09-01T10:00:00", agora, {"5m": sem, "15m": boa}),
        _historico("periodo_200_dias", "PETR4", "2026-04-01T10:00:00", agora, {"1h": sem, "1d": boa}),
        _historico("periodo_1000_dias", "PETR4", "2023-01-02T10:00:00", agora, {"1d": boa}),
        _historico("desde_depois_de_agora", "PETR4", "2026-10-23T10:00:00", agora, {"1m": boa}),
        _historico("desde_com_fuso", "PETR4", "2026-10-20T14:00:00+00:00", "2026-10-22T15:00:00+00:00",
                   {"1m": boa}),
        _historico("fracao_de_segundo", "PETR4", "2026-10-20T11:00:00.75", "2026-10-22T12:00:00.5-03:00",
                   {"1m": boa}),
    ]


def _diarias_dict(r):
    return {"barras": [{"data": b["data"].isoformat(), "abre": b["abre"], "alta": b["alta"], "baixa": b["baixa"],
                        "fech": b["fech"]} for b in r["barras"]],
            "hoje": r["hoje"].isoformat(), "preco": r["preco"], "fonte": r["fonte"]}


def _diarias(nome, resposta, passos):
    entrada = {"resposta": resposta, "passos": passos}
    chamadas, saidas = [], []
    with base.congelar(), _sem_rede(_falso({"*": resposta}, chamadas)):
        mk._DIARIAS.clear()
        try:
            for p in passos:
                desde = date.fromisoformat(p["desde"]) if p.get("desde") else None
                with mock.patch.object(mk.time, "time", return_value=p["agora"]):
                    try:
                        saidas.append(_diarias_dict(mk.barras_diarias(p["ticker"], desde)))
                    except mk.SemDados as e:
                        saidas.append(_erro(e))
        finally:
            mk._DIARIAS.clear()
    return base.caso(nome, "barras_diarias", entrada, {"passos": saidas, "chamadas": chamadas})


def _casos_diarias():
    ts = [1761051600, 1761138000, 1761224400]
    resp = {"meta": {"gmtoffset": -10800, "regularMarketTime": 1761685200, "regularMarketPrice": 10.4},
            "timestamp": ts,
            "indicators": {"quote": [{"open": [10, None, 10.2], "high": [11, 11, 11], "low": [9, 9, None],
                                      "close": [10, 10, 10]}]}}
    p = lambda t="PETR4", d=None, a=1761000000.0: {"ticker": t, "desde": d, "agora": a}   # noqa: E731
    sem_meta = {"meta": {}, "timestamp": ts, "indicators": {"quote": [{"high": [11, 12, 13], "low": [9, 9, 9],
                                                                    "close": [10, 10.5, 11]}]}}
    preco_invalido = {"meta": {"gmtoffset": 0, "regularMarketPrice": 0, "regularMarketTime": 0},
                      "timestamp": ts, "indicators": {"quote": [{"high": [11, 12, 13], "low": [9, 9, 9],
                                                                "close": [10, 10.5, 11]}]}}
    return [
        _diarias("data_e_cache", resp, [p(), p(a=1761000899.9), p(a=1761000900.0), p(a=1761001000.0)]),
        _diarias("alcance_diferente_nao_usa_cache", resp,
                 [p(), p(d="2025-12-31"), p(d="2025-12-31", a=1761000100.0), p(t="VALE3", a=1761000100.0)]),
        _diarias("sem_meta", sem_meta, [p()]),
        _diarias("preco_e_mercado_invalidos", preco_invalido, [p()]),
        _diarias("sem_barras", {"meta": {}, "timestamp": [], "indicators": {"quote": [{}]}}, [p()]),
        _diarias("so_barras_sem_minima", {"meta": {}, "timestamp": ts,
                                          "indicators": {"quote": [{"high": [1, 1, 1], "close": [1, 1, 1]}]}},
                 [p()]),
        _diarias("gmtoffset_vira_o_dia", {"meta": {"gmtoffset": 3600 * 14}, "timestamp": [1761051600 + 36000],
                                          "indicators": {"quote": [{"open": [5], "high": [6], "low": [4],
                                                                   "close": [5.5]}]}}, [p()]),
    ]


def _casos_range():
    hoje = date(*base.HOJE)
    dias = [None, 0, 100, 120, 121, 200, 305, 306, 500, 670, 671, 900, -30, -200]
    out = []
    for d in dias:
        desde = None if d is None else date.fromordinal(hoje.toordinal() - d)
        with base.congelar():
            r = mk._range_diarias(desde)
        out.append(base.caso(f"dias_{d}", "range_diarias",
                             {"desde": None if desde is None else desde.isoformat()}, {"range": r}))
    return out


def _api(nome, ticker, nome_conhecido, resposta):
    chamadas = []
    with base.congelar(), _sem_rede(_falso({"*": resposta}, chamadas)), \
            mock.patch.object(mk.time, "time", return_value=base.AGORA):
        try:
            saida = mk.Mercado()._dados_api(ticker, nome_conhecido)
        except mk.SemDados as e:
            saida = _erro(e)
    return base.caso(nome, "dados_api", {"ticker": ticker, "nome_conhecido": nome_conhecido, "resposta": resposta},
                     saida)


def _linhas(n, base_ts=1758000000, passo=86400, f0=20.0):
    """n pregões sintéticos (alta, baixa, fechamento) com ruído determinístico."""
    ts = [base_ts + i * passo for i in range(n)]
    cl = [round(f0 + (i % 7) * 0.37 - (i % 3) * 0.21, 4) for i in range(n)]
    hi = [round(c + 0.5 + (i % 4) * 0.1, 4) for i, c in enumerate(cl)]
    lo = [round(c - 0.4 - (i % 5) * 0.05, 4) for i, c in enumerate(cl)]
    return ts, hi, lo, cl


def _resp_api(n, meta, ajustar=None):
    ts, hi, lo, cl = _linhas(n)
    if ajustar:
        hi, lo, cl = ajustar(hi, lo, cl)
    return {"meta": meta, "timestamp": ts, "indicators": {"quote": [{"high": hi, "low": lo, "close": cl}]}}


def _casos_api():
    n = 80
    ultimo_ts = 1758000000 + (n - 1) * 86400
    meta = {"gmtoffset": -10800, "regularMarketTime": ultimo_ts, "regularMarketPrice": 21.37, "longName": "Petrobras PN",
            "shortName": "PETROBRAS", "regularMarketDayHigh": 21.9, "regularMarketDayLow": 20.8,
            "fiftyTwoWeekHigh": 25.5, "fiftyTwoWeekLow": 12, "regularMarketVolume": 123456789}

    def buracos(hi, lo, cl):
        hi, lo, cl = list(hi), list(lo), list(cl)
        hi[3], lo[10], cl[20] = None, None, 0
        return hi, lo, cl

    return [
        _api("completo", "PETR4", "", _resp_api(n, meta)),
        _api("nome_conhecido", "PETR4", "Nome do usuário", _resp_api(n, meta)),
        _api("nome_curto", "PETR4", "", _resp_api(n, {**meta, "longName": ""})),
        _api("sem_nome", "PETR4", "", _resp_api(n, {k: v for k, v in meta.items() if "Name" not in k})),
        _api("preco_ausente_usa_ultimo_fechamento", "PETR4", "",
             _resp_api(n, {k: v for k, v in meta.items() if k != "regularMarketPrice"})),
        _api("preco_zero_usa_ultimo_fechamento", "PETR4", "", _resp_api(n, {**meta, "regularMarketPrice": 0})),
        _api("sem_mercado", "PETR4", "", _resp_api(n, {"gmtoffset": -10800, "regularMarketTime": ultimo_ts})),
        _api("mercado_invalido", "PETR4", "",
             _resp_api(n, {**meta, "regularMarketDayHigh": 0, "fiftyTwoWeekLow": None, "regularMarketVolume": 0})),
        _api("sem_horario_de_mercado", "PETR4", "", _resp_api(n, {"regularMarketPrice": 21.37})),
        _api("mercado_um_dia_depois", "PETR4", "", _resp_api(n, {**meta, "regularMarketTime": ultimo_ts + 86400})),
        _api("valores_nulos_descartados", "PETR4", "", _resp_api(n, meta, buracos)),
        _api("exatamente_15_linhas", "PETR4", "", _resp_api(15, {"regularMarketPrice": 20.0})),
        _api("insuficiente_14_linhas", "PETR4", "", _resp_api(14, meta)),
        _api("insuficiente_por_nulos", "PETR4", "", _resp_api(15, meta, lambda h, l, c: (h[:-1] + [None], l, c))),
        _api("sem_barras", "PETR4", "", {"meta": {}, "timestamp": [], "indicators": {"quote": [{}]}}),
        _api("sem_desvio", "PETR4", "", _resp_api(n, {**meta, "gmtoffset": None})),
        _api("atr_zero_sem_risco", "PETR4", "", {
            "meta": {"regularMarketPrice": 10.0}, "timestamp": [1758000000 + i * 86400 for i in range(20)],
            "indicators": {"quote": [{"high": [10.0] * 20, "low": [10.0] * 20, "close": [10.0] * 20}]}}),
    ]


def casos():
    return _casos_historico() + _casos_diarias() + _casos_range() + _casos_api()
