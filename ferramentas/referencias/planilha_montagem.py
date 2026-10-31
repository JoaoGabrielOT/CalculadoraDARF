"""Referências da planilha: linhas a gravar (nucleo.py:777-834), conversão de célula (google_sync.py:76-83) e
normalização da leitura (google_sync.py:427-441).

montar_linhas: entrada = {"meses": [json do mês, na ordem], "cfg": {...}}; os meses são gravados na pasta de dados e
carregados por `nc.carregar`, como faz o aplicativo. Saída = as 8 abas (listas de linhas). A aba Exclusões vem de um
`set` no Python (nucleo.py:165-166), então o teste a compara sem ordem.
celula: entrada = lista de valores; saída = lista de dicionários.
normalizar_leitura: entrada = {aba: linhas lidas}; saída = {aba: linhas completadas e cortadas na largura}.
"""
import google_sync as gs

from . import base

nc = base.nc


def _venda(i, data, qtd, preco, mod=50.5):
    return {"id": i, "data": data, "qtd": qtd, "preco": preco, "mod": mod}


def _lote(i, ticker, data, qtd, preco, vendas=(), tipo=None, origem=None, mod=50.5):
    l = {"id": i, "ticker": ticker, "tipo": tipo or nc.tipo_por_ticker(ticker), "data_compra": data, "qtd": qtd,
         "preco": preco, "vendas": list(vendas), "mod": mod}
    if origem:
        l["origem"] = origem
    return l


def _mes(mes, lotes=(), fechado=False, darf_anterior=0.0, excluidos=None, mod=50.5):
    return {"mes": mes, "fechado": fechado, "darf_anterior": darf_anterior, "lotes": list(lotes),
            "excluidos": excluidos or {}, "mod": mod}


def _meta(i, ticker, lote_id, qtd, criada_em, **extra):
    m = {"id": i, "ticker": ticker, "tipo": "Ação", "lote_id": lote_id, "qtd": qtd, "criada_em": criada_em,
         "status": "ativa", "mod": 60.25}
    m.update(extra)
    return m


def _montar(nome, meses, cfg):
    with base.pasta_dados() as pasta, base.congelar():
        base.gravar_arquivos(pasta, {f"{m['mes']}.json": m for m in meses})
        linhas = nc.montar_linhas([m["mes"] for m in meses], cfg)
    return base.caso(nome, "montar_linhas", {"meses": meses, "cfg": cfg}, linhas)


def _cfg_completa():
    niveis = [{"desde": "2026-10-20", "stop": 5.0, "calc_em": "2026-10-20"},
              {"desde": "2026-10-22", "stop": 7.0, "calc_em": "2026-10-21"}]
    return {
        "tema": "Dark",
        "amigos": [{"email": "ana@exemplo.com", "desde": "2026-09-01", "mod": 70.5},
                   {"email": "beto@exemplo.com", "desde": "2026-09-15"}],
        "radar": [
            {"ticker": "VALE3", "nome": "Vale", "desde": "2026-08-01", "pos": 2, "mod": 71.5},
            {"ticker": "PETR4", "nome": "Petrobras", "desde": "2026-08-02", "pos": 0, "mod": 71.5},
            {"ticker": "ITUB4", "nome": "Itaú Unibanco", "desde": "2026-08-03", "pos": 2},
            {"ticker": "WEGE3", "desde": "2026-08-04"},
            {"ticker": "ABEV3", "nome": "Ambev", "desde": "2026-08-05", "pos": 1, "mod": 72.5},
        ],
        "caixa": {"saldo": 1234.565, "data": "2026-10-20", "mod": 73.5},
        "excluidos": {"amigos:velho@exemplo.com": 80.5, "radar:OLD3": 81.5, "metas:meta-x": 82.5},
        "metas": [
            _meta("meta-b", "PETR4", "L1", 100, "2026-10-21T10:00:00-03:00", gatilho="alvo", preco_alvo=36.5,
                  lucro_desejado=250.0, oco="oco-1"),
            _meta("meta-a", "PETR4", "L1", 100, "2026-10-21T10:00:00-03:00", preco_alvo=40.0, oco="oco-1",
                  cancelada_por="meta-s", cancelada_detalhe="Cancelada: o stop foi executado", status="cancelada"),
            _meta("meta-s", "PETR4", "L1", 100, "2026-10-20T11:00:00-03:00", gatilho="stop", stop_inicial=5.0,
                  stop_atual=7.0, movel=True, niveis=niveis, oco="oco-1", mod=61.5,
                  sugestao={"stop": 5.0, "atr": 0.5, "motivo": "ATR × 2"}),
            _meta("meta-e", "VALE3", "L2", 10, "2026-10-19T09:00:00-03:00", preco_alvo=70.0, lucro_desejado=0.0,
                  status="executada", ultimo_erro="",
                  execucao={"venda_id": "vx", "data": "2026-10-22", "hora": "10:15", "preco_usado": 70.0,
                            "motivo": "Máxima ≥ preço-alvo", "ok": True}),
            _meta("meta-f", "ITUB4", "L3", 5, "2026-10-19T09:00:00-03:00", preco_alvo=35.0, ultimo_erro="Sem cotação",
                  stop_atual=0.0, movel=False, niveis=[]),
        ],
    }


