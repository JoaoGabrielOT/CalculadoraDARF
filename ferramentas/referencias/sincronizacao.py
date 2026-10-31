"""Referências da sincronização sem rede: mesclar_tudo e as linhas a gravar (nucleo.py:1171-1211;
calculadora_darf.py:2865-2876; android/main.py:2357-2359).

Cada caso é um roteiro: entrada = {"arquivos": {nome: json} da pasta de dados local (inclui config.json), "abas": {aba:
linhas lidas da planilha, já normalizadas}, "agora": epoch do relógio do núcleo}; saída = {"mudou", "avisos",
"arquivos": {nome: json} depois, "cfg": configuração final, "linhas": montar_linhas de todos os meses locais}.
A configuração é lida de config.json (ler_config) e passada a mesclar_tudo, como faz o aplicativo. As abas vêm de
montar_linhas sobre uma pasta de dados "remota" (outro aparelho). A aba Exclusões vem de um set no Python; aqui fica
ordenada para o arquivo gerado ser estável (o teste compara sem ordem mesmo assim).
"""
import copy

from . import base
from .planilha_montagem import _lote, _meta, _mes, _venda

nc = base.nc

T0 = 1761000000.123
CRIADA = "2026-10-20T11:00:00-03:00"
EXEC_A = {"venda_id": "auto-meta-a", "data": "2026-10-22", "hora": "10:00", "preco_usado": 21.78}
EXEC_S = {"venda_id": "auto-meta-s", "data": "2026-10-21", "hora": "10:00", "preco_usado": 9.0}
STOP = dict(gatilho="stop", stop_inicial=5.0, stop_atual=5.0, movel=True,
            niveis=[{"desde": "2026-10-20", "stop": 5.0, "calc_em": "2026-10-20"}])


def _cfg(**extra):
    """Configuração completa. O radar sempre traz `nome` e o caixa as três chaves (como o aplicativo grava): o modelo
    Dart as normaliza, então configurações sem elas não fazem parte destes roteiros."""
    cfg = {"tema": "Dark", "amigos": [], "radar": [], "planilhas": {}, "pendente": False, "excluidos": {},
           "caixa": {"saldo": 0.0, "data": "", "mod": 0}, "metas": [], **extra}
    cfg["radar"] = [{"nome": "", **r} for r in cfg["radar"]]
    cfg["caixa"] = {"saldo": 0.0, "data": "", "mod": 0, **cfg["caixa"]}
    return cfg


def _remota(meses, cfg):
    """Abas que outro aparelho gravaria na planilha."""
    with base.pasta_dados() as pasta, base.congelar():
        base.gravar_arquivos(pasta, {f"{m['mes']}.json": m for m in meses})
        linhas = nc.montar_linhas([m["mes"] for m in meses], cfg)
    linhas["Exclusões"] = sorted(linhas["Exclusões"], key=str)
    return linhas


def _sincronizar(nome, meses, cfg, abas, agora=T0):
    arquivos = {f"{m['mes']}.json": m for m in meses}
    arquivos["config.json"] = cfg
    avisos = []
    with base.pasta_dados() as pasta, base.congelar():
        base.gravar_arquivos(pasta, arquivos)
        nc.agora = lambda: agora
        local = nc.ler_config()
        mudou = nc.mesclar_tudo(nc.reconstruir(abas), local, metas_r=nc.reconstruir_metas(abas), avisos=avisos)
        linhas = nc.montar_linhas(nc.listar_meses(), local)
        linhas["Exclusões"] = sorted(linhas["Exclusões"], key=str)
        saida = {"mudou": mudou, "avisos": avisos, "arquivos": base.arquivos(pasta), "cfg": local,
                 "linhas": linhas}
    entrada = {"arquivos": copy.deepcopy(arquivos), "abas": abas, "agora": agora}
    return base.caso(nome, "sincronizar", entrada, saida)


