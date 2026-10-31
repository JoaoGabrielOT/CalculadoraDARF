"""Referências da cadeia de compras, das compras abertas, da reserva e da criação e cancelamento de metas
(metas.py:116-353, 431-432, 463-472).

Cada caso é um roteiro: entrada = {"arquivos": {nome: json} gravados antes, "operacoes": [...]}; saída =
{"resultados": [{"retorno": ..., "arquivos": {nome: json} depois da operação}]}. A configuração é lida uma vez no
início (como faz o aplicativo) e reaproveitada entre as operações. Números não finitos vêm como texto
("inf", "-inf", "nan"). O ValueError vira {"erro": texto}.
Operações: criar_meta {lote_id, qtd, preco_alvo, lucro_desejado?, oco_com?, agora_meta?}, criar_stop {lote_id, qtd,
preco_stop, movel?, oco_com?, preco_atual?, sugestao?, agora_meta?}, cancelar {meta_id}, reservado {lote_id,
ignorar?}, cadeia {lote_id} -> [[mês, id]], venda_existente {venda_id} -> [id da compra, id da venda] ou null,
raizes, lotes_abertos -> [[mês, id]], posicoes_abertas -> [[mês, id, restante, livre, [ids]]],
lotes_para_meta -> [[mês, id, livre]], parceira_oco {lote_id, gatilho} -> id ou null, fechar_mes {mes},
ida_e_volta (montar_linhas + reconstruir_metas da configuração gravada).
"""
import copy
from datetime import datetime

from . import base

nc = base.nc
mt = base.mt

T0 = 1761000000.123
CRIADA = "2026-10-20T11:00:00-03:00"


def _venda(i, data, qtd, preco):
    return {"id": i, "data": data, "qtd": qtd, "preco": preco, "mod": 50.5}


def _lote(i, ticker, data, qtd, preco, vendas=(), origem=None):
    l = {"id": i, "ticker": ticker, "tipo": nc.tipo_por_ticker(ticker), "data_compra": data, "qtd": qtd,
         "preco": preco, "vendas": list(vendas), "mod": 50.5}
    if origem:
        l["origem"] = origem
    return l


def _mes(mes, lotes=(), fechado=False):
    return {"mes": mes, "fechado": fechado, "darf_anterior": 0.0, "lotes": list(lotes), "excluidos": {},
            "mod": 50.5}


def _alvo(i, lote_id, qtd, status="ativa", oco=None, criada=CRIADA, **extra):
    m = {"id": i, "ticker": "PETR4", "tipo": "Ação", "lote_id": lote_id, "qtd": qtd, "preco_alvo": 20.0,
         "criada_em": criada, "status": status, "mod": 5.5}
    if oco:
        m["oco"] = oco
    m.update(extra)
    return m


def _stop(i, lote_id, qtd, status="ativa", oco=None, criada=CRIADA):
    m = {"id": i, "ticker": "PETR4", "tipo": "Ação", "lote_id": lote_id, "qtd": qtd, "gatilho": "stop",
         "stop_inicial": 9.0, "movel": False, "stop_atual": 9.0,
         "niveis": [{"desde": "2026-10-20", "stop": 9.0, "calc_em": "2026-10-20"}],
         "criada_em": criada, "status": status, "mod": 5.5}
    if oco:
        m["oco"] = oco
    return m


def _config(metas):
    return {"metas": metas}


def _n(v):
    return float(v) if isinstance(v, str) else v


def _ids(itens):
    return [m["id"] for m in itens]


