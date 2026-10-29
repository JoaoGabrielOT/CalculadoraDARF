"""Meta de lucro / preço-alvo: cálculo do preço de venda e registro automático da venda quando o preço-alvo é atingido.

Compartilhado entre a versão Windows (calculadora_darf.py) e a versão Android (android/main.py).

Fórmula (estimativa conservadora, venda tratada isoladamente, sem isenção de R$ 20 mil nem prejuízos anteriores):
    G = L / (1 - alíquota)   se L > 0 (senão G = L)     lucro bruto necessário para sobrar L depois do imposto
    P = (G + Q*PM*(1+t) + C) / (Q*(1-t))                 preço de venda; t = taxa da B3 do regime; C = corretagem
O imposto sobre o lucro após taxas é 15% (swing) ou 20% (day trade); o IRRF é só uma antecipação desse imposto e
por isso não muda o preço-alvo (só reduz o que sobra para pagar na DARF).

As metas ficam em config.json (cfg["metas"]) e entram na sincronização como a aba "Metas". A venda gerada vai para
o mês da barra que atingiu o alvo, com id "auto-<id da meta>"; o status "executada" é gravado logo depois e, se o app
fechar entre as duas gravações, a próxima verificação só reconcilia o status (nunca duplica a venda).
"""
import math
import threading
from datetime import datetime, timedelta, timezone

import nucleo as nc

FUSO = timezone(timedelta(hours=-3))     # horário de Brasília (sem horário de verão desde 2019)
AVISO_REGISTRO = "Registro automático no app; não envia ordem à corretora"
STATUS_ROTULO = {"ativa": "Ativa", "executada": "Executada", "cancelada": "Cancelada", "inválida": "Inválida"}
EM_ANDAMENTO = object()                   # sinal de "já há uma verificação rodando" para as telas
_VERIFICANDO = threading.Lock()          # uma verificação por vez no processo


def agora_br():
    return datetime.now(FUSO)


def iso(dt):
    return dt.astimezone(FUSO).isoformat(timespec="seconds")


def _dt(texto):
    dt = datetime.fromisoformat(texto)
    return dt if dt.tzinfo else dt.replace(tzinfo=FUSO)


def teto_centavo(v):
    """Arredonda para cima no centavo (o preço sugerido nunca fica abaixo do necessário)."""
    return math.ceil(round(v * 100, 6)) / 100


# ---------------------------------------------------------------- calculadora

def _regime(day_trade):
    return (nc.TAXA_B3_DAYTRADE, nc.ALIQ_DAYTRADE) if day_trade else (nc.TAXA_B3_SWING, nc.ALIQ_SWING)


def projetar(lote, qtd, preco, day_trade=False):
    """Resultado de vender qtd do lote por preco, com as mesmas contas de nc.calcular_venda.

    Retorna as chaves de calcular_venda mais imposto, irrf (retenção estimada), darf_estimado,
    custos (taxas B3 + corretagem) e lucro_apos_imposto."""
    venda = {"qtd": qtd, "preco": preco, "data": lote["data_compra"] if day_trade else ""}
    c = nc.calcular_venda(lote, venda)
    imposto = max(c["liquido"], 0) * (nc.ALIQ_DAYTRADE if day_trade else nc.ALIQ_SWING)
    if day_trade:
        irrf = max(c["liquido"], 0) * nc.IRRF_DAYTRADE
    else:
        irrf = c["venda"] * nc.IRRF_SWING
    if irrf <= 1:    # a Receita só retém acima de R$ 1,00
        irrf = 0.0
    c.update(imposto=imposto, irrf=irrf, darf_estimado=max(imposto - irrf, 0.0),
             custos=c["taxas"] + c["corretagem"], lucro_apos_imposto=c["liquido"] - imposto)
    return c