def _simples(nome, local_meses, local_cfg, remoto_meses, remoto_cfg, agora=T0):
    return _sincronizar(nome, local_meses, local_cfg, _remota(remoto_meses, remoto_cfg), agora)


def _casos_basicos():
    mes = _mes("2026-10", [
        _lote("l1", "PETR4", "2026-10-02", 100, 30.0, [_venda("v1", "2026-10-10", 50, 33.0)]),
        _lote("l2", "VALE3", "2026-10-03", 10, 60.0)])
    cfg = _cfg(amigos=[{"email": "ana@exemplo.com", "desde": "2026-09-01", "mod": 70.5}],
               radar=[{"ticker": "PETR4", "nome": "Petrobras", "desde": "2026-08-02", "pos": 0, "mod": 71.5}],
               caixa={"saldo": 100.5, "data": "2026-10-20", "mod": 5.5})
    vazia = _remota([], _cfg())
    mes_novo = copy.deepcopy(mes)
    mes_novo["mod"] = 20.5
    mes_novo["lotes"][0]["preco"] = 31.0
    mes_novo["lotes"][0]["mod"] = 20.5
    mes_novo["lotes"][0]["vendas"][0].update(preco=34.0, mod=20.5)
    mes_novo["lotes"].append(_lote("l3", "ITUB4", "2026-10-04", 5, 30.0, mod=20.5))
    cfg_remota = _cfg(amigos=[{"email": "ana@exemplo.com", "desde": "2026-09-02", "mod": 80.5},
                              {"email": "beto@exemplo.com", "desde": "2026-09-15", "mod": 80.5}],
                      radar=[{"ticker": "PETR4", "nome": "Petrobras SA", "desde": "2026-08-02", "pos": 1, "mod": 81.5},
                             {"ticker": "VALE3", "nome": "Vale", "desde": "2026-08-03", "pos": 0, "mod": 81.5}],
                      caixa={"saldo": 900.0, "data": "2026-10-25", "mod": 50.5})
    mes_velho = copy.deepcopy(mes)
    mes_velho["lotes"][0]["preco"] = 1.0
    mes_velho["lotes"][0]["mod"] = 1.5
    cfg_velha = _cfg(amigos=[{"email": "ana@exemplo.com", "desde": "2026-01-01", "mod": 1.5}],
                     radar=[{"ticker": "PETR4", "nome": "Velha", "desde": "2026-01-02", "pos": 3, "mod": 1.5}],
                     caixa={"saldo": 1.0, "data": "2026-01-01", "mod": 1.5})
    return [
        _sincronizar("primeira_sincronizacao_planilha_vazia", [mes], cfg, vazia),
        _simples("planilha_igual_ao_local", [mes], cfg, [mes], cfg),
        _simples("edicao_remota_mais_nova", [mes], cfg, [mes_novo], cfg_remota),
        _simples("local_mais_novo", [mes], cfg, [mes_velho], cfg_velha),
        _simples("sem_dados_locais", [], _cfg(), [mes_novo], cfg_remota),
        _simples("caixa_remoto_mais_velho", [mes], cfg, [mes], _cfg(caixa={"saldo": 7.0, "mod": 1.5})),
        _simples("caixa_remoto_mais_novo", [mes], cfg, [mes], _cfg(caixa={"saldo": 7.0, "data": "2026-10-26",
                                                                          "mod": 99.5})),
        _simples("caixa_remoto_com_mod_igual", [mes], cfg, [mes], _cfg(caixa={"saldo": 7.0, "mod": 5.5})),
    ]


