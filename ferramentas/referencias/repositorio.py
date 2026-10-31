"""Referências do repositório local: salvar/carregar com carimbo de alterações, config e listagem de meses
(nucleo.py:125-226).

Cada caso é um roteiro: entrada = {"arquivos": {nome: json} gravados antes, "operacoes": [...]}; saída =
{"arquivos": {nome: json} depois de todas as operações, "resultados": [resultado de cada operação]}.
Operações: salvar {dados, carimbar}, gravar_config {dados, carimbar}, carregar {mes}, ler_config, listar_meses,
mes_inicial. Cada uma traz o `agora` em vigor (o relógio muda entre operações).
"""
import copy

from . import base

nc = base.nc

T0 = 1761000000.123
T1 = 1761000100.5
T2 = 1761000200.25


def _venda(i, data, qtd, preco, mod=100.5):
    return {"id": i, "data": data, "qtd": qtd, "preco": preco, "mod": mod}


def _lote(i, ticker, qtd, preco, vendas=(), mod=100.5, tipo="Ação", data="2026-10-02"):
    return {"id": i, "ticker": ticker, "tipo": tipo, "data_compra": data, "qtd": qtd, "preco": preco,
            "vendas": list(vendas), "mod": mod}


def _mes(mes, lotes=(), fechado=False, darf_anterior=0.0, excluidos=None, mod=100.5):
    return {"mes": mes, "fechado": fechado, "darf_anterior": darf_anterior, "lotes": list(lotes),
            "excluidos": dict(excluidos or {}), "mod": mod}


def _mes_base():
    return _mes("2026-10", [
        _lote("l1", "PETR4", 200, 30.5, [_venda("v1", "2026-10-15", 50, 33.25), _venda("v2", "2026-10-20", 20, 34.0)]),
        _lote("l2", "VALE3", 100, 60.0, [_venda("v3", "2026-10-10", 100, 61.1)], data="2026-10-10"),
    ])


def _executar(op):
    nome = op["op"]
    if nome == "salvar":
        nc.salvar(copy.deepcopy(op["dados"]), carimbar=op["carimbar"])
        return None
    if nome == "gravar_config":
        nc.gravar_config(copy.deepcopy(op["dados"]), carimbar=op["carimbar"])
        return None
    if nome == "carregar":
        return nc.carregar(op["mes"])
    if nome == "ler_config":
        return nc.ler_config()
    if nome == "listar_meses":
        return nc.listar_meses()
    if nome == "mes_inicial":
        return nc.mes_inicial()
    raise ValueError(nome)


def _salvar(agora, dados, carimbar=True):
    return {"op": "salvar", "agora": agora, "dados": dados, "carimbar": carimbar}


def _config(agora, dados, carimbar=True):
    return {"op": "gravar_config", "agora": agora, "dados": dados, "carimbar": carimbar}


def _simples(op, agora=T0, **extra):
    return {"op": op, "agora": agora, **extra}


def _roteiro(nome, arquivos, operacoes):
    with base.pasta_dados() as pasta, base.congelar():
        base.gravar_arquivos(pasta, arquivos)
        resultados = []
        for op in operacoes:
            nc.agora = lambda t=op["agora"]: t
            resultados.append(_executar(op))
        saida = {"arquivos": base.arquivos(pasta), "resultados": resultados}
    return base.caso(nome, "roteiro", {"arquivos": arquivos, "operacoes": operacoes}, saida)


def _meta(id_, **extra):
    m = {"id": id_, "ticker": "PETR4", "tipo": "Ação", "lote_id": "l1", "qtd": 10, "preco_alvo": 40.5,
         "criada_em": "2026-10-20T10:00:00-03:00", "status": "ativa", "lucro_desejado": 100.0, "mod": 100.5}
    m.update(extra)
    return m


def _stop(id_, stop_atual, niveis):
    return {"id": id_, "ticker": "VALE3", "tipo": "Ação", "lote_id": "l2", "qtd": 5, "gatilho": "stop",
            "stop_inicial": 55.0, "movel": True, "stop_atual": stop_atual, "niveis": niveis,
            "criada_em": "2026-10-20T10:00:00-03:00", "status": "ativa", "mod": 100.5}


