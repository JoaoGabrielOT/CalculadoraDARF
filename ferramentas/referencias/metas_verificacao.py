"""Referências da verificação e execução automática de metas, da preparação do fechamento do mês e da descrição das
metas para a tela (metas.py:420-460, 463-742, 747-781).

Cada caso é um roteiro: entrada = {"arquivos": {nome: json} gravados antes, "operacoes": [...]}; saída =
{"resultados": [{"retorno": ..., "chamadas": ..., "cfg": ..., "arquivos": {nome: json} depois da operação}]}. A
configuração é lida uma vez no início (como faz o aplicativo) e reaproveitada entre as operações.
Cada operação tem "t" (epoch do relógio do núcleo, padrão T0) e, quando preciso, "agora" (instante ISO passado à
verificação; sem fuso vale Brasília).
Operações:
- verificar {agora?, historicos: {ticker: spec}, diarias?: {ticker: spec}} -> relatório ou null;
- aplicar {agora?, historicos: {ticker: spec ou ausente}, diarias?: {ticker: {barras, hoje}}} -> relatório
  (histórico já baixado: spec {"ok": ...} ou {"erro_msg": texto});
- preparar_fechamento {mes, agora?, historicos, diarias?} -> {bloqueio, executadas, invalidas} (ids);
- fechar_mes {mes}; descricao {} -> {com_todas, sem_todas} (uma descrição por meta da configuração);
- mensagem_erro {erro, texto} -> texto.
spec de histórico: {"ok": {barras: [{dt, alta, baixa?, abre?}], fonte, intervalo, diarias?: {barras, hoje}}} ou
{"erro": tipo, "texto"} com tipo em sem_dados, limite, conexao, timeout, geral (ValueError; o texto pode conter
"Too Many" ou "resolve"). Diárias: {barras: [{data, abre, alta, baixa, fech}], hoje} ou {"erro": ...}.
"chamadas" registra o que a verificação pediu: {"historico": [[ticker, desde]], "diarias": [[ticker, desde]]}.
Relatório: ids por lista, mudou e avisos.
"""
import copy
from datetime import date, datetime

from . import base

nc = base.nc
mt = base.mt
mk = base.mk

T0 = 1761000000.123
CRIADA = "2026-10-20T11:00:00-03:00"


class RateLimitError(Exception):
    """O nome do tipo é o que mensagem_erro reconhece."""


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


def _alvo(i, lote_id="L1", qtd=100, preco=21.78, status="ativa", oco=None, criada=CRIADA, **extra):
    m = {"id": i, "ticker": "PETR4", "tipo": "Ação", "lote_id": lote_id, "qtd": qtd, "preco_alvo": preco,
         "criada_em": criada, "status": status, "mod": 5.5}
    if oco:
        m["oco"] = oco
    m.update(extra)
    return m


def _stop(i, lote_id="L1", qtd=100, stop=9.0, status="ativa", oco=None, movel=False, criada=CRIADA, niveis=None,
          **extra):
    m = {"id": i, "ticker": "PETR4", "tipo": "Ação", "lote_id": lote_id, "qtd": qtd, "gatilho": "stop",
         "stop_inicial": stop, "movel": movel, "stop_atual": stop,
         "niveis": niveis if niveis is not None else [{"desde": criada[:10], "stop": stop, "calc_em": criada[:10]}],
         "criada_em": criada, "status": status, "mod": 5.5}
    if oco:
        m["oco"] = oco
    m.update(extra)
    return m


def _arquivos(metas, lotes=None, fechado=False, extra=None):
    lotes = lotes if lotes is not None else [_lote("L1", "PETR4", "2026-10-01", 100, 10.0)]
    out = {"2026-10.json": _mes("2026-10", lotes, fechado), "config.json": {"metas": list(metas)}}
    out.update(extra or {})
    return out


def _b(dt, alta, baixa=None, abre=None):
    b = {"dt": dt, "alta": alta}
    if baixa is not None:
        b["baixa"] = baixa
    if abre is not None:
        b["abre"] = abre
    return b


def _ok(barras, diarias=None, fonte="Yahoo Finance", intervalo="1m"):
    r = {"barras": barras, "fonte": fonte, "intervalo": intervalo}
    if diarias is not None:
        r["diarias"] = diarias
    return {"ok": r}


def _d(data, alta, baixa, fech, abre=None):
    return {"data": data, "abre": fech if abre is None else abre, "alta": alta, "baixa": baixa, "fech": fech}


def _pregoes(n=30, fim="2026-10-22", alta=11.0, baixa=9.0, fech=10.0):
    ultimo = date.fromisoformat(fim)
    return [_d(date.fromordinal(ultimo.toordinal() - (n - 1 - i)).isoformat(), alta, baixa, fech)
            for i in range(n)]


def _erro(tipo, texto="x"):
    return {"erro": tipo, "texto": texto}


