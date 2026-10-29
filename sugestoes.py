"""Sugestão de alvo e stop por volatilidade (ATR), para as metas de venda automática.

Compartilhado entre a versão Windows (calculadora_darf.py) e a versão Android (android/main.py).

Barras: lista de {"data": date, "abre": float|None, "alta", "baixa", "fech"} só de pregões fechados e em ordem
(mercado.barras_diarias; sugerir() descarta a barra de hoje, que ainda está parcial).

Swing:     stop inicial = compra − 2·ATR(14); stop móvel (Chandelier) = máxima de 22 pregões − 3·ATR(22);
           stop sugerido = o maior dos dois (arredondado para baixo no centavo);
           alvo = compra + 2·(compra − stop inicial) (relação risco/retorno 1:2, arredondado para cima).
Day trade: stop = o maior entre o suporte S1 do pregão anterior e compra − ATR(14), desde que abaixo da compra;
           alvo = resistência R1 se ela der pelo menos o mesmo ganho que o risco, senão compra + 2·risco.
"""
from datetime import date

import mercado as mk
import metas as mt
import nucleo as nc

MIN_BARRAS = 15                 # ATR(14) precisa de 15 fechamentos
MULT_STOP_SWING = 2
MULT_CHANDELIER = 3
PERIODO_CHANDELIER = 22
RR = 2
MULT_STOP_DT = 1
LIMITE_RISCO = 0.02             # perda máxima de uma operação: 2% do patrimônio
LIMITE_MES = 0.06               # perda máxima no mês: 6% do patrimônio
AVISO_SUGESTAO = ("Sugestão baseada na volatilidade (ATR); não é recomendação de investimento e não há garantia "
                  "de resultado.")
AVISO_PROVENTOS = ("Os preços do Yahoo não são ajustados por proventos: na data-ex de um dividendo o preço cai e "
                   "pode disparar o stop.")
AVISO_GAP = ("Em gap de baixa o app registra a abertura como pior preço plausível; na corretora um stop limitado "
             "pode nem executar.")


class SemSugestao(Exception):
    pass


def _series(barras):
    return [b["alta"] for b in barras], [b["baixa"] for b in barras], [b["fech"] for b in barras]


def _fmt_dec(v, casas=1):
    return f"{v:.{casas}f}".replace(".", ",")


# ---------------------------------------------------------------- sugestões

def sugestao_swing(compra, barras):
    """Stop e alvo de swing trade a partir de pregões fechados. Levanta SemSugestao sem dados ou sem volatilidade."""
    altas, baixas, fechs = _series(barras)
    atr14 = mk.calcular_atr(altas, baixas, fechs, 14)
    if atr14 is None:
        raise SemSugestao("Histórico insuficiente: faltam pregões para calcular o ATR.")
    stop_inicial = compra - MULT_STOP_SWING * atr14
    if atr14 <= 0 or compra - stop_inicial <= 0:
        raise SemSugestao("Volatilidade zero, sem sugestão.")
    atr22 = mk.calcular_atr(altas, baixas, fechs, PERIODO_CHANDELIER)
    chandelier = mk.calcular_chandelier(barras, PERIODO_CHANDELIER, MULT_CHANDELIER)
    stop = mt.piso_centavo(max(stop_inicial, chandelier) if chandelier is not None else stop_inicial)
    if stop < 0.01:
        raise SemSugestao("Volatilidade alta demais para o preço da compra: o stop ficaria abaixo de R$ 0,01.")
    alvo = mt.teto_centavo(compra + RR * (compra - stop_inicial))
    return {"modo": "swing", "atr14": atr14, "atr22": atr22, "stop_inicial": stop_inicial, "chandelier": chandelier,
            "stop": stop, "alvo": alvo, "movel_disponivel": chandelier is not None,
            "base_data": barras[-1]["data"]}


