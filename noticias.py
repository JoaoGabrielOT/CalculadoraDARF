"""Notícias dos ativos do radar (Google Notícias, RSS) e logos das empresas.

Compartilhado entre Windows e Android. As funções de rede devem rodar fora da thread da interface.
"""
import json
import re
import threading
import time
import unicodedata
from html import unescape
from datetime import datetime
from email.utils import parsedate_to_datetime
from urllib.parse import quote, urlparse

import nucleo as nc

URL_RSS = "https://news.google.com/rss/search?q={q}&hl=pt-BR&gl=BR&ceid=BR:pt-419"
URL_LOGO_PNG = "https://raw.githubusercontent.com/thefintz/icones-b3/main/icones/{t}.png"
URL_LOGO_SVG = "https://icons.brapi.dev/icons/{t}.svg"
URL_FAVICON = "https://www.google.com/s2/favicons?domain={d}&sz=64"
UA = {"User-Agent": "Mozilla/5.0 (CalculadoraDARF)"}
INTERVALO = 10 * 60          # segundos entre buscas automáticas
JANELA_NOTIFICACAO = 24 * 3600  # só notifica o que foi publicado nas últimas 24 h
MAX_ITENS = 150
MAX_VISTOS = 3000
MAX_NOTIFICACOES = 3         # acima disso, uma notificação de resumo
VALIDADE_LOGO_AUSENTE = 7 * 86400
TRAVA = threading.RLock()

# (rótulo exibido, expressões já sem acento e em minúsculas)
TEMAS = [
    ("Fato relevante", [r"fato relevante", r"comunicado ao mercado"]),
    ("Resultado", [r"resultado", r"balanco", r"lucro", r"prejuizo", r"ebitda", r"receita liquida", r"guidance",
                   r"\d\s?t\d{2}\b", r"trimestre"]),
    ("Proventos", [r"dividendo", r"\bjcp\b", r"juros sobre (o )?capital", r"provento", r"data.com", r"bonificac"]),
    ("Recomendação", [r"recomendac", r"preco.alvo", r"rebaix", r"eleva .*(recomendac|preco)", r"downgrade",
                      r"upgrade", r"\brating\b", r"compra ou venda", r"carteira recomendada"]),
    ("Fusão/aquisição", [r"aquisic", r"adquir", r"fusao", r"incorporac", r"\bopa\b", r"desinvestimento",
                         r"venda de (ativo|participac|subsidiaria|refinaria)"]),
    ("Oferta/recompra", [r"recompra", r"follow.on", r"oferta (publica|subsequente|de acoes)", r"\bipo\b",
                         r"emissao de (acoes|debentures)"]),
    ("Desdobramento", [r"desdobramento", r"grupamento", r"\bsplit\b", r"inplit"]),
    ("Governança", [r"\bceo\b", r"presidente", r"renuncia", r"conselho de administracao", r"diretor financeiro",
                    r"assembleia"]),
    ("Jurídico", [r"\bcvm\b", r"investigac", r"\bmulta\b", r"recuperacao judicial", r"falencia", r"\bprocesso\b",
                  r"operacao da policia"]),
    ("Forte oscilação", [r"dispara", r"desaba", r"despenca", r"derrete", r"salta", r"\bdisparam", r"tomb[ao]",
                         r"maior (alta|queda)", r"circuit breaker", r"recorde"]),
]
_TEMAS = [(rot, [re.compile(p) for p in pads]) for rot, pads in TEMAS]
SUFIXOS_NOME = re.compile(
    r"\b(inc|corp|corporation|company|co|ltd|limited|plc|holdings?|group|s\.?a|sa|nv|ag|se|pfd|on|pn|unt|"
    r"common stock|class [a-c]|adr|bdr|drn)\b\.?", re.I)


# ---------------------------------------------------------------- texto

def sem_acento(s):
    return "".join(c for c in unicodedata.normalize("NFKD", s or "") if not unicodedata.combining(c)).lower()