def _casos_exclusao():
    local = _mes("2026-10", [
        _lote("l1", "PETR4", "2026-10-02", 100, 30.0, [_venda("v1", "2026-10-10", 50, 33.0, mod=10.5),
                                                       _venda("v2", "2026-10-11", 10, 33.5, mod=10.5)], mod=10.5),
        _lote("l2", "VALE3", "2026-10-03", 10, 60.0, mod=10.5)], excluidos={"l9": 30.5})
    remoto = _mes("2026-10", [
        _lote("l1", "PETR4", "2026-10-02", 100, 30.0, [_venda("v1", "2026-10-10", 50, 33.0, mod=10.5)], mod=10.5),
        _lote("l2", "VALE3", "2026-10-03", 10, 60.0, mod=10.5),
        _lote("l9", "ITUB4", "2026-10-04", 5, 30.0, mod=20.5)], excluidos={"v2": 40.5, "l2": 10.5})
    cfg_local = _cfg(amigos=[{"email": "ana@exemplo.com", "desde": "2026-09-01", "mod": 10.5},
                             {"email": "caio@exemplo.com", "desde": "2026-09-01", "mod": 10.5}],
                     radar=[{"ticker": "PETR4", "desde": "2026-08-02", "pos": 0, "mod": 10.5},
                            {"ticker": "OLD3", "desde": "2026-08-02", "pos": 1, "mod": 10.5}],
                     excluidos={"amigos:beto@exemplo.com": 60.5, "radar:NOVA3": 60.5})
    cfg_remota = _cfg(amigos=[{"email": "beto@exemplo.com", "desde": "2026-09-01", "mod": 20.5}],
                      radar=[{"ticker": "NOVA3", "desde": "2026-08-02", "pos": 0, "mod": 20.5}],
                      excluidos={"amigos:ana@exemplo.com": 50.5, "radar:OLD3": 10.5})
    return [_simples("exclusao_nos_dois_sentidos", [local], cfg_local, [remoto], cfg_remota)]


def _casos_metas():
    alvo = dict(preco_alvo=21.78, lucro_desejado=1000.0)
    auto_a = {"id": "auto-meta-a", "data": "2026-10-22", "qtd": 100, "preco": 21.78, "mod": 11.5}
    # meta executada no remoto contra ativa mais nova no local (sem a venda)
    mes_sem = _mes("2026-10", [_lote("L1", "PETR4", "2026-10-01", 100, 10.0, mod=5.5)], mod=5.5)
    mes_com = _mes("2026-10", [_lote("L1", "PETR4", "2026-10-01", 100, 10.0, [auto_a], mod=5.5)], mod=5.5)
    ativa = _meta("meta-a", "PETR4", "L1", 100, CRIADA, mod=9e9, **alvo)
    exec_a = _meta("meta-a", "PETR4", "L1", 100, CRIADA, status="executada", execucao=EXEC_A, mod=11.5, **alvo)

    # venda automática em dois meses (mês seguinte recebe o lote ao fechar)
    v = {"id": "auto-meta-x", "data": "2026-10-31", "qtd": 50, "preco": 20.0, "mod": 12.5}
    d10 = _mes("2026-10", [_lote("L1", "PETR4", "2026-10-01", 100, 10.0, [v], mod=5.5)], mod=5.5)
    d11 = _mes("2026-11", [_lote("L1~2026-11", "PETR4", "2026-10-01", 100, 10.0, [{**v, "data": "2026-11-01"}],
                                 origem="L1", mod=5.5)], mod=5.5)

    # OCO duplo: o aparelho local executou o alvo, o remoto executou o stop (mais cedo)
    local_oco = _mes("2026-10", [_lote("L1", "PETR4", "2026-10-01", 100, 10.0, [auto_a], mod=5.5)], mod=5.5)
    alvo_oco = _meta("meta-a", "PETR4", "L1", 100, CRIADA, status="executada", execucao=EXEC_A, oco="oco-1",
                     mod=11.5, **alvo)
    stop_ativa = _meta("meta-s", "PETR4", "L1", 100, CRIADA, oco="oco-1", mod=6.5, **STOP)
    stop_exec = _meta("meta-s", "PETR4", "L1", 100, CRIADA, oco="oco-1", status="executada", execucao=EXEC_S,
                      mod=7e9, **STOP)
    auto_s = {"id": "auto-meta-s", "data": "2026-10-21", "qtd": 100, "preco": 9.0, "mod": 9e9}
    remoto_oco = _mes("2026-10", [_lote("L1", "PETR4", "2026-10-01", 100, 10.0, [auto_s], mod=5.5)], mod=5.5)

    # mês fechado: as duas vendas ficam e sai um aviso
    fechado = _mes("2026-10", [_lote("L1", "PETR4", "2026-10-01", 200, 10.0, [
        auto_a, {"id": "auto-meta-s", "data": "2026-10-21", "qtd": 100, "preco": 9.0, "mod": 9.5}], mod=5.5)],
        fechado=True, mod=5.5)
    stop_exec_local = _meta("meta-s", "PETR4", "L1", 100, CRIADA, oco="oco-1", status="executada", execucao=EXEC_S,
                            mod=8.5, **STOP)

    return [
        _simples("meta_executada_remota_contra_ativa_local", [mes_sem], _cfg(metas=[ativa]), [mes_com],
                 _cfg(metas=[exec_a])),
        _simples("meta_executada_local_contra_ativa_remota", [mes_com], _cfg(metas=[exec_a]), [mes_sem],
                 _cfg(metas=[ativa])),
        _simples("meta_cancelada_remota", [mes_sem], _cfg(metas=[ativa]), [mes_sem],
                 _cfg(metas=[{**ativa, "status": "cancelada", "mod": 1e10}])),
        _simples("venda_auto_em_meses_diferentes", [d10, d11], _cfg(), [], _cfg()),
        _simples("venda_auto_em_meses_diferentes_via_planilha", [d10], _cfg(), [d11], _cfg()),
        _simples("oco_duplo", [local_oco], _cfg(metas=[alvo_oco, stop_ativa]), [remoto_oco],
                 _cfg(metas=[stop_exec])),
        _simples("oco_duplo_mes_fechado_com_aviso", [fechado], _cfg(metas=[alvo_oco, stop_exec_local]), [], _cfg()),
    ]