def calcular_preco_alvo(lote, qtd, lucro_liquido, day_trade=False):
    """Preço de venda por ação para sobrar lucro_liquido (R$) depois de taxas, corretagem e imposto.

    day_trade: use True quando a venda será no mesmo dia da compra. Retorna a projeção em preço sugerido
    (arredondado para cima no centavo), mais preco_exato, preco_medio, bruto_necessario e lucro_desejado."""
    if not math.isfinite(qtd) or qtd <= 0:
        raise ValueError("Quantidade inválida.")
    if not math.isfinite(lucro_liquido):
        raise ValueError("Lucro desejado inválido.")
    t, aliq = _regime(day_trade)
    bruto = lucro_liquido / (1 - aliq) if lucro_liquido > 0 else lucro_liquido
    corretagem = nc.CORRETAGEM_POR_ORDEM * (1 + qtd / lote["qtd"])
    try:
        exato = (bruto + qtd * lote["preco"] * (1 + t) + corretagem) / (qtd * (1 - t))
    except OverflowError:
        raise ValueError("Valores grandes demais para calcular.")
    if not math.isfinite(exato):
        raise ValueError("Valores grandes demais para calcular.")
    if exato <= 0:
        raise ValueError("Com esse resultado o preço de venda seria zero ou negativo.")
    preco = max(teto_centavo(exato), 0.01)
    r = projetar(lote, qtd, preco, day_trade)
    r.update(preco=preco, preco_exato=exato, preco_medio=lote["preco"], bruto_necessario=bruto,
             lucro_desejado=lucro_liquido, qtd=qtd, day_trade=day_trade)
    return r


# ---------------------------------------------------------------- localização da compra

def _carregar_meses():
    return {m: nc.carregar(m) for m in nc.listar_meses()}


def _cadeia(meses, lote_id):
    """Compra e as cópias levadas para os meses seguintes (origem): lista de (mês, dados, lote) em ordem."""
    por_id, filho = {}, {}
    for mes, d in meses.items():
        for l in d["lotes"]:
            por_id[l["id"]] = (mes, d, l)
            if l.get("origem"):
                filho[l["origem"]] = l["id"]
    cadeia, atual = [], lote_id
    while atual in por_id and all(c[2]["id"] != atual for c in cadeia):
        cadeia.append(por_id[atual])
        atual = filho.get(atual)
    return cadeia


def _venda_existente(meses, venda_id):
    for d in meses.values():
        for l in d["lotes"]:
            for v in l["vendas"]:
                if v["id"] == venda_id:
                    return l, v
    return None


def _raizes(meses):
    """{id da compra: id da compra original}, seguindo "origem" das cópias levadas na virada de mês."""
    origem = {l["id"]: l["origem"] for d in meses.values() for l in d["lotes"] if l.get("origem")}

    def raiz(i):
        visto = set()
        while i in origem and i not in visto:
            visto.add(i)
            i = origem[i]
        return i
    return {i: raiz(i) for i in origem}


def reservado(cfg, lote_id, meses=None):
    """Quantidade da compra já comprometida com metas ativas, somando as metas feitas sobre a compra original
    ou sobre qualquer cópia dela nos meses seguintes."""
    raizes = _raizes(meses if meses is not None else _carregar_meses())
    alvo = raizes.get(lote_id, lote_id)
    return sum(m["qtd"] for m in cfg.get("metas", [])
               if m.get("status") == "ativa" and raizes.get(m["lote_id"], m["lote_id"]) == alvo)


def lotes_para_meta(cfg):
    """Compras de meses abertos com quantidade livre (sem contar as metas ativas): lista de (mês, lote, livre)."""
    saida = []
    with nc.TRAVA:
        meses = _carregar_meses()
        for mes, d in meses.items():
            if d["fechado"]:
                continue
            for l in d["lotes"]:
                livre = nc.restante(l) - reservado(cfg, l["id"], meses)
                if livre > 0:
                    saida.append((mes, l, livre))
    return saida


# ---------------------------------------------------------------- criação e cancelamento

