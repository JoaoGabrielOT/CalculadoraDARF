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

import mercado as mk
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


def piso_centavo(v):
    """Arredonda para baixo no centavo (o stop sugerido nunca fica acima do calculado)."""
    return math.floor(round(v * 100, 6)) / 100


def gatilho(meta):
    """"alvo" (venda quando a máxima chega ao preço-alvo) ou "stop" (venda quando a mínima chega ao stop).
    Metas gravadas antes do stop não têm o campo e são alvos."""
    return meta.get("gatilho") or "alvo"


def preco_gatilho(meta):
    return meta["stop_atual"] if gatilho(meta) == "stop" else meta["preco_alvo"]


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


def reservado(cfg, lote_id, meses=None, ignorar=()):
    """Quantidade da compra já comprometida com metas ativas, somando as metas feitas sobre a compra original
    ou sobre qualquer cópia dela nos meses seguintes. Um par OCO (alvo + stop) conta uma vez só (a maior
    quantidade). ignorar: ids de metas que não entram na conta."""
    raizes = _raizes(meses if meses is not None else _carregar_meses())
    alvo = raizes.get(lote_id, lote_id)
    total, grupos = 0, {}
    for m in cfg.get("metas", []):
        if m.get("status") != "ativa" or m["id"] in ignorar or raizes.get(m["lote_id"], m["lote_id"]) != alvo:
            continue
        if m.get("oco"):
            grupos[m["oco"]] = max(grupos.get(m["oco"], 0), m["qtd"])
        else:
            total += m["qtd"]
    return total + sum(grupos.values())


def _lotes_abertos(meses):
    """Compras de meses abertos com saldo: lista de (mês, dados, lote), uma por cadeia de cópias (vale a do
    mês mais recente; se essa já foi toda vendida, a compra não está aberta)."""
    raizes = _raizes(meses)
    por_raiz = {}
    for mes in sorted(meses):
        d = meses[mes]
        if d["fechado"]:
            continue
        for l in d["lotes"]:
            por_raiz[raizes.get(l["id"], l["id"])] = (mes, d, l)
    return sorted((x for x in por_raiz.values() if nc.restante(x[2]) > 0),
                  key=lambda x: (x[0], x[2]["ticker"], x[2]["id"]))


def posicoes_abertas(cfg):
    """Todas as compras abertas com saldo: lista de (mês, compra, restante, livre, metas ativas da compra).
    Diferente de lotes_para_meta, não esconde as que estão com a quantidade toda reservada (livre 0)."""
    saida = []
    with nc.TRAVA:
        meses = _carregar_meses()
        raizes = _raizes(meses)
        for mes, _, l in _lotes_abertos(meses):
            raiz = raizes.get(l["id"], l["id"])
            ativas = [m for m in metas_ativas(cfg) if raizes.get(m["lote_id"], m["lote_id"]) == raiz]
            saida.append((mes, l, nc.restante(l), nc.restante(l) - reservado(cfg, l["id"], meses), ativas))
    return saida


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

def _validar_preco(valor, rotulo, artigo="O"):
    try:
        valor = round(float(valor), 2)
    except (TypeError, ValueError, OverflowError):
        raise ValueError(f"{rotulo} inválido.")
    if not math.isfinite(valor):
        raise ValueError(f"{rotulo} inválido.")
    if valor <= 0:
        raise ValueError(f"{artigo} {rotulo.lower()} deve ser maior que zero.")
    return valor