def _executar(op, cfg):
    nome = op["op"]
    agora = datetime.fromisoformat(op["agora_meta"]) if op.get("agora_meta") else None
    if nome == "criar_meta":
        lucro = op.get("lucro_desejado")
        return mt.criar_meta(cfg, op["lote_id"], _n(op["qtd"]), _n(op["preco_alvo"]),
                             None if lucro is None else _n(lucro), agora, op.get("oco_com"))
    if nome == "criar_stop":
        atual = op.get("preco_atual")
        return mt.criar_stop(cfg, op["lote_id"], _n(op["qtd"]), _n(op["preco_stop"]), op.get("movel", False),
                             op.get("oco_com"), None if atual is None else _n(atual), agora, op.get("sugestao"))
    if nome == "cancelar":
        return mt.cancelar_meta(cfg, op["meta_id"])
    if nome == "reservado":
        return mt.reservado(cfg, op["lote_id"], None, tuple(op.get("ignorar", ())))
    if nome == "cadeia":
        return [[mes, l["id"]] for mes, _, l in mt._cadeia(mt._carregar_meses(), op["lote_id"])]
    if nome == "venda_existente":
        achado = mt._venda_existente(mt._carregar_meses(), op["venda_id"])
        return None if achado is None else [achado[0]["id"], achado[1]["id"]]
    if nome == "raizes":
        return mt._raizes(mt._carregar_meses())
    if nome == "lotes_abertos":
        return [[mes, l["id"]] for mes, _, l in mt._lotes_abertos(mt._carregar_meses())]
    if nome == "posicoes_abertas":
        return [[mes, l["id"], restante, livre, _ids(ativas)]
                for mes, l, restante, livre, ativas in mt.posicoes_abertas(cfg)]
    if nome == "lotes_para_meta":
        return [[mes, l["id"], livre] for mes, l, livre in mt.lotes_para_meta(cfg)]
    if nome == "parceira_oco":
        m = mt.parceira_oco(cfg, op["lote_id"], op["gatilho"])
        return None if m is None else m["id"]
    if nome == "fechar_mes":
        r, prox = nc.fechar_mes(nc.carregar(op["mes"]))
        return {"prox": prox, "darf": r["darf"]}
    if nome == "ida_e_volta":
        linhas = nc.montar_linhas(nc.listar_meses(), cfg)
        return nc.reconstruir_metas(linhas)
    raise ValueError(nome)


def _op(op, agora=T0, **extra):
    return {"op": op, "agora": agora, **extra}


def _roteiro(nome, arquivos, operacoes):
    with base.pasta_dados() as pasta, base.congelar():
        base.gravar_arquivos(pasta, arquivos)
        cfg = nc.ler_config()
        resultados = []
        for op in operacoes:
            nc.agora = lambda t=op["agora"]: t
            try:
                retorno = copy.deepcopy(_executar(op, cfg))     # o dicionário devolvido é o da configuração
            except ValueError as e:
                retorno = {"erro": str(e)}
            resultados.append({"retorno": retorno, "arquivos": base.arquivos(pasta)})
    return base.caso(nome, "roteiro", {"arquivos": arquivos, "operacoes": operacoes}, {"resultados": resultados})


def _basico(metas=()):
    return {
        "2026-09.json": _mes("2026-09", [_lote("F1", "PETR4", "2026-09-01", 100, 10.0)], fechado=True),
        "2026-10.json": _mes("2026-10", [
            _lote("L1", "PETR4", "2026-10-01", 100, 10.0),
            _lote("L2", "VALE3", "2026-10-02", 50, 60.0, [_venda("V2", "2026-10-05", 20, 61.0)]),
            _lote("L3", "ITUB4", "2026-10-03", 10, 30.0, [_venda("V3", "2026-10-06", 10, 31.0)]),
        ]),
        "config.json": _config(list(metas)),
    }


