import math
import threading
import time
from datetime import date, datetime, timedelta

TTL_HISTORICO = 30 * 60     # segundos
DIAS_HISTORICO = 180
PERIODOS_ATR = 14

FAIXAS_RISCO = [
    (2.2, "Menor Risco", "#10b981", "#ffffff"),
    (3.0, "Médio Risco", "#f59e0b", "#1f2937"),
    (4.5, "Alto Risco", "#f97316", "#ffffff"),
    (math.inf, "Alto Risco / Muito Alto", "#ef4444", "#ffffff"),
]


class SemDados(Exception):
    pass


def calcular_atr(maximas, minimas, fechamentos, n=PERIODOS_ATR):
    """ATR de Wilder: média móvel suavizada do True Range."""
    trs = [max(maximas[i] - minimas[i], abs(maximas[i] - fechamentos[i - 1]), abs(minimas[i] - fechamentos[i - 1]))
           for i in range(1, len(fechamentos))]
    if len(trs) < n:
        return None
    atr = sum(trs[:n]) / n
    for tr in trs[n:]:
        atr = (atr * (n - 1) + tr) / n
    return atr


def calcular_pivos(alta, baixa, fech):
    """Pontos de pivô clássicos do pregão: PP=(H+L+C)/3, R1=2·PP−L (resistência), S1=2·PP−H (suporte)."""
    pp = (alta + baixa + fech) / 3
    return {"pp": pp, "r1": 2 * pp - baixa, "s1": 2 * pp - alta}


def calcular_chandelier(barras, n=22, mult=3):
    """Chandelier Exit: máxima das últimas n barras − mult × ATR(n) de Wilder. barras: dicts com alta, baixa e
    fech, em ordem. Retorna None com menos de n+1 barras."""
    if len(barras) < n + 1:
        return None
    atr = calcular_atr([b["alta"] for b in barras], [b["baixa"] for b in barras], [b["fech"] for b in barras], n)
    if atr is None:
        return None
    return max(b["alta"] for b in barras[-n:]) - mult * atr


def serie_chandelier(barras, n=22, mult=3):
    """Chandelier Exit de cada prefixo de barras em uma só passada: o item i é igual a
    calcular_chandelier(barras[:i + 1], n, mult) (None enquanto faltam barras)."""
    saida = [None] * len(barras)
    atr, trs, anterior = None, [], None
    for i, b in enumerate(barras):
        if i >= 1:
            tr = max(b["alta"] - b["baixa"], abs(b["alta"] - anterior["fech"]), abs(b["baixa"] - anterior["fech"]))
            trs.append(tr)
            if i == n:
                atr = sum(trs) / n      # a mesma semente de calcular_atr (média simples dos n primeiros)
            elif i > n:
                atr = (atr * (n - 1) + tr) / n
        anterior = b
        if atr is not None:
            saida[i] = max(x["alta"] for x in barras[i - n + 1:i + 1]) - mult * atr
    return saida


def classificar_risco(atr_pct):
    """< 2,2 verde; 2,2 a 3,0 amarelo; acima de 3,0 até 4,5 laranja; acima de 4,5 vermelho."""
    for i, (limite, rotulo, fundo, texto) in enumerate(FAIXAS_RISCO):
        if (atr_pct < limite) if i == 0 else (atr_pct <= limite):
            return rotulo, fundo, texto
    return FAIXAS_RISCO[-1][1:]


def _valido(v):
    return v is not None and not (isinstance(v, float) and math.isnan(v)) and v > 0


URL_CHART = "https://query1.finance.yahoo.com/v8/finance/chart/{t}.SA"
UA = {"User-Agent": "Mozilla/5.0"}

# período do gráfico -> (range e intervalo do Yahoo, validade do cache em segundos)
PERIODOS_GRAFICO = {
    "1D": ("1d", "5m", 60), "5D": ("5d", "30m", 120), "1M": ("1mo", "1d", 900), "6M": ("6mo", "1d", 1800),
    "1A": ("1y", "1d", 1800), "5A": ("5y", "1wk", 3600), "Máx": ("max", "1mo", 3600),
}


