"""Regras de cálculo, armazenamento local e conversão para a planilha.

Compartilhado entre a versão Windows (calculadora_darf.py) e a versão Android (android/main.py).
"""
import calendar
import json
import re
import threading
import time
import uuid
from collections import Counter, defaultdict
from datetime import date, datetime, timedelta
from functools import cmp_to_key, lru_cache
from pathlib import Path

TAXA_B3_SWING = 0.0003        # 0,0300% por operação (compra e venda)
TAXA_B3_DAYTRADE = 0.00023    # 0,0230% por operação (compra e venda)
CORRETAGEM_POR_ORDEM = 0.0
ALIQ_SWING = 0.15
ALIQ_DAYTRADE = 0.20
IRRF_SWING = 0.00005          # 0,005% sobre o valor da venda
IRRF_DAYTRADE = 0.01          # 1% sobre o lucro do dia
LIMITE_ISENCAO = 20000.0
DARF_MINIMO = 10.0

DADOS = Path("dados")
CONFIG = DADOS / "config.json"
TRAVA = threading.RLock()     # protege leituras/gravações locais feitas por threads diferentes


def configurar(pasta):
    """Define a pasta onde ficam os arquivos de dados."""
    global DADOS, CONFIG
    DADOS = Path(pasta)
    DADOS.mkdir(parents=True, exist_ok=True)
    CONFIG = DADOS / "config.json"


def agora():
    return round(time.time(), 3)


# ---------------------------------------------------------------- formatação

def brl(v):
    s = f"{abs(v):,.2f}".replace(",", "X").replace(".", ",").replace("X", ".")
    return ("-R$ " if v < -0.004 else "R$ ") + s


def parse_num(s):
    s = s.strip().replace("R$", "").replace(" ", "")
    if "," in s:
        s = s.replace(".", "").replace(",", ".")
    v = float(s)
    if v <= 0:
        raise ValueError
    return v


def parse_valor(s):
    """Valor em reais que aceita zero e negativo: "10.000,50", "-250", "R$ 0"."""
    s = (s or "").strip().replace("R$", "").replace(" ", "")
    negativo = s.startswith("-")
    s = s.lstrip("-")
    if "," in s or re.fullmatch(r"\d{1,3}(\.\d{3})+", s):  # "10.000" é dez mil
        s = s.replace(".", "").replace(",", ".")
    v = float(s)
    return -v if negativo else v


def fmt_num(v):
    """Número para preencher um campo de edição: 32.5 -> "32,50"."""
    t = f"{v:.8f}".rstrip("0")
    inteiro, dec = t.split(".")
    return f"{inteiro},{dec.ljust(2, '0')}"


def parse_qtd(s):
    v = int(s.strip().replace(".", ""))
    if v <= 0:
        raise ValueError
    return v


def parse_data(s):
    return datetime.strptime(s.strip(), "%d/%m/%Y").date()


def fmt_data(iso):
    return date.fromisoformat(iso).strftime("%d/%m/%Y")


def fmt_mes(mes):
    a, m = mes.split("-")
    return f"{m}/{a}"


def preco_texto(v):
    return f"{v:.2f}".replace(".", ",")


def proximo_mes(mes):
    a, m = map(int, mes.split("-"))
    m += 1
    if m > 12:
        a, m = a + 1, 1
    return f"{a:04d}-{m:02d}"


def limites_mes(mes):
    a, m = map(int, mes.split("-"))
    return date(a, m, 1), date(a, m, calendar.monthrange(a, m)[1])


# ---------------------------------------------------------------- armazenamento

def arquivo(mes):
    return DADOS / f"{mes}.json"


def mes_vazio(mes):
    return {"mes": mes, "fechado": False, "darf_anterior": 0.0, "lotes": [], "excluidos": {}}


def carregar(mes):
    p = arquivo(mes)
    if p.exists():
        d = json.loads(p.read_text(encoding="utf-8"))
        d.setdefault("excluidos", {})
        return d
    return mes_vazio(mes)


def _campos(x):
    return {k: v for k, v in x.items() if k not in ("mod", "vendas")}


def salvar(d, carimbar=True):
    """Grava o mês. Com carimbar=True, marca a hora de alteração do que mudou e registra o que foi excluído."""
    with TRAVA:
        d.setdefault("excluidos", {})
        if carimbar:
            t = agora()
            p = arquivo(d["mes"])
            antigo = json.loads(p.read_text(encoding="utf-8")) if p.exists() else None
            if antigo is None or (antigo.get("fechado"), antigo.get("darf_anterior")) != (
                    d.get("fechado"), d.get("darf_anterior")):
                d["mod"] = t
            d.setdefault("mod", 0)
            lotes_ant = {l["id"]: l for l in (antigo or {}).get("lotes", [])}
            vendas_ant = {v["id"]: v for l in lotes_ant.values() for v in l["vendas"]}
            ids = set()
            for l in d["lotes"]:
                ids.add(l["id"])
                o = lotes_ant.get(l["id"])
                if o is None or _campos(o) != _campos(l):
                    l["mod"] = t
                l.setdefault("mod", 0)
                for v in l["vendas"]:
                    ids.add(v["id"])
                    ov = vendas_ant.get(v["id"])
                    if ov is None or _campos(ov) != _campos(v):
                        v["mod"] = t
                    v.setdefault("mod", 0)
            for i in (set(lotes_ant) | set(vendas_ant)) - ids:
                d["excluidos"][i] = t
        arquivo(d["mes"]).write_text(json.dumps(d, ensure_ascii=False, indent=2), encoding="utf-8")


def listar_meses():
    return sorted(p.stem for p in DADOS.glob("????-??.json"))


def mes_inicial():
    abertos = [m for m in listar_meses() if not carregar(m)["fechado"]]
    return abertos[0] if abertos else date.today().strftime("%Y-%m")


CONFIG_PADRAO = {"tema": "Dark", "amigos": [], "radar": [], "planilhas": {}, "pendente": False, "excluidos": {},
                 "caixa": {"saldo": 0.0, "data": "", "mod": 0}, "metas": []}


def ler_config():
    try:
        cfg = json.loads(CONFIG.read_text(encoding="utf-8"))
    except Exception:
        cfg = {}
    for k, v in CONFIG_PADRAO.items():
        cfg.setdefault(k, json.loads(json.dumps(v)))
    return cfg


def _chave_lista(nome):
    return {"amigos": "email", "metas": "id"}.get(nome, "ticker")


SEM_CARIMBO = {"metas": ("niveis", "stop_atual")}     # mudanças que não contam como edição do registro