def _cfg_inicial():
    return {
        "tema": "Dark",
        "amigos": [{"email": "a@x.com", "desde": "2026-09-01", "mod": 100.5},
                   {"email": "b@x.com", "desde": "2026-09-02", "mod": 100.5}],
        "radar": [{"ticker": "PETR4", "nome": "Petrobras", "desde": "2026-09-01", "pos": 0, "mod": 100.5},
                  {"ticker": "VALE3", "nome": "Vale", "desde": "2026-09-01", "pos": 1, "mod": 100.5}],
        "planilhas": {"a@x.com": "planilha-1"},
        "pendente": True,
        "excluidos": {"radar:ITUB4": 90.5},
        "caixa": {"saldo": 1500.75, "data": "2026-10-01", "mod": 100.5},
        "metas": [_meta("m1"), _meta("m2")],
        "noticias_notificar": True,
        "radar_ordem_lista": ["VALE3", "PETR4"],
    }


def casos():
    out = []

    # --- meses
    out.append(_roteiro("salvar_mes_novo", {}, [
        _salvar(T1, _mes("2026-10", [
            {"id": "l1", "ticker": "PETR4", "tipo": "Ação", "data_compra": "2026-10-02", "qtd": 200, "preco": 30.5,
             "vendas": [{"id": "v1", "data": "2026-10-15", "qtd": 50, "preco": 33.25}]},
            {"id": "l2", "ticker": "Itaú", "tipo": "Ação", "data_compra": "2026-10-03", "qtd": 1, "preco": 1.125,
             "vendas": []},
        ], mod=0)),
        _simples("carregar", T1, mes="2026-10"),
    ]))

    editado = _mes_base()
    editado["lotes"][1]["preco"] = 61.25
    out.append(_roteiro("editar_preco_de_um_lote", {"2026-10.json": _mes_base()}, [_salvar(T1, editado)]))

    out.append(_roteiro("regravar_sem_mudanca_nao_carimba", {"2026-10.json": _mes_base()},
                        [_salvar(T1, _mes_base())]))

    fechado = _mes_base()
    fechado["fechado"] = True
    fechado["darf_anterior"] = 12.34
    out.append(_roteiro("fechar_mes_carimba_o_mes", {"2026-10.json": _mes_base()}, [_salvar(T1, fechado)]))

    sem_venda = _mes_base()
    del sem_venda["lotes"][0]["vendas"][1]
    out.append(_roteiro("excluir_uma_venda", {"2026-10.json": _mes_base()}, [_salvar(T1, sem_venda)]))

    sem_lote = _mes_base()
    del sem_lote["lotes"][0]
    out.append(_roteiro("excluir_lote_com_vendas", {"2026-10.json": _mes_base()}, [_salvar(T1, sem_lote)]))

    mudancas = _mes_base()
    mudancas["lotes"][0]["qtd"] = 300
    mudancas["lotes"][0]["vendas"][0]["preco"] = 34.5
    del mudancas["lotes"][1]
    mudancas["lotes"].append(_lote("l3", "BBAS3", 10, 27.0, mod=0))
    mudancas["darf_anterior"] = 5.5
    out.append(_roteiro("sem_carimbar", {"2026-10.json": _mes_base()}, [_salvar(T1, mudancas, carimbar=False)]))

    sequencia = _mes_base()
    sequencia["lotes"][0]["preco"] = 31.0
    sequencia2 = copy.deepcopy(sequencia)
    del sequencia2["lotes"][1]
    sequencia2["lotes"][0]["vendas"][0]["qtd"] = 40
    out.append(_roteiro("duas_gravacoes_em_sequencia", {"2026-10.json": _mes_base()},
                        [_salvar(T1, sequencia), _salvar(T2, sequencia2)]))

    out.append(_roteiro("carregar_sem_excluidos_e_ausente", {
        "2026-09.json": {"mes": "2026-09", "fechado": True, "darf_anterior": 1.5, "lotes": [], "mod": 7.0}}, [
        _simples("carregar", mes="2026-09"), _simples("carregar", mes="2026-08")]))

    # --- config
    out.append(_roteiro("config_padrao_quando_ausente_e_gravar", {}, [
        _simples("ler_config"),
        _config(T1, {"tema": "Dark", "amigos": [{"email": "a@x.com", "desde": "2026-10-01"}],
                     "radar": [{"ticker": "PETR4", "nome": "Petrobras", "desde": "2026-10-01"}],
                     "planilhas": {}, "pendente": False, "excluidos": {},
                     "caixa": {"saldo": 0.0, "data": "", "mod": 0}, "metas": [_meta("m1", mod=0)]}),
        _simples("ler_config", T1),
    ]))

    out.append(_roteiro("config_parcial_completa_padrao",
                        {"config.json": {"tema": "Light", "noticias_notificar": False}}, [_simples("ler_config")]))

    cfg2 = _cfg_inicial()
    del cfg2["amigos"][1]
    del cfg2["radar"][1]
    del cfg2["metas"][1]
    cfg2["radar"][0]["nome"] = "Petrobras PN"
    cfg2["amigos"].append({"email": "c@x.com", "desde": "2026-10-28"})
    cfg2["caixa"]["saldo"] = 1600.0
    cfg2["metas"].append(_meta("m3", ticker="ITUB4", mod=0))
    out.append(_roteiro("config_incluir_e_remover_radar_amigos_metas", {"config.json": _cfg_inicial()}, [
        _config(T1, cfg2), _simples("ler_config", T1)]))

    out.append(_roteiro("config_sem_mudanca_nao_carimba", {"config.json": _cfg_inicial()},
                        [_config(T1, _cfg_inicial())]))

    niv = [{"desde": "2026-10-20", "stop": 55.0, "calc_em": "2026-10-20T10:00:00-03:00"}]
    inicial = _cfg_inicial()
    inicial["metas"] = [_meta("m1"), _stop("s1", 55.0, niv)]
    subiu = copy.deepcopy(inicial)
    subiu["metas"][1]["stop_atual"] = 58.5
    subiu["metas"][1]["niveis"] = niv + [{"desde": "2026-10-27", "stop": 58.5, "calc_em": "2026-10-27T10:00:00-03:00"}]
    mudou_alvo = copy.deepcopy(subiu)
    mudou_alvo["metas"][1]["qtd"] = 3
    mudou_alvo["metas"][0]["status"] = "cancelada"
    out.append(_roteiro("config_stop_atual_e_niveis_nao_carimbam", {"config.json": inicial}, [
        _config(T1, subiu), _config(T2, mudou_alvo)]))

    out.append(_roteiro("config_sem_carimbar", {"config.json": _cfg_inicial()}, [
        _config(T1, {**_cfg_inicial(), "tema": "Light", "radar": [], "caixa": {"saldo": 9.5, "data": "x", "mod": 0}},
                carimbar=False)]))

    # --- listagem
    lixo = {"mes": "x"}
    out.append(_roteiro("listar_meses_ignora_nomes_fora_do_padrao", {
        "config.json": _cfg_inicial(), "2026-1.json": lixo, "abcd-ef.json": _mes("abcd-ef"),
        "2026-10.json": _mes("2026-10"), "2025-12.json": _mes("2025-12"), "2026-09.json": _mes("2026-09"),
        "noticias.json": {"itens": []}, "2026-10-extra.json": lixo,
    }, [_simples("listar_meses")]))
    out.append(_roteiro("listar_meses_vazio", {}, [_simples("listar_meses")]))

    out.append(_roteiro("mes_inicial_primeiro_aberto", {
        "2026-08.json": _mes("2026-08", fechado=True), "2026-09.json": _mes("2026-09"),
        "2026-10.json": _mes("2026-10")}, [_simples("mes_inicial")]))
    out.append(_roteiro("mes_inicial_todos_fechados_usa_hoje", {
        "2026-08.json": _mes("2026-08", fechado=True), "2026-09.json": _mes("2026-09", fechado=True)},
        [_simples("mes_inicial")]))
    out.append(_roteiro("mes_inicial_sem_meses_usa_hoje", {}, [_simples("mes_inicial")]))
    return out
