"""Referências da reconstrução da planilha (nucleo.py:837-972) e da compatibilidade de leitura.

Cada caso: entrada = {aba: linhas lidas}; saída = {"dados": reconstruir(abas) como objeto, "metas": reconstruir_metas(abas)}.
`dados` = {"meses": {mês: json do mês}, "amigos": [...], "radar": [...], "excluidos": {...}, "caixa": {...} | null}.
Relógio, ids (id0001...) e "hoje" congelados. Os casos de ida e volta usam a saída de `montar_linhas` como entrada.
Não há caso com número gigante em data (OverflowError não capturado no Python) nem NaN/infinito.
"""
from . import base
from .planilha_montagem import _cfg_completa, _lote, _mes, _venda

nc = base.nc

RESUMO, COMPRAS, VENDAS, AMIGOS, RADAR, CAIXA, METAS, EXCLUSOES = 13, 13, 17, 3, 5, 3, 14, 4


def _l(n, **cols):
    """Linha de n colunas vazias com as colunas c<i>=valor preenchidas."""
    row = [""] * n
    for k, v in cols.items():
        row[int(k[1:])] = v
    return row


def _compra(mes="10/2026", ticker="PETR4", tipo="Ação", data="2026-10-05", qtd=100, preco=30.5, id_="c1",
            origem="", mod=50.5):
    return [mes, ticker, tipo, data, qtd, preco, "", "", "", "", id_, origem, mod]


def _venda_linha(mes="10/2026", data="2026-10-12", qtd=40, preco=33.25, id_="v1", lote="c1", mod=51.5):
    return _l(VENDAS, c0=mes, c5=data, c6=qtd, c7=preco, c14=id_, c15=lote, c16=mod)


def _executar(nome, abas):
    with base.congelar():
        dados = nc.reconstruir(abas)
        metas = nc.reconstruir_metas(abas)
    meses, amigos, radar, excl, caixa = dados
    saida = {"dados": {"meses": meses, "amigos": amigos, "radar": radar, "excluidos": excl, "caixa": caixa},
             "metas": metas}
    return base.caso(nome, "reconstruir", abas, saida)


def _ida_e_volta(nome, meses, cfg):
    with base.pasta_dados() as pasta, base.congelar():
        base.gravar_arquivos(pasta, {f"{m['mes']}.json": m for m in meses})
        linhas = nc.montar_linhas([m["mes"] for m in meses], cfg)
    linhas["Exclusões"] = sorted(linhas["Exclusões"], key=str)  # vem de um set: fixa a ordem do arquivo gerado
    return _executar(nome, linhas)


def _casos_ida_e_volta():
    jan = _mes("2026-01", [
        _lote("a1", "PETR4", "2026-01-05", 200, 30.5, [_venda("va1", "2026-01-20", 50, 33.1),
                                                       _venda("va0", "2026-01-10", 20, 31.0)]),
        _lote("a2", "T1TW34", "2026-01-06", 20, 9.0, [_venda("va2", "2026-01-15", 10, 10.0)]),
        _lote("a3", "VALE3", "2026-01-07", 10, 60.0, [_venda("va3", "2026-01-08", 10, 61.0)], origem="a0"),
    ], excluidos={"zz1": 90.5, "zz2": 91.5})
    fev = _mes("2026-02", [
        _lote("b1", "AAPL34", "2026-02-03", 500, 40.0, [_venda("vb1", "2026-02-12", 500, 48.0)]),
        _lote("b2", "ITUB4", "2026-02-04", 100, 30.25),
    ], fechado=True, darf_anterior=3.5)
    mar = _mes("2026-03", [])
    return [
        _ida_e_volta("ida_e_volta_completo", [jan, fev, mar], _cfg_completa()),
        _ida_e_volta("ida_e_volta_vazio", [], {"tema": "Dark"}),
        _ida_e_volta("ida_e_volta_caixa_sem_data_e_radar_sem_pos", [mar], {
            "caixa": {"saldo": 500.0, "data": "", "mod": 1.5},
            "radar": [{"ticker": "B3SA3", "desde": "2026-08-01"},
                      {"ticker": "ABEV3", "nome": "Ambev", "desde": "2026-08-02", "pos": 0}]}),
        _ida_e_volta("ida_e_volta_empate_binario", [_mes("2026-10", [
            _lote("e1", "PETR4", "2026-10-02", 1, 1.125),
            _lote("e2", "PETR4", "2026-10-03", 3, 0.125, [_venda("ve2", "2026-10-09", 1, 0.375)])])],
            {"caixa": {"saldo": 0.125, "data": "2026-10-10"}}),
    ]