def gravar_config(cfg, carimbar=True):
    """Grava a configuração, marcando a hora de alteração dos amigos, do radar e das metas. A subida do stop
    móvel (niveis/stop_atual da meta) não carimba: ela é unida na mesclagem e não pode fazer uma meta ativa
    parecer mais recente que um cancelamento feito em outro aparelho."""
    with TRAVA:
        cfg.setdefault("excluidos", {})
        if carimbar:
            t = agora()
            try:
                antigo = json.loads(CONFIG.read_text(encoding="utf-8"))
            except Exception:
                antigo = {}
            for nome in ("amigos", "radar", "metas"):
                k = _chave_lista(nome)
                ignorar = SEM_CARIMBO.get(nome, ())
                ant = {x[k]: x for x in antigo.get(nome, [])}
                atuais = set()
                for x in cfg.get(nome, []):
                    atuais.add(x[k])
                    o = ant.get(x[k])
                    if o is None or {c: v for c, v in _campos(o).items() if c not in ignorar} != {
                            c: v for c, v in _campos(x).items() if c not in ignorar}:
                        x["mod"] = t
                    x.setdefault("mod", 0)
                for chave in set(ant) - atuais:
                    cfg["excluidos"][f"{nome}:{chave}"] = t
        CONFIG.write_text(json.dumps(cfg, ensure_ascii=False, indent=2), encoding="utf-8")


# ---------------------------------------------------------------- radar

def ordenar_radar(radar):
    """Radar na ordem escolhida pelo usuário (campo pos); itens sem pos mantêm a posição relativa."""
    return [r for _, r in sorted(enumerate(radar), key=lambda e: (e[1].get("pos", e[0]), e[0]))]


def adicionar_radar(cfg, ticker, nome=""):
    """Inclui o ativo no fim do radar (não grava)."""
    radar = cfg.setdefault("radar", [])
    if any(r["ticker"] == ticker for r in radar):
        return None
    pos = max((r.get("pos", i) for i, r in enumerate(radar)), default=-1) + 1
    item = {"ticker": ticker, "nome": nome or "", "desde": date.today().isoformat(), "pos": pos}
    radar.append(item)
    return item


def reordenar_radar(cfg, tickers):
    """Aplica a nova ordem (lista de tickers); a posição vai para a planilha e sincroniza entre aparelhos."""
    por_ticker = {r["ticker"]: r for r in cfg.get("radar", [])}
    novos = [por_ticker[t] for t in tickers if t in por_ticker]
    novos += [r for r in ordenar_radar(cfg.get("radar", [])) if r["ticker"] not in tickers]
    for i, r in enumerate(novos):
        r["pos"] = i
    cfg["radar"] = novos


# ---------------------------------------------------------------- regras

def vendido(lote):
    return sum(v["qtd"] for v in lote["vendas"])


def restante(lote):
    return lote["qtd"] - vendido(lote)


def sem_venda(lote, venda_id):
    """Cópia da compra sem uma das vendas (usada ao editar essa venda)."""
    return {**lote, "vendas": [v for v in lote["vendas"] if v["id"] != venda_id]}


def erro_edicao_lote(lote, novo):
    """Valida a edição de uma compra que já pode ter vendas. Retorna a mensagem de erro ou None."""
    ja = vendido(lote)
    if novo["qtd"] < ja:
        return f"A quantidade não pode ser menor que a já vendida ({ja})."
    if lote["vendas"]:
        primeira = min(v["data"] for v in lote["vendas"])
        if novo["data_compra"] > primeira:
            return f"A data da compra não pode ser depois da primeira venda ({fmt_data(primeira)})."
    return None


def status_lote(lote):
    r = restante(lote)
    if r == lote["qtd"]:
        return "Não vendido"
    if r == 0:
        return "Vendido"
    return "Vendido parcial"


def calcular_venda(lote, v):
    q = v["qtd"]
    compra = q * lote["preco"]
    venda = q * v["preco"]
    dt = v["data"] == lote["data_compra"]
    taxa = TAXA_B3_DAYTRADE if dt else TAXA_B3_SWING
    taxas = (compra + venda) * taxa
    corretagem = CORRETAGEM_POR_ORDEM * (1 + q / lote["qtd"])
    bruto = venda - compra
    liquido = bruto - taxas - corretagem
    return {"dt": dt, "compra": compra, "venda": venda, "taxas": taxas,
            "corretagem": corretagem, "bruto": bruto, "liquido": liquido}


def apurar(d):
    ops = []
    for l in d["lotes"]:
        for v in l["vendas"]:
            c = calcular_venda(l, v)
            c.update(ticker=l["ticker"], tipo=l["tipo"], data=v["data"], qtd=v["qtd"],
                     preco=v["preco"], lote_id=l["id"], venda_id=v["id"])
            ops.append(c)

    vendas_acoes_st = sum(o["venda"] for o in ops if not o["dt"] and o["tipo"] == "Ação")
    isento = vendas_acoes_st <= LIMITE_ISENCAO

    for o in ops:
        if o["dt"]:
            o["regime"] = "Day trade"
            o["imposto"] = max(o["liquido"], 0) * ALIQ_DAYTRADE
        elif o["tipo"] == "Ação" and isento:
            o["regime"] = "Swing (isento)"
            o["imposto"] = 0.0
        else:
            o["regime"] = "Swing"
            o["imposto"] = max(o["liquido"], 0) * ALIQ_SWING

    res_acoes_st = sum(o["liquido"] for o in ops if not o["dt"] and o["tipo"] == "Ação")
    res_bdr_st = sum(o["liquido"] for o in ops if not o["dt"] and o["tipo"] == "BDR")
    base_st = (min(res_acoes_st, 0) if isento else res_acoes_st) + res_bdr_st
    base_dt = sum(o["liquido"] for o in ops if o["dt"])
    imp_st = max(base_st, 0) * ALIQ_SWING
    imp_dt = max(base_dt, 0) * ALIQ_DAYTRADE

    irrf_st_dia = defaultdict(float)
    res_dt_dia = defaultdict(float)
    for o in ops:
        if o["dt"]:
            res_dt_dia[o["data"]] += o["liquido"]
        else:
            irrf_st_dia[o["data"]] += o["venda"] * IRRF_SWING
    irrf_st = sum(x for x in irrf_st_dia.values() if x > 1)
    irrf_dt = sum(r * IRRF_DAYTRADE for r in res_dt_dia.values() if r * IRRF_DAYTRADE > 1)
    irrf = irrf_st + irrf_dt

    imposto_total = imp_st + imp_dt
    darf_mes = max(imposto_total - irrf, 0)
    darf_anterior = d.get("darf_anterior", 0.0)
    darf = darf_mes + darf_anterior

    return {
        "ops": ops,
        "vendas_acoes_st": vendas_acoes_st,
        "isento": isento,
        "bruto": sum(o["bruto"] for o in ops),
        "custos": sum(o["taxas"] + o["corretagem"] for o in ops),
        "imp_st": imp_st,
        "imp_dt": imp_dt,
        "imposto_total": imposto_total,
        "irrf": irrf,
        "lucro_liquido": sum(o["liquido"] for o in ops) - imposto_total,
        "darf_mes": darf_mes,
        "darf_anterior": darf_anterior,
        "darf": darf,
    }