def temas(titulo):
    """Temas importantes encontrados no título (vazio = notícia comum)."""
    t = sem_acento(titulo)
    return [rot for rot, pads in _TEMAS if any(p.search(t) for p in pads)]


def nome_busca(nome):
    """Nome curto da empresa para a busca (ex.: 'Apple Inc.' -> 'Apple')."""
    n = re.split(r"\s[-–(]|,", nome or "")[0]
    n = SUFIXOS_NOME.sub(" ", n)
    n = re.sub(r"[^\w&' .]", " ", n)
    n = re.sub(r"\s+", " ", n).strip(" .")
    return n if len(n) >= 3 else ""


def consulta(ticker, nome=""):
    """Ações: só o ticker (nomes como 'Vale' trariam resultados demais). BDRs: ticker ou nome da empresa."""
    q = f'"{ticker}"'
    if nc.tipo_por_ticker(ticker) == "BDR":
        n = nome_busca(nome)
        if n:  # só o nome traria lançamentos de produtos; "ações" mantém o foco no mercado
            q = f'({q} OR "{n}" ações)'
    return q + " when:7d"


RUIDO = re.compile(r"cotacao e indicadores|resultados, dividendos, cotacao|^\S+ \(\w+\) - trademap")


def pertinente(titulo, ticker, nome=""):
    """Descarta páginas de cotação e, nos BDRs, matérias que não citam o ticker nem a empresa no título."""
    t = sem_acento(titulo)
    if RUIDO.search(t) or len(t) < 20:
        return False
    if nc.tipo_por_ticker(ticker) != "BDR":
        return True
    n = sem_acento(nome_busca(nome))
    return ticker.lower() in t or bool(n and re.search(r"\b" + re.escape(n) + r"\b", t))


def dominio(url):
    try:
        d = urlparse(url).netloc.lower()
    except ValueError:
        return ""
    return d[4:] if d.startswith("www.") else d


def url_favicon(item):
    d = dominio(item.get("fonte_url", ""))
    return URL_FAVICON.format(d=d) if d else ""


