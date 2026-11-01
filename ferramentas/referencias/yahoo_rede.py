"""Referências da parte sem rede de `Mercado.cotacao`, `fechamento`, `preco_venda` e `grafico` (mercado.py:265-325, 441-466).

O módulo `requests` é trocado pela rede falsa (`_rede_falsa`), o `yfinance` some e o relógio fica em AGORA/HOJE
(hoje = 2026-10-28); cada caso usa um `Mercado()` novo.

Funções (campo `funcao` de cada caso):
- cotacao: entrada {ticker, respostas: [{status, json}]}; saída {pedidos, resultado: preço}
- fechamento: entrada {ticker, dia, respostas}; saída {pedidos, resultado: [preço, data real]}
- preco_venda: entrada {ticker, dia, respostas}; saída {pedidos, resultado: [preço, texto]}
- grafico: entrada {ticker, periodo, respostas}; saída {pedidos, resultado: {ticker, periodo, pontos, referencia,
  desvio, intradiario}}
Em falha, a saída é {pedidos, erro, mensagem}.
"""
import http
from datetime import date, datetime, timezone
from unittest import mock

from . import _rede_falsa as rf
from . import base

mk = base.mk


def _executar(funcao, argumentos, respostas):
    pedidos = []
    reais = [rf.Resposta(r["status"], json=r.get("json"), motivo=http.HTTPStatus(r["status"]).phrase)
             for r in respostas]
    cm, pedidos = rf.rede(reais)
    saida = {}
    with rf.sem_modulo("yfinance"), base.congelar(), cm, mock.patch.object(mk.time, "time", return_value=base.AGORA):
        try:
            saida["resultado"] = funcao(mk.Mercado(), *argumentos)
        except (mk.SemDados, RuntimeError, rf.RequestException) as e:
            saida.update(rf.erro(e))
    return {"pedidos": pedidos, **saida}


def _grafico_dict(g):
    return {"ticker": g["ticker"], "periodo": g["periodo"], "pontos": g["pontos"], "referencia": g["referencia"],
            "desvio": g["desvio"], "intradiario": g["intradiario"]}


def _caso(nome, funcao, ticker, extra, respostas):
    entrada = {"ticker": ticker, **extra, "respostas": respostas}
    if funcao == "cotacao":
        saida = _executar(lambda m, t: m.cotacao(t), (ticker,), respostas)
    elif funcao == "fechamento":
        saida = _executar(lambda m, t, d: list(m.fechamento(t, d)), (ticker, date.fromisoformat(extra["dia"])), respostas)
    elif funcao == "preco_venda":
        saida = _executar(lambda m, t, d: list(m.preco_venda(t, d)), (ticker, date.fromisoformat(extra["dia"])), respostas)
    else:
        saida = _executar(lambda m, t, p: _grafico_dict(m.grafico(t, p)), (ticker, extra["periodo"]), respostas)
    return base.caso(nome, funcao, entrada, saida)


def _chart(timestamps, close, meta=None, quote=None):
    q = {"close": close} if quote is None else quote
    return {"chart": {"result": [{"meta": meta if meta is not None else {}, "timestamp": timestamps,
                                  "indicators": {"quote": [q]}}], "error": None}}


def _ok(corpo):
    return [{"status": 200, "json": corpo}]


def _falhas(funcao, ticker, extra):
    """Os mesmos pedidos com resposta vazia, 404, 429 e 500."""
    vazia = {"chart": {"result": [], "error": None}}
    return [
        _caso("resultado_vazio", funcao, ticker, extra, _ok(vazia)),
        _caso("http_404", funcao, ticker, extra, [{"status": 404, "json": {"chart": {"error": {"code": "Not Found"}}}}]),
        _caso("http_429", funcao, ticker, extra, [{"status": 429}]),
        _caso("http_500", funcao, ticker, extra, [{"status": 500}]),
    ]


def _ts(dia, hora=13):
    """Instante (timestamp) de `dia` (AAAA-MM-DD) às `hora` UTC."""
    d = date.fromisoformat(dia)
    return int(datetime(d.year, d.month, d.day, hora, tzinfo=timezone.utc).timestamp())