def info_darf(r, mes):
    if r["darf"] >= DARF_MINIMO:
        return f"Código 6015 · vence no último dia útil de {fmt_mes(proximo_mes(mes))}"
    if r["darf"] > 0:
        return "Abaixo de R$ 10 · acumula para o próximo mês"
    return "Nada a pagar neste mês"


def fechar_mes(d):
    """Fecha o mês, leva os ativos não vendidos para o mês seguinte e retorna (apuração, próximo mês)."""
    with TRAVA:
        r = apurar(d)
        d["fechado"] = True
        d["resumo"] = {k: v for k, v in r.items() if k != "ops"}
        salvar(d)
        prox = proximo_mes(d["mes"])
        nd = carregar(prox)
        if not nd["fechado"]:
            ja = {l.get("origem") for l in nd["lotes"]}
            for l in d["lotes"]:
                if restante(l) > 0 and l["id"] not in ja:
                    # id derivado da compra de origem: dois aparelhos que fecham o mesmo mês geram o mesmo id
                    nd["lotes"].append({"id": f"{l['id']}~{prox}", "origem": l["id"], "ticker": l["ticker"],
                                        "tipo": l["tipo"], "data_compra": l["data_compra"],
                                        "qtd": restante(l), "preco": l["preco"], "vendas": []})
            nd["darf_anterior"] = r["darf"] if r["darf"] < DARF_MINIMO else 0.0
            salvar(nd)
        return r, prox


def mes_aceita_venda_retroativa(mes, mes_atual):
    """Venda de um mês anterior ao aberto: só em mês sem arquivo ou fechado sem nenhuma compra em aberto (caso dos
    meses criados por venda retroativa; a marcação "retroativo" não vai para a planilha)."""
    if mes >= mes_atual:
        return False
    if not arquivo(mes).exists():
        return True
    d = carregar(mes)
    return bool(d.get("retroativo")) or (d["fechado"] and all(restante(l) == 0 for l in d["lotes"]))


def registrar_venda_retroativa(d, lote_id, venda):
    """Grava a venda no mês em que ela ocorreu (fechado, com a apuração própria) e tira a quantidade vendida da
    compra do mês atual d. DARF abaixo do mínimo do mês da venda passa para o darf_anterior de d.
    Retorna o mês da venda."""
    with TRAVA:
        mes = venda["data"][:7]
        lote = next(l for l in d["lotes"] if l["id"] == lote_id)
        if lote["vendas"]:
            # a corretagem das vendas é rateada por lote["qtd"]; reduzir a quantidade mudaria a DARF delas
            raise ValueError("Essa compra já tem venda neste mês. Registre a venda antiga antes das vendas do mês.")
        dm = carregar(mes)
        darf_ant = dm.get("resumo", {}).get("darf", 0.0)
        levada_ant = darf_ant if darf_ant < DARF_MINIMO else 0.0
        dm["retroativo"] = True
        dm["fechado"] = True
        dm["mod"] = agora()
        novo = {"id": novo_id(), "ticker": lote["ticker"], "tipo": lote["tipo"], "data_compra": lote["data_compra"],
                "qtd": venda["qtd"], "preco": lote["preco"], "vendas": [{"id": novo_id(), **venda}]}
        if lote.get("origem"):
            novo["origem"] = lote["origem"]   # compra já debitada no mês de origem: não gera novo débito no caixa
        dm["lotes"].append(novo)
        r = apurar(dm)
        dm["resumo"] = {k: v for k, v in r.items() if k != "ops"}
        salvar(dm)
        levada = r["darf"] if r["darf"] < DARF_MINIMO else 0.0
        d["darf_anterior"] = max(d.get("darf_anterior", 0.0) - levada_ant + levada, 0.0)
        lote["qtd"] -= venda["qtd"]
        if lote["qtd"] <= 0:
            d["lotes"] = [l for l in d["lotes"] if l["id"] != lote_id]
        salvar(d)
        return mes


def mensagem_fechamento(r, prox):
    if r["darf"] >= DARF_MINIMO:
        msg = (f"DARF a pagar: {brl(r['darf'])}\nCódigo: 6015\n"
               f"Vencimento: último dia útil de {fmt_mes(prox)}.")
    elif r["darf"] > 0:
        msg = f"A DARF de {brl(r['darf'])} é menor que R$ 10 e foi transferida para {fmt_mes(prox)}."
    else:
        msg = "Não há DARF a pagar neste mês."
    return msg + f"\n\nAtivos não vendidos foram levados para {fmt_mes(prox)}."


def novo_id():
    return uuid.uuid4().hex


SUFIXOS_BDR = ("31", "32", "33", "34", "35", "39")


def tipo_por_ticker(ticker):
    """Ação ou BDR pelo código de negociação da B3: BDRs terminam em 31, 32, 33, 34, 35 ou 39
    (ex.: AAPL34, T1TW34); o resto é ação ou unit (PETR4, TAEE11). O "F" do fracionário é ignorado."""
    t = (ticker or "").strip().upper()
    if t.endswith("F") and len(t) > 5:
        t = t[:-1]
    m = re.fullmatch(r"[A-Z0-9]{4}(\d{2})", t)
    return "BDR" if m and m.group(1) in SUFIXOS_BDR else "Ação"


def inferir_tipo(ticker, conhecidos=None):
    """Mantido por compatibilidade: o tipo vem sempre do ticker."""
    return tipo_por_ticker(ticker)


def corrigir_tipos_mes(d):
    """Ajusta o tipo (Ação/BDR) das compras do mês pelo ticker. Retorna True se algo mudou."""
    mudou = False
    for l in d.get("lotes", []):
        certo = tipo_por_ticker(l["ticker"])
        if l.get("tipo") != certo:
            l["tipo"] = certo
            mudou = True
    return mudou


def corrigir_tipos():
    """Corrige os registros já gravados; as compras alteradas recebem nova hora e vencem na sincronização."""
    mudou = False
    with TRAVA:
        for mes in listar_meses():
            d = carregar(mes)
            if corrigir_tipos_mes(d):
                salvar(d)
                mudou = True
    return mudou


def historico_tickers(meses_recentes=6):
    """Frequência de operações por ticker nos últimos meses e o tipo conhecido de cada um."""
    freq, tipos = Counter(), {}
    for mes in listar_meses()[-meses_recentes:]:
        for l in carregar(mes)["lotes"]:
            freq[l["ticker"]] += (0 if l.get("origem") else 1) + len(l["vendas"])
            tipos[l["ticker"]] = l["tipo"]
    return freq, tipos


def sugestoes(d, so_custodia=False):
    freq, tipos = historico_tickers()
    custodia = {l["ticker"] for l in d["lotes"] if restante(l) > 0}
    if so_custodia:
        lista = sorted(custodia, key=lambda t: (-freq[t], t))
    else:
        lista = sorted(set(freq) | custodia, key=lambda t: (-(freq[t] + (2 if t in custodia else 0)), t))
    return lista[:6], tipos


