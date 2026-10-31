"""Referências dos modelos: arquivos que o Python grava (ou que a 1.12 deixaria) e o que ele regrava após carregar.

Cada caso: entrada = {nome do arquivo: conteúdo JSON}, saída = os mesmos arquivos depois de o Python carregar e
salvar (nc.carregar + nc.salvar para os meses, nc.ler_config + nc.gravar_config para o config.json), sem carimbar.
"""
from datetime import datetime, timedelta, timezone

from . import base

nc = base.nc
mt = base.mt

FUSO = timezone(timedelta(hours=-3))


def _regravar(pasta):
    """O que o Python grava depois de carregar e salvar cada arquivo da pasta."""
    for p in sorted(pasta.glob("????-??.json")):
        nc.salvar(nc.carregar(p.stem), carimbar=False)
    if (pasta / "config.json").exists():
        nc.gravar_config(nc.ler_config(), carimbar=False)
    return base.arquivos(pasta)


def _caso(nome, preparar):
    """Roda `preparar(pasta)` (grava os arquivos de entrada) e regrava com o Python."""
    with base.pasta_dados() as pasta, base.congelar():
        preparar(pasta)
        entrada = base.arquivos(pasta)
        saida = _regravar(pasta)
    return base.caso(nome, "arquivos", entrada, saida)


def _lote(ticker, tipo, data, qtd, preco):
    return {"id": nc.novo_id(), "ticker": ticker, "tipo": tipo, "data_compra": data, "qtd": qtd, "preco": preco,
            "vendas": []}


def _meses_pelo_python(pasta):
    """Mês com venda, fechamento com resumo e compra levada (origem), e mês retroativo."""
    d = nc.carregar("2026-09")
    petr = _lote("PETR4", "Ação", "2026-09-02", 200, 30.5)
    petr["vendas"].append({"id": nc.novo_id(), "data": "2026-09-15", "qtd": 50, "preco": 33.25})
    vale = _lote("VALE3", "Ação", "2026-09-10", 100, 60.0)
    vale["vendas"].append({"id": nc.novo_id(), "data": "2026-09-10", "qtd": 100, "preco": 61.1})
    d["lotes"] += [petr, vale]
    nc.salvar(d)
    nc.fechar_mes(nc.carregar("2026-09"))
    d = nc.carregar("2026-10")
    d["lotes"].append(_lote("IVVB11", "BDR", "2026-10-05", 10, 250.75))
    nc.salvar(d)
    # venda retroativa: a compra de origem (levada para 2026-10) foi vendida em agosto
    d = nc.carregar("2026-10")
    levada = next(l for l in d["lotes"] if l.get("origem"))
    nc.registrar_venda_retroativa(d, levada["id"], {"data": "2026-08-20", "qtd": 30, "preco": 35.0})