def sugestao_day_trade(compra, dia_anterior, atr14):
    """Stop e alvo de day trade com os pivôs do pregão anterior (dia_anterior = barra) e o ATR(14)."""
    if not atr14 or atr14 <= 0:
        raise SemSugestao("Volatilidade zero, sem sugestão.")
    p = mk.calcular_pivos(dia_anterior["alta"], dia_anterior["baixa"], dia_anterior["fech"])
    candidato = max(p["s1"], compra - MULT_STOP_DT * atr14)
    stop = candidato if candidato < compra else compra - MULT_STOP_DT * atr14
    risco = compra - stop
    if risco <= 0:
        raise SemSugestao("Volatilidade zero, sem sugestão.")
    stop = mt.piso_centavo(stop)
    if stop < 0.01:
        raise SemSugestao("Volatilidade alta demais para o preço da compra: o stop ficaria abaixo de R$ 0,01.")
    alvo = p["r1"] if p["r1"] > compra and (p["r1"] - compra) >= risco else compra + RR * risco
    return {"modo": "day_trade", "atr14": atr14, "atr22": None, "pp": p["pp"], "r1": p["r1"], "s1": p["s1"],
            "stop": stop, "alvo": mt.teto_centavo(alvo), "movel_disponivel": False,
            "base_data": dia_anterior["data"]}


def sugerir(lote, barras, hoje, preco_atual):
    """Sugestão para uma compra aberta. Usa só os pregões anteriores a `hoje` (date). É day trade quando a compra
    foi feita hoje. Levanta SemSugestao (a mensagem explica o motivo). Retorna a sugestão com "preco_atual",
    "stop_valido" (o stop está abaixo da cotação), "alvo_imediato" (o alvo já está na cotação ou abaixo) e
    "avisos" (textos)."""
    fechadas = sorted((b for b in barras if b["data"] < hoje), key=lambda b: b["data"])
    if len(fechadas) < MIN_BARRAS:
        raise SemSugestao(f"Histórico insuficiente: {len(fechadas)} pregões fechados (mínimo {MIN_BARRAS}).")
    compra = lote["preco"]
    if preco_atual and (compra > 3 * preco_atual or compra < preco_atual / 3):
        raise SemSugestao("O preço da compra está muito longe da cotação (possível desdobramento ou grupamento): "
                          "sem sugestão.")
    if lote["data_compra"] == hoje.isoformat():
        altas, baixas, fechs = _series(fechadas)
        sug = sugestao_day_trade(compra, fechadas[-1], mk.calcular_atr(altas, baixas, fechs, 14))
    else:
        sug = sugestao_swing(compra, fechadas)
    sug["preco_atual"] = preco_atual
    sug["stop_valido"] = not preco_atual or sug["stop"] < preco_atual
    sug["alvo_imediato"] = bool(preco_atual) and sug["alvo"] <= preco_atual
    avisos = []
    if sug["modo"] == "day_trade":
        avisos.append("Day trade: se a venda não ocorrer hoje, a operação passa a ser swing e esta sugestão "
                      "deixa de valer.")
    elif not sug["movel_disponivel"]:
        avisos.append("Stop móvel indisponível: o histórico tem menos de 23 pregões fechados.")
    if not sug["stop_valido"]:
        avisos.append("Preço já abaixo do stop sugerido: os botões de stop ficam desativados.")
    if sug["alvo_imediato"]:
        avisos.append("O alvo sugerido não está acima da cotação: a meta executaria na próxima barra ao preço "
                      "do alvo.")
    sug["avisos"] = avisos
    return sug


def avaliar(lote, qtd, sug, preco_atual, day_trade):
    """Projeção líquida (taxas e imposto) de alvo e stop para qtd da compra, distâncias até a cotação e
    relação risco/retorno. perda_stop é o resultado após imposto no stop: negativo (perda, sem imposto) quando o
    stop fica abaixo da compra e positivo (lucro protegido) quando fica acima."""
    pa = mt.projetar(lote, qtd, sug["alvo"], day_trade)
    ps = mt.projetar(lote, qtd, sug["stop"], day_trade)
    compra = lote["preco"]
    risco = compra - sug["stop"]
    lucro, perda = pa["lucro_apos_imposto"], ps["lucro_apos_imposto"]
    return {"proj_alvo": pa, "proj_stop": ps, "lucro_alvo": lucro, "perda_stop": perda,
            "dist_alvo_pct": (sug["alvo"] / preco_atual - 1) * 100 if preco_atual else None,
            "dist_stop_pct": (sug["stop"] / preco_atual - 1) * 100 if preco_atual else None,
            "rr_preco": (sug["alvo"] - compra) / risco if risco > 0 else None,
            "rr_liquido": lucro / abs(perda) if perda < 0 else None}


# ---------------------------------------------------------------- patrimônio e limites