def _validar_lote(cfg, lote_id, qtd, meses, ignorar=()):
    """Valida a quantidade e a compra (aberta, com saldo livre) de uma nova meta. Retorna (qtd, mês, dados, compra).
    Chamar com nc.TRAVA. ignorar: metas que não contam como reservadas (a parceira de um OCO)."""
    try:
        qtd = int(qtd)
    except (TypeError, ValueError, OverflowError):
        raise ValueError("Quantidade inválida.")
    if qtd <= 0:
        raise ValueError("Quantidade inválida.")
    achado = next(((m, d, l) for m, d in meses.items() for l in d["lotes"] if l["id"] == lote_id), None)
    if achado is None:
        raise ValueError("Essa compra não existe mais.")
    mes, d, lote = achado
    if d["fechado"]:
        raise ValueError("O mês dessa compra está fechado.")
    livre = nc.restante(lote) - reservado(cfg, lote_id, meses, ignorar)
    if qtd > nc.restante(lote):
        raise ValueError(f"Quantidade maior que a disponível ({nc.restante(lote)}).")
    if qtd > livre:
        raise ValueError(f"Quantidade maior que a livre ({livre}): o resto já está em outras metas ativas.")
    return qtd, mes, d, lote


def _candidatas_oco(cfg, lote_id, gatilho_novo, meses):
    raizes = _raizes(meses)
    raiz = raizes.get(lote_id, lote_id)
    ativas = metas_ativas(cfg)
    saida = []
    for m in ativas:
        if gatilho(m) == gatilho_novo or raizes.get(m["lote_id"], m["lote_id"]) != raiz:
            continue
        if m.get("oco") and any(o is not m and o.get("oco") == m["oco"] for o in ativas):
            continue    # já tem par ativo
        saida.append(m)
    return sorted(saida, key=lambda m: (m["criada_em"], m["id"]))


def parceira_oco(cfg, lote_id, gatilho_novo, meses=None):
    """Meta ativa que pode virar o par OCO de uma nova meta com esse gatilho: da mesma compra (ou de uma cópia
    dela), com o gatilho oposto e sem outro par ativo. Retorna a mais antiga ou None."""
    candidatas = _candidatas_oco(cfg, lote_id, gatilho_novo, meses if meses is not None else _carregar_meses())
    return candidatas[0] if candidatas else None


def _parear(cfg, meses, meta, oco_com):
    """Liga a nova meta à parceira como OCO (as duas recebem o mesmo "oco"). Levanta ValueError se não puder."""
    par = next((m for m in cfg.get("metas", []) if m["id"] == oco_com), None)
    if par is None or par.get("status") != "ativa":
        raise ValueError("A meta escolhida para o OCO não está mais ativa.")
    if all(c["id"] != par["id"] for c in _candidatas_oco(cfg, meta["lote_id"], gatilho(meta), meses)):
        raise ValueError("Essa meta não pode formar um OCO com a nova: precisa ser da mesma compra, de gatilho "
                         "oposto e sem outro par.")
    if par["qtd"] != meta["qtd"]:
        raise ValueError(f"O OCO exige a mesma quantidade nas duas metas ({par['qtd']} un.).")
    oco = f"oco-{nc.novo_id()}"
    meta["oco"] = par["oco"] = oco


def criar_meta(cfg, lote_id, qtd, preco_alvo, lucro_desejado=None, agora=None, oco_com=None):
    """Valida e registra uma meta ativa (grava a configuração). Levanta ValueError com a mensagem para o usuário.
    oco_com: id de uma meta de stop ativa para ligar as duas (OCO: quando uma executa, a outra é cancelada)."""
    if lucro_desejado is not None:
        try:
            lucro_desejado = round(float(lucro_desejado), 2)
        except (TypeError, ValueError, OverflowError):
            raise ValueError("Lucro desejado inválido.")
        if not math.isfinite(lucro_desejado):
            raise ValueError("Lucro desejado inválido.")
    preco_alvo = _validar_preco(preco_alvo, "Preço-alvo")
    with nc.TRAVA:
        meses = _carregar_meses()
        qtd, mes, d, lote = _validar_lote(cfg, lote_id, qtd, meses, (oco_com,) if oco_com else ())
        meta = {"id": f"meta-{nc.novo_id()}", "ticker": lote["ticker"], "tipo": lote["tipo"], "lote_id": lote_id,
                "qtd": qtd, "preco_alvo": preco_alvo, "criada_em": iso(agora or agora_br()), "status": "ativa"}
        if lucro_desejado is not None:
            meta["lucro_desejado"] = lucro_desejado
        if oco_com:
            _parear(cfg, meses, meta, oco_com)
        cfg.setdefault("metas", []).append(meta)
        nc.gravar_config(cfg)
    return meta