def variacao(preco, anterior):
    """(variação em R$, variação %) em relação ao fechamento anterior."""
    if not _valido(preco) or not _valido(anterior):
        return None, None
    return preco - anterior, (preco / anterior - 1) * 100


def anterior_de(pares, dia_atual):
    """Último fechamento de um pregão anterior ao dia atual do mercado; pares = [(data, fechamento)]."""
    antes = [c for d, c in sorted(pares) if d < dia_atual]
    return antes[-1] if antes else None


def _get_chart(ticker, params):
    import requests
    r = requests.get(URL_CHART.format(t=ticker), params=params, headers=UA, timeout=20)
    if r.status_code == 429:
        raise RuntimeError("Too Many Requests")
    if r.status_code == 404:
        raise SemDados(f"Sem dados para {ticker} no Yahoo Finance.")
    r.raise_for_status()
    res = (r.json().get("chart") or {}).get("result") or []
    if not res:
        raise SemDados(f"Sem dados para {ticker} no Yahoo Finance.")
    return res[0]


def intervalos_historico(dias):
    """Intervalos do Yahoo a tentar, do mais fino ao mais grosso, conforme a idade do período pedido:
    1m cobre até 7 dias por consulta, 5m/15m até 60 dias, 1h até ~2 anos e 1d sem limite."""
    if dias <= 7:
        return ["1m", "5m", "15m", "1h", "1d"]
    if dias <= 60:
        return ["5m", "15m", "1h", "1d"]
    if dias <= 700:
        return ["1h", "1d"]
    return ["1d"]


def historico_desde(ticker, desde, agora=None):
    """Máximas, mínimas e aberturas das barras do Yahoo desde `desde` (datetime; sem fuso vale Brasília), no
    intervalo mais fino disponível. Retorna {"barras": [{"ts", "dt" (datetime com fuso), "alta", "baixa", "abre"}],
    "fonte", "intervalo"}; baixa e abre ficam None quando o Yahoo não as informa. Levanta SemDados se não houver
    nenhuma barra. Executar fora da thread da interface."""
    from datetime import datetime, timezone
    fuso_padrao = timezone(timedelta(hours=-3))
    if desde.tzinfo is None:
        desde = desde.replace(tzinfo=fuso_padrao)
    agora = agora or datetime.now(timezone.utc)
    dias = (agora - desde).total_seconds() / 86400
    ultimo = None
    for intervalo in intervalos_historico(max(dias, 0)):
        inicio = int(desde.timestamp()) - (86400 if intervalo in ("1h", "1d") else 0)
        try:
            res = _get_chart(ticker, {"period1": inicio, "period2": int(agora.timestamp()) + 60,
                                      "interval": intervalo, "includePrePost": "false"})
        except SemDados as e:
            ultimo = e
            continue
        tz = timezone(timedelta(seconds=(res.get("meta") or {}).get("gmtoffset") or -10800))
        q = ((res.get("indicators") or {}).get("quote") or [{}])[0]
        baixas, aberturas = q.get("low") or [], q.get("open") or []

        def campo(lista, i):
            return float(lista[i]) if i < len(lista) and _valido(lista[i]) else None
        barras = [{"ts": ts, "dt": datetime.fromtimestamp(ts, tz), "alta": float(a), "baixa": campo(baixas, i),
                   "abre": campo(aberturas, i)}
                  for i, (ts, a) in enumerate(zip(res.get("timestamp") or [], q.get("high") or [])) if _valido(a)]
        if barras:
            return {"barras": barras, "fonte": "Yahoo Finance", "intervalo": intervalo}
    raise ultimo or SemDados(f"Sem histórico de {ticker} desde {desde:%d/%m/%Y %H:%M}.")