def criar_meta(cfg, lote_id, qtd, preco_alvo, lucro_desejado=None, agora=None):
    """Valida e registra uma meta ativa (grava a configuração). Levanta ValueError com a mensagem para o usuário."""
    try:
        qtd = int(qtd)
    except (TypeError, ValueError, OverflowError):
        raise ValueError("Quantidade inválida.")
    if qtd <= 0:
        raise ValueError("Quantidade inválida.")
    if lucro_desejado is not None:
        try:
            lucro_desejado = round(float(lucro_desejado), 2)
        except (TypeError, ValueError, OverflowError):
            raise ValueError("Lucro desejado inválido.")
        if not math.isfinite(lucro_desejado):
            raise ValueError("Lucro desejado inválido.")
    try:
        preco_alvo = round(float(preco_alvo), 2)
    except (TypeError, ValueError, OverflowError):
        raise ValueError("Preço-alvo inválido.")
    if not math.isfinite(preco_alvo):
        raise ValueError("Preço-alvo inválido.")
    if preco_alvo <= 0:
        raise ValueError("O preço-alvo deve ser maior que zero.")
    with nc.TRAVA:
        meses = _carregar_meses()
        achado = next(((m, d, l) for m, d in meses.items() for l in d["lotes"] if l["id"] == lote_id), None)
        if achado is None:
            raise ValueError("Essa compra não existe mais.")
        mes, d, lote = achado
        if d["fechado"]:
            raise ValueError("O mês dessa compra está fechado.")
        livre = nc.restante(lote) - reservado(cfg, lote_id, meses)
        if qtd > nc.restante(lote):
            raise ValueError(f"Quantidade maior que a disponível ({nc.restante(lote)}).")
        if qtd > livre:
            raise ValueError(f"Quantidade maior que a livre ({livre}): o resto já está em outras metas ativas.")
        meta = {"id": f"meta-{nc.novo_id()}", "ticker": lote["ticker"], "tipo": lote["tipo"], "lote_id": lote_id,
                "qtd": qtd, "preco_alvo": preco_alvo, "criada_em": iso(agora or agora_br()), "status": "ativa"}
        if lucro_desejado is not None:
            meta["lucro_desejado"] = lucro_desejado
        cfg.setdefault("metas", []).append(meta)
        nc.gravar_config(cfg)
    return meta


def cancelar_meta(cfg, meta_id):
    """Cancela uma meta ativa. Se a venda automática já foi registrada, só reconcilia o status e avisa."""
    with nc.TRAVA:
        meta = next((m for m in cfg.get("metas", []) if m["id"] == meta_id), None)
        if meta is None or meta.get("status") != "ativa":
            raise ValueError("Só metas ativas podem ser canceladas.")
        if _venda_existente(_carregar_meses(), "auto-" + meta_id):
            _reconciliar(cfg, meta)
            nc.gravar_config(cfg)
            raise ValueError("Essa meta já foi executada.")
        meta["status"] = "cancelada"
        meta.pop("ultimo_erro", None)
        nc.gravar_config(cfg)


# ---------------------------------------------------------------- verificação

def achar_barra(barras, preco_alvo, criada_em):
    """Primeira barra (em ordem de tempo) que começa depois da criação da meta e cuja máxima chegou ao alvo."""
    for b in sorted(barras, key=lambda b: b["dt"]):
        if b["dt"] >= criada_em and b["alta"] + 1e-9 >= preco_alvo:
            return b
    return None


def mensagem_erro(e):
    nome = type(e).__name__
    if "SemDados" in nome:
        return str(e)
    if "RateLimit" in nome or "Too Many" in str(e):
        return "Limite de consultas do Yahoo atingido. Tente em alguns minutos."
    if "Connection" in nome or "Timeout" in nome or "resolve" in str(e).lower():
        return "Sem conexão com a internet."
    return f"Erro ao consultar o histórico: {str(e)[:120]}"


def metas_ativas(cfg):
    return [m for m in cfg.get("metas", []) if m.get("status") == "ativa"]


def buscar_historicos(metas, historico):
    """Baixa o histórico de cada ticker desde a meta mais antiga. Rede: executar fora da thread da interface.
    historico(ticker, desde) -> {"barras": [...], "fonte": str, "intervalo": str}.
    Retorna {ticker: ("ok", resultado) ou ("erro", mensagem)}."""
    desde = {}
    for m in metas:
        c = _dt(m["criada_em"])
        desde[m["ticker"]] = min(c, desde.get(m["ticker"], c))
    saida = {}
    for ticker, d in desde.items():
        try:
            saida[ticker] = ("ok", historico(ticker, d))
        except Exception as e:
            saida[ticker] = ("erro", mensagem_erro(e))
    return saida


def _reconciliar(cfg, meta):
    """A venda automática já existe: só acerta o status da meta."""
    meta["status"] = "executada"
    meta.pop("ultimo_erro", None)
    if not meta.get("execucao"):
        achado = _venda_existente(_carregar_meses(), "auto-" + meta["id"])
        v = achado[1]
        meta["execucao"] = {"venda_id": v["id"], "data": v["data"], "hora": "", "preco_usado": v["preco"],
                            "origem": "reconciliada", "barra_ts": 0, "motivo": "Venda automática já registrada",
                            "verificado_em": iso(agora_br())}