# ---------------------------------------------------------------- conversões do roteiro para o formato do Python

def _dt(texto):
    return mt._dt(texto)


def _barra(b):
    d = datetime.fromisoformat(b["dt"])
    out = {"ts": int(d.timestamp()), "dt": d, "alta": b["alta"]}
    for k in ("baixa", "abre"):
        if k in b:
            out[k] = b[k]
    return out


def _diaria(b):
    return {"data": date.fromisoformat(b["data"]), "abre": b["abre"], "alta": b["alta"], "baixa": b["baixa"],
            "fech": b["fech"]}


def _diarias(d):
    return {"barras": [_diaria(b) for b in d["barras"]], "hoje": date.fromisoformat(d["hoje"])}


def _excecao(tipo, texto):
    if tipo == "sem_dados":
        return mk.SemDados(texto)
    if tipo == "limite":
        return RateLimitError(texto)
    if tipo == "conexao":
        return ConnectionError(texto)
    if tipo == "timeout":
        return TimeoutError(texto)
    if tipo == "geral":
        return ValueError(texto)
    raise ValueError(tipo)


def _resultado(spec):
    if "erro" in spec:
        raise _excecao(spec["erro"], spec["texto"])
    r = dict(spec["ok"])
    r["barras"] = [_barra(b) for b in r["barras"]]
    if r.get("diarias") is not None:
        r["diarias"] = _diarias(r["diarias"])
    return r


def _funcoes(op, chamadas):
    historicos = op.get("historicos", {})
    diarias = op.get("diarias")

    def historico(ticker, desde):
        chamadas["historico"].append([ticker, desde.isoformat()])
        return _resultado(historicos[ticker])

    def barras_diarias(ticker, desde):
        chamadas["diarias"].append([ticker, desde.isoformat()])
        spec = diarias[ticker]
        if "erro" in spec:
            raise _excecao(spec["erro"], spec["texto"])
        return _diarias(spec)

    return historico, (barras_diarias if diarias is not None else None)


def _agora(op):
    return _dt(op["agora"]) if op.get("agora") else None


def _ids(itens):
    return [m["id"] for m in itens]


def _relatorio(rel):
    if rel is None:
        return None
    return {"executadas": _ids(rel["executadas"]), "invalidas": _ids(rel["invalidas"]),
            "reconciliadas": _ids(rel["reconciliadas"]), "aguardando": _ids(rel["aguardando"]),
            "erros": _ids(rel["erros"]), "mudou": rel["mudou"], "avisos": list(rel["avisos"])}


def _executar(op, cfg, chamadas):
    nome = op["op"]
    if nome == "verificar":
        historico, diarias = _funcoes(op, chamadas)
        return _relatorio(mt.verificar(cfg, historico, _agora(op), diarias))
    if nome == "aplicar":
        historicos = {}
        for ticker, spec in op["historicos"].items():
            if "erro_msg" in spec:
                historicos[ticker] = ("erro", spec["erro_msg"])
            else:
                historicos[ticker] = ("ok", _resultado(spec))
        diarias = op.get("diarias")
        if diarias is not None:
            diarias = {t: _diarias(d) for t, d in diarias.items()}
        return _relatorio(mt.aplicar(cfg, historicos, _agora(op), diarias))
    if nome == "preparar_fechamento":
        historico, diarias = _funcoes(op, chamadas)
        res = mt.preparar_fechamento(cfg, op["mes"], historico, _agora(op), diarias)
        return {"bloqueio": res["bloqueio"], "executadas": _ids(res["executadas"]),
                "invalidas": _ids(res["invalidas"])}
    if nome == "fechar_mes":
        r, prox = nc.fechar_mes(nc.carregar(op["mes"]))
        return {"prox": prox, "darf": r["darf"]}
    if nome == "descricao":
        return {"com_todas": [mt.descricao(m, cfg["metas"]) for m in cfg["metas"]],
                "sem_todas": [mt.descricao(m) for m in cfg["metas"]]}
    if nome == "mensagem_erro":
        return mt.mensagem_erro(_excecao(op["erro"], op["texto"]))
    raise ValueError(nome)


def _op(op, t=T0, **extra):
    return {"op": op, "t": t, **extra}


def _roteiro(nome, arquivos, operacoes):
    with base.pasta_dados() as pasta, base.congelar():
        base.gravar_arquivos(pasta, arquivos)
        cfg = nc.ler_config()
        resultados = []
        for op in operacoes:
            nc.agora = lambda t=op["t"]: t
            chamadas = {"historico": [], "diarias": []}
            retorno = copy.deepcopy(_executar(op, cfg, chamadas))
            resultados.append({"retorno": retorno, "chamadas": chamadas, "cfg": copy.deepcopy(cfg),
                               "arquivos": base.arquivos(pasta)})
    return base.caso(nome, "roteiro", {"arquivos": arquivos, "operacoes": operacoes}, {"resultados": resultados})