def _correntes():
    """Cadeia 2026-08 -> 09 -> 10 -> 11 de uma compra, mais compras soltas, com metas feitas em várias cópias."""
    return {
        "2026-08.json": _mes("2026-08", [_lote("C1", "PETR4", "2026-08-03", 100, 10.0)], fechado=True),
        "2026-09.json": _mes("2026-09", [_lote("C1~2026-09", "PETR4", "2026-08-03", 100, 10.0, origem="C1"),
                                         _lote("D1", "VALE3", "2026-09-02", 40, 60.0)], fechado=True),
        "2026-10.json": _mes("2026-10", [_lote("C1~2026-10", "PETR4", "2026-08-03", 100, 10.0,
                                               origem="C1~2026-09"),
                                         _lote("D1~2026-10", "VALE3", "2026-09-02", 40, 60.0, origem="D1"),
                                         _lote("E1", "ITUB4", "2026-10-02", 30, 30.0)]),
        "2026-11.json": _mes("2026-11", [_lote("C1~2026-11", "PETR4", "2026-08-03", 100, 10.0,
                                               origem="C1~2026-10"),
                                         _lote("E1~2026-11", "ITUB4", "2026-10-02", 30, 30.0, origem="E1",
                                               vendas=[_venda("VE", "2026-11-04", 30, 31.0)])]),
        "config.json": _config([
            _alvo("m1", "C1", 30),
            _alvo("m2", "C1~2026-10", 20),
            _alvo("m3", "C1~2026-11", 10, status="cancelada"),
            _alvo("m4", "C1~2026-09", 5, status="executada"),
            _alvo("m5", "D1", 15, oco="oco-1"),
            _stop("m6", "D1~2026-10", 25, oco="oco-1"),
            _alvo("m7", "E1", 7, oco="oco-2"),
            _stop("m8", "E1~2026-11", 12, oco="oco-2"),
            _stop("m9", "E1", 3, oco="oco-2"),
            _alvo("m10", "inexistente", 99),
        ]),
    }


