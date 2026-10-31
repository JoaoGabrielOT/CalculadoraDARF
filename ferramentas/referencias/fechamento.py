"""Referências do fechamento de mês, da venda retroativa e dos tickers frequentes (nucleo.py:378-441, 488-517, 742-743).

Cada caso é um roteiro: entrada = {"arquivos": {nome: json} gravados antes, "operacoes": [...]}; saída =
{"resultados": [{"retorno": ..., "arquivos": {nome: json} depois da operação}]}.
Operações: fechar_mes {mes}, mes_aceita {mes, mes_atual}, registrar_retroativa {mes, lote_id, venda},
corrigir_tipos, historico {meses_recentes}, sugestoes {mes, so_custodia}, custodia_atual. fechar_mes e
registrar_retroativa recebem o mês carregado do arquivo (como faz o aplicativo). Cada operação traz o `agora` em
vigor; o ValueError vira {"erro": texto}.
"""
from . import base

nc = base.nc

T0 = 1761000000.123


def _venda(i, data, qtd, preco):
    return {"id": i, "data": data, "qtd": qtd, "preco": preco, "mod": 50.5}


def _lote(i, ticker, data, qtd, preco, vendas=(), tipo=None, origem=None):
    l = {"id": i, "ticker": ticker, "tipo": tipo or nc.tipo_por_ticker(ticker), "data_compra": data, "qtd": qtd,
         "preco": preco, "vendas": list(vendas), "mod": 50.5}
    if origem:
        l["origem"] = origem
    return l


def _mes(mes, lotes=(), fechado=False, darf_anterior=0.0, **extra):
    return {"mes": mes, "fechado": fechado, "darf_anterior": darf_anterior, "lotes": list(lotes),
            "excluidos": {}, "mod": 50.5, **extra}


def _resumo(darf):
    return {"vendas_acoes_st": 0.0, "isento": True, "bruto": 0.0, "custos": 0.0, "imp_st": 0.0, "imp_dt": 0.0,
            "imposto_total": 0.0, "irrf": 0.0, "lucro_liquido": 0.0, "darf_mes": darf, "darf_anterior": 0.0,
            "darf": darf}


def _executar(op):
    nome = op["op"]
    if nome == "fechar_mes":
        r, prox = nc.fechar_mes(nc.carregar(op["mes"]))
        return {"apuracao": r, "prox": prox}
    if nome == "mes_aceita":
        return nc.mes_aceita_venda_retroativa(op["mes"], op["mes_atual"])
    if nome == "registrar_retroativa":
        return nc.registrar_venda_retroativa(nc.carregar(op["mes"]), op["lote_id"], dict(op["venda"]))
    if nome == "corrigir_tipos":
        return nc.corrigir_tipos()
    if nome == "historico":
        freq, tipos = nc.historico_tickers(op["meses_recentes"])
        return {"freq": dict(freq), "tipos": tipos}
    if nome == "sugestoes":
        lista, tipos = nc.sugestoes(nc.carregar(op["mes"]), op["so_custodia"])
        return {"lista": lista, "tipos": tipos}
    if nome == "custodia_atual":
        return nc.custodia_atual()
    raise ValueError(nome)


def _op(op, agora=T0, **extra):
    return {"op": op, "agora": agora, **extra}


def _fechar(mes, agora=T0):
    return _op("fechar_mes", agora, mes=mes)


def _retro(mes, lote_id, data, qtd, preco, agora=T0):
    return _op("registrar_retroativa", agora, mes=mes, lote_id=lote_id,
               venda={"data": data, "qtd": qtd, "preco": preco})


def _roteiro(nome, arquivos, operacoes):
    with base.pasta_dados() as pasta, base.congelar():
        base.gravar_arquivos(pasta, arquivos)
        resultados = []
        for op in operacoes:
            nc.agora = lambda t=op["agora"]: t
            try:
                retorno = _executar(op)
            except ValueError as e:
                retorno = {"erro": str(e)}
            resultados.append({"retorno": retorno, "arquivos": base.arquivos(pasta)})
    return base.caso(nome, "roteiro", {"arquivos": arquivos, "operacoes": operacoes}, {"resultados": resultados})