def resultado_aberto(lote, preco_atual):
    """Ganho ou perda da quantidade ainda não vendida: (valor em R$, variação em %)."""
    if not preco_atual or restante(lote) <= 0:
        return None
    return (preco_atual - lote["preco"]) * restante(lote), (preco_atual / lote["preco"] - 1) * 100


def fmt_resultado(res):
    if res is None:
        return "—"
    valor, pct = res
    sinal = "+" if valor > 0.004 else ""
    pct_txt = f"{pct:.2f}".replace(".", ",")
    return f"{sinal}{brl(valor)} ({sinal}{pct_txt}%)"


# ---------------------------------------------------------------- caixa e liquidação (D+2)

DIAS_SEMANA = ["Segunda-feira", "Terça-feira", "Quarta-feira", "Quinta-feira", "Sexta-feira", "Sábado", "Domingo"]
DIAS_LIQUIDACAO = 2


def _pascoa(ano):
    """Domingo de Páscoa (algoritmo de Meeus/Jones/Butcher)."""
    a, b, c = ano % 19, ano // 100, ano % 100
    d, e = b // 4, b % 4
    f = (b + 8) // 25
    g = (b - f + 1) // 3
    h = (19 * a + b - d - g + 15) % 30
    i, k = c // 4, c % 4
    l = (32 + 2 * e + 2 * i - h - k) % 7
    m = (a + 11 * h + 22 * l) // 451
    mes = (h + l - 7 * m + 114) // 31
    dia = (h + l - 7 * m + 114) % 31 + 1
    return date(ano, mes, dia)


@lru_cache(maxsize=None)
def feriados_b3(ano):
    """Dias sem pregão na B3: feriados nacionais, Carnaval, Sexta-feira Santa, Corpus Christi, 24 e 31/12."""
    p = _pascoa(ano)
    fixos = [(1, 1), (4, 21), (5, 1), (9, 7), (10, 12), (11, 2), (11, 15), (12, 24), (12, 25), (12, 31)]
    dias = {date(ano, m, d) for m, d in fixos}
    if ano >= 2024:
        dias.add(date(ano, 11, 20))  # Consciência Negra (Lei 14.759/2023)
    dias |= {p - timedelta(days=48), p - timedelta(days=47), p - timedelta(days=2), p + timedelta(days=60)}
    return frozenset(dias)


def dia_util(d):
    return d.weekday() < 5 and d not in feriados_b3(d.year)


def calcular_data_liquidacao(data_operacao, dias_uteis=DIAS_LIQUIDACAO):
    """Data de liquidação financeira na B3: D+2 em dias úteis (sem fins de semana nem feriados)."""
    d = date.fromisoformat(data_operacao) if isinstance(data_operacao, str) else data_operacao
    n = 0
    while n < dias_uteis:
        d += timedelta(days=1)
        if dia_util(d):
            n += 1
    return d


def fmt_liquidacao(d):
    return f"{DIAS_SEMANA[d.weekday()]}, {d:%d/%m/%Y}"


def dias_uteis_entre(inicio, fim):
    """Quantos dias úteis há depois de inicio até fim (0 se fim <= inicio)."""
    n, d = 0, inicio
    while d < fim:
        d += timedelta(days=1)
        if dia_util(d):
            n += 1
    return n


def rotulo_vencimento(d, hoje=None):
    """Rótulo do agrupamento da agenda: Hoje, Amanhã (D+1), Depois de amanhã (D+2) ou o dia da semana."""
    hoje = hoje or date.today()
    if d < hoje:
        return f"Liquidado em {d:%d/%m/%Y}"
    if d == hoje:
        return "Hoje"
    n = dias_uteis_entre(hoje, d)
    if d == hoje + timedelta(days=1):
        nome = "Amanhã"
    elif d == hoje + timedelta(days=2):
        nome = "Depois de amanhã"
    else:
        nome = f"{DIAS_SEMANA[d.weekday()]}, {d:%d/%m}"
    return f"{nome} (D+{n})"


def resumo_ordem(lado, qtd, preco, data_operacao, preco_compra=None, day_trade=False):
    """Impacto financeiro de uma ordem. lado: "compra" ou "venda". Na venda em day trade, informe o preço
    de compra: a B3 liquida só o resultado do dia. Retorna bruto, taxas, irrf, liquido (com sinal) e liquidacao."""
    bruto = qtd * preco
    irrf = 0.0
    if lado == "compra":
        taxas = bruto * TAXA_B3_SWING
        liquido = -(bruto + taxas)
    elif day_trade:
        compra = qtd * (preco_compra or 0)
        taxas = (bruto + compra) * TAXA_B3_DAYTRADE
        resultado = bruto - compra - taxas
        irrf = resultado * IRRF_DAYTRADE if resultado * IRRF_DAYTRADE > 1 else 0.0
        liquido = resultado - irrf
    else:
        taxas = bruto * TAXA_B3_SWING
        irrf = bruto * IRRF_SWING if bruto * IRRF_SWING > 1 else 0.0
        liquido = bruto - taxas - irrf
    return {"bruto": bruto, "taxas": taxas, "irrf": irrf, "liquido": liquido, "day_trade": day_trade and lado != "compra",
            "liquidacao": calcular_data_liquidacao(data_operacao)}


def lancamentos_caixa(meses=None):
    """Movimentos financeiros de todas as operações gravadas, com data de liquidação (D+2).

    Compra (parte que não virou day trade): -(valor + taxas B3). Venda swing: +(valor - taxas B3).
    Day trade: só o resultado do dia (venda - compra - taxas). IRRF retido entra como débito no dia.
    Compras levadas de um mês para o outro (origem) não geram novo débito.
    meses: dados de outra pessoa ({mês: dados}); por padrão, os meses gravados neste aparelho."""
    itens = []
    irrf_st_dia, res_dt_dia = defaultdict(float), defaultdict(float)
    fontes = (meses[m] for m in sorted(meses)) if meses is not None else (carregar(m) for m in listar_meses())
    for dados_mes in fontes:
        for l in dados_mes["lotes"]:
            if not l.get("origem"):
                q = l["qtd"] - sum(v["qtd"] for v in l["vendas"] if v["data"] == l["data_compra"])
                if q > 0:
                    bruto = q * l["preco"]
                    itens.append({"id": f"c:{l['id']}", "data": l["data_compra"], "ticker": l["ticker"],
                                  "tipo": "Compra", "qtd": q, "valor": -(bruto + bruto * TAXA_B3_SWING)})
            for v in l["vendas"]:
                c = calcular_venda(l, v)
                if c["dt"]:
                    res_dt_dia[v["data"]] += c["liquido"]
                    itens.append({"id": f"v:{v['id']}", "data": v["data"], "ticker": l["ticker"],
                                  "tipo": "Day trade", "qtd": v["qtd"], "valor": c["liquido"]})
                else:
                    irrf_st_dia[v["data"]] += c["venda"] * IRRF_SWING
                    itens.append({"id": f"v:{v['id']}", "data": v["data"], "ticker": l["ticker"],
                                  "tipo": "Venda", "qtd": v["qtd"], "valor": c["venda"] - c["venda"] * TAXA_B3_SWING})
    for dia, valor in irrf_st_dia.items():
        if valor > 1:
            itens.append({"id": f"irrf:st:{dia}", "data": dia, "ticker": "IRRF", "tipo": "IRRF (dedo-duro)",
                          "qtd": 0, "valor": -valor})
    for dia, res in res_dt_dia.items():
        if res * IRRF_DAYTRADE > 1:
            itens.append({"id": f"irrf:dt:{dia}", "data": dia, "ticker": "IRRF", "tipo": "IRRF day trade",
                          "qtd": 0, "valor": -res * IRRF_DAYTRADE})
    for it in itens:
        it["liquidacao"] = calcular_data_liquidacao(it["data"])
    itens.sort(key=lambda x: (x["liquidacao"], x["data"], x["ticker"]))
    return itens