def _casos_montagem():
    out = []

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
    out.append(_montar("meses_e_config_completos", [jan, fev, mar], _cfg_completa()))

    out.append(_montar("sem_nada", [], {"tema": "Dark"}))
    out.append(_montar("caixa_indefinido_e_radar_sem_pos", [mar], {
        "caixa": {"saldo": 500.0, "data": "", "mod": 1.5},
        "radar": [{"ticker": "B3SA3", "desde": "2026-08-01"}, {"ticker": "ABEV3", "nome": "Ambev",
                                                              "desde": "2026-08-02", "pos": 0}]}))
    out.append(_montar("caixa_com_saldo_zero_e_exclusao_com_dois_pontos_no_valor", [mar], {
        "caixa": {"saldo": 0, "data": "2026-10-01"}, "excluidos": {"radar:A:B": 5.5}}))

    # Review Focus 5: compra de 1 ação a 1,125 -> Total 1,12 (meio-para-par), não 1,13.
    out.append(_montar("total_com_empate_binario", [_mes("2026-10", [
        _lote("e1", "PETR4", "2026-10-02", 1, 1.125),
        _lote("e2", "PETR4", "2026-10-03", 3, 0.125, [_venda("ve2", "2026-10-09", 1, 0.375)])])],
        {"caixa": {"saldo": 0.125, "data": "2026-10-10"}}))

    # Review Focus 2: vendas na mesma data, gravadas fora da ordem de id; o empate segue a ordem dos lotes.
    out.append(_montar("empate_vendas_mesma_data", [_mes("2026-10", [
        _lote("L9", "PETR4", "2026-10-01", 100, 30.0, [_venda("v9", "2026-10-15", 10, 31.0)]),
        _lote("L1", "VALE3", "2026-10-01", 100, 60.0, [_venda("v5", "2026-10-15", 10, 61.0),
                                                       _venda("v1", "2026-10-15", 5, 62.0),
                                                       _venda("v0", "2026-10-14", 5, 62.0)]),
        _lote("L5", "ITUB4", "2026-10-01", 100, 30.0, [_venda("v3", "2026-10-15", 10, 31.0)])])], {}))
    return out


def _caso_celulas():
    valores = [None, "", True, False, 0, 0.0, 21.78, -0.0, "texto", 1e16, 7, -3.5, " ", "Itaú ≥ 1", 1.125]
    return base.caso("valores_variados", "celula", valores, [gs.celula(v) for v in valores])


def _normalizar(lidas):
    """Trecho de `Google.ler` (google_sync.py:439-441) sem a parte de rede."""
    res = {a: [] for a in gs.ABAS}
    for aba, linhas in lidas.items():
        if aba not in gs.ABAS:
            continue
        n = len(gs.ABAS[aba]["colunas"])
        res[aba] = [(linha + [""] * n)[:n] for linha in linhas]
    return res


def _caso_normalizacao():
    lidas = {
        "Resumo": [["10/2026", "Aberto"], ["09/2026"] + [1.5] * 15],
        "Radar": [["PETR4", "Petrobras", 46000, 71.5]],
        "Metas": [[f"c{i}" for i in range(12)]],
        "Caixa": [],
        "Fantasma": [["x"]],
    }
    return base.caso("abas_faltando_e_linhas_curtas_ou_longas", "normalizar_leitura", lidas, _normalizar(lidas))


def casos():
    return _casos_montagem() + [_caso_celulas(), _caso_normalizacao()]