def _verificar(historicos, agora="2026-10-25T18:00:00", diarias=None, t=T0):
    extra = {"diarias": diarias} if diarias is not None else {}
    return _op("verificar", t=t, agora=agora, historicos=historicos, **extra)


def casos():
    out = []
    petr = "PETR4"

    # --- execução de alvo: preço, data, hora e fonte; segunda verificação não encontra metas ativas
    out.append(_roteiro("executa_alvo", _arquivos([_alvo("meta-a")]), [
        _verificar({petr: _ok([_b("2026-10-21T10:30:00-03:00", 21.9)], fonte="Yahoo Finance", intervalo="1m")}),
        _verificar({petr: _ok([_b("2026-10-21T10:30:00-03:00", 21.9)])}),
    ]))
    out.append(_roteiro("alvo_na_tolerancia_e_fuso_utc", _arquivos([_alvo("meta-a", preco=21.78)]), [
        _verificar({petr: _ok([_b("2026-10-21T13:30:00+00:00", 21.78 - 5e-10), _b("2026-10-21T14:30:00+00:00", 30)],
                              fonte="Fonte X", intervalo="5m")}),
    ]))
    out.append(_roteiro("sem_atingir_e_limpa_erro", _arquivos([_alvo("meta-a", ultimo_erro="Sem conexão com a internet.")]), [
        _verificar({petr: _ok([_b("2026-10-21T10:00:00-03:00", 20.0)])}),
        _verificar({petr: _ok([_b("2026-10-21T10:00:00-03:00", 20.0)])}),
        _verificar({petr: _ok([_b("2026-10-19T10:00:00-03:00", 99.0)])}),
    ]))
    out.append(_roteiro("app_fechado_dias_depois", _arquivos([_alvo("meta-a")]), [
        _verificar({petr: _ok([_b("2026-10-22T14:20:00-03:00", 21.0), _b("2026-10-23T10:05:00-03:00", 21.8),
                               _b("2026-10-24T10:05:00-03:00", 25)])}, agora="2026-10-29T09:00:00"),
    ]))

    # --- execução de stop, gap e abertura acima do stop
    out.append(_roteiro("executa_stop_e_gap", _arquivos([
        _stop("meta-s1", stop=9.0)]), [
        _verificar({petr: _ok([_b("2026-10-21T10:30:00-03:00", 10, 8.95, 9.5)])}),
    ]))
    out.append(_roteiro("stop_com_gap_de_baixa", _arquivos([_stop("meta-s")]), [
        _verificar({petr: _ok([_b("2026-10-21T10:00:00-03:00", 9.0, 8.4, 8.5)])}),
    ]))
    out.append(_roteiro("stop_gap_abaixo_de_um_centavo", _arquivos([_stop("meta-s", stop=0.05)]), [
        _verificar({petr: _ok([_b("2026-10-21T10:00:00-03:00", 0.05, 0.001, 0.004)])}),
    ]))
    out.append(_roteiro("stop_abertura_acima_do_stop", _arquivos([_stop("meta-s")]), [
        _verificar({petr: _ok([_b("2026-10-21T10:00:00-03:00", 9.5, 8.9, 9.2)])}),
    ]))
    out.append(_roteiro("maxima_acima_do_alvo_nao_dispara_stop", _arquivos([_stop("meta-s")]), [
        _verificar({petr: _ok([_b("2026-10-21T10:00:00-03:00", 50, 9.5, 10)])}),
        _verificar({petr: _ok([_b("2026-10-21T10:00:00-03:00", 50)])}),      # barra sem mínima
    ]))

    # --- inválidas e aguardando
    out.append(_roteiro("quantidade_insuficiente", _arquivos([_alvo("meta-a")], lotes=[
        _lote("L1", "PETR4", "2026-10-01", 100, 10.0, [_venda("manual", "2026-10-19", 60, 12.0)])]), [
        _verificar({petr: _ok([_b("2026-10-21T10:00:00-03:00", 30)])}),
    ]))
    out.append(_roteiro("compra_inexistente", _arquivos([_alvo("meta-a", lote_id="nada")]), [
        _verificar({petr: _ok([_b("2026-10-21T10:00:00-03:00", 30)])}),
    ]))
    out.append(_roteiro("data_anterior_a_compra", _arquivos([_alvo("meta-a")], lotes=[
        _lote("L1", "PETR4", "2026-10-25", 100, 10.0)]), [
        _verificar({petr: _ok([_b("2026-10-21T10:00:00-03:00", 30)])}),
    ]))
    out.append(_roteiro("mes_fechado_invalida", _arquivos([_alvo("meta-a"), _stop("meta-s", stop=9.0)],
                                                          fechado=True), [
        _verificar({petr: _ok([_b("2026-10-21T10:00:00-03:00", 30, 5)])}, agora="2026-11-04T09:00:00"),
    ]))
    out.append(_roteiro("compra_nao_estava_aberta_no_mes", _arquivos([
        _alvo("meta-a", criada="2026-09-01T10:00:00-03:00")]), [
        _verificar({petr: _ok([_b("2026-09-15T10:00:00-03:00", 30)])}),
    ]))
    out.append(_roteiro("mes_seguinte_aguarda_e_executa_depois", _arquivos([_alvo("meta-a"), _stop("meta-s", stop=9.0)]), [
        _verificar({petr: _ok([_b("2026-11-03T10:00:00-03:00", 30, 15)])}, agora="2026-11-04T09:00:00"),
        _verificar({petr: _ok([_b("2026-11-03T10:00:00-03:00", 30, 15)])}, agora="2026-11-04T09:00:00"),
        _op("fechar_mes", mes="2026-10"),
        _verificar({petr: _ok([_b("2026-11-03T10:00:00-03:00", 30, 15)])}, agora="2026-11-04T09:00:00"),
    ]))

    # --- reconciliação
    out.append(_roteiro("reinicio_reconcilia_sem_duplicar", _arquivos([_alvo("meta-a")], lotes=[
        _lote("L1", "PETR4", "2026-10-01", 100, 10.0, [_venda("auto-meta-a", "2026-10-21", 100, 21.78)])]), [
        _verificar({petr: _ok([_b("2026-10-22T10:00:00-03:00", 40)])}),
    ]))
    out.append(_roteiro("reconcilia_com_execucao_preenchida", _arquivos([
        _alvo("meta-a", ultimo_erro="x", execucao={"venda_id": "auto-meta-a", "data": "2026-10-21", "hora": "10:00",
                                                   "preco_usado": 21.78, "origem": "teste", "barra_ts": 7,
                                                   "motivo": "m", "verificado_em": "2026-10-21T10:00:00-03:00"})],
        lotes=[_lote("L1", "PETR4", "2026-10-01", 100, 10.0, [_venda("auto-meta-a", "2026-10-21", 100, 21.78)])]), [
        _verificar({petr: _ok([_b("2026-10-22T10:00:00-03:00", 40)])}),
    ]))
    out.append(_roteiro("reconcilia_e_cancela_o_par_oco", _arquivos([
        _alvo("meta-a", oco="oco-1"), _stop("meta-s", oco="oco-1")], lotes=[
        _lote("L1", "PETR4", "2026-10-01", 100, 10.0, [_venda("auto-meta-a", "2026-10-21", 100, 21.78)])]), [
        _verificar({petr: _ok([_b("2026-10-22T10:00:00-03:00", 40, 1)])}),
    ]))
    out.append(_roteiro("reconcilia_par_executado_sem_venda", _arquivos([
        _alvo("meta-a", oco="oco-1"), _stop("meta-s", oco="oco-1", status="executada")], lotes=[
        _lote("L1", "PETR4", "2026-10-01", 100, 10.0, [_venda("auto-meta-a", "2026-10-21", 100, 21.78)])]), [
        _verificar({petr: _ok([_b("2026-10-22T10:00:00-03:00", 40, 1)])}),
    ]))
    duas = [_venda("auto-meta-a", "2026-10-22", 100, 21.78), _venda("auto-meta-s", "2026-10-21", 100, 9.0)]
    out.append(_roteiro("duas_vendas_remove_a_perdedora", _arquivos([
        _alvo("meta-a", oco="oco-1", qtd=100), _stop("meta-s", oco="oco-1", qtd=100)], lotes=[
        _lote("L1", "PETR4", "2026-10-01", 200, 10.0, duas)]), [
        _verificar({petr: _ok([_b("2026-10-22T10:00:00-03:00", 1.0)])}),
    ]))
    out.append(_roteiro("duas_vendas_em_mes_fechado_avisa", _arquivos([
        _alvo("meta-a", oco="oco-1", qtd=100), _stop("meta-s", oco="oco-1", qtd=100)], lotes=[
        _lote("L1", "PETR4", "2026-10-01", 200, 10.0, duas)], fechado=True), [
        _verificar({petr: _ok([_b("2026-10-22T10:00:00-03:00", 1.0)])}),
    ]))
    out.append(_roteiro("duas_vendas_com_par_ja_executado", _arquivos([
        _alvo("meta-a", oco="oco-1", qtd=100), _stop("meta-s", oco="oco-1", qtd=100, status="executada",
                                                      execucao={"venda_id": "auto-meta-s", "data": "2026-10-21",
                                                                "hora": "10:00", "preco_usado": 9.0,
                                                                "origem": "t", "barra_ts": 0, "motivo": "t"})],
        lotes=[_lote("L1", "PETR4", "2026-10-01", 200, 10.0, duas)]), [
        _verificar({petr: _ok([_b("2026-10-22T10:00:00-03:00", 1.0)])}),
    ]))

    # --- OCO
    par = [_alvo("meta-a", oco="oco-1"), _stop("meta-s", oco="oco-1")]
    out.append(_roteiro("oco_alvo_executa_e_cancela_o_stop", _arquivos(par), [
        _verificar({petr: _ok([_b("2026-10-21T10:00:00-03:00", 30, 15, 16)])}),
    ]))
    out.append(_roteiro("oco_stop_executa_e_cancela_o_alvo", _arquivos(par), [
        _verificar({petr: _ok([_b("2026-10-21T10:00:00-03:00", 12, 8.5, 9.5)])}),
    ]))
    out.append(_roteiro("oco_mesma_barra_vence_o_stop", _arquivos(par), [
        _verificar({petr: _ok([_b("2026-10-21T10:00:00-03:00", 30, 8.0, 15)])}),
    ]))
    out.append(_roteiro("oco_barras_diferentes_vence_a_mais_cedo", _arquivos(par), [
        _verificar({petr: _ok([_b("2026-10-21T10:00:00-03:00", 30, 15, 16),
                               _b("2026-10-22T10:00:00-03:00", 12, 8.0, 9.5)])}),
    ]))
    out.append(_roteiro("oco_stop_antes_do_alvo", _arquivos(par), [
        _verificar({petr: _ok([_b("2026-10-21T10:00:00-03:00", 12, 8.0, 9.5),
                               _b("2026-10-22T10:00:00-03:00", 30, 15, 16)])}),
    ]))
    out.append(_roteiro("oco_so_o_alvo_dispara", _arquivos(par), [
        _verificar({petr: _ok([_b("2026-10-21T10:00:00-03:00", 30, 15, 16)])}),
        _verificar({petr: _ok([_b("2026-10-21T10:00:00-03:00", 30, 15, 16)])}),
    ]))
    out.append(_roteiro("oco_nenhum_dispara", _arquivos(par), [
        _verificar({petr: _ok([_b("2026-10-21T10:00:00-03:00", 15, 12, 13)])}),
    ]))
    out.append(_roteiro("oco_vencedora_em_mes_fechado_invalida_e_o_par_continua", _arquivos(
        par, fechado=True), [
        _verificar({petr: _ok([_b("2026-10-21T10:00:00-03:00", 30, 15, 16)])}),
    ]))
    out.append(_roteiro("oco_par_ja_executado_cancela_a_ativa", _arquivos([
        _alvo("meta-a", oco="oco-1"),
        _stop("meta-s", oco="oco-1", status="executada",
              execucao={"venda_id": "auto-meta-s", "data": "2026-10-21", "hora": "10:00", "preco_usado": 9.0,
                        "origem": "t", "barra_ts": 0, "gatilho": "stop", "motivo": "t"})],
        lotes=[_lote("L1", "PETR4", "2026-10-01", 100, 10.0, [_venda("auto-meta-s", "2026-10-21", 100, 9.0)])]), [
        _verificar({petr: _ok([_b("2026-10-22T10:00:00-03:00", 30, 15, 16)])}),
    ]))

    # --- órfãs do OCO (aparelho de 12 colunas perdeu o campo "oco")
    def exec_(i, tipo, data, oco=None, qtd=100, **extra):
        f = _alvo if tipo == "alvo" else _stop
        return f(i, qtd=qtd, status="executada", oco=oco,
                 execucao={"venda_id": "auto-" + i, "data": data, "hora": "10:00", "preco_usado": 9.0,
                           "origem": "t", "barra_ts": 0, "motivo": "t"}, **extra)

    lote200 = [_lote("L1", "PETR4", "2026-10-01", 200, 10.0)]
    out.append(_roteiro("orfa_alvo_executado_sem_oco_cancela_o_stop", _arquivos([
        exec_("meta-a", "alvo", "2026-10-21"), _stop("meta-s", oco="oco-1")], lotes=lote200), [
        _verificar({petr: _ok([_b("2026-10-22T10:00:00-03:00", 10, 8.5, 9.5)])}),
    ]))
    out.append(_roteiro("orfa_stop_executado_sem_oco_cancela_o_alvo", _arquivos([
        _alvo("meta-a", oco="oco-1"), exec_("meta-s", "stop", "2026-10-21")], lotes=lote200), [
        _verificar({petr: _ok([_b("2026-10-22T10:00:00-03:00", 30.0)])}),
    ]))
    out.append(_roteiro("orfa_de_outro_oco_ou_par_existente_nao_cancela", _arquivos([
        exec_("meta-a", "alvo", "2026-10-21", oco="oco-1"), _stop("meta-s", oco="oco-2"),
        _alvo("meta-b", oco="oco-2", preco=99.0)], lotes=lote200), [
        _verificar({petr: _ok([_b("2026-10-22T10:00:00-03:00", 10, 8.5, 9.5)])}),
    ]))
    out.append(_roteiro("orfa_quantidade_diferente_ou_criada_depois_nao_cancela", _arquivos([
        exec_("meta-a", "alvo", "2026-10-21", qtd=50), _stop("meta-s", oco="oco-1", qtd=100),
        exec_("meta-c", "alvo", "2026-10-10", oco="oco-3"), _stop("meta-d", oco="oco-4", qtd=100)],
        lotes=lote200), [
        _verificar({petr: _ok([_b("2026-10-22T10:00:00-03:00", 10, 20, 20)])}),
    ]))
    out.append(_roteiro("orfa_em_cadeia_de_copias", {
        "2026-10.json": _mes("2026-10", [_lote("L1", "PETR4", "2026-10-01", 200, 10.0)], fechado=True),
        "2026-11.json": _mes("2026-11", [_lote("L1~2026-11", "PETR4", "2026-10-01", 200, 10.0, origem="L1")]),
        "config.json": {"metas": [exec_("meta-a", "alvo", "2026-11-03"),
                                  _stop("meta-s", oco="oco-1", lote_id="L1~2026-11")]},
    }, [_verificar({petr: _ok([_b("2026-11-04T10:00:00-03:00", 10, 20, 20)])}, agora="2026-11-05T09:00:00")]))

    # --- stop móvel
    def movel(**kw):
        return _stop("meta-s", movel=True, stop=kw.pop("stop", 4.0), niveis=[], **kw)

    horario = [_b("2026-10-21T10:00:00-03:00", 10, 5.5, 6.0), _b("2026-10-22T10:00:00-03:00", 10, 4.9, 6.0)]
    out.append(_roteiro("movel_sobe_o_stop_e_depois_dispara", _arquivos([movel()]), [
        _verificar({petr: _ok(horario, fonte="Yahoo", intervalo="1h")},
                   diarias={petr: {"barras": _pregoes(fim="2026-10-22"), "hoje": "2026-10-23"}},
                   agora="2026-10-23T09:00:00"),
    ]))
    out.append(_roteiro("movel_sobe_e_nao_dispara_idempotente", _arquivos([movel(stop=4.0)]), [
        _verificar({petr: _ok([_b("2026-10-21T10:00:00-03:00", 10, 9.9, 10)])},
                   diarias={petr: {"barras": _pregoes(fim="2026-10-22"), "hoje": "2026-10-23"}},
                   agora="2026-10-23T09:00:00"),
        _verificar({petr: _ok([_b("2026-10-21T10:00:00-03:00", 10, 9.9, 10)])},
                   diarias={petr: {"barras": _pregoes(fim="2026-10-22"), "hoje": "2026-10-23"}},
                   agora="2026-10-23T09:00:00"),
    ]))
    out.append(_roteiro("movel_falha_de_dados_mantem_o_stop", _arquivos([movel()]), [
        _verificar({petr: _ok([_b("2026-10-21T10:00:00-03:00", 10, 9.0)], fonte="Yahoo", intervalo="1h")},
                   diarias={petr: _erro("sem_dados", "sem dados")}, agora="2026-10-25T18:00:00"),
    ]))
    out.append(_roteiro("movel_diarias_dentro_do_historico", _arquivos([movel()]), [
        _verificar({petr: _ok([_b("2026-10-21T10:00:00-03:00", 10, 9.9, 10)],
                              diarias={"barras": _pregoes(fim="2026-10-22"), "hoje": "2026-10-23"})},
                   agora="2026-10-23T09:00:00"),
    ]))
    out.append(_roteiro("movel_aplicar_com_diarias_por_ticker", _arquivos([movel()]), [
        _op("aplicar", agora="2026-10-23T09:00:00",
            historicos={petr: _ok([_b("2026-10-21T10:00:00-03:00", 10, 9.9, 10)])},
            diarias={petr: {"barras": _pregoes(fim="2026-10-22"), "hoje": "2026-10-23"}}),
    ]))
    barras_hoje = _pregoes(n=29, fim="2026-10-21") + [_d("2026-10-22", 20.0, 19.0, 20.0, abre=19.0)]
    out.append(_roteiro("movel_hoje_do_cache_nao_fica_atras_do_relogio", _arquivos([movel()]), [
        _op("aplicar", agora="2026-10-25T18:00:00",
            historicos={petr: _ok([_b("2026-10-23T10:00:00-03:00", 30.0, 25.0, 26.0)],
                                  diarias={"barras": barras_hoje, "hoje": "2026-10-22"})}),
    ]))
    out.append(_roteiro("movel_so_busca_diarias_do_ticker_movel", _arquivos([
        movel(), _stop("meta-fixo", stop=4.0, movel=False), _alvo("meta-v", preco=99.0)],
        lotes=[_lote("L1", "PETR4", "2026-10-01", 300, 10.0),
               _lote("L2", "VALE3", "2026-10-01", 10, 60.0)]), [
        _verificar({petr: _ok([_b("2026-10-21T10:00:00-03:00", 10, 9.9, 10)])},
                   diarias={petr: {"barras": _pregoes(fim="2026-10-22"), "hoje": "2026-10-23"}},
                   agora="2026-10-23T09:00:00"),
    ]))

    # --- consulta: desde mais antigo por ticker, erros e histórico ausente
    outra = _alvo("meta-v", preco=99.0, criada="2026-10-15T09:00:00-03:00")
    outra["ticker"] = "VALE3"
    outra["lote_id"] = "L2"
    out.append(_roteiro("consulta_usa_a_meta_mais_antiga_de_cada_ticker", _arquivos([
        _alvo("meta-a", preco=99.0, criada="2026-10-20T11:00:00-03:00"),
        _alvo("meta-b", preco=98.0, criada="2026-10-18T08:00:00+00:00"),
        _stop("meta-c", stop=1.0, movel=True, criada="2026-10-19T09:00:00-03:00"),
        _stop("meta-d", stop=1.0, movel=True, criada="2026-10-17T09:00:00"),
        outra, _alvo("meta-x", status="cancelada", criada="2026-01-01T09:00:00-03:00")],
        lotes=[_lote("L1", "PETR4", "2026-10-01", 1000, 10.0), _lote("L2", "VALE3", "2026-10-01", 10, 60.0)]), [
        _verificar({petr: _ok([_b("2026-10-21T10:00:00-03:00", 10, 9.9, 10)]),
                    "VALE3": _ok([_b("2026-10-21T10:00:00-03:00", 10, 9.9, 10)])},
                   diarias={petr: {"barras": _pregoes(fim="2026-10-22"), "hoje": "2026-10-23"}}),
    ]))
    erros = [("sem_dados", "Sem dados para PETR4 no Yahoo Finance."),
             ("limite", "429"), ("conexao", "x"), ("timeout", "tempo esgotado"),
             ("geral", "falha qualquer"), ("geral", "HTTP 429 Too Many Requests"),
             ("geral", "Could not RESOLVE host"), ("geral", "é" * 200)]
    for i, (tipo, texto) in enumerate(erros):
        out.append(_roteiro(f"erro_{i}_{tipo}", _arquivos([_alvo("meta-a")]), [
            _verificar({petr: _erro(tipo, texto)}),
            _verificar({petr: _erro(tipo, texto)}),
            _verificar({petr: _ok([_b("2026-10-21T10:00:00-03:00", 20.0)])}),
        ]))
    out.append(_roteiro("erro_em_um_ticker_nao_afeta_o_outro", _arquivos([
        _alvo("meta-a"), _alvo("meta-b", preco=20.0), outra],
        lotes=[_lote("L1", "PETR4", "2026-10-01", 300, 10.0), _lote("L2", "VALE3", "2026-10-01", 10, 60.0)]), [
        _verificar({petr: _erro("conexao"), "VALE3": _ok([_b("2026-10-21T10:00:00-03:00", 100.0)])}),
    ]))
    out.append(_roteiro("aplicar_historico_ausente_e_erro_pronto", _arquivos([_alvo("meta-a"), outra],
        lotes=[_lote("L1", "PETR4", "2026-10-01", 300, 10.0), _lote("L2", "VALE3", "2026-10-01", 10, 60.0)]), [
        _op("aplicar", historicos={petr: {"erro_msg": "Falhou"}}),
        _op("aplicar", historicos={petr: {"erro_msg": "Falhou"}}),
        _op("aplicar", historicos={}),
        _op("aplicar", historicos={petr: _ok([_b("2026-10-21T10:00:00-03:00", 30)])}),
        _op("aplicar", historicos={petr: _ok([_b("2026-10-21T10:00:00-03:00", 30)])}),
    ]))
    out.append(_roteiro("verificar_sem_metas_ativas_devolve_nulo", _arquivos([
        _alvo("meta-a", status="cancelada"), _alvo("meta-b", status="executada")]), [
        _verificar({petr: _ok([_b("2026-10-21T10:00:00-03:00", 30)])}),
    ]))
    out.append(_roteiro("alvo_e_stop_na_mesma_barra_sem_oco_executam_os_dois", _arquivos([
        _alvo("meta-a", qtd=50), _stop("meta-s", qtd=50)]), [
        _verificar({petr: _ok([_b("2026-10-21T10:00:00-03:00", 30, 8.0, 15)])}),
    ]))

    # --- preparação do fechamento do mês
    out.append(_roteiro("fechamento_com_falha_bloqueia", _arquivos([_alvo("meta-a")]), [
        _op("preparar_fechamento", mes="2026-10", agora="2026-10-31T18:00:00",
            historicos={petr: _erro("sem_dados", "Sem dados para PETR4 no Yahoo Finance.")}),
        _op("preparar_fechamento", mes="2026-10", agora="2026-10-31T18:00:00",
            historicos={petr: _erro("geral", "falha")}),
    ]))
    out.append(_roteiro("fechamento_registra_meta_atingida_antes", _arquivos([_alvo("meta-a")]), [
        _op("preparar_fechamento", mes="2026-10", agora="2026-10-31T18:00:00",
            historicos={petr: _ok([_b("2026-10-21T10:00:00-03:00", 30)])}),
    ]))
    out.append(_roteiro("fechamento_sem_metas_no_mes_nao_consulta", _arquivos([
        _alvo("meta-a", lote_id="nada"), _alvo("meta-b", status="cancelada")]), [
        _op("preparar_fechamento", mes="2026-10", historicos={}),
        _op("preparar_fechamento", mes="2026-09", historicos={}),
    ]))
    out.append(_roteiro("fechamento_so_considera_as_metas_do_mes", {
        "2026-09.json": _mes("2026-09", [_lote("V1", "VALE3", "2026-09-01", 10, 60.0)]),
        "2026-10.json": _mes("2026-10", [_lote("L1", "PETR4", "2026-10-01", 100, 10.0)]),
        "config.json": {"metas": [_alvo("meta-a"),
                                  dict(_alvo("meta-v", lote_id="V1", qtd=10, preco=70.0), ticker="VALE3")]},
    }, [
        _op("preparar_fechamento", mes="2026-10", agora="2026-10-31T18:00:00",
            historicos={petr: _ok([_b("2026-10-21T10:00:00-03:00", 30)]),
                        "VALE3": _erro("conexao")}),
    ]))
    out.append(_roteiro("fechamento_executa_e_invalida_metas_do_mes", _arquivos([
        _alvo("meta-a", qtd=60), _stop("meta-s", qtd=60), _alvo("meta-b", qtd=60, preco=15.0)]), [
        _op("preparar_fechamento", mes="2026-10", agora="2026-10-31T18:00:00",
            historicos={petr: _ok([_b("2026-10-21T10:00:00-03:00", 30, 15)])}),
    ]))

    # --- mensagem_erro
    mensagens = [("sem_dados", "Sem dados."), ("limite", "x"), ("conexao", "x"), ("timeout", "x"),
                 ("geral", "Too Many Requests"), ("geral", "nao resolve o nome"),
                 ("geral", "RESOLVE"), ("geral", "texto " * 40), ("geral", "á" * 119 + "bcd"),
                 ("geral", "")]
    for i, (tipo, texto) in enumerate(mensagens):
        out.append(_roteiro(f"mensagem_erro_{i}_{tipo}", _arquivos([]), [
            _op("mensagem_erro", erro=tipo, texto=texto)]))

    # --- descrição
    metas = [
        _alvo("m1", lucro_desejado=1000.0),
        _alvo("m2", preco=21.785, criada="2026-10-20T14:00:00+00:00"),
        _alvo("m3", status="executada", execucao={"venda_id": "auto-m3", "data": "2026-10-21", "hora": "10:30",
                                                  "preco_usado": 21.78, "motivo": "máxima 21,90 ≥ alvo 21,78"}),
        _alvo("m4", status="executada", execucao={"venda_id": "auto-m4", "data": "2026-10-21", "hora": "",
                                                  "preco_usado": 22, "origem": "reconciliada"}),
        _alvo("m5", status="executada"),
        _alvo("m6", status="cancelada", cancelada_detalhe="Cancelada automaticamente (OCO): stop executado em 21/10"),
        _alvo("m7", status="cancelada"),
        _alvo("m8", status="inválida", ultimo_erro="A compra desta meta não existe mais."),
        _alvo("m9", ultimo_erro="Sem conexão com a internet."),
        _alvo("m10", status="xyz"),
        _stop("m11", stop=9.0),
        _stop("m12", stop=9.0, movel=True, stop_inicial=8.0, lucro_desejado=50.0),
        _stop("m13", stop=9.0, movel=True, stop_inicial=9.003),
        _stop("m14", stop=9.0, movel=True, stop_inicial=9.005),
        _alvo("m15", oco="oco-1"), _stop("m16", oco="oco-1", movel=True),
        _alvo("m17", oco="oco-solto"),
        _stop("m18", oco="oco-3", status="executada", stop=8.5,
              execucao={"venda_id": "auto-m18", "data": "2026-10-22", "hora": "11:05", "preco_usado": 8.5,
                        "motivo": "mínima 8,40 ≤ stop 8,50 (abertura em gap 8,40)"}),
        _alvo("m19", oco="oco-3", status="cancelada", preco=30.5,
              cancelada_detalhe="Cancelada automaticamente (OCO): stop executado em 22/10"),
        _alvo("m20", oco="oco-4"), _alvo("m21", oco="oco-4", preco=0.125),
    ]
    sem_status = _alvo("m22")
    del sem_status["status"]
    metas.append(sem_status)
    out.append(_roteiro("descricao_das_metas", _arquivos(metas, lotes=[_lote("L1", "PETR4", "2026-10-01", 100, 10.0)]),
                        [_op("descricao")]))
    return out