def criar_stop(cfg, lote_id, qtd, preco_stop, movel=False, oco_com=None, preco_atual=None, agora=None,
               sugestao=None):
    """Registra um stop ativo: a venda automática acontece quando a mínima de uma barra chega ao stop. Com
    movel=True o stop só sobe (Chandelier Exit calculado pelo app depois da criação). preco_atual (opcional)
    recusa um stop que já estaria disparado. Levanta ValueError com a mensagem para o usuário."""
    preco_stop = _validar_preco(preco_stop, "Stop")
    if preco_atual is not None and preco_stop >= preco_atual:
        raise ValueError(f"O stop deve ficar abaixo do preço atual ({nc.brl(preco_atual)}).")
    with nc.TRAVA:
        meses = _carregar_meses()
        qtd, mes, d, lote = _validar_lote(cfg, lote_id, qtd, meses, (oco_com,) if oco_com else ())
        criada = iso(agora or agora_br())
        meta = {"id": f"meta-{nc.novo_id()}", "ticker": lote["ticker"], "tipo": lote["tipo"], "lote_id": lote_id,
                "qtd": qtd, "gatilho": "stop", "stop_inicial": preco_stop, "movel": bool(movel),
                "stop_atual": preco_stop,
                "niveis": [{"desde": criada[:10], "stop": preco_stop, "calc_em": criada[:10]}],
                "criada_em": criada, "status": "ativa"}
        if sugestao:
            meta["sugestao"] = dict(sugestao)
        if oco_com:
            _parear(cfg, meses, meta, oco_com)
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


def nivel_vigente(niveis, data_iso):
    """Stop em vigor numa data (AAAA-MM-DD): o maior nível cujo "desde" não é posterior a ela."""
    validos = [n["stop"] for n in niveis if n["desde"] <= data_iso]
    return max(validos) if validos else None


def achar_barra_stop(barras, niveis, criada_em):
    """Primeira barra que começa depois da criação do stop e cuja mínima chegou ao stop vigente na data dela.
    Retorna (barra, stop vigente) ou None. Barras sem mínima válida não contam."""
    for b in sorted(barras, key=lambda b: b["dt"]):
        if b["dt"] < criada_em or b.get("baixa") is None:
            continue
        nivel = nivel_vigente(niveis, b["dt"].date().isoformat())
        if nivel is not None and b["baixa"] <= nivel + 1e-9:
            return b, nivel
    return None


def preco_execucao_stop(barra, nivel):
    """Preço em que o app registra a venda do stop: o próprio stop, ou a abertura quando a barra abriu abaixo
    dele (gap de baixa, pior preço plausível). Retorna (preço, houve_gap)."""
    abre = barra.get("abre")
    if abre is not None and abre < nivel - 1e-9:
        return max(piso_centavo(abre), 0.01), True
    return nivel, False


def atualizar_stop_movel(meta, barras, hoje):
    """Sobe o stop móvel (Chandelier Exit de 22 pregões, 3 ATR) com os pregões fechados desde a criação da meta.
    barras: diárias do mercado ({"data", "alta", "baixa", "fech"}); hoje: date (só conta data < hoje). Cada nível
    novo vale a partir do dia seguinte ao pregão que o calculou; o stop nunca desce e, sem dados suficientes,
    fica como está. Retorna True se acrescentou algum nível. Repetir a chamada não muda nada. O Chandelier de
    todos os pregões sai de uma passada só (mercado.serie_chandelier)."""
    if gatilho(meta) != "stop" or not meta.get("movel"):
        return False
    criada = _dt(meta["criada_em"]).date()
    fechadas = sorted((b for b in barras if b["data"] < hoje), key=lambda b: b["data"])
    niveis = meta.setdefault("niveis", [])
    ultimo = max([n["stop"] for n in niveis] + [meta["stop_atual"]])
    mudou = False
    for b, c in zip(fechadas, mk.serie_chandelier(fechadas)):
        if b["data"] < criada or c is None:
            continue
        novo = piso_centavo(c)
        if novo > ultimo + 1e-9:
            niveis.append({"desde": (b["data"] + timedelta(days=1)).isoformat(), "stop": novo,
                           "calc_em": b["data"].isoformat()})
            ultimo = novo
            mudou = True
    if mudou:
        meta["stop_atual"] = ultimo
    return mudou


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