def _casos_cotacao():
    t = "PETR4"
    ts = [_ts("2026-10-22"), _ts("2026-10-23"), _ts("2026-10-26")]
    return [
        _caso("preco_da_meta", "cotacao", t, {}, _ok(_chart(ts, [37.1, 37.9, 38.2], {"regularMarketPrice": 38.45}))),
        _caso("preco_inteiro_da_meta", "cotacao", t, {}, _ok(_chart(ts, [37.1], {"regularMarketPrice": 38}))),
        _caso("preco_zero_usa_ultimo_fechamento", "cotacao", t, {},
              _ok(_chart(ts, [37.1, None, 0, 38.0, None], {"regularMarketPrice": 0}))),
        _caso("preco_nulo_usa_ultimo_fechamento", "cotacao", t, {},
              _ok(_chart(ts, [37.1, 37.9, 38.2], {"regularMarketPrice": None}))),
        _caso("sem_meta_usa_fechamento", "cotacao", t, {}, _ok(_chart(ts, [37.1, 37.9, 38.2], {}))),
        _caso("fechamento_inteiro", "cotacao", t, {}, _ok(_chart(ts, [37, 38], {}))),
        _caso("preco_negativo_usa_fechamento", "cotacao", t, {},
              _ok(_chart(ts, [37.1, 37.9], {"regularMarketPrice": -1.5}))),
        _caso("sem_fechamento_valido", "cotacao", t, {}, _ok(_chart(ts, [None, 0, None], {}))),
        _caso("sem_indicadores", "cotacao", t, {},
              _ok({"chart": {"result": [{"meta": {}, "timestamp": ts}], "error": None}})),
        _caso("quote_vazio", "cotacao", t, {}, _ok(_chart(ts, [], {}, quote={}))),
        _caso("chart_nulo", "cotacao", t, {}, _ok({"chart": None})),
    ] + _falhas("cotacao", "VALE3", {})


def _casos_fechamento():
    t = "PETR4"
    dias = ["2026-10-20", "2026-10-21", "2026-10-22", "2026-10-23", "2026-10-26"]
    ts = [_ts(d) for d in dias]
    meta = {"gmtoffset": -10800}
    corpo = _chart(ts, [36.5, 37.1, 37.9, 38.2, 38.8], meta)
    return [
        _caso("dia_com_pregao", "fechamento", t, {"dia": "2026-10-22"}, _ok(corpo)),
        _caso("ultimo_dia_disponivel", "fechamento", t, {"dia": "2026-10-26"}, _ok(corpo)),
        _caso("sabado_usa_sexta", "fechamento", t, {"dia": "2026-10-24"}, _ok(corpo)),
        _caso("depois_do_ultimo_dado", "fechamento", t, {"dia": "2026-11-05"}, _ok(corpo)),
        _caso("antes_do_primeiro_dado", "fechamento", t, {"dia": "2026-10-19"}, _ok(corpo)),
        _caso("ignora_fechamentos_invalidos", "fechamento", t, {"dia": "2026-10-23"},
              _ok(_chart(ts, [36.5, 37.1, 37.9, None, 0], meta))),
        _caso("fuso_muda_o_dia", "fechamento", t, {"dia": "2026-10-23"},
              _ok(_chart([_ts("2026-10-23", 1), _ts("2026-10-24", 1)], [10.5, 11.5], meta))),
        _caso("gmtoffset_ausente", "fechamento", t, {"dia": "2026-10-23"},
              _ok(_chart([_ts("2026-10-23", 1), _ts("2026-10-24", 1)], [10.5, 11.5], {}))),
        _caso("gmtoffset_zero", "fechamento", t, {"dia": "2026-10-23"},
              _ok(_chart([_ts("2026-10-23", 1), _ts("2026-10-24", 1)], [10.5, 11.5], {"gmtoffset": 0}))),
        _caso("fora_de_ordem", "fechamento", t, {"dia": "2026-10-23"},
              _ok(_chart([ts[3], ts[1], ts[0], ts[2]], [38.2, 37.1, 36.5, 37.9], meta))),
        _caso("mesmo_dia_dois_pontos_pega_o_maior", "fechamento", t, {"dia": "2026-10-22"},
              _ok(_chart([_ts("2026-10-22", 13), _ts("2026-10-22", 14)], [40.0, 39.0], meta))),
        _caso("fechamento_inteiro", "fechamento", t, {"dia": "2026-10-22"},
              _ok(_chart([_ts("2026-10-22")], [38], meta))),
        _caso("timestamps_mais_longos_que_fechamentos", "fechamento", t, {"dia": "2026-10-26"},
              _ok(_chart(ts, [36.5, 37.1], meta))),
        _caso("sem_nenhum_fechamento_valido", "fechamento", t, {"dia": "2026-10-26"},
              _ok(_chart(ts, [None, 0, None, None, None], meta))),
        _caso("sem_timestamps", "fechamento", t, {"dia": "2026-10-26"}, _ok(_chart([], [], meta))),
    ] + _falhas("fechamento", "VALE3", {"dia": "2026-10-22"})


def _casos_preco_venda():
    t = "PETR4"
    ts = [_ts("2026-10-26"), _ts("2026-10-27")]
    corpo = _chart(ts, [38.8, 39.1], {"gmtoffset": -10800, "regularMarketPrice": 39.4})
    return [
        _caso("hoje_usa_cotacao", "preco_venda", t, {"dia": "2026-10-28"}, _ok(corpo)),
        _caso("futuro_usa_cotacao", "preco_venda", t, {"dia": "2026-11-02"}, _ok(corpo)),
        _caso("ontem_usa_fechamento", "preco_venda", t, {"dia": "2026-10-27"}, _ok(corpo)),
        _caso("dia_passado_usa_fechamento", "preco_venda", t, {"dia": "2026-10-26"}, _ok(corpo)),
        _caso("passado_sem_fechamento", "preco_venda", t, {"dia": "2026-10-20"}, _ok(corpo)),
        _caso("hoje_http_429", "preco_venda", t, {"dia": "2026-10-28"}, [{"status": 429}]),
        _caso("passado_http_404", "preco_venda", t, {"dia": "2026-10-20"}, [{"status": 404}]),
    ]


