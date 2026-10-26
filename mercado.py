import math
import threading
import time
from datetime import date, timedelta

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


def classificar_risco(atr_pct):
    """< 2,2 verde; 2,2 a 3,0 amarelo; acima de 3,0 até 4,5 laranja; acima de 4,5 vermelho."""
    for i, (limite, rotulo, fundo, texto) in enumerate(FAIXAS_RISCO):
        if (atr_pct < limite) if i == 0 else (atr_pct <= limite):
            return rotulo, fundo, texto
    return FAIXAS_RISCO[-1][1:]


def _valido(v):
    return v is not None and not (isinstance(v, float) and math.isnan(v)) and v > 0


class Mercado:
    def __init__(self):
        self._hist = {}
        self._nomes = {}
        self._trava = threading.Lock()

    def limpar(self):
        with self._trava:
            self._hist.clear()

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
                fim = int(agora)
                inicio = fim - DIAS_HISTORICO * 86400
                r = requests.get(f"https://query1.finance.yahoo.com/v8/finance/chart/{ticker}.SA",
                                 params={"period1": inicio, "period2": fim, "interval": "1d"},
                                 headers={"User-Agent": "Mozilla/5.0"}, timeout=20)
                if r.status_code == 429:
                    raise RuntimeError("Too Many Requests")
                if r.status_code == 404:
                    raise SemDados(f"Sem dados para {ticker} no Yahoo Finance.")
                r.raise_for_status()
                res = (r.json().get("chart") or {}).get("result") or []
                if not res:
                    raise SemDados(f"Sem dados para {ticker} no Yahoo Finance.")
                meta = res[0].get("meta", {})
                q = ((res[0].get("indicators") or {}).get("quote") or [{}])[0]
                linhas = [(a, b, c) for a, b, c in zip(q.get("high") or [], q.get("low") or [], q.get("close") or [])
                          if _valido(a) and _valido(b) and _valido(c)]
                if len(linhas) < PERIODOS_ATR + 1:
                    raise SemDados(f"Histórico insuficiente para {ticker}.")
                hi, lo, cl = (list(x) for x in zip(*linhas))
                h = (agora, {"media6m": sum(cl) / len(cl), "atr": calcular_atr(hi, lo, cl), "ultimo": cl[-1],
                             "preco": meta.get("regularMarketPrice"),
                             "nome": meta.get("longName") or meta.get("shortName") or ""})
                self._hist[ticker] = h
            preco = h[1]["preco"] if _valido(h[1]["preco"]) else h[1]["ultimo"]
            nome = nome_conhecido or h[1]["nome"]
            atr = h[1]["atr"]
            atr_pct = atr / preco * 100 if atr and preco else None
            risco = classificar_risco(atr_pct) if atr_pct is not None else None
            return {"ticker": ticker, "nome": nome, "preco": preco, "media6m": h[1]["media6m"],
                    "atr": atr, "atr_pct": atr_pct, "risco": risco, "hora": time.time()}

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
                h = (agora, {"media6m": sum(cl) / len(cl), "atr": calcular_atr(hi, lo, cl), "ultimo": cl[-1]})
                self._hist[ticker] = h

            preco = None
            try:
                preco = float(t.fast_info.last_price)
            except Exception:
                preco = None
            if not _valido(preco):
                preco = h[1]["ultimo"]

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
            return {"ticker": ticker, "nome": nome, "preco": preco, "media6m": h[1]["media6m"],
                    "atr": atr, "atr_pct": atr_pct, "risco": risco, "hora": time.time()}