def buscar_historicos(metas, historico, diarias=None):
    """Baixa o histórico de cada ticker desde a meta mais antiga. Rede: executar fora da thread da interface.
    historico(ticker, desde) -> {"barras": [...], "fonte": str, "intervalo": str}.
    diarias(ticker, desde) -> barras diárias (mercado.barras_diarias): buscadas também para os tickers com stop
    móvel, e guardadas em resultado["diarias"] (None se a consulta falhar; o stop então fica como está).
    Retorna {ticker: ("ok", resultado) ou ("erro", mensagem)}."""
    desde, desde_movel = {}, {}
    for m in metas:
        c = _dt(m["criada_em"])
        desde[m["ticker"]] = min(c, desde.get(m["ticker"], c))
        if gatilho(m) == "stop" and m.get("movel"):
            desde_movel[m["ticker"]] = min(c, desde_movel.get(m["ticker"], c))
    saida = {}
    for ticker, d in desde.items():
        try:
            res = dict(historico(ticker, d))
        except Exception as e:
            saida[ticker] = ("erro", mensagem_erro(e))
            continue
        if diarias is not None and ticker in desde_movel:
            try:
                res["diarias"] = diarias(ticker, desde_movel[ticker].date())
            except Exception:
                res["diarias"] = None
        saida[ticker] = ("ok", res)
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


def _executar(cfg, meta, barra, fonte, agora, preco_exec=None, motivo=None):
    """Registra a venda da meta na barra que disparou o gatilho, ao preço preco_exec (o preço-alvo, o stop ou a
    abertura em gap). Retorna "executada", "inválida" ou "aguardando"."""
    rot = "Stop" if gatilho(meta) == "stop" else "Alvo"
    if preco_exec is None:
        preco_exec = meta["preco_alvo"]
    if motivo is None:
        motivo = f"máxima {nc.preco_texto(barra['alta'])} ≥ alvo {nc.preco_texto(meta['preco_alvo'])}"
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
            _marcar(meta, "ativa", f"{rot} atingido em {nc.fmt_data(data_iso)}. Feche o mês anterior para "
                                    f"abrir {nc.fmt_mes(mes)} e registrar a venda.")
            return "aguardando"
        _marcar(meta, "inválida", f"{rot} atingido em {nc.fmt_data(data_iso)}, mas essa compra não estava "
                                   "aberta nesse mês.")
        return "inválida"
    _, d, lote = alvo
    if d["fechado"]:
        _marcar(meta, "inválida", f"{rot} atingido em {nc.fmt_data(data_iso)}, mas o mês {nc.fmt_mes(mes)} já foi "
                                   "fechado. Registre a venda manualmente se ela ocorreu.")
        return "inválida"
    if data_iso < lote["data_compra"]:
        _marcar(meta, "inválida", f"A data do {rot.lower()} é anterior à data da compra.")
        return "inválida"
    livre = nc.restante(lote)
    if livre < meta["qtd"]:
        _marcar(meta, "inválida", f"Quantidade insuficiente: restam {livre} de {meta['ticker']} nessa compra e a "
                                   f"meta vende {meta['qtd']}. Nenhuma venda foi registrada.")
        return "inválida"
    lote["vendas"].append({"id": vid, "data": data_iso, "qtd": meta["qtd"], "preco": preco_exec})
    nc.salvar(d)
    meta["status"] = "executada"
    meta.pop("ultimo_erro", None)
    meta["execucao"] = {
        "venda_id": vid, "data": data_iso, "hora": barra["dt"].strftime("%H:%M"), "preco_usado": preco_exec,
        "origem": fonte, "barra_ts": barra.get("ts", 0), "gatilho": gatilho(meta), "motivo": motivo,
        "verificado_em": iso(agora)}
    return "executada"