def patrimonio(cfg, cotacoes, hoje=None, meses=None):
    """Patrimônio para a regra dos 2%: caixa projetado + posições abertas a mercado.

    Usa o caixa projetado (e não o disponível) porque ele já desconta a compra ainda não liquidada, que o valor da
    posição também conta. Cada cadeia de cópias de uma compra entra uma vez. cotacoes: {ticker: preço}; posição
    sem cotação fica de fora e é listada em "sem_cotacao". Caixa não definido: só posições.
    Retorna {"valor", "caixa", "posicoes", "caixa_definido", "sem_cotacao"}."""
    if meses is None:
        with nc.TRAVA:
            meses = mt._carregar_meses()
    resumo = nc.resumo_caixa(cfg, hoje, meses)
    posicoes, sem = 0.0, []
    for _, _, lote in mt._lotes_abertos(meses):
        preco = (cotacoes or {}).get(lote["ticker"])
        if not preco:
            if lote["ticker"] not in sem:
                sem.append(lote["ticker"])
            continue
        posicoes += nc.restante(lote) * preco
    caixa = resumo["projetado"] if resumo["definido"] else 0.0
    return {"valor": caixa + posicoes, "caixa": caixa, "posicoes": posicoes, "caixa_definido": resumo["definido"],
            "sem_cotacao": sorted(sem)}


def resumo_patrimonio(cfg, cotacoes, hoje=None):
    """(patrimonio(), resultado do mês de hoje) lendo os meses uma vez só; é o que linhas_rodape() mostra."""
    hoje = hoje or date.today()
    with nc.TRAVA:
        meses = mt._carregar_meses()
    return patrimonio(cfg, cotacoes, hoje, meses), resultado_mes(meses, hoje.strftime("%Y-%m"))


def alerta_risco(resultado, patrimonio):
    """Compara a perda no stop com 2% do patrimônio. resultado: o resultado no stop (negativo = perda); resultado
    zero ou positivo (stop acima da compra) não é risco e nunca alerta. patrimonio: número ou o dict de
    patrimonio(). Retorna {"pct" (perda em % do patrimônio ou None), "limite" (R$), "excede"}."""
    valor = patrimonio["valor"] if isinstance(patrimonio, dict) else patrimonio
    limite = valor * LIMITE_RISCO if valor and valor > 0 else 0.0
    if resultado >= 0:
        return {"pct": None, "limite": limite, "excede": False}
    perda = abs(resultado)
    if not valor or valor <= 0:
        return {"pct": None, "limite": 0.0, "excede": True}
    return {"pct": perda / valor * 100, "limite": limite, "excede": perda > limite}


def resultado_mes(meses, mes):
    """Resultado líquido das vendas do mês (antes do imposto). meses: {mês: dados}."""
    d = meses.get(mes) or {"lotes": []}
    return sum(nc.calcular_venda(l, v)["liquido"] for l in d["lotes"] for v in l["vendas"])


# ---------------------------------------------------------------- texto para as telas

def montar_item(lote, qtd, diarias, pat=None, hoje=None):
    """Tudo o que o cartão de uma compra mostra. diarias: resultado de mercado.barras_diarias, ou a exceção /
    mensagem da consulta que falhou. pat: resultado de patrimonio() (opcional). Retorna o item de linhas_card."""
    item = {"lote": lote, "qtd": qtd, "sug": None, "aval": None, "alerta": None, "erro": None, "preco_atual": None}
    if isinstance(diarias, Exception):
        item["erro"] = mt.mensagem_erro(diarias)
        return item
    if isinstance(diarias, str):
        item["erro"] = diarias
        return item
    hoje = hoje or max(diarias["hoje"], date.today())
    item["preco_atual"] = diarias["preco"]
    try:
        sug = sugerir(lote, diarias["barras"], hoje, diarias["preco"])
    except SemSugestao as e:
        item["erro"] = str(e)
        return item
    item["sug"] = sug
    item["aval"] = avaliar(lote, qtd, sug, diarias["preco"], sug["modo"] == "day_trade")
    if pat is not None:
        item["alerta"] = alerta_risco(item["aval"]["perda_stop"], pat)
    return item