_DIARIAS = {}                  # (ticker, range) -> (hora, resultado)
_TRAVA_DIARIAS = threading.Lock()
VALIDADE_DIARIAS = 15 * 60     # segundos


def _range_diarias(desde):
    """Menor range do Yahoo que cobre `desde` com 60 dias de folga (para o ATR e o Chandelier)."""
    if desde is None:
        return "6mo"
    if isinstance(desde, datetime):
        desde = desde.date()
    dias = (date.today() - desde).days + 60
    for limite, alcance in ((180, "6mo"), (365, "1y"), (730, "2y")):
        if dias <= limite:
            return alcance
    return "5y"


def barras_diarias(ticker, desde=None):
    """Barras diárias (ordem crescente) do Yahoo, a mesma fonte no Windows e no Android. `desde` (date ou
    datetime) amplia o período para cobrir a data. Retorna {"barras": [{"data": date, "abre", "alta", "baixa",
    "fech"}], "hoje" (data do último pregão em andamento), "preco", "fonte"}; as barras incluem a de hoje, ainda
    parcial, quando existe. Cache de 15 minutos. Levanta SemDados. Executar fora da thread da interface."""
    alcance = _range_diarias(desde)
    chave = (ticker, alcance)
    agora = time.time()
    with _TRAVA_DIARIAS:
        c = _DIARIAS.get(chave)
        if c and agora - c[0] < VALIDADE_DIARIAS:
            return c[1]
    from datetime import datetime, timezone
    res = _get_chart(ticker, {"range": alcance, "interval": "1d", "includePrePost": "false"})
    meta = res.get("meta") or {}
    desvio = meta.get("gmtoffset") or 0
    q = ((res.get("indicators") or {}).get("quote") or [{}])[0]
    listas = [q.get(k) or [] for k in ("open", "high", "low", "close")]
    barras = []
    for i, ts in enumerate(res.get("timestamp") or []):
        abre, alta, baixa, fech = (float(l[i]) if i < len(l) and _valido(l[i]) else None for l in listas)
        if alta is None or baixa is None or fech is None:
            continue
        barras.append({"data": datetime.fromtimestamp(ts + desvio, timezone.utc).date(), "abre": abre,
                       "alta": alta, "baixa": baixa, "fech": fech})
    if not barras:
        raise SemDados(f"Sem dados para {ticker} no Yahoo Finance.")
    t_mercado = meta.get("regularMarketTime")
    hoje = datetime.fromtimestamp(t_mercado + desvio, timezone.utc).date() if t_mercado else barras[-1]["data"]
    preco = meta.get("regularMarketPrice")
    out = {"barras": barras, "hoje": hoje, "preco": float(preco) if _valido(preco) else barras[-1]["fech"],
           "fonte": "Yahoo Finance"}
    with _TRAVA_DIARIAS:
        _DIARIAS[chave] = (agora, out)
    return out


def _extras(dados, hi, lo, cl, anterior, mercado=None):
    """Variação do dia, mínima/máxima de 6 meses e distância até a média; mercado = máxima/mínima do dia,
    de 52 semanas e volume, quando o Yahoo informa."""
    preco = dados["preco"]
    var, var_pct = variacao(preco, anterior)
    media = dados["media6m"]
    dados.update({"anterior": anterior, "var": var, "var_pct": var_pct, "min6m": min(lo), "max6m": max(hi),
                  "var6m_pct": (preco / cl[0] - 1) * 100 if _valido(preco) and _valido(cl[0]) else None,
                  "vs_media_pct": (preco / media - 1) * 100 if _valido(preco) and _valido(media) else None})
    for k, v in (mercado or {}).items():
        dados[k] = float(v) if _valido(v) else None
    return dados