def _par_oco(cfg, meta):
    """Outra meta do mesmo grupo OCO (ou None)."""
    if not meta.get("oco"):
        return None
    return next((m for m in cfg.get("metas", []) if m is not meta and m.get("oco") == meta["oco"]), None)


def _cancelar_por_oco(par, vencedora):
    """A parceira de um OCO foi executada: a outra meta é cancelada, sem nenhuma venda."""
    ex = vencedora.get("execucao") or {}
    quando = nc.fmt_data(ex["data"])[:5] if ex.get("data") else "?"
    rot = "stop" if gatilho(vencedora) == "stop" else "alvo"
    par["status"] = "cancelada"
    par.pop("ultimo_erro", None)
    par["cancelada_por"] = vencedora["id"]
    par["cancelada_detalhe"] = f"Cancelada automaticamente (OCO): {rot} executado em {quando}"


def _cancelar_orfas_oco(cfg):
    """Aparelho antigo (12 colunas) reescreve a meta executada sem o "oco" e a parceira ativa, que ainda o tem,
    não acharia o par e executaria também (venda duplicada). Conservador: uma meta ativa com oco é cancelada
    como OCO quando uma meta executada de gatilho oposto, da mesma compra e da mesma quantidade, saiu depois da
    criação dela e o grupo oco dela não tem nenhuma outra meta (é o par que perdeu o campo). Retorna True se
    cancelou alguma."""
    metas = cfg.get("metas", [])
    executadas = [m for m in metas if m.get("status") == "executada" and m.get("execucao")]
    if not executadas or not any(m.get("oco") for m in metas_ativas(cfg)):
        return False
    raizes = _raizes(_carregar_meses())
    mudou = False
    for ex in executadas:
        raiz = raizes.get(ex["lote_id"], ex["lote_id"])
        for m in metas_ativas(cfg):
            if (not m.get("oco") or gatilho(m) == gatilho(ex) or m["qtd"] != ex["qtd"]
                    or raizes.get(m["lote_id"], m["lote_id"]) != raiz
                    or (ex.get("oco") and ex["oco"] != m["oco"])
                    or m["criada_em"][:10] > (ex["execucao"].get("data") or "")):
                continue
            if any(o is not m and o is not ex and o.get("oco") == m["oco"] for o in metas):
                continue    # o par de verdade existe: é outro OCO
            _cancelar_por_oco(m, ex)
            mudou = True
    return mudou


def _resolver_vendas_duplicadas(cfg, rel):
    """As duas metas de um OCO têm venda registrada: fica a mais cedo e a outra é desfeita (nucleo.resolver_oco),
    exceto em mês fechado, onde só avisa."""
    meses = _carregar_meses()
    avisos = []
    for mes in nc.resolver_oco(meses, cfg.get("metas", []), avisos):
        nc.salvar(meses[mes])
    rel["avisos"].extend(avisos)


def _candidata(meta, hist, diarias, agora):
    """Barra que disparou a meta: ((barra, preço de execução, motivo) ou None, se o stop móvel subiu)."""
    subiu = False
    if gatilho(meta) == "stop":
        if meta.get("movel"):
            dia = hist.get("diarias") or (diarias or {}).get(meta["ticker"])
            if dia and dia.get("barras"):
                # o "hoje" do cache pode estar atrasado (consulta de ontem): nunca antes da data do relógio
                subiu = atualizar_stop_movel(meta, dia["barras"], max(dia.get("hoje") or agora.date(), agora.date()))
        achado = achar_barra_stop(hist["barras"], meta.get("niveis") or [], _dt(meta["criada_em"]))
        if achado is None:
            return None, subiu
        barra, nivel = achado
        preco, gap = preco_execucao_stop(barra, nivel)
        motivo = f"mínima {nc.preco_texto(barra['baixa'])} ≤ stop {nc.preco_texto(nivel)}"
        if gap:
            motivo += f" (abertura em gap {nc.preco_texto(barra['abre'])})"
        return (barra, preco, motivo), subiu
    barra = achar_barra(hist["barras"], meta["preco_alvo"], _dt(meta["criada_em"]))
    if barra is None:
        return None, subiu
    return (barra, meta["preco_alvo"],
            f"máxima {nc.preco_texto(barra['alta'])} ≥ alvo {nc.preco_texto(meta['preco_alvo'])}"), subiu


