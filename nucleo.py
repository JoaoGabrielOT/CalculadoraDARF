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


CONFIG_PADRAO = {"tema": "Dark", "amigos": [], "radar": [], "planilhas": {}, "pendente": False, "excluidos": {}}


def ler_config():
    try:
        cfg = json.loads(CONFIG.read_text(encoding="utf-8"))
    except Exception:
        cfg = {}
    for k, v in CONFIG_PADRAO.items():
        cfg.setdefault(k, json.loads(json.dumps(v)))
    return cfg


def _chave_lista(nome):
    return "email" if nome == "amigos" else "ticker"


def gravar_config(cfg, carimbar=True):
    """Grava a configuração, marcando a hora de alteração dos amigos e do radar."""
    with TRAVA:
        cfg.setdefault("excluidos", {})
        if carimbar:
            t = agora()
            try:
                antigo = json.loads(CONFIG.read_text(encoding="utf-8"))
            except Exception:
                antigo = {}
            for nome in ("amigos", "radar"):
                k = _chave_lista(nome)
                ant = {x[k]: x for x in antigo.get(nome, [])}
                atuais = set()
                for x in cfg.get(nome, []):
                    atuais.add(x[k])
                    o = ant.get(x[k])
                    if o is None or _campos(o) != _campos(x):
                        x["mod"] = t
                    x.setdefault("mod", 0)
                for chave in set(ant) - atuais:
                    cfg["excluidos"][f"{nome}:{chave}"] = t
        CONFIG.write_text(json.dumps(cfg, ensure_ascii=False, indent=2), encoding="utf-8")


# ---------------------------------------------------------------- regras

def vendido(lote):
    return sum(v["qtd"] for v in lote["vendas"])


def restante(lote):
    return lote["qtd"] - vendido(lote)


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


def inferir_tipo(ticker, conhecidos=None):
    if conhecidos and ticker in conhecidos:
        return conhecidos[ticker]
    m = re.fullmatch(r"[A-Z]{4}(\d{2})", ticker)
    return "BDR" if m and m.group(1) in ("31", "32", "33", "34", "35", "39") else "Ação"


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
    lista_radar = [[r["ticker"], r.get("nome", ""), serial(r["desde"]), r.get("mod", 0)] for r in cfg.get("radar", [])]
    return {"Resumo": resumo, "Compras": compras, "Vendas": vendas, "Amigos": lista_amigos,
            "Radar": lista_radar, "Exclusões": excl}


def reconstruir(abas):
    """Converte as linhas da planilha em (meses, amigos, radar, exclusões da configuração)."""
    larguras = {"Resumo": 13, "Compras": 13, "Vendas": 17, "Amigos": 3, "Radar": 4, "Exclusões": 4}
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
            radar.append({"ticker": ticker, "nome": str(row[1] or ""), "desde": desde, "mod": _num(row[3])})
    return meses, amigos, radar, excl_cfg


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


def mesclar_lista(local, remoto, chave, excl, prefixo):
    itens = {x[chave]: x for x in remoto}
    for x in local:
        itens[x[chave]] = _escolher(x, itens.get(x[chave]))
    return [x for k, x in itens.items() if excl.get(f"{prefixo}:{k}", -1) < x.get("mod", 0)]


def mesclar_tudo(remoto, cfg):
    """Mescla os dados da planilha com os locais e grava o resultado. Retorna True se algo local mudou."""
    meses_r, amigos_r, radar_r, excl_r = remoto
    mudou = False
    with TRAVA:
        for mes in sorted(set(listar_meses()) | set(meses_r)):
            local = carregar(mes) if arquivo(mes).exists() else None
            novo = mesclar_mes(local, meses_r.get(mes))
            if local is None or json.dumps(novo, sort_keys=True) != json.dumps(local, sort_keys=True):
                salvar(novo, carimbar=False)
                mudou = True
        excl = dict(excl_r)
        for k, t in cfg.get("excluidos", {}).items():
            excl[k] = max(t, excl.get(k, 0))
        amigos = mesclar_lista(cfg.get("amigos", []), amigos_r, "email", excl, "amigos")
        radar = mesclar_lista(cfg.get("radar", []), radar_r, "ticker", excl, "radar")
        antes = json.dumps([cfg.get("amigos"), cfg.get("radar"), cfg.get("excluidos")], sort_keys=True)
        cfg["amigos"], cfg["radar"], cfg["excluidos"] = amigos, radar, excl
        if json.dumps([amigos, radar, excl], sort_keys=True) != antes:
            mudou = True
        gravar_config(cfg, carimbar=False)
    return mudou