def casos():
    out = []

    # --- criação de alvo: validações e arredondamentos
    out.append(_roteiro("criar_meta_validacoes", _basico(), [
        _op("criar_meta", lote_id="L1", qtd=0, preco_alvo=20.0),
        _op("criar_meta", lote_id="L1", qtd=-3, preco_alvo=20.0),
        _op("criar_meta", lote_id="L1", qtd=0.5, preco_alvo=20.0),
        _op("criar_meta", lote_id="L1", qtd="inf", preco_alvo=20.0),
        _op("criar_meta", lote_id="L1", qtd="-inf", preco_alvo=20.0),
        _op("criar_meta", lote_id="L1", qtd="nan", preco_alvo=20.0),
        _op("criar_meta", lote_id="L1", qtd=101, preco_alvo=20.0),
        _op("criar_meta", lote_id="L1", qtd=1e308, preco_alvo=20.0),
        _op("criar_meta", lote_id="L1", qtd=1e19, preco_alvo=20.0),
        _op("criar_meta", lote_id="L1", qtd=10, preco_alvo=0),
        _op("criar_meta", lote_id="L1", qtd=10, preco_alvo=-1),
        _op("criar_meta", lote_id="L1", qtd=10, preco_alvo=0.004),
        _op("criar_meta", lote_id="L1", qtd=10, preco_alvo="inf"),
        _op("criar_meta", lote_id="L1", qtd=10, preco_alvo="nan"),
        _op("criar_meta", lote_id="L1", qtd=10, preco_alvo=20.0, lucro_desejado="inf"),
        _op("criar_meta", lote_id="L1", qtd=10, preco_alvo=20.0, lucro_desejado="nan"),
        _op("criar_meta", lote_id="L1", qtd=10, preco_alvo=20.0, lucro_desejado="-inf"),
        _op("criar_meta", lote_id="inexistente", qtd=10, preco_alvo=20.0),
        _op("criar_meta", lote_id="F1", qtd=10, preco_alvo=20.0),          # mês fechado
        _op("criar_meta", lote_id="L3", qtd=1, preco_alvo=20.0),           # compra toda vendida
        _op("criar_meta", lote_id="L2", qtd=31, preco_alvo=20.0),          # restam 30
        _op("criar_meta", lote_id="L1", qtd=10.9, preco_alvo=21.785, lucro_desejado=1000.555, agora_meta=CRIADA),
        _op("criar_meta", lote_id="L1", qtd=80, preco_alvo=21.775, agora_meta="2026-10-20T14:00:00+00:00"),
        _op("criar_meta", lote_id="L1", qtd=11, preco_alvo=20.0),          # 10 + 80 reservados: livre 10
        _op("criar_meta", lote_id="L1", qtd=10, preco_alvo=20.0, lucro_desejado=-50.0),
        _op("reservado", lote_id="L1"),
        _op("lotes_para_meta"),
        _op("lotes_abertos"),
    ]))

    # --- criação de stop
    out.append(_roteiro("criar_stop_validacoes", _basico(), [
        _op("criar_stop", lote_id="L1", qtd=100, preco_stop=0),
        _op("criar_stop", lote_id="L1", qtd=100, preco_stop=-1),
        _op("criar_stop", lote_id="L1", qtd=100, preco_stop="inf"),
        _op("criar_stop", lote_id="L1", qtd=100, preco_stop="nan"),
        _op("criar_stop", lote_id="L1", qtd=100, preco_stop=10.0, preco_atual=10.0),
        _op("criar_stop", lote_id="L1", qtd=100, preco_stop=10.5, preco_atual=10.0),
        _op("criar_stop", lote_id="L1", qtd=10, preco_stop=9.0, preco_atual="nan"),
        _op("criar_stop", lote_id="L1", qtd=101, preco_stop=9.0),
        _op("criar_stop", lote_id="L1", qtd=0, preco_stop=9.0),
        _op("criar_stop", lote_id="F1", qtd=1, preco_stop=9.0),
        _op("criar_stop", lote_id="inexistente", qtd=1, preco_stop=9.0),
        _op("criar_stop", lote_id="L1", qtd=40, preco_stop=9.995, movel=True, preco_atual=10.0,
            sugestao={"modo": "swing", "atr14": 1.0, "atr22": 1.1, "compra": 10.0}, agora_meta=CRIADA),
        _op("criar_stop", lote_id="L1", qtd=30, preco_stop=8.0, sugestao={}, agora_meta="2026-10-21T01:30:00+00:00"),
        _op("criar_stop", lote_id="L1", qtd=21, preco_stop=8.0),           # 80 reservadas: livre 20
        _op("criar_stop", lote_id="L1", qtd=20, preco_stop=7.0),
        _op("posicoes_abertas"),
        _op("reservado", lote_id="L1"),
    ]))

    # --- OCO
    out.append(_roteiro("criar_oco_e_recusas", _basico(), [
        _op("criar_meta", lote_id="L1", qtd=100, preco_alvo=21.78, agora_meta=CRIADA),          # meta-id0001
        _op("criar_stop", lote_id="L1", qtd=50, preco_stop=9.0, oco_com="meta-id0001"),         # quantidade diferente
        _op("criar_meta", lote_id="L1", qtd=100, preco_alvo=25.0, oco_com="meta-id0001"),       # mesmo gatilho
        _op("criar_stop", lote_id="L1", qtd=100, preco_stop=9.0, oco_com="meta-inexistente"),
        _op("parceira_oco", lote_id="L1", gatilho="stop"),
        _op("parceira_oco", lote_id="L1", gatilho="alvo"),
        _op("criar_stop", lote_id="L1", qtd=100, preco_stop=9.0, oco_com="meta-id0001", agora_meta=CRIADA),
        _op("criar_stop", lote_id="L1", qtd=100, preco_stop=8.0, oco_com="meta-id0001"),        # alvo já tem par
        _op("parceira_oco", lote_id="L1", gatilho="stop"),
        _op("reservado", lote_id="L1"),
        _op("reservado", lote_id="L1", ignorar=["meta-id0001"]),
        _op("criar_meta", lote_id="L1", qtd=1, preco_alvo=30.0),
        _op("lotes_para_meta"),
        _op("posicoes_abertas"),
        _op("cancelar", meta_id="meta-id0004"),
        _op("parceira_oco", lote_id="L1", gatilho="stop"),
        _op("criar_stop", lote_id="L1", qtd=100, preco_stop=8.5, oco_com="meta-id0001"),
        _op("cancelar", meta_id="meta-id0001"),
        _op("parceira_oco", lote_id="L1", gatilho="alvo"),
        _op("posicoes_abertas"),
        _op("criar_stop", lote_id="L2", qtd=30, preco_stop=50.0, oco_com="meta-id0001"),    # alvo cancelado
        _op("criar_stop", lote_id="L2", qtd=10, preco_stop=50.0, oco_com="meta-inexistente"),
        _op("criar_meta", lote_id="L2", qtd=30, preco_alvo=70.0, oco_com="meta-id0006"),     # outra compra
        _op("criar_meta", lote_id="L2", qtd=30, preco_alvo=70.0),
        _op("cancelar", meta_id="meta-id0011"),
        _op("criar_stop", lote_id="L2", qtd=30, preco_stop=50.0, oco_com="meta-id0011"),
        _op("posicoes_abertas"),
    ]))

    # --- cancelamento
    auto = _basico([_alvo("meta-x", "L1", 10), _alvo("meta-y", "L1", 10),
                    _alvo("meta-z", "L1", 5, status="executada"),
                    _alvo("meta-w", "L1", 5, ultimo_erro="Sem conexão com a internet.")])
    auto["2026-10.json"]["lotes"][1]["vendas"].append(_venda("auto-meta-x", "2026-10-08", 10, 21.78))
    auto["2026-10.json"]["lotes"][0]["vendas"].append(_venda("auto-meta-y", "2026-10-09", 10, 22.5))
    auto["config.json"]["metas"][1]["execucao"] = {"venda_id": "auto-meta-y", "data": "2026-10-09"}
    out.append(_roteiro("cancelar_meta", auto, [
        _op("cancelar", meta_id="meta-inexistente"),
        _op("cancelar", meta_id="meta-z"),
        _op("cancelar", meta_id="meta-x", ),               # venda automática já existe: reconcilia e avisa
        _op("cancelar", meta_id="meta-x"),                 # agora executada
        _op("cancelar", meta_id="meta-y"),                 # execução já preenchida: só o status
        _op("cancelar", meta_id="meta-w"),
        _op("cancelar", meta_id="meta-w"),
        _op("venda_existente", venda_id="auto-meta-x"),
        _op("venda_existente", venda_id="V3"),
        _op("venda_existente", venda_id="nao-existe"),
    ]))

    # --- cadeia, raízes, reserva e compras abertas
    out.append(_roteiro("cadeia_reserva_e_posicoes", _correntes(), [
        _op("cadeia", lote_id="C1"),
        _op("cadeia", lote_id="C1~2026-10"),
        _op("cadeia", lote_id="E1"),
        _op("cadeia", lote_id="inexistente"),
        _op("raizes"),
        _op("reservado", lote_id="C1"),
        _op("reservado", lote_id="C1~2026-11"),
        _op("reservado", lote_id="C1~2026-11", ignorar=["m1", "m3"]),
        _op("reservado", lote_id="D1~2026-10"),
        _op("reservado", lote_id="D1~2026-10", ignorar=["m5"]),
        _op("reservado", lote_id="E1"),
        _op("reservado", lote_id="E1", ignorar=["m7", "m9"]),
        _op("reservado", lote_id="inexistente"),
        _op("lotes_abertos"),
        _op("posicoes_abertas"),
        _op("lotes_para_meta"),
        _op("parceira_oco", lote_id="C1~2026-10", gatilho="stop"),
        _op("parceira_oco", lote_id="D1", gatilho="stop"),
        _op("parceira_oco", lote_id="E1", gatilho="stop"),
        _op("criar_meta", lote_id="C1~2026-11", qtd=51, preco_alvo=20.0),
        _op("criar_meta", lote_id="C1~2026-11", qtd=50, preco_alvo=20.0),
    ]))

    # --- reserva atravessa a virada de mês
    out.append(_roteiro("reserva_atravessa_virada_de_mes", _basico(), [
        _op("criar_meta", lote_id="L1", qtd=100, preco_alvo=21.78, agora_meta=CRIADA),
        _op("fechar_mes", mes="2026-10"),
        _op("raizes"),
        _op("reservado", lote_id="L1~2026-11"),
        _op("lotes_para_meta"),
        _op("lotes_abertos"),
        _op("posicoes_abertas"),
        _op("criar_meta", lote_id="L1~2026-11", qtd=100, preco_alvo=25.0, agora_meta=CRIADA),
        _op("criar_stop", lote_id="L1~2026-11", qtd=1, preco_stop=8.0),
    ]))

    # --- compras abertas: a última cópia vale antes de filtrar; ciclos e filhos repetidos
    out.append(_roteiro("lotes_abertos_ultima_copia_e_ciclos", {
        "2026-10.json": _mes("2026-10", [
            _lote("A", "PETR4", "2026-10-01", 100, 10.0),
            _lote("B", "VALE3", "2026-10-01", 10, 60.0),
            _lote("Y", "ABEV3", "2026-10-01", 10, 13.0, origem="Z"),
            _lote("Z", "ABEV3", "2026-10-01", 10, 13.0, origem="Y"),
        ]),
        "2026-11.json": _mes("2026-11", [
            _lote("A~2026-11", "PETR4", "2026-10-01", 100, 10.0, origem="A",
                  vendas=[_venda("v1", "2026-11-03", 100, 12.0)]),
            _lote("B~2026-11", "VALE3", "2026-10-01", 10, 60.0, origem="B"),
            _lote("B2~2026-11", "VALE3", "2026-10-01", 10, 60.0, origem="B"),
            _lote("O1", "ITUB4", "2026-11-01", 10, 30.0, origem="sumiu"),
        ]),
        "2026-12.json": _mes("2026-12", [_lote("W", "WEGE3", "2026-12-01", 10, 40.0)], fechado=True),
        "config.json": _config([_alvo("m1", "A", 100), _alvo("m2", "B", 4), _alvo("m3", "Y", 3),
                                _alvo("m4", "Z", 2), _alvo("m5", "O1", 1)]),
    }, [
        _op("lotes_abertos"),
        _op("cadeia", lote_id="A"),
        _op("cadeia", lote_id="B"),
        _op("cadeia", lote_id="Y"),
        _op("cadeia", lote_id="Z"),
        _op("raizes"),
        _op("reservado", lote_id="Y"),
        _op("reservado", lote_id="Z"),
        _op("reservado", lote_id="B2~2026-11"),
        _op("reservado", lote_id="O1"),
        _op("posicoes_abertas"),
        _op("lotes_para_meta"),
    ]))

    # --- ida e volta pela planilha
    out.append(_roteiro("planilha_ida_e_volta", _basico(), [
        _op("criar_meta", lote_id="L1", qtd=40, preco_alvo=21.78, lucro_desejado=1000, agora_meta=CRIADA),
        _op("criar_stop", lote_id="L1", qtd=40, preco_stop=9.0, movel=True, oco_com="meta-id0001",
            sugestao={"modo": "swing", "atr14": 0.5, "atr22": 0.6, "compra": 10.0}, agora_meta=CRIADA),
        _op("criar_stop", lote_id="L1", qtd=20, preco_stop=8.5, agora_meta="2026-10-21T00:00:00-03:00"),
        _op("criar_meta", lote_id="L2", qtd=30, preco_alvo=70.0, agora_meta=CRIADA),
        _op("cancelar", meta_id="meta-id0004"),
        _op("ida_e_volta"),
    ]))
    out.append(_roteiro("planilha_ida_e_volta_de_metas_antigas", _basico([
        _alvo("meta-1", "L1", 10, lucro_desejado=250.5, ultimo_erro="Sem conexão com a internet."),
        _alvo("meta-2", "L1", 10, status="executada", execucao={"venda_id": "auto-meta-2", "data": "2026-10-09",
                                                                  "hora": "10:15", "preco_usado": 22.5}),
        _stop("meta-3", "L1", 10, oco="oco-9"), _alvo("meta-4", "L1", 10, oco="oco-9"),
    ]), [_op("ida_e_volta")]))

    return out