def tempo_relativo(ts, agora=None):
    s = max(0, (agora or time.time()) - ts)
    if s < 3600:
        return f"há {max(1, int(s // 60))} min"
    if s < 86400:
        return f"há {int(s // 3600)} h"
    dias = int(s // 86400)
    if dias < 7:
        return "há 1 dia" if dias == 1 else f"há {dias} dias"
    return datetime.fromtimestamp(ts).strftime("%d/%m/%Y")


# ---------------------------------------------------------------- RSS

def _itens_xml(xml_texto):
    """(título, link, guid, pubDate, fonte, url da fonte) de cada <item>."""
    try:
        import xml.etree.ElementTree as ET
    except ImportError:  # Python embarcado sem o módulo pyexpat: leitura simples por expressões regulares
        ET = None
    if ET is not None:
        for it in ET.fromstring(xml_texto).iter("item"):
            f = it.find("source")
            yield (it.findtext("title") or "", it.findtext("link") or "", it.findtext("guid") or "",
                   it.findtext("pubDate") or "", (f.text or "") if f is not None else "",
                   f.get("url", "") if f is not None else "")
        return
    txt = xml_texto.decode("utf-8", "replace") if isinstance(xml_texto, bytes) else xml_texto

    def tag(bloco, nome):
        m = re.search(rf"<{nome}\b[^>]*>(.*?)</{nome}>", bloco, re.S)
        return unescape(re.sub(r"^<!\[CDATA\[|\]\]>$", "", m.group(1))) if m else ""

    for bloco in re.findall(r"<item>(.*?)</item>", txt, re.S):
        m = re.search(r'<source[^>]*url="([^"]*)"', bloco)
        yield (tag(bloco, "title"), tag(bloco, "link"), tag(bloco, "guid"), tag(bloco, "pubDate"),
               tag(bloco, "source"), unescape(m.group(1)) if m else "")


def ler_rss(xml_texto, ticker, nome=""):
    """Itens do RSS do Google Notícias: id, título, link, fonte, data (timestamp) e temas."""
    itens = []
    for titulo, link, guid, data, fonte, fonte_url in _itens_xml(xml_texto):
        titulo, link, fonte = titulo.strip(), link.strip(), fonte.strip()
        if not titulo or not link:
            continue
        if fonte and titulo.endswith(" - " + fonte):
            titulo = titulo[: -len(fonte) - 3].rstrip()
        if not pertinente(titulo, ticker, nome):
            continue
        try:
            ts = parsedate_to_datetime(data).timestamp()
        except (TypeError, ValueError):
            ts = time.time()
        itens.append({"id": (guid or link).strip(), "titulo": titulo, "link": link, "fonte": fonte,
                      "fonte_url": fonte_url, "data": ts, "tickers": [ticker], "temas": temas(titulo)})
    return itens


def chave_titulo(titulo):
    return re.sub(r"\W+", "", sem_acento(titulo))[:90]


def mesclar(listas):
    """Junta as notícias de vários ativos: a mesma matéria aparece uma vez, com todos os tickers."""
    por_chave = {}
    for itens in listas:
        for it in itens:
            k = chave_titulo(it["titulo"])
            atual = por_chave.get(k)
            if atual is None:
                por_chave[k] = dict(it, tickers=list(it["tickers"]))
            else:
                for t in it["tickers"]:
                    if t not in atual["tickers"]:
                        atual["tickers"].append(t)
    return sorted(por_chave.values(), key=lambda i: i["data"], reverse=True)[:MAX_ITENS]


def buscar_ticker(ticker, nome=""):
    import requests
    r = requests.get(URL_RSS.format(q=quote(consulta(ticker, nome))), headers=UA, timeout=20)
    if r.status_code == 429:
        raise RuntimeError("Too Many Requests")
    r.raise_for_status()
    return ler_rss(r.content, ticker, nome)


# ---------------------------------------------------------------- estado local

def _arquivo():
    return nc.DADOS / "noticias.json"


def ler_estado():
    with TRAVA:
        try:
            d = json.loads(_arquivo().read_text(encoding="utf-8"))
        except (OSError, ValueError):
            d = {}
    d.setdefault("itens", [])
    d.setdefault("vistos", {})      # id -> hora em que foi visto (evita notificar duas vezes)
    d.setdefault("conhecidos", [])  # tickers cujas notícias antigas já foram marcadas como vistas
    d.setdefault("hora", 0)
    d.setdefault("lidas_ate", 0)    # notícias vistas até aqui não contam como novas na aba
    d.setdefault("erros", {})
    return d


def gravar_estado(d):
    with TRAVA:
        if len(d["vistos"]) > MAX_VISTOS:
            d["vistos"] = dict(sorted(d["vistos"].items(), key=lambda kv: kv[1])[-MAX_VISTOS:])
        tmp = _arquivo().with_suffix(".tmp")
        tmp.write_text(json.dumps(d, ensure_ascii=False), encoding="utf-8")
        tmp.replace(_arquivo())


def atualizar(radar, agora=None):
    """Busca as notícias de todos os ativos do radar e grava o estado.

    Devolve (itens, novas_relevantes). Uma notícia relevante é nova quando ainda não foi vista, tem
    algum tema importante e saiu nas últimas 24 h. Na primeira busca de um ativo, o que já existe é
    marcado como visto sem notificar.
    """
    agora = agora or time.time()
    tickers = [(r["ticker"], r.get("nome", "")) for r in radar]
    listas, erros = [], {}
    for t, nome in tickers:
        try:
            listas.append(buscar_ticker(t, nome))
        except Exception as e:  # um ativo com erro não impede os outros
            erros[t] = str(e)[:200]
    with TRAVA:
        d = ler_estado()
        validos = {t for t, _ in tickers}
        antigos = [dict(i, tickers=[t for t in i["tickers"] if t in validos]) for i in d["itens"]]
        antigos = [i for i in antigos if i["tickers"] and not any(t in i["tickers"] for t in validos - set(erros))]
        itens = mesclar(listas + [antigos])
        conhecidos = set(d["conhecidos"])
        novas = []
        for it in itens:
            if it["id"] in d["vistos"]:
                continue
            d["vistos"][it["id"]] = agora
            estreia = not (set(it["tickers"]) & conhecidos)
            if it["temas"] and not estreia and agora - it["data"] <= JANELA_NOTIFICACAO:
                novas.append(it)
        d["conhecidos"] = sorted(conhecidos | (validos - set(erros)))
        d["itens"], d["hora"], d["erros"] = itens, agora, erros
        if not d["lidas_ate"]:
            d["lidas_ate"] = agora
        gravar_estado(d)
    return itens, novas


def precisa_atualizar(d, agora=None):
    return (agora or time.time()) - d.get("hora", 0) >= INTERVALO


def eh_nova(d, item):
    """Chegou depois da última vez que a aba de notícias foi aberta."""
    return d["vistos"].get(item["id"], 0) > d.get("lidas_ate", 0)


def nao_lidas(d):
    return sum(1 for i in d["itens"] if eh_nova(d, i))


def marcar_lidas(agora=None):
    with TRAVA:
        d = ler_estado()
        d["lidas_ate"] = agora or time.time()
        gravar_estado(d)
        return d


def textos_notificacao(novas):
    """[(título, texto, link)] para notificar; muitas novidades viram um resumo só."""
    if len(novas) <= MAX_NOTIFICACOES:
        saida = []
        for i in novas:
            titulo = f"{', '.join(i['tickers'][:3])} · {i['temas'][0]}"
            corpo = f"{i['titulo']} ({i['fonte']})" if i["fonte"] else i["titulo"]
            saida.append((titulo, corpo, i["link"]))
        return saida
    tickers = []
    for i in novas:
        tickers += [t for t in i["tickers"] if t not in tickers]
    return [(f"{len(novas)} notícias relevantes", "Sobre " + ", ".join(tickers[:6]) + (
        "…" if len(tickers) > 6 else ""), "")]


# ---------------------------------------------------------------- logos

def iniciais(ticker):
    return re.sub(r"\d.*$", "", ticker)[:4] or ticker[:4]


def urls_logo(ticker):
    """PNG do ticker, PNG da raiz (4 letras) e SVG (só o Android exibe SVG)."""
    raiz = iniciais(ticker)
    png = [URL_LOGO_PNG.format(t=ticker)]
    if raiz != ticker:
        png.append(URL_LOGO_PNG.format(t=raiz))
    return png, URL_LOGO_SVG.format(t=ticker)


def baixar_imagem(url, destino, validade=VALIDADE_LOGO_AUSENTE):
    """Bytes de uma imagem PNG com cache em disco; None se não existir (lembra a ausência por 7 dias)."""
    falta = destino.with_suffix(".falta")
    if destino.exists():
        return destino.read_bytes()
    if falta.exists() and time.time() - falta.stat().st_mtime < validade:
        return None
    import requests
    destino.parent.mkdir(parents=True, exist_ok=True)
    try:
        r = requests.get(url, headers=UA, timeout=15)
    except Exception:
        return None  # sem rede: tenta de novo na próxima vez
    if r.status_code == 200 and r.content[:8] == b"\x89PNG\r\n\x1a\n":
        destino.write_bytes(r.content)
        falta.unlink(missing_ok=True)
        return r.content
    if r.status_code in (403, 404) or r.status_code == 200:
        falta.write_bytes(b"")
    return None


def logo_png(ticker):
    """PNG da logo do ativo (cache em dados/logos) ou None."""
    pasta = nc.DADOS / "logos"
    for url in urls_logo(ticker)[0]:
        nome = url.rsplit("/", 1)[-1]
        b = baixar_imagem(url, pasta / nome)
        if b:
            return b
    return None


def favicon_png(item):
    d = dominio(item.get("fonte_url", ""))
    if not d:
        return None
    return baixar_imagem(URL_FAVICON.format(d=d), nc.DADOS / "logos" / "fontes" / (re.sub(r"[^\w.-]", "_", d)
                                                                                     + ".png"))