def _casos_compat():
    out = []
    S = nc.serial
    # abas antigas: Metas com 12 colunas (sem Gatilho/Detalhes), Radar com 4 colunas e com Posição "".
    out.append(_executar("metas_12_colunas_radar_4_colunas", {
        "Metas": [["m1", "petr4 ", "Ação", "L1", 100, 36.5, 250.0, "2026-10-21T10:00:00-03:00", "ativa", "", "", 60.25]],
        "Radar": [["PETR4", "Petrobras", S("2026-08-02"), 71.5], ["VALE3", "Vale", S("2026-08-03"), 72.5]],
    }))
    out.append(_executar("radar_posicao_vazia_e_preenchida", {
        "Radar": [["PETR4", "Petrobras", S("2026-08-02"), 71.5, ""], ["VALE3", "Vale", S("2026-08-03"), 72.5, 3],
                  ["ITUB4", "Itaú", S("2026-08-04"), 73.5, 0], ["WEGE3", "", S("2026-08-05"), 1.5, " "],
                  ["ABEV3", "Ambev", S("2026-08-06"), 1.5, "2"], ["B3SA3", "B3", S("2026-08-07"), 1.5, 2.7],
                  ["MGLU3", "Magalu", S("2026-08-08"), 1.5, "abc"]],
    }))
    # colunas faltando em todas as abas
    out.append(_executar("colunas_faltando_em_todas_as_abas", {
        "Resumo": [["10/2026", "Fechado"], ["09/2026"]],
        "Compras": [["10/2026", "PETR4", "Ação", S("2026-10-05"), 100, 30.5, 3050.0, 40, 60, "Parcial", "c1"],
                    ["10/2026", "VALE3", "Ação", S("2026-10-06"), 10, 60.0]],
        "Vendas": [["10/2026", "PETR4", "Ação", "2026-10-05", 30.5, S("2026-10-12"), 40, 33.25, 1330.0, "Swing",
                    1.0, 100.0, 99.0, 0.0, "v1", "c1"]],
        "Amigos": [["ana@exemplo.com", S("2026-09-01")]],
        "Radar": [["PETR4"]],
        "Caixa": [[100.5, S("2026-10-01")]],
        "Exclusões": [["registro", "10/2026", "c9"], ["amigos", "", "x@y.com"]],
        "Metas": [["m1", "PETR4"], ["m2", "VALE3", "Ação", "L1", 5, 70.0, "", "2026-10-21T10:00:00-03:00"]],
    }))
    out.append(_executar("abas_ausentes_e_vazias", {"Fantasma": [["x"]], "Resumo": [], "Caixa": []}))
    out.append(_executar("abas_vazias", {}))
    # linhas malformadas
    out.append(_executar("linhas_malformadas", {
        "Resumo": [_l(RESUMO, c0="abc", c1="Fechado"), _l(RESUMO, c0="10-2026"), _l(RESUMO, c0="1/2026", c1="Fechado",
                                                                                   c10=2.5, c12=9.5),
                   _l(RESUMO, c0="13/2026"), _l(RESUMO, c0="a/b"), _l(RESUMO, c0="10/2026/1"),
                   _l(RESUMO, c0="10/2026", c10="x", c12="y")],
        "Compras": [_compra(mes="abc"), _compra(qtd="x", id_="c2"), _compra(data="31/02/2026", id_="c3"),
                    _compra(data="texto", id_="c4"), _compra(preco="", id_="c5"), _compra(preco="abc", id_="c6"),
                    _compra(qtd="", id_="c7"), _compra(data="", id_="c8"), _compra(id_="c9", ticker=" vale3 "),
                    _compra(id_="", qtd="x"), _compra(id_="", ticker="itub4", data=S("2026-10-07"))],
        "Vendas": [_venda_linha(mes="abc"), _venda_linha(qtd="x", id_="v2"), _venda_linha(data="31/02/2026", id_="v3"),
                   _venda_linha(preco="abc", id_="v4"), _venda_linha(lote="zzz", id_="v5"),
                   _venda_linha(mes="09/2026", id_="v6"), _venda_linha(id_="", qtd="x"),
                   _venda_linha(id_="", qtd=5, data=S("2026-10-13")), _venda_linha(id_="v7", mod="abc")],
        "Exclusões": [_l(EXCLUSOES, c0="registro", c1="abc", c2="v9", c3=5.5),
                      _l(EXCLUSOES, c0="registro", c1="10/2026", c2="v8", c3=6.5),
                      _l(EXCLUSOES, c0="registro", c1="11/2026", c2="v7", c3="x"),
                      _l(EXCLUSOES, c0="amigos", c2="a@b.com", c3=7.5), _l(EXCLUSOES, c0="radar", c2="", c3=8.5),
                      _l(EXCLUSOES, c0="metas", c2="m1"), _l(EXCLUSOES, c0="outro", c2="a:b", c3=9.5)],
        "Amigos": [_l(AMIGOS, c0="", c1=S("2026-09-01")), _l(AMIGOS, c0="a@b.com", c1="texto", c2=1.5),
                   _l(AMIGOS, c0="c@d.com", c1="", c2="y")],
        "Radar": [_l(RADAR, c0="", c1="x"), _l(RADAR, c0="PETR4", c1="Petrobras", c2="31/02/2026", c3="x"),
                  _l(RADAR, c0="VALE3", c1=None, c2=None)],
        "Caixa": [_l(CAIXA, c0="x", c1="texto", c2=5)],
    }))
    out.append(_executar("caixa_com_duas_linhas", {
        "Caixa": [[100.5, nc.serial("2026-10-01"), 5.5], [999.0, nc.serial("2026-10-02"), 9.5]]}))
    out.append(_executar("caixa_primeira_linha_invalida_ignora_a_segunda", {
        "Caixa": [["x", "texto", 5], [999.0, nc.serial("2026-10-02"), 9.5]]}))
    out.append(_executar("caixa_saldo_vazio_e_data_texto", {"Caixa": [["", "05/10/2026", ""]]}))
    out.append(_executar("radar_ticker_repetido_e_email_maiusculo", {
        "Amigos": [[" Ana@Exemplo.COM ", S("2026-09-01"), 70.5], ["ana@exemplo.com", S("2026-09-02"), 71.5],
                   ["   ", S("2026-09-03"), 72.5]],
        "Radar": [[" petr4 ", "Petrobras", S("2026-08-02"), 71.5, 0], ["PETR4", "Outra", S("2026-08-03"), 72.5, 1],
                  ["vale3", 0, S("2026-08-04"), 73.5, 2], ["  ", "x", S("2026-08-05"), 1, 3]],
    }))
    out.append(_executar("estrutura_completa_com_ids_vazios_na_ordem", {
        "Resumo": [_l(RESUMO, c0="10/2026", c1="Aberto", c10=1.5, c12=5.5)],
        "Compras": [_compra(id_="", ticker="petr4"), _compra(id_="", ticker="vale3", tipo="BDR", origem="c0"),
                    _compra(mes="11/2026", id_="c1", ticker="aapl34", tipo="Ação")],
        "Vendas": [_venda_linha(id_="", lote="c1"), _venda_linha(mes="11/2026", id_="", lote="c1", qtd=1)],
        "Exclusões": [["registro", "11/2026", "zz", 3.5]],
    }))
    out.append(_executar("lote_duplicado_e_resumo_duplicado", {
        "Resumo": [_l(RESUMO, c0="10/2026", c1="Fechado", c10=1.5, c12=5.5),
                   _l(RESUMO, c0="10/2026", c1="Aberto", c10=2.5, c12=6.5)],
        "Compras": [_compra(id_="c1"), _compra(id_="c1", qtd=7), _compra(id_="c2", ticker="vale3")],
        "Vendas": [_venda_linha(id_="v1", lote="c1")],
    }))
    return out