class Mercado:
    def __init__(self):
        self._hist = {}
        self._nomes = {}
        self._graficos = {}
        self._trava = threading.Lock()

    def limpar(self):
        with self._trava:
            self._hist.clear()

    def cotacao(self, ticker):
        """Preço atual (com o atraso do Yahoo). Executar fora da thread da interface."""
        try:
            import yfinance as yf
        except ImportError:
            yf = None
        if yf is not None:
            t = yf.Ticker(f"{ticker}.SA")
            try:
                preco = float(t.fast_info.last_price)
            except Exception:
                preco = None
            if not _valido(preco):
                df = t.history(period="5d", interval="1d", auto_adjust=False)
                if df is None or df.empty:
                    raise SemDados(f"Sem cotação para {ticker}.")
                preco = float(df["Close"].dropna().tolist()[-1])
            return preco
        import requests
        r = requests.get(f"https://query1.finance.yahoo.com/v8/finance/chart/{ticker}.SA",
                         params={"range": "5d", "interval": "1d"}, headers={"User-Agent": "Mozilla/5.0"}, timeout=20)
        if r.status_code == 429:
            raise RuntimeError("Too Many Requests")
        if r.status_code == 404:
            raise SemDados(f"Sem cotação para {ticker}.")
        r.raise_for_status()
        res = (r.json().get("chart") or {}).get("result") or []
        if not res:
            raise SemDados(f"Sem cotação para {ticker}.")
        preco = res[0].get("meta", {}).get("regularMarketPrice")
        if not _valido(preco):
            fech = [c for c in ((res[0].get("indicators") or {}).get("quote") or [{}])[0].get("close") or [] if _valido(c)]
            if not fech:
                raise SemDados(f"Sem cotação para {ticker}.")
            preco = fech[-1]
        return float(preco)


    def preco_venda(self, ticker, dia):
        """Preço sugerido para uma venda: a cotação atual quando a data é hoje; senão, o fechamento do dia
        (ou do último pregão antes dele). Executar fora da thread da interface."""
        if dia >= date.today():
            return self.cotacao(ticker), "Cotação atual"
        preco, dia_real = self.fechamento(ticker, dia)
        return preco, f"Fechamento de {dia_real:%d/%m/%Y}"

    def fechamento(self, ticker, dia):
        inicio, fim = dia - timedelta(days=10), dia + timedelta(days=1)
        try:
            import yfinance as yf
        except ImportError:
            yf = None
        if yf is not None:
            df = yf.Ticker(f"{ticker}.SA").history(start=inicio.isoformat(), end=fim.isoformat(), interval="1d",
                                                   auto_adjust=False)
            pares = [] if df is None or df.empty else [
                (idx.date(), float(c)) for idx, c in df["Close"].dropna().items()]
        else:
            import requests
            from datetime import datetime, timezone
            p1 = int(datetime(inicio.year, inicio.month, inicio.day, tzinfo=timezone.utc).timestamp())
            p2 = int(datetime(fim.year, fim.month, fim.day, tzinfo=timezone.utc).timestamp()) + 86400
            r = requests.get(f"https://query1.finance.yahoo.com/v8/finance/chart/{ticker}.SA",
                             params={"period1": p1, "period2": p2, "interval": "1d"},
                             headers={"User-Agent": "Mozilla/5.0"}, timeout=20)
            if r.status_code == 429:
                raise RuntimeError("Too Many Requests")
            if r.status_code == 404:
                raise SemDados(f"Sem cotação para {ticker}.")
            r.raise_for_status()
            res = (r.json().get("chart") or {}).get("result") or []
            if not res:
                raise SemDados(f"Sem cotação para {ticker}.")
            desvio = (res[0].get("meta") or {}).get("gmtoffset") or 0
            fech = (((res[0].get("indicators") or {}).get("quote") or [{}])[0].get("close")) or []
            pares = [(datetime.fromtimestamp(ts + desvio, timezone.utc).date(), float(c))
                     for ts, c in zip(res[0].get("timestamp") or [], fech) if _valido(c)]
        validos = [(d, c) for d, c in sorted(pares) if d <= dia]
        if not validos:
            raise SemDados(f"Sem fechamento de {ticker} até {dia:%d/%m/%Y}.")
        return validos[-1][1], validos[-1][0]

    def dados(self, ticker, nome_conhecido=""):
        """Executar fora da thread da interface. Usa o yfinance quando instalado (Windows) e a API
        de gráficos do Yahoo diretamente quando não (Android)."""
        try:
            import yfinance  # noqa: F401
        except ImportError:
            return self._dados_api(ticker, nome_conhecido)
        return self._dados_yf(ticker, nome_conhecido)

    def _dados_api(self, ticker, nome_conhecido=""):
        import requests
        with self._trava:
            agora = time.time()
            h = self._hist.get(ticker)
            if not h or agora - h[0] > 60:
                from datetime import datetime, timezone
                fim = int(agora)
                inicio = fim - DIAS_HISTORICO * 86400
                res = _get_chart(ticker, {"period1": inicio, "period2": fim, "interval": "1d"})
                meta = res.get("meta", {})
                desvio = meta.get("gmtoffset") or 0
                q = ((res.get("indicators") or {}).get("quote") or [{}])[0]
                linhas = [(datetime.fromtimestamp(ts + desvio, timezone.utc).date(), a, b, c)
                          for ts, a, b, c in zip(res.get("timestamp") or [], q.get("high") or [], q.get("low") or [],
                                                 q.get("close") or [])
                          if _valido(a) and _valido(b) and _valido(c)]
                if len(linhas) < PERIODOS_ATR + 1:
                    raise SemDados(f"Histórico insuficiente para {ticker}.")
                datas, hi, lo, cl = (list(x) for x in zip(*linhas))
                t_mercado = meta.get("regularMarketTime")
                dia = (datetime.fromtimestamp(t_mercado + desvio, timezone.utc).date() if t_mercado
                       else datas[-1])
                h = (agora, {"media6m": sum(cl) / len(cl), "atr": calcular_atr(hi, lo, cl), "ultimo": cl[-1],
                             "preco": meta.get("regularMarketPrice"),
                             "nome": meta.get("longName") or meta.get("shortName") or "",
                             "anterior": anterior_de(list(zip(datas, cl)), dia), "hi": hi, "lo": lo, "cl": cl,
                             "mercado": {"max_dia": meta.get("regularMarketDayHigh"),
                                         "min_dia": meta.get("regularMarketDayLow"),
                                         "max52": meta.get("fiftyTwoWeekHigh"), "min52": meta.get("fiftyTwoWeekLow"),
                                         "volume": meta.get("regularMarketVolume")}})
                self._hist[ticker] = h
            preco = h[1]["preco"] if _valido(h[1]["preco"]) else h[1]["ultimo"]
            nome = nome_conhecido or h[1]["nome"]
            atr = h[1]["atr"]
            atr_pct = atr / preco * 100 if atr and preco else None
            risco = classificar_risco(atr_pct) if atr_pct is not None else None
            dados = {"ticker": ticker, "nome": nome, "preco": preco, "media6m": h[1]["media6m"],
                     "atr": atr, "atr_pct": atr_pct, "risco": risco, "hora": time.time()}
            return _extras(dados, h[1]["hi"], h[1]["lo"], h[1]["cl"], h[1]["anterior"], h[1]["mercado"])

    def _dados_yf(self, ticker, nome_conhecido=""):
        import yfinance as yf

        with self._trava:
            simbolo = f"{ticker}.SA"
            t = yf.Ticker(simbolo)
            agora = time.time()
            h = self._hist.get(ticker)
            if not h or agora - h[0] > TTL_HISTORICO:
                inicio = (date.today() - timedelta(days=DIAS_HISTORICO)).isoformat()
                df = t.history(start=inicio, interval="1d", auto_adjust=False)
                if df is None or df.empty:
                    raise SemDados(f"Sem dados para {ticker} no Yahoo Finance.")
                df = df.dropna(subset=["High", "Low", "Close"])
                if len(df) < PERIODOS_ATR + 1:
                    raise SemDados(f"Histórico insuficiente para {ticker}.")
                hi = [float(x) for x in df["High"].tolist()]
                lo = [float(x) for x in df["Low"].tolist()]
                cl = [float(x) for x in df["Close"].tolist()]
                try:
                    datas = [idx.date() for idx in df.index]
                except Exception:
                    datas = []
                h = (agora, {"media6m": sum(cl) / len(cl), "atr": calcular_atr(hi, lo, cl), "ultimo": cl[-1],
                             "hi": hi, "lo": lo, "cl": cl, "pares": list(zip(datas, cl))})
                self._hist[ticker] = h

            preco = anterior = None
            try:
                preco = float(t.fast_info.last_price)
            except Exception:
                preco = None
            try:
                anterior = float(t.fast_info.previous_close)
            except Exception:
                anterior = None
            extras = {}
            for chave, campo in (("max_dia", "day_high"), ("min_dia", "day_low"), ("max52", "year_high"),
                                 ("min52", "year_low"), ("volume", "last_volume")):
                try:
                    extras[chave] = getattr(t.fast_info, campo)
                except Exception:
                    extras[chave] = None
            if not _valido(preco):
                preco = h[1]["ultimo"]
            if not _valido(anterior):
                anterior = anterior_de(h[1]["pares"], date.today())

            nome = nome_conhecido or self._nomes.get(ticker)
            if not nome:
                try:
                    info = t.info or {}
                    nome = info.get("longName") or info.get("shortName") or ""
                except Exception:
                    nome = ""
                self._nomes[ticker] = nome

            atr = h[1]["atr"]
            atr_pct = atr / preco * 100 if atr and preco else None
            risco = classificar_risco(atr_pct) if atr_pct is not None else None
            dados = {"ticker": ticker, "nome": nome, "preco": preco, "media6m": h[1]["media6m"],
                     "atr": atr, "atr_pct": atr_pct, "risco": risco, "hora": time.time()}
            return _extras(dados, h[1]["hi"], h[1]["lo"], h[1]["cl"], anterior, extras)

    def grafico(self, ticker, periodo):
        """Pontos (timestamp, fechamento) do período para o gráfico, com o fechamento de referência
        (fechamento anterior no 1D; primeiro ponto nos demais). Executar fora da thread da interface."""
        alcance, intervalo, validade = PERIODOS_GRAFICO[periodo]
        chave = ("g", ticker, periodo)
        agora = time.time()
        c = self._graficos.get(chave)
        if c and agora - c[0] < validade:
            return c[1]
        res = _get_chart(ticker, {"range": alcance, "interval": intervalo, "includePrePost": "false"})
        meta = res.get("meta", {})
        q = ((res.get("indicators") or {}).get("quote") or [{}])[0]
        pontos = [(ts, float(v)) for ts, v in zip(res.get("timestamp") or [], q.get("close") or []) if _valido(v)]
        if len(pontos) < 2:
            raise SemDados(f"Sem dados de {periodo} para {ticker}.")
        preco = meta.get("regularMarketPrice")
        if periodo == "1D":
            ref = meta.get("previousClose") or meta.get("chartPreviousClose") or pontos[0][1]
            if _valido(preco):  # o último ponto intradiário pode estar alguns minutos atrás da cotação
                pontos[-1] = (pontos[-1][0], float(preco))
        else:
            ref = pontos[0][1]
        g = {"ticker": ticker, "periodo": periodo, "pontos": pontos, "referencia": float(ref),
             "desvio": meta.get("gmtoffset") or 0, "intradiario": intervalo.endswith("m")}
        self._graficos[chave] = (agora, g)
        return g