def _marcar(meta, status, erro=None):
    """Altera status/erro da meta; retorna True se algo mudou."""
    antes = (meta.get("status"), meta.get("ultimo_erro"))
    meta["status"] = status
    if erro:
        meta["ultimo_erro"] = erro
    else:
        meta.pop("ultimo_erro", None)
    return antes != (meta.get("status"), meta.get("ultimo_erro"))


def _executar(cfg, meta, barra, fonte, agora):
    """Registra a venda da meta na barra que atingiu o alvo. Retorna "executada", "inválida" ou "aguardando"."""
    vid = "auto-" + meta["id"]
    meses = _carregar_meses()
    data_iso = barra["dt"].date().isoformat()
    mes = data_iso[:7]
    cadeia = _cadeia(meses, meta["lote_id"])
    alvo = next((c for c in cadeia if c[0] == mes), None)
    if not cadeia:
        _marcar(meta, "inválida", "A compra desta meta não existe mais.")
        return "inválida"
    if alvo is None:
        if cadeia[-1][0] < mes:
            _marcar(meta, "ativa", f"Alvo atingido em {nc.fmt_data(data_iso)}. Feche o mês anterior para "
                                    f"abrir {nc.fmt_mes(mes)} e registrar a venda.")
            return "aguardando"
        _marcar(meta, "inválida", f"Alvo atingido em {nc.fmt_data(data_iso)}, mas essa compra não estava "
                                   "aberta nesse mês.")
        return "inválida"
    _, d, lote = alvo
    if d["fechado"]:
        _marcar(meta, "inválida", f"Alvo atingido em {nc.fmt_data(data_iso)}, mas o mês {nc.fmt_mes(mes)} já foi "
                                   "fechado. Registre a venda manualmente se ela ocorreu.")
        return "inválida"
    if data_iso < lote["data_compra"]:
        _marcar(meta, "inválida", "A data do alvo é anterior à data da compra.")
        return "inválida"
    livre = nc.restante(lote)
    if livre < meta["qtd"]:
        _marcar(meta, "inválida", f"Quantidade insuficiente: restam {livre} de {meta['ticker']} nessa compra e a "
                                   f"meta vende {meta['qtd']}. Nenhuma venda foi registrada.")
        return "inválida"
    lote["vendas"].append({"id": vid, "data": data_iso, "qtd": meta["qtd"], "preco": meta["preco_alvo"]})
    nc.salvar(d)
    meta["status"] = "executada"
    meta.pop("ultimo_erro", None)
    meta["execucao"] = {
        "venda_id": vid, "data": data_iso, "hora": barra["dt"].strftime("%H:%M"), "preco_usado": meta["preco_alvo"],
        "origem": fonte, "barra_ts": barra.get("ts", 0),
        "motivo": f"máxima {nc.preco_texto(barra['alta'])} ≥ alvo {nc.preco_texto(meta['preco_alvo'])}",
        "verificado_em": iso(agora)}
    return "executada"


def aplicar(cfg, historicos, agora=None):
    """Aplica os históricos já baixados às metas ativas (só disco, rápido). Retorna o relatório
    {"executadas", "invalidas", "reconciliadas", "aguardando", "erros": listas de metas, "mudou": bool}."""
    agora = agora or agora_br()
    rel = {"executadas": [], "invalidas": [], "reconciliadas": [], "aguardando": [], "erros": [], "mudou": False}
    with nc.TRAVA:
        for meta in metas_ativas(cfg):
            # confirma de novo, com a trava, que a meta continua ativa e que a venda ainda não existe
            if meta.get("status") != "ativa":
                continue
            if _venda_existente(_carregar_meses(), "auto-" + meta["id"]):
                _reconciliar(cfg, meta)
                nc.gravar_config(cfg)
                rel["reconciliadas"].append(meta)
                rel["mudou"] = True
                continue
            res = historicos.get(meta["ticker"])
            if res is None:
                continue
            if res[0] == "erro":
                if _marcar(meta, "ativa", res[1]):
                    nc.gravar_config(cfg)
                    rel["mudou"] = True
                rel["erros"].append(meta)
                continue
            hist = res[1]
            barra = achar_barra(hist["barras"], meta["preco_alvo"], _dt(meta["criada_em"]))
            if barra is None:
                if _marcar(meta, "ativa"):
                    nc.gravar_config(cfg)
                    rel["mudou"] = True
                continue
            fonte = f"{hist.get('fonte', 'Yahoo Finance')} · intervalo {hist.get('intervalo', '?')}"
            antes = (meta.get("status"), meta.get("ultimo_erro"))
            resultado = _executar(cfg, meta, barra, fonte, agora)
            if resultado != "aguardando" or antes != (meta.get("status"), meta.get("ultimo_erro")):
                nc.gravar_config(cfg)
                rel["mudou"] = True
            rel[{"executada": "executadas", "inválida": "invalidas", "aguardando": "aguardando"}[resultado]].append(meta)
    return rel