def _casos_radar_e_antiga():
    mes = _mes("2026-10", [_lote("l1", "PETR4", "2026-10-02", 100, 30.0)])
    cfg_remota = _cfg(
        radar=[{"ticker": "VALE3", "nome": "Vale", "desde": "2026-08-01", "pos": 2, "mod": 71.5},
               {"ticker": "ITUB4", "nome": "Itaú", "desde": "2026-08-02", "pos": 0, "mod": 71.5},
               {"ticker": "WEGE3", "desde": "2026-08-04", "mod": 71.5}],
        metas=[_meta("meta-b", "PETR4", "l1", 100, CRIADA, preco_alvo=36.5, lucro_desejado=250.0)])
    cfg_local = _cfg(radar=[{"ticker": "ABEV3", "nome": "Ambev", "desde": "2026-08-05", "pos": 1, "mod": 5.5},
                            {"ticker": "B3SA3", "desde": "2026-08-06", "mod": 5.5}])
    abas = _remota([mes], cfg_remota)
    sem_posicao = copy.deepcopy(abas)
    sem_posicao["Radar"] = [r[:4] for r in sem_posicao["Radar"]]
    antiga = copy.deepcopy(abas)
    antiga["Radar"] = [r[:4] for r in antiga["Radar"]]
    antiga["Metas"] = [r[:12] for r in antiga["Metas"]]
    return [
        _sincronizar("radar_com_posicao", [mes], cfg_local, abas),
        _sincronizar("radar_sem_posicao", [mes], cfg_local, sem_posicao),
        _sincronizar("planilha_antiga_metas_12_radar_4", [mes], cfg_local, antiga),
        _sincronizar("planilha_sem_abas", [mes], cfg_local, {}),
    ]


def casos():
    return _casos_basicos() + _casos_exclusao() + _casos_metas() + _casos_radar_e_antiga()