class Cotacoes:
    """Cache das cotações dos ativos em carteira, atualizado em segundo plano."""

    VALIDADE = 60

    def __init__(self, mercado):
        self.mercado = mercado
        self.precos = {}     # ticker -> (preço ou None, hora)
        self._rodando = False
        self._trava = threading.Lock()

    def preco(self, ticker):
        p = self.precos.get(ticker)
        return p[0] if p else None

    def pendentes(self, tickers):
        agora = time.time()
        return sorted(t for t in set(tickers) if t not in self.precos or agora - self.precos[t][1] > self.VALIDADE)

    def atualizar(self, tickers, ao_terminar):
        """Busca as cotações vencidas numa thread e chama ao_terminar() (da thread) se algo mudou."""
        faltam = self.pendentes(tickers)
        with self._trava:
            if not faltam or self._rodando:
                return False
            self._rodando = True

        def trabalho():
            try:
                for t in faltam:
                    try:
                        p = self.mercado.cotacao(t)
                    except Exception:
                        p = self.preco(t)
                    self.precos[t] = (p, time.time())
            finally:
                self._rodando = False
            ao_terminar()

        threading.Thread(target=trabalho, daemon=True).start()
        return True


# ---------------------------------------------------------------- lista do radar (filtros e ordenação)

FILTROS_RADAR = ["Todos", "Em alta", "Em queda", "Em carteira"]
ORDENS_RADAR = [("manual", "Minha ordem"), ("alta", "Maior alta do dia"), ("queda", "Maior queda do dia"),
                ("ticker", "Ticker (A–Z)"), ("risco", "Menor risco (ATR%)"), ("media", "Mais abaixo da média 6m")]