def _semestre():
    """Janeiro a junho de 2026: compras levadas, DARF pequena indo para darf_anterior e DARF a pagar."""
    jan = _mes("2026-01", [
        _lote("a1", "PETR4", "2026-01-05", 200, 30.5, [_venda("va1", "2026-01-20", 50, 33.1)]),
        _lote("a2", "T1TW34", "2026-01-06", 20, 9.0, [_venda("va2", "2026-01-15", 10, 10.0)]),
        _lote("a3", "VALE3", "2026-01-07", 10, 60.0, [_venda("va3", "2026-01-08", 10, 61.0)]),
    ])
    fev = _mes("2026-02", [
        _lote("b1", "AAPL34", "2026-02-03", 500, 40.0, [_venda("vb1", "2026-02-12", 500, 48.0)]),
        _lote("b2", "ITUB4", "2026-02-04", 100, 30.25),
    ])
    mar = _mes("2026-03", [_lote("c1", "T1TW34", "2026-03-02", 30, 9.5, [_venda("vc1", "2026-03-10", 30, 9.7)])])
    return {"2026-01.json": jan, "2026-02.json": fev, "2026-03.json": mar}


def casos():
    out = []

    out.append(_roteiro("semestre_fechando_em_sequencia", _semestre(), [
        _fechar("2026-01", 100.5), _fechar("2026-02", 200.5), _fechar("2026-03", 300.5), _fechar("2026-04", 400.5),
        _fechar("2026-05", 500.5),
        _op("custodia_atual", 600.5),
        _fechar("2026-01", 700.5),     # janeiro de novo: fevereiro já está fechado, nada é copiado outra vez
    ]))

    out.append(_roteiro("fechar_mes_ja_fechado_nao_duplica_levadas", _semestre(), [
        _fechar("2026-01", 100.5), _fechar("2026-01", 200.5),
    ]))

    out.append(_roteiro("fechar_mes_com_proximo_aberto_que_ja_tem_a_origem", {
        "2026-01.json": _mes("2026-01", [_lote("a1", "PETR4", "2026-01-05", 100, 30.5,
                                               [_venda("va1", "2026-01-20", 40, 33.1)])]),
        "2026-02.json": _mes("2026-02", [_lote("a1~2026-02", "PETR4", "2026-01-05", 60, 30.5, origem="a1")],
                             darf_anterior=3.5),
    }, [_fechar("2026-01", 100.5)]))

    # --- venda retroativa
    base_retro = {"2026-06.json": _mes("2026-06", [_lote("L1", "T1TW34", "2026-05-05", 58, 9.0)])}
    out.append(_roteiro("retroativa_em_mes_sem_arquivo_e_segunda_venda", base_retro, [
        _op("mes_aceita", mes="2026-03", mes_atual="2026-06"),
        _op("mes_aceita", mes="2026-06", mes_atual="2026-06"),
        _retro("2026-06", "L1", "2026-03-15", 10, 10.0, 100.5),     # DARF pequena de março vai para junho
        _op("mes_aceita", mes="2026-03", mes_atual="2026-06"),
        _retro("2026-06", "L1", "2026-03-20", 30, 12.0, 200.5),     # DARF passa de R$ 10: sai de junho
        _op("historico", meses_recentes=6),
        _op("sugestoes", mes="2026-06", so_custodia=False),
    ]))

    out.append(_roteiro("retroativa_vendendo_a_compra_inteira", base_retro, [
        _retro("2026-06", "L1", "2026-04-15", 58, 10.0),
    ]))

    out.append(_roteiro("retroativa_recusa_compra_com_venda_no_mes_atual", {
        "2026-06.json": _mes("2026-06", [_lote("L1", "T1TW34", "2026-05-05", 58, 9.0,
                                               [_venda("V1", "2026-06-10", 10, 10.0)])])},
        [_retro("2026-06", "L1", "2026-03-15", 20, 10.0)]))

    out.append(_roteiro("retroativa_de_lote_levado_mantem_a_origem", {
        "2026-06.json": _mes("2026-06", [_lote("L1~2026-06", "T1TW34", "2026-05-05", 58, 9.0, origem="L1")])},
        [_retro("2026-06", "L1~2026-06", "2026-03-15", 20, 10.0)]))

    out.append(_roteiro("retroativa_em_mes_fechado_sem_compras_abertas", {
        "2026-02.json": _mes("2026-02", [_lote("F1", "T1TW34", "2026-01-10", 10, 9.0,
                                               [_venda("VF1", "2026-02-05", 10, 10.0)])],
                             fechado=True, resumo=_resumo(1.5)),
        "2026-03.json": _mes("2026-03", [_lote("F2", "ITUB4", "2026-03-02", 10, 30.0)], fechado=True),
        "2026-04.json": _mes("2026-04", [_lote("F3", "ITUB4", "2026-04-02", 10, 30.0,
                                               [_venda("VF3", "2026-04-03", 10, 31.0)])], fechado=True,
                             retroativo=True),
        "2026-05.json": _mes("2026-05"),
        "2026-06.json": _mes("2026-06", [_lote("L1", "T1TW34", "2026-01-05", 58, 9.0)], darf_anterior=1.0),
    }, [
        _op("mes_aceita", mes="2026-02", mes_atual="2026-06"),   # fechado e tudo vendido
        _op("mes_aceita", mes="2026-03", mes_atual="2026-06"),   # fechado com compra levada
        _op("mes_aceita", mes="2026-04", mes_atual="2026-06"),   # retroativo
        _op("mes_aceita", mes="2026-05", mes_atual="2026-06"),   # aberto
        _op("mes_aceita", mes="2026-07", mes_atual="2026-06"),   # futuro
        _retro("2026-06", "L1", "2026-02-20", 20, 10.0, 100.5),
    ]))

    # --- correção de tipos
    out.append(_roteiro("corrigir_tipos_regrava_so_o_que_mudou", {
        "2026-08.json": _mes("2026-08", [_lote("t1", "PETR4", "2026-08-02", 10, 30.0, tipo="BDR")]),
        "2026-09.json": _mes("2026-09", [_lote("t2", "AAPL34", "2026-09-02", 10, 30.0, tipo="BDR")]),
    }, [_op("corrigir_tipos", 100.5), _op("corrigir_tipos", 200.5)]))

    # --- tickers frequentes
    meses = {
        "2026-01.json": _mes("2026-01", [_lote("h0", "OLD3", "2026-01-02", 10, 5.0,
                                               [_venda("hv0", "2026-01-03", 5, 5.5)])], fechado=True),
        "2026-02.json": _mes("2026-02", [_lote("h1", "PETR4", "2026-02-02", 10, 30.0,
                                               [_venda("hv1", "2026-02-03", 5, 31.0)]),
                                         _lote("h2", "VALE3", "2026-02-02", 10, 60.0)], fechado=True),
        "2026-03.json": _mes("2026-03", [_lote("h3", "BBAS3", "2026-03-02", 10, 27.0),
                                         _lote("h4", "ABEV3", "2026-03-02", 10, 13.0),
                                         _lote("h5", "PETR4~", "2026-03-02", 10, 30.0, origem="h1")],
                             fechado=True),
        "2026-04.json": _mes("2026-04", [_lote("h6", "WEGE3", "2026-04-02", 10, 40.0),
                                         _lote("h7", "ITUB4", "2026-04-02", 10, 30.0),
                                         _lote("h8", "MGLU3", "2026-04-02", 10, 2.0)], fechado=True),
        "2026-05.json": _mes("2026-05", [_lote("h9", "AAPL34", "2026-05-02", 10, 40.0,
                                               [_venda("hv9", "2026-05-03", 5, 41.0),
                                                _venda("hv10", "2026-05-04", 5, 42.0)]),
                                         _lote("h10", "ABEV3", "2026-05-02", 10, 13.0, origem="h4")],
                             fechado=True),
        "2026-06.json": _mes("2026-06", [_lote("h11", "TAEE11", "2026-06-02", 10, 11.0),
                                         _lote("h12", "ABEV3~", "2026-06-02", 10, 13.0, origem="h10"),
                                         _lote("h13", "ZZZ3", "2026-06-02", 10, 1.0, [_venda("hv13", "2026-06-03", 10,
                                                                                            1.0)])]),
        "2026-07.json": _mes("2026-07", [_lote("h14", "VALE3", "2026-07-02", 10, 60.0),
                                         _lote("h15", "PETR4", "2026-07-02", 10, 30.0)]),
    }
    out.append(_roteiro("tickers_com_empates_de_frequencia", meses, [
        _op("historico", meses_recentes=6),
        _op("historico", meses_recentes=2),
        _op("historico", meses_recentes=0),
        _op("sugestoes", mes="2026-06", so_custodia=False),
        _op("sugestoes", mes="2026-06", so_custodia=True),
        _op("sugestoes", mes="2026-07", so_custodia=False),
        _op("sugestoes", mes="2026-07", so_custodia=True),
        _op("custodia_atual"),
    ]))

    out.append(_roteiro("tickers_sem_nenhum_mes", {}, [
        _op("historico", meses_recentes=6),
        _op("sugestoes", mes="2026-10", so_custodia=False),
        _op("custodia_atual"),
    ]))
    return out