def resumo_caixa(cfg, hoje=None, meses=None):
    """Saldo disponível (D+0), em trânsito e projetado, a partir do saldo informado pelo usuário.

    O saldo informado vale para o dia em que foi definido e já inclui o que liquidou até esse dia.
    O que liquida depois disso é somado ao disponível quando a data chega (status Liquidado)."""
    hoje = hoje or date.today()
    caixa = cfg.get("caixa") or {}
    base = date.fromisoformat(caixa["data"]) if caixa.get("data") else None
    saldo = float(caixa.get("saldo") or 0.0)
    itens = lancamentos_caixa(meses)
    entrou = 0.0
    for it in itens:
        it["status"] = "Liquidado" if it["liquidacao"] <= hoje else "Pendente"
        if base and base < it["liquidacao"] <= hoje:
            entrou += it["valor"]
    pendentes = [it for it in itens if it["status"] == "Pendente"]
    a_debitar = sum(it["valor"] for it in pendentes if it["valor"] < 0)
    a_receber = sum(it["valor"] for it in pendentes if it["valor"] > 0)
    disponivel = saldo + entrou
    return {"definido": base is not None, "base": base, "saldo_base": saldo, "entrou": entrou,
            "disponivel": disponivel,
            "a_debitar": a_debitar, "a_receber": a_receber, "transito": a_debitar + a_receber,
            "projetado": disponivel + a_debitar + a_receber, "itens": itens}


def agenda_caixa(resumo, hoje=None, dias_historico=15):
    """Lançamentos pendentes e os liquidados nos últimos dias, agrupados pela data de liquidação:
    lista de (data, rótulo, total do dia, itens)."""
    hoje = hoje or date.today()
    limite = hoje - timedelta(days=dias_historico)
    grupos = defaultdict(list)
    for it in resumo["itens"]:
        if it["liquidacao"] > limite:
            grupos[it["liquidacao"]].append(it)
    return [(d, rotulo_vencimento(d, hoje), sum(i["valor"] for i in grupos[d]), grupos[d])
            for d in sorted(grupos, reverse=False)]


def projecao_caixa(resumo, hoje=None):
    """Liquidações pendentes por data, com o saldo que sobra depois de cada uma:
    lista de (data, rótulo, total do dia, itens, saldo após o dia)."""
    hoje = hoje or date.today()
    saldo = resumo["disponivel"]
    saida = []
    for d, rot, total, itens in agenda_caixa(resumo, hoje):
        if d > hoje:
            saldo += total
            saida.append((d, rot, total, itens, saldo))
    return saida


def definir_saldo(cfg, valor, hoje=None):
    """Define o saldo disponível de hoje (o que já liquidou até hoje deve estar incluído)."""
    hoje = hoje or date.today()
    cfg["caixa"] = {"saldo": round(float(valor), 2), "data": hoje.isoformat(), "mod": agora()}


def ajustar_saldo(cfg, delta, hoje=None):
    """Aporte (delta > 0) ou retirada (delta < 0) sobre o saldo disponível atual."""
    atual = resumo_caixa(cfg, hoje)["disponivel"]
    definir_saldo(cfg, atual + delta, hoje)


def custodia_atual():
    return {l["ticker"] for l in carregar(mes_inicial())["lotes"] if restante(l) > 0}


# ---------------------------------------------------------------- planilha (linhas <-> dados)

EPOCA = date(1899, 12, 30)


def serial(iso):
    return (date.fromisoformat(iso) - EPOCA).days


def de_serial(v):
    if isinstance(v, (int, float)) and not isinstance(v, bool):
        return (EPOCA + timedelta(days=int(v))).isoformat()
    s = str(v).strip()
    try:
        return parse_data(s).isoformat()
    except ValueError:
        return date.fromisoformat(s).isoformat()


def mes_iso(rotulo):
    m, a = str(rotulo).strip().split("/")
    return f"{int(a):04d}-{int(m):02d}"


def _num(v, padrao=0.0):
    try:
        return float(v) if v not in ("", None) else padrao
    except (TypeError, ValueError):
        return padrao


CAMPOS_DETALHES = ("oco", "stop_inicial", "stop_atual", "movel", "niveis", "cancelada_por", "cancelada_detalhe",
                   "sugestao")


def linha_meta(m):
    """Linha da aba "Metas" (14 colunas). As 12 primeiras são as da versão anterior; Gatilho e Detalhes (JSON com
    os campos do stop e do OCO) vêm depois. Na meta de stop o Preço-alvo fica vazio, e a versão anterior, que não
    entende stop, pula a linha em vez de tratá-la como alvo."""
    stop = m.get("gatilho") == "stop"
    detalhes = {"id": m["id"], "gatilho": "stop" if stop else "alvo"}
    for k in CAMPOS_DETALHES:
        if m.get(k) not in (None, ""):
            detalhes[k] = m[k]
    return [m["id"], m["ticker"], m.get("tipo", ""), m["lote_id"], m["qtd"], "" if stop else m["preco_alvo"],
            m["lucro_desejado"] if m.get("lucro_desejado") is not None else "", m["criada_em"],
            m.get("status", "ativa"), m.get("ultimo_erro", ""),
            json.dumps(m["execucao"], ensure_ascii=False) if m.get("execucao") else "", m.get("mod", 0),
            detalhes["gatilho"], json.dumps(detalhes, ensure_ascii=False, separators=(",", ":"))]