def aplicar(cfg, historicos, agora=None, diarias=None):
    """Aplica os históricos já baixados às metas ativas (só disco, rápido). Retorna o relatório
    {"executadas", "invalidas", "reconciliadas", "aguardando", "erros": listas de metas, "mudou": bool,
    "avisos": textos para o usuário (venda duplicada de OCO em mês fechado, que exige ajuste manual)}.
    diarias: {ticker: barras diárias} para os stops móveis, quando não vierem dentro de cada histórico.

    Em cada par OCO só uma meta executa: vence a barra mais cedo e, na mesma barra, o stop (conservador);
    quando uma executa, a outra é cancelada."""
    agora = agora or agora_br()
    rel = {"executadas": [], "invalidas": [], "reconciliadas": [], "aguardando": [], "erros": [], "mudou": False,
           "avisos": []}
    with nc.TRAVA:
        if _cancelar_orfas_oco(cfg):
            nc.gravar_config(cfg)
            rel["mudou"] = True
        achadas = {}     # id da meta -> (meta, (barra, preço, motivo, fonte))
        for meta in metas_ativas(cfg):
            # confirma de novo, com a trava, que a meta continua ativa e que a venda ainda não existe
            if meta.get("status") != "ativa":
                continue
            if _venda_existente(_carregar_meses(), "auto-" + meta["id"]):
                _reconciliar(cfg, meta)
                par = _par_oco(cfg, meta)
                if par is not None and par.get("status") in ("ativa", "executada") and _venda_existente(
                        _carregar_meses(), "auto-" + par["id"]):
                    if par["status"] == "ativa":
                        _reconciliar(cfg, par)
                    _resolver_vendas_duplicadas(cfg, rel)      # as duas vendas existem: fica só a primeira
                elif par is not None and par.get("status") == "ativa":
                    _cancelar_por_oco(par, meta)
                nc.gravar_config(cfg)
                if meta["status"] == "executada":
                    rel["reconciliadas"].append(meta)
                rel["mudou"] = True
                continue
            par = _par_oco(cfg, meta)
            if par is not None and par.get("status") == "executada":    # queda entre a venda e o cancelamento
                _cancelar_por_oco(meta, par)
                nc.gravar_config(cfg)
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
            achado, subiu = _candidata(meta, hist, diarias, agora)
            if subiu:
                nc.gravar_config(cfg)
                rel["mudou"] = True
            if achado is None:
                if _marcar(meta, "ativa"):
                    nc.gravar_config(cfg)
                    rel["mudou"] = True
                continue
            fonte = f"{hist.get('fonte', 'Yahoo Finance')} · intervalo {hist.get('intervalo', '?')}"
            achadas[meta["id"]] = (meta, achado + (fonte,))
        # em cada par OCO que disparou, só vence uma: a barra mais cedo; na mesma barra, o stop
        perdedoras = set()
        for mid, (meta, (barra, _, _, _)) in achadas.items():
            par = _par_oco(cfg, meta)
            if par is None or par["id"] not in achadas:
                continue
            outra = achadas[par["id"]][1][0]
            minha = (barra["dt"], 0 if gatilho(meta) == "stop" else 1)
            dela = (outra["dt"], 0 if gatilho(par) == "stop" else 1)
            if dela < minha:
                perdedoras.add(mid)
        for mid, (meta, (barra, preco, motivo, fonte)) in achadas.items():
            if mid in perdedoras or meta.get("status") != "ativa":
                continue
            antes = (meta.get("status"), meta.get("ultimo_erro"))
            resultado = _executar(cfg, meta, barra, fonte, agora, preco, motivo)
            if resultado == "executada":
                par = _par_oco(cfg, meta)
                if par is not None and par.get("status") == "ativa":
                    _cancelar_por_oco(par, meta)
            if resultado != "aguardando" or antes != (meta.get("status"), meta.get("ultimo_erro")):
                nc.gravar_config(cfg)
                rel["mudou"] = True
            rel[{"executada": "executadas", "inválida": "invalidas", "aguardando": "aguardando"}[resultado]].append(meta)
    return rel