def _casos_editadas_a_mao():
    """Review Focus 1: células editadas à mão na planilha."""
    out = []
    S = nc.serial
    out.append(_executar("editadas_a_mao_id_numerico", {
        "Compras": [_compra(id_=123, ticker="petr4"), _compra(id_=123.0, ticker="vale3"),
                    _compra(id_=0, ticker="itub4"), _compra(id_=True, ticker="wege3"),
                    _compra(id_=12.5, ticker="abev3")],
        "Vendas": [_venda_linha(id_="v1", lote=123), _venda_linha(id_=77, lote=123.0, qtd=1),
                   _venda_linha(id_=77.0, lote="True", qtd=2)],
    }))
    out.append(_executar("editadas_a_mao_quantidade", {
        "Compras": [_compra(id_="a", qtd=100.0), _compra(id_="b", qtd=100.9), _compra(id_="c", qtd="100"),
                    _compra(id_="d", qtd=" 100 "), _compra(id_="e", qtd="100.0"), _compra(id_="f", qtd=-5.5),
                    _compra(id_="g", qtd=True), _compra(id_="h", qtd=False), _compra(id_="i", qtd="1_0")],
        "Vendas": [_venda_linha(id_="v1", lote="a", qtd=10.0), _venda_linha(id_="v2", lote="a", qtd=10.9),
                   _venda_linha(id_="v3", lote="a", qtd="10"), _venda_linha(id_="v4", lote="a", qtd="10.0")],
    }))
    out.append(_executar("editadas_a_mao_data_texto", {
        "Compras": [_compra(id_="a", data="5/10/2026"), _compra(id_="b", data="05/10/2026"),
                    _compra(id_="c", data="2026-10-05"), _compra(id_="d", data=" 2026-10-05 "),
                    _compra(id_="e", data=46300.7), _compra(id_="f", data=46300), _compra(id_="g", data="20261005"),
                    _compra(id_="h", data="2026-10-05T10:00:00"), _compra(id_="i", data=True),
                    _compra(id_="j", data="5/10/26"), _compra(id_="k", data="2026-1-5"), _compra(id_="l", data=0)],
        "Vendas": [_venda_linha(id_="v1", lote="a", data="12/10/2026"), _venda_linha(id_="v2", lote="a", data="12-10-2026"),
                   _venda_linha(id_="v3", lote="a", data=46307.0)],
        "Amigos": [["a@b.com", "5/10/2026", 1], ["c@d.com", 46300.9, 2], ["e@f.com", True, 3]],
        "Radar": [["PETR4", "P", "5/10/2026", 1, ""], ["VALE3", "V", True, 2, ""]],
        "Caixa": [[10, "5/10/2026", 3]],
    }))
    out.append(_executar("editadas_a_mao_mes_com_espaco", {
        "Resumo": [_l(RESUMO, c0=" 10/2026", c1="Fechado"), _l(RESUMO, c0="9/2026 ", c1="fechado"),
                   _l(RESUMO, c0="10 / 2026"), _l(RESUMO, c0=10.2026), _l(RESUMO, c0=" 8/ 2026 ", c1="Fechado"),
                   _l(RESUMO, c0="07/26"), _l(RESUMO, c0="")],
        "Compras": [_compra(mes=" 10/2026", id_="a"), _compra(mes="10/2026 ", id_="b"), _compra(mes="10 /2026", id_="c"),
                    _compra(mes=True, id_="d"), _compra(mes="", id_="e")],
        "Exclusões": [["registro", " 10/2026", "x", 1.5], ["registro", " 7 /2026 ", "y", 2.5]],
    }))
    out.append(_executar("editadas_a_mao_booleano_em_coluna_numerica", {
        "Resumo": [_l(RESUMO, c0="10/2026", c1=True, c10=True, c12=True),
                   _l(RESUMO, c0="09/2026", c1="Fechado", c10=False, c12="TRUE")],
        "Compras": [_compra(id_="a", preco=True), _compra(id_="b", preco=False), _compra(id_="c", preco="TRUE"),
                    _compra(id_="d", qtd="TRUE"), _compra(id_="e", origem=True, mod=True),
                    _compra(id_="f", origem=0), _compra(id_="g", origem=5), _compra(id_="h", origem=5.0)],
        "Vendas": [_venda_linha(id_="v1", lote="a", preco=True, mod=True)],
        "Amigos": [["a@b.com", S("2026-09-01"), True], [True, S("2026-09-01"), 1]],
        "Radar": [[True, False, S("2026-08-02"), True, True], ["PETR4", True, S("2026-08-02"), False, False]],
        "Caixa": [[True, S("2026-10-01"), True]],
        "Exclusões": [[True, "10/2026", True, True], ["registro", "10/2026", True, True]],
    }))
    out.append(_executar("editadas_a_mao_textos_e_valores_numericos", {
        "Compras": [_compra(id_="a", ticker=" petr4", tipo=5, preco="30.5"), _compra(id_="b", ticker=7, tipo=None),
                    _compra(id_="c", preco="1e2"), _compra(id_="d", preco="30,5"), _compra(id_="e", preco=" 31 "),
                    _compra(id_="f", mod="abc"), _compra(id_="g", mod="12.5"), _compra(id_="h", mod=None),
                    _compra(id_="i", ticker="itub4", tipo="BDR")],
        "Exclusões": [["registro", "10/2026", 123, "5"], ["amigos", "", 123.0, 1], [5, "", "x", 1]],
    }))
    out.append(_executar("editadas_a_mao_celulas_nulas", {
        "Resumo": [[None, None], ["10/2026", None, None, None, None, None, None, None, None, None, None, None, None]],
        "Compras": [["10/2026", "PETR4", "Ação", S("2026-10-05"), 10, 30.5, None, None, None, None, None, None, None]],
        "Amigos": [["a@b.com", S("2026-09-01"), None], [None, S("2026-09-01"), 1]],
        "Radar": [["PETR4", None, S("2026-08-02"), None, None]],
        "Caixa": [[None, S("2026-10-01"), None]],
    }))
    return out