def montar_linhas(meses, cfg):
    resumo, compras, vendas, excl = [], [], [], []
    for mes in meses:
        d = carregar(mes)
        r = apurar(d)
        m = fmt_mes(mes)
        resumo.append([m, "Fechado" if d["fechado"] else "Aberto", round(r["vendas_acoes_st"], 2),
                       "Sim" if r["isento"] else "Não", round(r["bruto"], 2), round(r["custos"], 2),
                       round(r["imp_st"], 2), round(r["imp_dt"], 2), round(r["irrf"], 2),
                       round(r["lucro_liquido"], 2), round(r["darf_anterior"], 2), round(r["darf"], 2),
                       d.get("mod", 0)])
        ops = {o["venda_id"]: o for o in r["ops"]}
        linhas_v = []
        for l in d["lotes"]:
            compras.append([m, l["ticker"], l["tipo"], serial(l["data_compra"]), l["qtd"], l["preco"],
                            round(l["qtd"] * l["preco"], 2), vendido(l), restante(l), status_lote(l),
                            l["id"], l.get("origem", ""), l.get("mod", 0)])
            for v in l["vendas"]:
                o = ops[v["id"]]
                linhas_v.append([m, l["ticker"], l["tipo"], serial(l["data_compra"]), l["preco"],
                                 serial(v["data"]), v["qtd"], v["preco"], round(o["venda"], 2), o["regime"],
                                 round(o["taxas"] + o["corretagem"], 2), round(o["bruto"], 2),
                                 round(o["liquido"], 2), round(o["imposto"], 2), v["id"], l["id"], v.get("mod", 0)])
        vendas += sorted(linhas_v, key=lambda x: x[5])
        for i, t in d.get("excluidos", {}).items():
            excl.append(["registro", m, i, t])
    for chave, t in cfg.get("excluidos", {}).items():
        tipo, valor = chave.split(":", 1)
        excl.append([tipo, "", valor, t])
    lista_amigos = [[a["email"], serial(a["desde"]), a.get("mod", 0)] for a in cfg.get("amigos", [])]
    lista_radar = [[r["ticker"], r.get("nome", ""), serial(r["desde"]), r.get("mod", 0), r.get("pos", i)]
                   for i, r in enumerate(ordenar_radar(cfg.get("radar", [])))]
    caixa = cfg.get("caixa") or {}
    lista_caixa = [[round(float(caixa.get("saldo") or 0), 2), serial(caixa["data"]), caixa.get("mod", 0)]] \
        if caixa.get("data") else []
    lista_metas = [linha_meta(m) for m in sorted(cfg.get("metas", []), key=lambda m: (m["criada_em"], m["id"]))]
    return {"Resumo": resumo, "Compras": compras, "Vendas": vendas, "Amigos": lista_amigos,
            "Radar": lista_radar, "Caixa": lista_caixa, "Metas": lista_metas, "Exclusões": excl}


def reconstruir(abas):
    """Converte as linhas da planilha em (meses, amigos, radar, exclusões da configuração, caixa)."""
    larguras = {"Resumo": 13, "Compras": 13, "Vendas": 17, "Amigos": 3, "Radar": 5, "Exclusões": 4, "Caixa": 3}
    abas = {k: [(list(r) + [""] * larguras.get(k, 0))[:max(larguras.get(k, 0), len(r))] for r in v]
            for k, v in abas.items()}
    meses, lotes = {}, {}
    for row in abas.get("Resumo", []):
        try:
            mes = mes_iso(row[0])
            meses[mes] = {"mes": mes, "fechado": row[1] == "Fechado", "darf_anterior": _num(row[10]),
                          "lotes": [], "excluidos": {}, "mod": _num(row[12])}
        except (ValueError, TypeError, IndexError):
            continue
    for row in abas.get("Compras", []):
        try:
            mes = mes_iso(row[0])
            l = {"id": str(row[10]) or novo_id(), "ticker": str(row[1]).upper(), "tipo": str(row[2]),
                 "data_compra": de_serial(row[3]), "qtd": int(row[4]), "preco": float(row[5]), "vendas": [],
                 "mod": _num(row[12])}
        except (ValueError, TypeError, IndexError):
            continue
        if row[11]:
            l["origem"] = str(row[11])
        meses.setdefault(mes, mes_vazio(mes))["lotes"].append(l)
        lotes[(mes, l["id"])] = l
    for row in abas.get("Vendas", []):
        try:
            mes = mes_iso(row[0])
            l = lotes.get((mes, str(row[15])))
            if l is not None:
                l["vendas"].append({"id": str(row[14]) or novo_id(), "data": de_serial(row[5]),
                                    "qtd": int(row[6]), "preco": float(row[7]), "mod": _num(row[16])})
        except (ValueError, TypeError, IndexError):
            continue
    excl_cfg = {}
    for row in abas.get("Exclusões", []):
        try:
            tipo, rotulo, valor, t = str(row[0]), row[1], str(row[2]), _num(row[3])
            if tipo == "registro":
                mes = mes_iso(rotulo)
                meses.setdefault(mes, mes_vazio(mes))["excluidos"][valor] = t
            elif valor:
                excl_cfg[f"{tipo}:{valor}"] = t
        except (ValueError, TypeError, IndexError):
            continue
    amigos = []
    for row in abas.get("Amigos", []):
        email = str(row[0]).strip().lower()
        if email:
            try:
                desde = de_serial(row[1])
            except (ValueError, TypeError):
                desde = date.today().isoformat()
            amigos.append({"email": email, "desde": desde, "mod": _num(row[2])})
    radar = []
    for row in abas.get("Radar", []):
        ticker = str(row[0]).strip().upper()
        if ticker and all(r["ticker"] != ticker for r in radar):
            try:
                desde = de_serial(row[2])
            except (ValueError, TypeError):
                desde = date.today().isoformat()
            item = {"ticker": ticker, "nome": str(row[1] or ""), "desde": desde, "mod": _num(row[3])}
            if str(row[4]).strip() != "":  # planilhas antigas não têm a coluna Posição
                item["pos"] = int(_num(row[4]))
            radar.append(item)
    caixa = None
    for row in abas.get("Caixa", [])[:1]:
        try:
            caixa = {"saldo": _num(row[0]), "data": de_serial(row[1]), "mod": _num(row[2])}
        except (ValueError, TypeError, IndexError):
            caixa = None
    for d in meses.values():
        corrigir_tipos_mes(d)
    return meses, amigos, radar, excl_cfg, caixa


def _campos_stop(detalhes):
    """Campos de uma meta de stop lidos dos Detalhes da planilha; None se faltam ou estão malformados."""
    try:
        campos = {"gatilho": "stop", "stop_inicial": float(detalhes["stop_inicial"]),
                  "stop_atual": float(detalhes["stop_atual"]), "movel": bool(detalhes.get("movel")),
                  "niveis": [{"desde": str(n["desde"]), "stop": float(n["stop"]),
                              "calc_em": str(n.get("calc_em", n["desde"]))} for n in detalhes["niveis"]]}
    except (KeyError, ValueError, TypeError, AttributeError):
        return None
    return campos