def verificar(cfg, historico, agora=None):
    """Busca o histórico e executa as metas atingidas. Retorna o relatório de aplicar() ou None quando outra
    verificação já está em andamento ou não há metas ativas. Pode ser chamada de uma thread."""
    if not _VERIFICANDO.acquire(blocking=False):
        return None
    try:
        ativas = metas_ativas(cfg)
        if not ativas:
            return None
        return aplicar(cfg, buscar_historicos(ativas, historico), agora)
    finally:
        _VERIFICANDO.release()


def preparar_fechamento(cfg, mes, historico, agora=None):
    """Roda a verificação antes de fechar o mês, para que um alvo já atingido nele seja registrado antes de a
    meta virar inválida. Retorna {"bloqueio": mensagem ou None, "executadas": [...], "invalidas": [...]}.
    Bloqueia (não fecha) quando a consulta falhou para alguma meta ativa daquele mês ou quando outra
    verificação está em andamento. Rede: executar fora da thread da interface."""
    with nc.TRAVA:
        meses = _carregar_meses()
        do_mes = [m for m in metas_ativas(cfg) if any(c[0] == mes for c in _cadeia(meses, m["lote_id"]))]
    saida = {"bloqueio": None, "executadas": [], "invalidas": []}
    if not do_mes:
        return saida
    rel = verificar(cfg, historico, agora)
    if rel is None:
        saida["bloqueio"] = "Há uma verificação de metas em andamento. Tente fechar o mês em instantes."
        return saida
    ids = {m["id"] for m in do_mes}
    saida["executadas"] = [m for m in rel["executadas"] if m["id"] in ids]
    saida["invalidas"] = [m for m in rel["invalidas"] if m["id"] in ids]
    falhas = [m for m in rel["erros"] if m["id"] in ids and m.get("status") == "ativa"]
    if falhas:
        det = "\n".join(f"{m['ticker']}: {m.get('ultimo_erro', 'erro ao consultar o histórico')}" for m in falhas)
        saida["bloqueio"] = ("Não foi possível confirmar se há metas atingidas neste mês, e fechar agora poderia "
                             f"invalidá-las. Tente de novo mais tarde.\n\n{det}")
    return saida


# ---------------------------------------------------------------- texto para as telas

def descricao(meta):
    """Textos para a lista de metas: título, status, detalhe e a cor (accent, danger, aviso ou muted)."""
    titulo = f"{meta['ticker']} · {meta['qtd']} un. a {nc.brl(meta['preco_alvo'])}"
    st = meta.get("status", "ativa")
    cor = {"ativa": "aviso", "executada": "accent", "cancelada": "muted", "inválida": "danger"}.get(st, "muted")
    partes = [f"Criada em {_dt(meta['criada_em']):%d/%m/%Y %H:%M}"]
    if meta.get("lucro_desejado") is not None:
        partes.append(f"lucro desejado {nc.brl(meta['lucro_desejado'])}")
    ex = meta.get("execucao")
    if st == "executada" and ex:
        quando = nc.fmt_data(ex["data"]) + (f" {ex['hora']}" if ex.get("hora") else "")
        partes.append(f"executada em {quando} a {nc.brl(ex['preco_usado'])} ({ex.get('motivo', '')})")
    if meta.get("ultimo_erro"):
        partes.append(meta["ultimo_erro"])
    return {"titulo": titulo, "status": STATUS_ROTULO.get(st, st), "detalhe": " · ".join(partes), "cor": cor,
            "erro": bool(meta.get("ultimo_erro"))}