def filtrar_ordenar(itens, dados, filtro="Todos", ordem="manual", custodia=()):
    """Itens do radar (dicts com 'ticker') filtrados e ordenados com as cotações em `dados` (ticker -> dict).
    Ativos ainda sem cotação ficam no fim das ordenações por número."""
    def campo(t, k):
        v = (dados.get(t) or {}).get(k)
        return v if isinstance(v, (int, float)) else None

    if filtro == "Em alta":
        itens = [i for i in itens if (campo(i["ticker"], "var_pct") or 0) > 0]
    elif filtro == "Em queda":
        itens = [i for i in itens if (campo(i["ticker"], "var_pct") or 0) < 0]
    elif filtro == "Em carteira":
        itens = [i for i in itens if i["ticker"] in custodia]
    chave = {"alta": ("var_pct", True), "queda": ("var_pct", False), "risco": ("atr_pct", False),
             "media": ("vs_media_pct", False)}.get(ordem)
    if ordem == "ticker":
        return sorted(itens, key=lambda i: i["ticker"])
    if chave:
        k, desc = chave
        com = [i for i in itens if campo(i["ticker"], k) is not None]
        sem = [i for i in itens if campo(i["ticker"], k) is None]
        return sorted(com, key=lambda i: campo(i["ticker"], k), reverse=desc) + sem
    return list(itens)


def resumo_dia(tickers, dados):
    """(quantos em alta, quantos em queda, variação média do dia em %) dos ativos com cotação."""
    vs = [(dados.get(t) or {}).get("var_pct") for t in tickers]
    vs = [v for v in vs if isinstance(v, (int, float))]
    return sum(v > 0 for v in vs), sum(v < 0 for v in vs), (sum(vs) / len(vs) if vs else None)


def fmt_pct(v, sinal=True):
    if v is None:
        return "—"
    return (f"{v:+.2f}%" if sinal else f"{v:.2f}%").replace(".", ",")


def fmt_volume(v):
    if not v:
        return "—"
    for lim, suf in ((1e9, " bi"), (1e6, " mi"), (1e3, " mil")):
        if v >= lim:
            return f"{v / lim:.1f}".replace(".", ",") + suf
    return str(int(v))