def reconstruir_metas(abas):
    """Metas da aba "Metas" da planilha (fora de reconstruir para não mudar o que ele devolve). A linha só é um
    stop quando os Detalhes são desta linha e trazem os campos do stop; do contrário vale o Preço-alvo (se
    também não for um número, a linha é descartada)."""
    metas = []
    for row in abas.get("Metas", []):
        row = (list(row) + [""] * 14)[:14]
        detalhes = {}
        if row[13]:
            try:
                lido = json.loads(str(row[13]))
                # os detalhes só valem se são desta linha (a planilha pode ter sido reordenada à mão)
                if isinstance(lido, dict) and lido.get("id") == str(row[0]).strip():
                    detalhes = lido
            except ValueError:
                pass
        campos_stop = _campos_stop(detalhes) if detalhes else None
        stop = campos_stop is not None and (str(row[12]).strip() == "stop" or detalhes.get("gatilho") == "stop")
        try:
            m = {"id": str(row[0]).strip(), "ticker": str(row[1]).strip().upper(), "tipo": str(row[2]),
                 "lote_id": str(row[3]), "qtd": int(row[4]),
                 "criada_em": str(row[7]), "status": str(row[8]) or "ativa", "mod": _num(row[11])}
            if stop:
                m.update(campos_stop)
            else:
                m["preco_alvo"] = float(row[5])
            datetime.fromisoformat(m["criada_em"])
        except (ValueError, TypeError):
            continue
        if not m["id"] or not m["ticker"]:
            continue
        if row[6] != "":
            m["lucro_desejado"] = _num(row[6])
        if row[9]:
            m["ultimo_erro"] = str(row[9])
        if row[10]:
            try:
                m["execucao"] = json.loads(str(row[10]))
            except ValueError:
                pass
        for k in ("oco", "cancelada_por", "cancelada_detalhe"):
            if detalhes.get(k):
                m[k] = str(detalhes[k])
        if isinstance(detalhes.get("sugestao"), dict):
            m["sugestao"] = detalhes["sugestao"]
        metas.append(m)
    return metas


# ---------------------------------------------------------------- mesclagem (vários aparelhos)

def _escolher(a, b):
    """Retorna o registro alterado por último (a vence empates)."""
    if a is None:
        return b
    if b is None:
        return a
    return a if a.get("mod", 0) >= b.get("mod", 0) else b


def mesclar_mes(local, remoto):
    if local is None:
        return remoto
    if remoto is None:
        return local
    meta = _escolher(local, remoto)
    excl = dict(remoto.get("excluidos", {}))
    for i, t in local.get("excluidos", {}).items():
        excl[i] = max(t, excl.get(i, 0))

    def apagado(x):
        return excl.get(x["id"], -1) >= x.get("mod", 0)

    lotes_l = {l["id"]: l for l in local["lotes"]}
    lotes_r = {l["id"]: l for l in remoto["lotes"]}
    vendas = {}
    for lado in (remoto["lotes"], local["lotes"]):  # local por último: vence empates
        for l in lado:
            for v in l["vendas"]:
                atual = vendas.get(v["id"])
                escolhido = _escolher(v, atual[1]) if atual else v
                vendas[v["id"]] = (l["id"], escolhido)
    ordem = list(lotes_l) + [i for i in lotes_r if i not in lotes_l]
    lotes = []
    for i in ordem:
        l = _escolher(lotes_l.get(i), lotes_r.get(i))
        if apagado(l):
            continue
        novo = {k: v for k, v in l.items() if k != "vendas"}
        novo["vendas"] = sorted((dict(v) for lid, v in vendas.values() if lid == i and not apagado(v)),
                                key=lambda v: (v["data"], v["id"]))
        lotes.append(novo)
    out = {"mes": local["mes"], "fechado": meta.get("fechado", False),
           "darf_anterior": meta.get("darf_anterior", 0.0), "mod": meta.get("mod", 0),
           "lotes": lotes, "excluidos": excl}
    if meta.get("resumo") and meta.get("fechado"):
        out["resumo"] = meta["resumo"]
    return out


def deduplicar_auto(meses):
    """Venda automática de meta (id "auto-...") só pode existir em um mês: se dois aparelhos a registraram em
    meses diferentes, fica a do mês mais antigo. meses: {mês: dados}. Retorna os meses alterados."""
    vistas, alterados = set(), set()
    for mes in sorted(meses):
        for l in meses[mes]["lotes"]:
            antes = len(l["vendas"])
            l["vendas"] = [v for v in l["vendas"]
                           if not str(v["id"]).startswith("auto-") or v["id"] not in vistas]
            vistas.update(v["id"] for v in l["vendas"] if str(v["id"]).startswith("auto-"))
            if len(l["vendas"]) != antes:
                alterados.add(mes)
    return alterados


def mesclar_lista(local, remoto, chave, excl, prefixo):
    itens = {x[chave]: x for x in remoto}
    for x in local:
        itens[x[chave]] = _escolher(x, itens.get(x[chave]))
    return [x for k, x in itens.items() if excl.get(f"{prefixo}:{k}", -1) < x.get("mod", 0)]


def _unir_niveis(a, b):
    """Níveis de dois aparelhos: um por data ("desde"), com o maior stop."""
    por_data = {}
    for n in list(a or []) + list(b or []):
        o = por_data.get(n["desde"])
        if o is None or n["stop"] > o["stop"]:
            por_data[n["desde"]] = dict(n)
    return [por_data[d] for d in sorted(por_data)]


CAMPOS_STOP = ("gatilho", "stop_inicial", "stop_atual", "movel", "niveis")
CAMPOS_NOVOS = CAMPOS_STOP + ("oco", "cancelada_por", "cancelada_detalhe", "sugestao")    # só a versão nova grava


def _completar_meta(vencedora, perdedora):
    """União de campos novos: o aparelho antigo reescreve só as 12 primeiras colunas, e o registro dele pode
    vencer por "mod" sem oco, níveis do stop etc. Os campos que a vencedora não tem e a perdedora tem são
    copiados. Os do stop só vêm de um stop (e nunca para uma meta com preço-alvo), e o motivo do cancelamento
    só para uma meta cancelada."""
    extra = {}
    for k in CAMPOS_NOVOS:
        if k in vencedora or perdedora.get(k) in (None, ""):
            continue
        if k in CAMPOS_STOP and (perdedora.get("gatilho") != "stop" or "preco_alvo" in vencedora):
            continue
        if k in ("cancelada_por", "cancelada_detalhe") and vencedora.get("status") != "cancelada":
            continue
        extra[k] = perdedora[k]
    return {**vencedora, **extra} if extra else vencedora


def _precedencia(m):
    """Status que não se desfaz: "executada" (a venda já foi registrada) e "cancelada" (ninguém reativa)."""
    return {"executada": 2, "cancelada": 1}.get(m.get("status"), 0)