def linhas_card(item):
    """Linhas do cartão de sugestão, iguais nas duas telas: [(rótulo, valor, cor)]. cor: None (texto normal),
    "accent", "danger", "aviso" ou "muted"."""
    if item.get("erro"):
        return [("Sugestão", item["erro"], "muted")]
    sug, av, atual = item["sug"], item["aval"], item.get("preco_atual")
    swing = sug["modo"] == "swing"
    linhas = [("Modo", f"{'Swing' if swing else 'Day trade'} · ATR(14) {nc.brl(sug['atr14'])} · "
                       f"pregão de {nc.fmt_data(sug['base_data'].isoformat())}", None)]
    if atual:
        linhas.append(("Cotação", f"{nc.brl(atual)} · compra {nc.brl(item['lote']['preco'])}", None))
    linhas.append(("Alvo sugerido", f"{nc.brl(sug['alvo'])} ({mk.fmt_pct(av['dist_alvo_pct'])} da cotação) · "
                                    f"lucro líquido {nc.brl(av['lucro_alvo'])}", "accent"))
    if swing:
        linhas.append(("Stop inicial", f"{nc.brl(sug['stop_inicial'])} (compra − {MULT_STOP_SWING}×ATR)", None))
        linhas.append(("Stop móvel", f"{nc.brl(sug['chandelier'])} (máxima de {PERIODO_CHANDELIER} pregões − "
                                     f"{MULT_CHANDELIER}×ATR, só sobe)" if sug["chandelier"] is not None
                                     else "indisponível (histórico curto)", None))
    else:
        linhas.append(("Pivôs do dia anterior", f"suporte {nc.brl(sug['s1'])} · pivô {nc.brl(sug['pp'])} · "
                                                f"resistência {nc.brl(sug['r1'])}", None))
    perda = av["perda_stop"] < 0
    linhas.append(("Stop sugerido", f"{nc.brl(sug['stop'])} ({mk.fmt_pct(av['dist_stop_pct'])} da cotação)"
                                    + (f" · perda líquida {nc.brl(av['perda_stop'])}" if perda else ""),
                   "danger" if perda else None))
    if not perda:
        linhas.append(("Lucro protegido no stop", f"lucro líquido após imposto {nc.brl(av['perda_stop'])}", "accent"))
    rr = []
    if av["rr_preco"] is not None:
        rr.append(f"1 : {_fmt_dec(av['rr_preco'])} por preço")
    if av["rr_liquido"] is not None:
        rr.append(f"1 : {_fmt_dec(av['rr_liquido'])} líquido")
    if rr:
        linhas.append(("Risco/retorno", " · ".join(rr), None))
    al = item.get("alerta")
    if al and al["excede"]:
        pct = f"{_fmt_dec(al['pct'], 2)}% do patrimônio" if al["pct"] is not None else "sem patrimônio para comparar"
        linhas.append(("Alerta de risco", f"A perda no stop ({nc.brl(abs(av['perda_stop']))}) é {pct}; o limite de "
                                          f"{_fmt_dec(LIMITE_RISCO * 100, 0)}% é {nc.brl(al['limite'])}.", "danger"))
    elif al and al["pct"] is not None:
        linhas.append(("Risco do stop", f"{_fmt_dec(al['pct'], 2)}% do patrimônio (limite "
                                        f"{_fmt_dec(LIMITE_RISCO * 100, 0)}%)", "muted"))
    for aviso in sug.get("avisos", []):
        linhas.append(("Aviso", aviso, "aviso"))
    return linhas


def linhas_rodape(pat, resultado):
    """Resumo no pé da tela: patrimônio considerado e resultado do mês contra o limite de 6%.
    pat: patrimonio(); resultado: resultado_mes()."""
    linhas = []
    if pat is not None:
        nota = "" if pat["caixa_definido"] else " (caixa não definido: só posições)"
        linhas.append(("Patrimônio considerado", f"{nc.brl(pat['valor'])} = caixa projetado {nc.brl(pat['caixa'])} + "
                                                  f"posições {nc.brl(pat['posicoes'])}{nota}", None))
        if pat["sem_cotacao"]:
            linhas.append(("Sem cotação", ", ".join(pat["sem_cotacao"]) + " (fora do patrimônio)", "aviso"))
        if pat["valor"] > 0:
            pct = resultado / pat["valor"] * 100
            excede = resultado < 0 and -resultado > pat["valor"] * LIMITE_MES
            linhas.append(("Resultado do mês", f"{nc.brl(resultado)} ({mk.fmt_pct(pct)} do patrimônio; limite de "
                                               f"perda {_fmt_dec(LIMITE_MES * 100, 0)}%)", "danger" if excede else None))
            return linhas
    linhas.append(("Resultado do mês", nc.brl(resultado), None))
    return linhas