def _detalhes(**campos):
    import json
    return json.dumps(campos, ensure_ascii=False)


def _meta_linha(id_="m1", ticker="PETR4", tipo="Ação", lote="L1", qtd=100, alvo=36.5, lucro="",
                criada="2026-10-21T10:00:00-03:00", status="ativa", erro="", execucao="", mod=60.25, gatilho="",
                detalhes=""):
    return [id_, ticker, tipo, lote, qtd, alvo, lucro, criada, status, erro, execucao, mod, gatilho, detalhes]


def _casos_metas():
    import json
    out = []
    niveis = [{"desde": "2026-10-20", "stop": 5.0, "calc_em": "2026-10-20"},
              {"desde": "2026-10-22", "stop": 7.0}]
    stop_ok = dict(id="s1", gatilho="stop", stop_inicial=5.0, stop_atual=7.0, movel=True, niveis=niveis)

    def m(nome, *linhas):
        out.append(_executar(nome, {"Metas": list(linhas)}))

    m("metas_alvo_completa", _meta_linha(lucro=250.0, erro="Sem cotação", status="executada",
                                         execucao=json.dumps({"venda_id": "vx", "ok": True, "preco_usado": 70.0}),
                                         detalhes=_detalhes(id="m1", oco="oco-1", cancelada_por="m2",
                                                            cancelada_detalhe="Cancelada",
                                                            sugestao={"stop": 5.0, "atr": 0.5})))
    m("metas_stop_com_preco_valido", _meta_linha(id_="s1", alvo=36.5, gatilho="stop", detalhes=json.dumps(stop_ok)),
      _meta_linha(id_="s1", alvo="", gatilho="stop", detalhes=json.dumps(stop_ok)),
      _meta_linha(id_="s1", alvo=40.0, gatilho="", detalhes=json.dumps(stop_ok)),
      _meta_linha(id_="s1", alvo=40.0, gatilho="alvo", detalhes=json.dumps(stop_ok)),
      _meta_linha(id_="s1", alvo=40.0, gatilho="alvo", detalhes=json.dumps({**stop_ok, "gatilho": "alvo"})),
      _meta_linha(id_="s1", alvo=40.0, gatilho="stop", detalhes=json.dumps({**stop_ok, "gatilho": "alvo"})),
      _meta_linha(id_="s1", alvo=40.0, gatilho=" stop ", detalhes=json.dumps(stop_ok)))
    m("metas_detalhes_de_outro_id", _meta_linha(id_="m1", alvo="", gatilho="stop",
                                                detalhes=json.dumps({**stop_ok, "id": "outro"})),
      _meta_linha(id_="m2", alvo=10.0, gatilho="stop", detalhes=json.dumps({**stop_ok, "id": "outro", "oco": "x"})),
      _meta_linha(id_=" s1 ", alvo=10.0, gatilho="stop", detalhes=json.dumps(stop_ok)),
      _meta_linha(id_="s1", alvo=10.0, detalhes=json.dumps({**stop_ok, "id": 5})),
      _meta_linha(id_="s1", alvo=10.0, detalhes=json.dumps({k: v for k, v in stop_ok.items() if k != "id"})))
    m("metas_detalhes_json_invalido", _meta_linha(detalhes="{nao e json"), _meta_linha(id_="m2", detalhes="[1, 2]"),
      _meta_linha(id_="m3", detalhes="123"), _meta_linha(id_="m4", detalhes="null"),
      _meta_linha(id_="m5", detalhes='"m5"'), _meta_linha(id_="m6", detalhes="{}"),
      _meta_linha(id_="m7", alvo="", gatilho="stop", detalhes="{nao e json"))
    base_s = {"id": "s1", "gatilho": "stop", "stop_inicial": 5.0, "stop_atual": 7.0}

    def stop(**extra):
        d = {**base_s, **extra}
        return _meta_linha(id_="s1", alvo="", gatilho="stop", detalhes=json.dumps(d))

    m("metas_stop_niveis_malformados",
      stop(niveis=[]), stop(niveis=[{"desde": "2026-10-20"}]), stop(niveis=[{"stop": 5.0}]),
      stop(niveis=[{"desde": "2026-10-20", "stop": "abc"}]), stop(niveis=["x"]), stop(niveis=[[1, 2]]),
      stop(niveis=[None]), stop(niveis=None), stop(niveis="abc"), stop(niveis=""), stop(niveis={}),
      stop(niveis={"desde": 1}), stop(niveis=5), stop(),
      stop(niveis=[{"desde": 5, "stop": "7.5", "calc_em": None}]),
      stop(niveis=[{"desde": "a", "stop": True, "calc_em": 3}]),
      stop(niveis=[{"desde": "a", "stop": None}]), stop(niveis=[{"desde": "a", "stop": [1]}]),
      stop(niveis=[{"desde": None, "stop": 1}]), stop(niveis=[{"desde": 1.5, "stop": 1, "calc_em": 2.0}]))
    m("metas_stop_campos_ruins",
      stop(stop_inicial="abc", niveis=[]), stop(stop_inicial=None, niveis=[]), stop(stop_atual="x", niveis=[]),
      stop(stop_inicial="5.5", stop_atual="6", niveis=[]), stop(movel=0, niveis=[]), stop(movel="", niveis=[]),
      stop(movel="nao", niveis=[]), stop(movel=[1], niveis=[]), stop(movel=None, niveis=[]),
      stop(stop_inicial=True, stop_atual=False, niveis=[]),
      _meta_linha(id_="s2", alvo=9.0, gatilho="stop",
                  detalhes=json.dumps({"id": "s2", "gatilho": "stop", "stop_inicial": 1.0, "niveis": []})),
      _meta_linha(id_="s3", alvo="", gatilho="stop",
                  detalhes=json.dumps({"id": "s3", "gatilho": "stop", "stop_inicial": 1.0, "niveis": []})))
    m("metas_criada_em", _meta_linha(id_="a", criada="2026-10-21T10:00:00-03:00"),
      _meta_linha(id_="b", criada="2026-10-21"), _meta_linha(id_="c", criada="2026-10-21 10:00:00"),
      _meta_linha(id_="d", criada="ontem"), _meta_linha(id_="e", criada=""), _meta_linha(id_="f", criada=46000),
      _meta_linha(id_="g", criada="2026-02-30T10:00:00"), _meta_linha(id_="h", criada="2026-10-21T25:00:00"),
      _meta_linha(id_="i", criada="2026-10-21T10:00:00Z"), _meta_linha(id_="j", criada=" 2026-10-21"),
      _meta_linha(id_="k", criada="2026-10-21T10:00:00.123456+00:00"))
    m("metas_id_e_ticker_vazios", _meta_linha(id_=""), _meta_linha(id_="  "), _meta_linha(id_="a", ticker=""),
      _meta_linha(id_="b", ticker="   "), _meta_linha(id_=" c ", ticker=" vale3 "), _meta_linha(id_=123, ticker=4),
      _meta_linha(id_=123.0, ticker="x"), _meta_linha(id_=0, ticker="y"))
    m("metas_lucro_desejado", _meta_linha(id_="a", lucro=0), _meta_linha(id_="b", lucro=0.0),
      _meta_linha(id_="c", lucro=""), _meta_linha(id_="d", lucro="abc"), _meta_linha(id_="e", lucro="12.5"),
      _meta_linha(id_="f", lucro=None), _meta_linha(id_="g", lucro=-3.5), _meta_linha(id_="h", lucro=True))
    m("metas_execucao", _meta_linha(id_="a", execucao="{nao e json"),
      _meta_linha(id_="b", execucao=json.dumps({"ok": False, "motivo": "x"})),
      _meta_linha(id_="c", execucao=" {\"ok\": true} "), _meta_linha(id_="d", execucao="   "),
      _meta_linha(id_="e", execucao=0), _meta_linha(id_="f", execucao=False))
    m("metas_sugestao", _meta_linha(id_="a", detalhes=_detalhes(id="a", sugestao=[1, 2])),
      _meta_linha(id_="b", detalhes=_detalhes(id="b", sugestao="texto")),
      _meta_linha(id_="c", detalhes=_detalhes(id="c", sugestao=None)),
      _meta_linha(id_="d", detalhes=_detalhes(id="d", sugestao={})),
      _meta_linha(id_="e", detalhes=_detalhes(id="e", sugestao={"stop": 5, "atr": 0.5, "n": {"a": [1, 2.5, None]}})),
      _meta_linha(id_="f", detalhes=_detalhes(id="f", oco="", cancelada_por=0, cancelada_detalhe=None)),
      _meta_linha(id_="g", detalhes=_detalhes(id="g", oco=5, cancelada_por=True, cancelada_detalhe=1.5)))
    m("metas_campos_basicos", _meta_linha(id_="a", qtd="x"), _meta_linha(id_="b", qtd=10.0),
      _meta_linha(id_="c", qtd=10.9), _meta_linha(id_="d", qtd="10"), _meta_linha(id_="e", alvo="abc"),
      _meta_linha(id_="f", alvo=""), _meta_linha(id_="g", alvo="40"), _meta_linha(id_="h", alvo=None),
      _meta_linha(id_="i", status=""), _meta_linha(id_="j", status="cancelada"), _meta_linha(id_="k", status=0),
      _meta_linha(id_="l", mod="x"), _meta_linha(id_="n", mod=""), _meta_linha(id_="o", tipo=""),
      _meta_linha(id_="p", lote=5), _meta_linha(id_="q", lote=" L1 "), _meta_linha(id_="r", erro=0),
      _meta_linha(id_="s", erro="falhou"), _meta_linha(id_="t", erro=5))
    # linhas curtas (completadas) e longas (cortadas em 14)
    m("metas_linhas_curtas_e_longas",
      ["a", "PETR4", "Ação", "L1", 10, 40.0, "", "2026-10-21T10:00:00-03:00"],
      ["b", "PETR4", "Ação", "L1", 10, 40.0, 5.0, "2026-10-21T10:00:00-03:00", "executada", "e", "", 5.5, "", "",
       "extra", "extra2"],
      ["c", "PETR4", "Ação", "L1", 10, 40.0, "", "2026-10-21T10:00:00-03:00", "ativa", "", "", 1.5, "stop",
       json.dumps({**stop_ok, "id": "c"}), "lixo"],
      ["d"], [], ["e", "PETR4"])
    m("metas_stop_so_pelo_detalhe", _meta_linha(id_="s1", alvo=10.0, gatilho="",
                                                 detalhes=json.dumps({**stop_ok, "gatilho": "stop"})),
      _meta_linha(id_="s1", alvo="", gatilho="", detalhes=json.dumps({**stop_ok, "gatilho": "stop"})),
      _meta_linha(id_="s1", alvo="", gatilho="stop", detalhes=json.dumps({**stop_ok, "oco": "o", "sugestao": {"a": 1}})))
    return out


def casos():
    return _casos_ida_e_volta() + _casos_compat() + _casos_editadas_a_mao() + _casos_metas()