def _config_pelo_python(pasta):
    """Amigos, radar com e sem pos, caixa, metas de todos os tipos e chaves que o app desconhece."""
    d = nc.carregar("2026-10")
    d["lotes"] += [_lote("PETR4", "Ação", "2026-10-01", 1000, 30.0), _lote("ITUB4", "Ação", "2026-10-01", 500, 25.0)]
    nc.salvar(d)
    petr, itub = (l["id"] for l in nc.carregar("2026-10")["lotes"])

    cfg = nc.ler_config()
    cfg["tema"] = "Light"
    cfg["amigos"] = [{"email": "ana@exemplo.com", "desde": "2026-09-01"}]
    nc.adicionar_radar(cfg, "PETR4", "Petrobras PN")
    nc.adicionar_radar(cfg, "ITUB4")
    cfg["radar"].append({"ticker": "WEGE3", "nome": "WEG", "desde": "2026-08-01"})     # sem pos
    nc.definir_saldo(cfg, 12345.67)
    cfg["planilhas"] = {"joao@exemplo.com": "id-da-planilha"}
    cfg["pendente"] = True
    cfg["noticias_notificar"] = True
    cfg["radar_ordem_lista"] = ["PETR4", "ITUB4", "WEGE3"]
    nc.gravar_config(cfg)

    alvo = mt.criar_meta(cfg, petr, 100, 40.0, lucro_desejado=500.0)
    stop_par = mt.criar_stop(cfg, petr, 100, 28.0, oco_com=alvo["id"])
    mt.criar_stop(cfg, petr, 200, 27.5, movel=True,
                  sugestao={"stop": 27.5, "alvo": 36.0, "atr": 1.1, "regime": "swing"})
    cancelada = mt.criar_meta(cfg, petr, 50, 45.0)
    mt.cancelar_meta(cfg, cancelada["id"])
    mt.criar_meta(cfg, itub, 100, 31.0)

    barra = {"ts": 1761674400, "dt": datetime(2026, 10, 28, 15, 0, tzinfo=FUSO), "alta": 40.5, "baixa": 39.0,
             "abre": 39.5}
    hist = {"barras": [barra], "fonte": "Yahoo Finance", "intervalo": "5m"}
    mt.aplicar(cfg, {"PETR4": ("ok", hist), "ITUB4": ("erro", "Sem conexão com a internet.")})
    assert stop_par["id"] and any(m["status"] == "executada" for m in cfg["metas"])
    assert any(m.get("ultimo_erro") for m in cfg["metas"])


def _meses_a_mao(pasta):
    """Como a 1.12 deixaria: sem excluidos, quantidades e preços inteiros ou float, compra levada."""
    base.gravar_arquivos(pasta, {
        "2026-05.json": {
            "mes": "2026-05", "fechado": False, "darf_anterior": 0, "mod": 0,
            "lotes": [{"id": "a1", "ticker": "PETR4", "tipo": "Ação", "data_compra": "2026-05-04", "qtd": 100.0,
                       "preco": 12, "mod": 0,
                       "vendas": [{"id": "v1", "data": "2026-05-10", "qtd": 40.0, "preco": 15, "mod": 0}]}],
        },
        "2026-06.json": {
            "mes": "2026-06", "fechado": True, "darf_anterior": 3.5, "mod": 1760000000.5,
            "lotes": [{"id": "a1~2026-06", "origem": "a1", "ticker": "PETR4", "tipo": "Ação",
                       "data_compra": "2026-05-04", "qtd": 60, "preco": 12.0, "vendas": [], "mod": 0}],
            "excluidos": {"antigo": 1759999999.9},
            "resumo": {"vendas_acoes_st": 600.0, "isento": True, "bruto": 120, "custos": 0.5, "imp_st": 0,
                       "imp_dt": 0.0, "imposto_total": 0, "irrf": 0, "lucro_liquido": 119.5, "darf_mes": 0,
                       "darf_anterior": 3.5, "darf": 3.5},
        },
    })


def _config_a_mao(pasta):
    base.gravar_arquivos(pasta, {"config.json": {
        "tema": "Dark", "amigos": [{"email": "a@b.com", "desde": "2026-01-02", "mod": 0}],
        "radar": [{"ticker": "VALE3", "nome": "Vale ON", "desde": "2026-01-02", "mod": 5, "pos": 3}],
        "caixa": {"saldo": 100, "data": "2026-10-01", "mod": 7},
        "metas": [{"id": "meta-x", "ticker": "VALE3", "tipo": "Ação", "lote_id": "a1", "qtd": 100,
                   "preco_alvo": 70, "criada_em": "2026-10-01T10:00:00-03:00", "status": "ativa", "mod": 0}],
        "futuro": {"a": [1, 2.5, None], "b": "ç"},
    }})


def _config_vazio(pasta):
    base.gravar_arquivos(pasta, {"config.json": {}})


def casos():
    return [
        _caso("meses_pelo_python", _meses_pelo_python),
        _caso("config_pelo_python", _config_pelo_python),
        _caso("meses_a_mao", _meses_a_mao),
        _caso("config_a_mao", _config_a_mao),
        _caso("config_vazio", _config_vazio),
    ]