def mesclar_metas(local, remoto):
    """Metas pelo id: "executada" vence qualquer outro status (a venda já foi registrada), "cancelada" vence
    "ativa" (um stop móvel que subiu em outro aparelho não ressuscita a meta); nos demais casos vale a
    alteração mais recente. A venda automática tem id fixo (auto-<meta>), então nunca duplica.
    Campos que só a versão nova conhece (oco, níveis...) que faltam no registro vencedor vêm do outro.
    Stop móvel presente nos dois aparelhos sem ter sido executado: vale o maior stop e a união dos níveis (o stop
    só sobe, então cada aparelho pode ter calculado níveis diferentes)."""
    itens = {m["id"]: m for m in remoto}
    for m in local:
        o = itens.get(m["id"])
        if o is None:
            itens[m["id"]] = m
            continue
        if _precedencia(m) != _precedencia(o):
            vencedora, perdedora = (m, o) if _precedencia(m) > _precedencia(o) else (o, m)
        else:
            vencedora = _escolher(m, o)
            perdedora = o if vencedora is m else m
        itens[m["id"]] = _completar_meta(vencedora, perdedora)
        if (m.get("gatilho") == "stop" and o.get("gatilho") == "stop" and m.get("movel") and o.get("movel")
                and m.get("status") != "executada" and o.get("status") != "executada"):
            niveis = _unir_niveis(m.get("niveis"), o.get("niveis"))
            itens[m["id"]] = {**itens[m["id"]], "niveis": niveis,
                              "stop_atual": max([n["stop"] for n in niveis] + [m["stop_atual"], o["stop_atual"]])}
    return sorted(itens.values(), key=lambda m: (m["criada_em"], m["id"]))


def _execucao_antes(a, b):
    """Ordem (-1, 0 ou 1) das execuções de duas metas do mesmo OCO: a data; na mesma data, o horário da barra
    (barra_ts quando as duas têm, senão a hora, se as duas têm); persistindo o empate, o stop vence (é o
    cenário conservador) e por fim o id."""
    ea, eb = a.get("execucao") or {}, b.get("execucao") or {}
    ta, tb = ea.get("barra_ts") or 0, eb.get("barra_ts") or 0
    ha, hb = ea.get("hora") or "", eb.get("hora") or ""
    for x, y in ((ea.get("data", ""), eb.get("data", "")), (ta, tb) if ta > 0 and tb > 0 else (0, 0),
                 (ha, hb) if ha and hb else ("", ""),
                 (0 if a.get("gatilho") == "stop" else 1, 0 if b.get("gatilho") == "stop" else 1), (a["id"], b["id"])):
        if x != y:
            return -1 if x < y else 1
    return 0


def resolver_oco(meses, metas, avisos=None):
    """Dois aparelhos podem executar lados opostos do mesmo OCO. Se as duas metas do grupo estão "executada",
    fica a de execução mais cedo (empate: o stop); a outra vira "cancelada" (com mod novo, para valer na
    sincronização) e a venda automática dela é removida, com registro de exclusão. Se essa venda está num mês
    fechado ela fica, a meta é cancelada com a explicação e o texto vai para `avisos` (lista, se dada): o ajuste
    é manual. meses: {mês: dados}; altera meses e metas no lugar. Retorna o conjunto de meses alterados."""
    grupos = defaultdict(list)
    for m in metas:
        if m.get("oco") and m.get("status") == "executada":
            grupos[m["oco"]].append(m)
    alterados = set()
    for membros in grupos.values():
        if len(membros) < 2:
            continue
        membros.sort(key=cmp_to_key(_execucao_antes))
        vencedora = membros[0]
        for perdedora in membros[1:]:
            ex = vencedora.get("execucao") or {}
            quando = f"{ex['data'][8:10]}/{ex['data'][5:7]}" if ex.get("data") else "?"
            detalhe = ("Cancelada automaticamente (OCO): "
                       f"{'stop' if vencedora.get('gatilho') == 'stop' else 'alvo'} executado em {quando}")
            vid = "auto-" + perdedora["id"]
            for mes, d in meses.items():
                for l in d["lotes"]:
                    if not any(v["id"] == vid for v in l["vendas"]):
                        continue
                    if d.get("fechado"):
                        detalhe += (f". A venda duplicada ficou em {fmt_mes(mes)}, mês fechado, e precisa de ajuste "
                                    "manual")
                        if avisos is not None:
                            avisos.append(f"{perdedora['ticker']}: a venda automática duplicada ficou no mês "
                                          f"fechado {fmt_mes(mes)} e não foi removida. Ajuste manual necessário.")
                        continue
                    l["vendas"] = [v for v in l["vendas"] if v["id"] != vid]
                    d.setdefault("excluidos", {})[vid] = agora()
                    alterados.add(mes)
            perdedora["status"] = "cancelada"
            perdedora.pop("ultimo_erro", None)
            perdedora.pop("execucao", None)
            perdedora["cancelada_por"] = vencedora["id"]
            perdedora["cancelada_detalhe"] = detalhe
            perdedora["mod"] = agora()
    return alterados


def mesclar_tudo(remoto, cfg, metas_r=None, avisos=None):
    """Mescla os dados da planilha com os locais e grava o resultado. Retorna True se algo local mudou.
    metas_r: metas da planilha (reconstruir_metas). avisos: lista que recebe os textos para o usuário (venda
    duplicada de OCO em mês fechado, que precisa de ajuste manual)."""
    meses_r, amigos_r, radar_r, excl_r = remoto[:4]
    caixa_r = remoto[4] if len(remoto) > 4 else None
    mudou = False
    with TRAVA:
        mesclados = {}
        for mes in sorted(set(listar_meses()) | set(meses_r)):
            local = carregar(mes) if arquivo(mes).exists() else None
            texto_local = json.dumps(local, sort_keys=True) if local is not None else None
            mesclados[mes] = (texto_local, mesclar_mes(local, meses_r.get(mes)))
        metas_l = sorted(cfg.get("metas", []), key=lambda m: (m["criada_em"], m["id"]))
        texto_metas = json.dumps(metas_l, sort_keys=True)
        metas = mesclar_metas(metas_l, metas_r or [])
        deduplicar_auto({mes: novo for mes, (_, novo) in mesclados.items()})
        resolver_oco({mes: novo for mes, (_, novo) in mesclados.items()}, metas, avisos)
        for mes, (texto_local, novo) in mesclados.items():
            if texto_local is None or json.dumps(novo, sort_keys=True) != texto_local:
                salvar(novo, carimbar=False)
                mudou = True
        excl = dict(excl_r)
        for k, t in cfg.get("excluidos", {}).items():
            excl[k] = max(t, excl.get(k, 0))
        amigos = mesclar_lista(cfg.get("amigos", []), amigos_r, "email", excl, "amigos")
        radar = ordenar_radar(mesclar_lista(cfg.get("radar", []), radar_r, "ticker", excl, "radar"))
        antes = json.dumps([cfg.get("amigos"), cfg.get("radar"), cfg.get("excluidos")], sort_keys=True)
        cfg["amigos"], cfg["radar"], cfg["excluidos"] = amigos, radar, excl
        if json.dumps([amigos, radar, excl], sort_keys=True) != antes:
            mudou = True
        if json.dumps(metas, sort_keys=True) != texto_metas:
            mudou = True
        cfg["metas"] = metas
        if caixa_r and caixa_r.get("mod", 0) > (cfg.get("caixa") or {}).get("mod", 0):
            cfg["caixa"] = caixa_r
            mudou = True
        gravar_config(cfg, carimbar=False)
        if corrigir_tipos():
            mudou = True
    return mudou