def verificar(cfg, historico, agora=None, diarias=None):
    """Busca o histórico e executa as metas atingidas. Retorna o relatório de aplicar() ou None quando outra
    verificação já está em andamento ou não há metas ativas. Pode ser chamada de uma thread.
    diarias(ticker, desde): barras diárias para os stops móveis (mercado.barras_diarias)."""
    if not _VERIFICANDO.acquire(blocking=False):
        return None
    try:
        ativas = metas_ativas(cfg)
        if not ativas:
            return None
        return aplicar(cfg, buscar_historicos(ativas, historico, diarias), agora)
    finally:
        _VERIFICANDO.release()


def preparar_fechamento(cfg, mes, historico, agora=None, diarias=None):
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
    rel = verificar(cfg, historico, agora, diarias)
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

def descricao(meta, todas=None):
    """Textos para a lista de metas: título, status, detalhe e a cor (accent, danger, aviso ou muted).
    todas: a lista de metas, para dizer com qual meta esta forma um OCO."""
    if gatilho(meta) == "stop":
        titulo = f"{meta['ticker']} · {meta['qtd']} un. · stop {nc.brl(meta['stop_atual'])}"
        if meta.get("movel"):
            titulo += " (móvel)"
    else:
        titulo = f"{meta['ticker']} · {meta['qtd']} un. a {nc.brl(meta['preco_alvo'])}"
    st = meta.get("status", "ativa")
    cor = {"ativa": "aviso", "executada": "accent", "cancelada": "muted", "inválida": "danger"}.get(st, "muted")
    partes = [f"Criada em {_dt(meta['criada_em']):%d/%m/%Y %H:%M}"]
    if (gatilho(meta) == "stop" and meta.get("movel") and meta.get("stop_inicial") is not None
            and abs(meta["stop_inicial"] - meta["stop_atual"]) > 0.004):
        partes.append(f"stop inicial {nc.brl(meta['stop_inicial'])}")
    if meta.get("lucro_desejado") is not None:
        partes.append(f"lucro desejado {nc.brl(meta['lucro_desejado'])}")
    if meta.get("oco"):
        par = next((m for m in (todas or []) if m is not meta and m.get("oco") == meta["oco"]), None)
        if par is None:
            partes.append("OCO")
        elif gatilho(par) == "stop":
            partes.append(f"OCO com stop {nc.brl(par['stop_atual'])}")
        else:
            partes.append(f"OCO com alvo {nc.brl(par['preco_alvo'])}")
    ex = meta.get("execucao")
    if st == "executada" and ex:
        quando = nc.fmt_data(ex["data"]) + (f" {ex['hora']}" if ex.get("hora") else "")
        partes.append(f"executada em {quando} a {nc.brl(ex['preco_usado'])} ({ex.get('motivo', '')})")
    if st == "cancelada" and meta.get("cancelada_detalhe"):
        partes.append(meta["cancelada_detalhe"])
    if meta.get("ultimo_erro"):
        partes.append(meta["ultimo_erro"])
    return {"titulo": titulo, "status": STATUS_ROTULO.get(st, st), "detalhe": " · ".join(partes), "cor": cor,
            "erro": bool(meta.get("ultimo_erro"))}