def _serie(inicio, n, passo, valor=10.0, delta=0.25):
    ts = [inicio + i * passo for i in range(n)]
    return ts, [round(valor + i * delta, 2) for i in range(n)]


def _casos_grafico():
    t = "PETR4"
    saidas = []
    for periodo, (_, intervalo, _) in mk.PERIODOS_GRAFICO.items():
        passo = {"5m": 300, "30m": 1800, "1d": 86400, "1wk": 604800, "1mo": 2592000}[intervalo]
        ts, fech = _serie(1761000000 - 8 * passo, 8, passo)
        meta = {"gmtoffset": -10800, "previousClose": 9.5, "chartPreviousClose": 9.0, "regularMarketPrice": 12.5}
        saidas.append(_caso(f"periodo_{periodo}", "grafico", t, {"periodo": periodo}, _ok(_chart(ts, fech, meta))))
    ts, fech = _serie(1760990000, 6, 300)
    base_meta = {"gmtoffset": -10800}
    saidas += [
        _caso("1D_previous_close", "grafico", t, {"periodo": "1D"},
              _ok(_chart(ts, fech, {**base_meta, "previousClose": 9.5, "chartPreviousClose": 9.0}))),
        _caso("1D_so_chart_previous_close", "grafico", t, {"periodo": "1D"},
              _ok(_chart(ts, fech, {**base_meta, "chartPreviousClose": 9.0}))),
        _caso("1D_previous_close_zero_cai_no_seguinte", "grafico", t, {"periodo": "1D"},
              _ok(_chart(ts, fech, {**base_meta, "previousClose": 0, "chartPreviousClose": 9.0}))),
        _caso("1D_sem_referencia_usa_primeiro_ponto", "grafico", t, {"periodo": "1D"}, _ok(_chart(ts, fech, base_meta))),
        _caso("1D_ultimo_ponto_vira_preco_da_meta", "grafico", t, {"periodo": "1D"},
              _ok(_chart(ts, fech, {**base_meta, "previousClose": 9.5, "regularMarketPrice": 11.77}))),
        _caso("1D_preco_inteiro_da_meta", "grafico", t, {"periodo": "1D"},
              _ok(_chart(ts, fech, {**base_meta, "regularMarketPrice": 12}))),
        _caso("1D_preco_invalido_mantem_ultimo_ponto", "grafico", t, {"periodo": "1D"},
              _ok(_chart(ts, fech, {**base_meta, "previousClose": 9.5, "regularMarketPrice": 0}))),
        _caso("1D_preco_nulo_mantem_ultimo_ponto", "grafico", t, {"periodo": "1D"},
              _ok(_chart(ts, fech, {**base_meta, "previousClose": 9.5, "regularMarketPrice": None}))),
        _caso("1M_ignora_previous_close_e_preco", "grafico", t, {"periodo": "1M"},
              _ok(_chart(ts, fech, {**base_meta, "previousClose": 9.5, "regularMarketPrice": 99.0}))),
        _caso("descarta_fechamentos_invalidos", "grafico", t, {"periodo": "5D"},
              _ok(_chart(ts, [10.0, None, 0, 10.5, -1.0, 11.0], base_meta))),
        _caso("fechamentos_inteiros", "grafico", t, {"periodo": "6M"}, _ok(_chart(ts[:3], [10, 11, 12], base_meta))),
        _caso("gmtoffset_ausente_vale_zero", "grafico", t, {"periodo": "1A"}, _ok(_chart(ts, fech, {}))),
        _caso("timestamps_mais_longos_que_fechamentos", "grafico", t, {"periodo": "1M"},
              _ok(_chart(ts, fech[:3], base_meta))),
        _caso("dois_pontos_bastam", "grafico", t, {"periodo": "5A"}, _ok(_chart(ts[:2], fech[:2], base_meta))),
        _caso("um_ponto_so", "grafico", t, {"periodo": "1M"}, _ok(_chart(ts[:1], fech[:1], base_meta))),
        _caso("so_um_valido", "grafico", t, {"periodo": "1M"}, _ok(_chart(ts[:3], [None, 10.0, 0], base_meta))),
        _caso("sem_pontos", "grafico", t, {"periodo": "Máx"}, _ok(_chart([], [], base_meta))),
    ]
    return saidas + _falhas("grafico", "VALE3", {"periodo": "1M"})


def casos():
    return _casos_cotacao() + _casos_fechamento() + _casos_preco_venda() + _casos_grafico()
