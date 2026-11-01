"""Referências da parte HTML das notícias (noticias.py:363-381): entidades, `_meta` e `ler_previa`, e de
`decodificar_link` (noticias.py:340-360) com a rede falsa.

Funções (campo `funcao` de cada caso):
- unescape: entrada texto; saída `html.unescape(texto)`.
- tabela_html5: entrada nula; saída o dict `html.entities.html5` inteiro.
- meta: entrada {html, nomes}; saída texto de `_meta`.
- ler_previa: entrada {html, url}; saída {img, resumo}.
- ler_rss: entrada {xml, ticker, nome, agora}; saída lista de itens de `ler_rss` (parser XML; `time.time` congelado).
- ler_rss_regex: igual, dentro de `sem_modulo("xml.etree.ElementTree")` (leitura por expressões regulares).
- data_rfc2822: entrada texto; saída timestamp de `parsedate_to_datetime(...).timestamp()` ou nulo quando lança
  (só datas com fuso explícito: sem fuso o Python usa a hora local da máquina que gerou).
- url_busca: entrada {ticker, nome}; saída `URL_RSS.format(q=quote(consulta(...)))`.
- quote: entrada {texto, seguro}; saída `urllib.parse.quote(texto, safe=seguro)`.
- decodificar_link: entrada {link, respostas: [{status, texto}]}; saída {pedidos, resultado} ou, em falha,
  {pedidos, erro, mensagem}. Cada pedido: {metodo, url, params, cabecalhos, dados, json, timeout, stream}.
"""
import http
import html as pyhtml
import json
import types
from email.utils import parsedate_to_datetime
from html.entities import html5
from urllib.parse import quote

from . import _rede_falsa as rede
from . import base

base.nc  # noqa: B018 (garante o sys.path da raiz)
import noticias as nt  # noqa: E402

UNESCAPE = [
    ("amp lt gt quot", "&amp; &lt; &gt; &quot;"),
    ("numérica de apóstrofo", "&#39;"),
    ("nbsp", "a&nbsp;b"),
    ("aacute", "&aacute;"),
    ("ccedil e atilde", "&ccedil;&atilde;o"),
    ("amp sem ponto e vírgula", "&amp"),
    ("ampx", "&ampx"),
    ("notit", "&notit;"),
    ("hex", "&#x41;"),
    ("decimal sem ponto e vírgula", "&#65"),
    ("zero", "&#0;"),
    ("faixa 128", "&#128;"),
    ("substituto", "&#xD800;"),
    ("acima do limite", "&#1114112;"),
    ("número enorme", "&#99999999999999999999;"),
    ("não caractere", "&#xFFFE;"),
    ("desconhecida", "&unknown;"),
    ("e comercial sozinho", "&"),
    ("sem entidade", "texto simples sem nada"),
    ("todas juntas", "&amp; &lt; &gt; &quot; &#39; &nbsp; &aacute; &ccedil;&atilde;o &amp &ampx &notit; &#x41; &#65 "
                     "&#0; &#128; &#xD800; &#1114112; &#99999999999999999999; &#xFFFE; &unknown; &"),
    ("prefixo mais longo", "&notin; &notinx &lte;x"),
    ("cr e controles", "&#13;&#1;&#x7f;&#x81;&#xB;"),
    ("zeros à esquerda", "&#0000065;&#x0041;"),
    ("maiúscula X", "&#X41;"),
    ("nome longo sem fim", "&" + "a" * 40 + ";"),
    ("fora do BMP", "&#x1F600;&Afr;"),
    ("e comercial em fim de texto", "A&B"),
]

PREVIAS = [
    ("aspas duplas e property",
     '<html><head><meta property="og:image" content="https://x.com/a.jpg"><meta property="og:description" content="Resumo A"></head>'),
    ("aspas simples e name",
     "<head><meta name='og:image' content='https://x.com/b.jpg'><meta name='description' content='Resumo B'></head>"),
    ("primeira ocorrência vence",
     '<head><meta property="og:image" content="https://x.com/1.jpg"><meta property="og:image" content="https://x.com/2.jpg"></head>'),
    ("content vazio ignorado",
     '<head><meta property="og:image" content=""><meta property="og:image" content="https://x.com/3.jpg"></head>'),
    ("content só espaços ignorado",
     '<head><meta property="og:description" content="   "><meta name="description" content="depois"></head>'),
    ("fallback twitter",
     '<head><meta name="twitter:image" content="https://x.com/t.jpg"><meta name="twitter:description" content="Resumo T"></head>'),
    ("twitter:image:src",
     '<head><meta name="twitter:image:src" content="https://x.com/s.jpg"></head>'),
    ("secure_url vence",
     '<head><meta property="og:image" content="https://x.com/n.jpg"><meta property="og:image:secure_url" content="https://x.com/s.jpg"></head>'),
    ("url relativa", '<head><meta property="og:image" content="img/a.jpg"></head>', "https://site.com/pasta/pagina.html"),
    ("url com //cdn", '<head><meta property="og:image" content="//cdn.site.com/a.jpg"></head>', "https://site.com/p"),
    ("url com /img.jpg", '<head><meta property="og:image" content="/img.jpg"></head>', "https://site.com/pasta/p?q=1"),
    ("descrição com quebras e nbsp",
     '<head><meta name="description" content="Linha um\n\n  linha&nbsp;dois e\tmais"></head>'),
    ("descrição com 700 caracteres",
     '<head><meta name="description" content="' + ("palavra " * 100) + '"></head>'),
    ("descrição com 700 caracteres fora do BMP",
     '<head><meta name="description" content="' + ("\U0001F600" * 700) + '"></head>'),
    ("sem </head>", '<meta property="og:image" content="https://x.com/z.jpg"><meta name="description" content="Sem fim">'),
    ("meta depois de </head> é ignorada",
     '<head></head><meta property="og:image" content="https://x.com/w.jpg">'),
    ("entidades no content",
     '<head><meta property="og:description" content="Lucro &amp; receita &quot;recorde&quot; &#233; &aacute;"></head>'),
    ("tag meta em maiúsculas", '<HEAD><META PROPERTY="OG:IMAGE" CONTENT="https://x.com/u.jpg"></HEAD>'),
    ("atributos misturados",
     '<head><meta data-x="1" property="og:description" content=\'Com "aspas" dentro\' ></head>'),
    ("aspa simples dentro de aspa dupla",
     "<head><meta property=\"og:description\" content=\"It's fine\"></head>"),
    ("espaços em volta do igual", '<head><meta property = "og:description" content = "Com espaços"></head>'),
    ("sem meta", "<head><title>x</title></head>"),
    ("vazio", ""),
    ("meta não fechada", '<head><meta property="og:description" content="x"'),
    ("imagem absoluta com outra base", '<head><meta property="og:image" content="http://outro.com/a.png"></head>', "https://site.com/p"),
    ("imagem com dois pontos", '<head><meta property="og:image" content="../up/a.png"></head>', "https://site.com/a/b/c.html"),
]

METAS = [
    ("primeiro nome que existe", '<meta property="og:title" content="T"><meta name="description" content="D">',
     ["og:description", "og:title", "description"]),
    ("nenhum nome", '<meta name="a" content="1">', ["b"]),
    ("chave em maiúsculas", '<meta property="OG:Title" content="  Ti  ">', ["og:title"]),
    ("name quando não há property", '<meta name="description" content="D">', ["description"]),
    ("property vence name", '<meta property="p" name="n" content="C">', ["p", "n"]),
    ("atributo repetido: o último vale", '<meta name="a" content="1" content="2">', ["a"]),
    ("sem aspas não é lido", "<meta name=a content=1>", ["a"]),
    ("entidade e strip", '<meta name="a" content=" &nbsp;x&nbsp; ">', ["a"]),
]


def _item(titulo, link="https://news.google.com/rss/articles/CBMiX", guid=None, data="Wed, 28 Oct 2026 10:00:00 GMT",
          fonte="Valor Econômico", fonte_url="https://valor.globo.com"):
    partes = []
    if titulo is not None:
        partes.append(f"<title>{titulo}</title>")
    if link is not None:
        partes.append(f"<link>{link}</link>")
    if guid is not None:
        partes.append(f'<guid isPermaLink="false">{guid}</guid>')
    if data is not None:
        partes.append(f"<pubDate>{data}</pubDate>")
    if fonte is not None:
        partes.append(f'<source url="{fonte_url}">{fonte}</source>')
    return "<item>" + "".join(partes) + "</item>"


def _rss(*itens, fim="</channel></rss>"):
    return ('<?xml version="1.0" encoding="UTF-8"?><rss version="2.0"><channel><title>"PETR4" - Google Notícias</title>'
            "<link>https://news.google.com/</link>" + "".join(itens) + fim)


_T1 = "Petrobras anuncia dividendos extraordinários de R$ 5 bilhões - Valor Econômico"
_T2 = "Petrobras bate recorde de produção no pré-sal em outubro - Exame"
_T3 = "Petrobras eleva preço do diesel nas refinarias a partir de amanhã - InfoMoney"

RSS = [
    ("item completo com fonte no título", "PETR4", "", _rss(_item(_T1, guid="g1"))),
    ("vários itens na ordem do documento", "PETR4", "", _rss(
        _item(_T1, guid="g1"),
        _item(_T2, guid="g2", fonte="Exame", fonte_url="https://exame.com", data="Tue, 27 Oct 2026 08:30:00 -0300"),
        _item(_T3, guid="g3", fonte="InfoMoney", fonte_url="https://www.infomoney.com.br",
              data="Mon, 26 Oct 2026 23:59:59 EST"))),
    ("item sem link é pulado", "PETR4", "", _rss(_item(_T1, link=None), _item(_T2, fonte="Exame"))),
    ("item sem título é pulado", "PETR4", "", _rss(_item(None), _item("   "), _item(_T2, fonte="Exame"))),
    ("ruído é descartado", "PETR4", "", _rss(
        _item("PETR4: cotação e indicadores - Petrobras PN - Investing.com", fonte="Investing.com"),
        _item("Petrobras: resultados, dividendos, cotação e mais notícias - Fundamentus", fonte="Fundamentus"),
        _item("PETR4 (PETR4) - TradeMap", fonte="TradeMap"),
        _item(_T2, fonte="Exame"))),
    ("título curto é descartado", "PETR4", "", _rss(_item("Petrobras sobe - Exame", fonte="Exame"))),
    ("sufixo da fonte só sai se for a mesma", "PETR4", "", _rss(
        _item(_T1, fonte="Exame"),
        _item("Petrobras anuncia dividendos extraordinários de R$ 5 bilhões - Valor", fonte="Valor Econômico"),
        _item("Petrobras anuncia dividendos extraordinários de R$ 5 bilhões - ", fonte=""))),
    ("sufixo com espaços antes", "PETR4", "", _rss(
        _item("Petrobras anuncia dividendos extraordinários de R$ 5 bilhões   - Valor Econômico"))),
    ("entidade &amp; no título", "PETR4", "", _rss(
        _item("Lucro da Petrobras sobe 10% &amp; supera expectativas do mercado - InfoMoney", fonte="InfoMoney"),
        _item("Petrobras &lt;PETR4&gt; fecha em alta &#8211; analistas veem mais espaço - Exame", fonte="Exame"))),
    ("CDATA no título", "PETR4", "", _rss(
        _item("<![CDATA[Petrobras fecha acordo bilionário com a Vale para exploração - Exame]]>", fonte="Exame"))),
    ("CDATA no link e na fonte", "PETR4", "", _rss(
        _item(_T2, link="<![CDATA[https://exemplo.com/a?x=1]]>", fonte="<![CDATA[Exame]]>"))),
    ("pubDate ausente usa agora", "PETR4", "", _rss(_item(_T2, data=None, fonte="Exame"))),
    ("pubDate inválido usa agora", "PETR4", "", _rss(
        _item(_T2, data="ontem às 10h", fonte="Exame"), _item(_T3, data="", fonte="InfoMoney"))),
    ("sem guid o id é o link", "PETR4", "", _rss(_item(_T2, link="  https://x.com/a  ", guid=None, fonte="Exame"))),
    ("guid com espaços", "PETR4", "", _rss(_item(_T2, guid="  abc-123  ", fonte="Exame"))),
    ("sem source", "PETR4", "", _rss(_item(_T2, fonte=None))),
    ("source com url com &amp;", "PETR4", "", _rss(_item(_T2, fonte="Exame", fonte_url="https://exame.com/?a=1&amp;b=2"))),
    ("source sem url", "PETR4", "", _rss(
        f"<item><title>{_T2}</title><link>https://x.com/a</link><source>Exame</source></item>")),
    ("título e fonte com espaços e quebras de linha", "PETR4", "", _rss(
        f'<item>\n  <title>\n   {_T2}\n  </title>\n  <link>\n   https://x.com/a\n  </link>\n'
        '  <source url="https://exame.com">\n Exame\n </source>\n</item>')),
    ("temas reconhecidos", "PETR4", "", _rss(
        _item("Petrobras anuncia dividendos e JCP após lucro recorde no trimestre - Exame", fonte="Exame"))),
    ("sem itens", "PETR4", "", _rss()),
    ("só elementos desconhecidos", "PETR4", "", _rss("<other>x</other>")),
    ("BDR cita o ticker", "AAPL34", "Apple Inc.", _rss(
        _item("AAPL34 sobe após lançamento de novo iPhone na Califórnia - Exame", fonte="Exame"))),
    ("BDR cita o nome", "AAPL34", "Apple Inc.", _rss(
        _item("Apple lança novo iPhone e ações reagem em Wall Street - InfoMoney", fonte="InfoMoney"))),
    ("BDR sem relação é descartado", "AAPL34", "Apple Inc.", _rss(
        _item("Mercado financeiro fecha em alta com dados de emprego dos EUA - InfoMoney", fonte="InfoMoney"))),
    ("BDR sem nome só aceita o ticker", "AAPL34", "", _rss(
        _item("Apple lança novo iPhone e ações reagem em Wall Street - InfoMoney", fonte="InfoMoney"),
        _item("AAPL34 sobe após lançamento de novo iPhone na Califórnia - Exame", fonte="Exame"))),
    ("BDR com fronteira de palavra no nome", "NVDC34", "Nvidia Corp", _rss(
        _item("Nvidiana é o apelido de uma cidade fictícia do interior paulista - Exame", fonte="Exame"),
        _item("Nvidia supera previsões e dispara com demanda por chips de IA - Exame", fonte="Exame"))),
    ("itens aninhados em outro elemento", "PETR4", "", _rss(
        f"<group><item><title>{_T2}</title><link>https://x.com/a</link></item></group>")),
    ("acentos e emoji no título", "PETR4", "", _rss(
        _item("Petrobras \U0001F680 dispara após descoberta de petróleo em águas profundas - Exame", fonte="Exame"))),
]

# Documentos malformados: só a leitura por expressões regulares os lê.
RSS_MALFORMADO = [
    ("sem fechar o rss", "PETR4", "", _rss(_item(_T1, guid="g1"), _item(_T2, guid="g2", fonte="Exame"), fim="")),
    ("e comercial solto no título", "PETR4", "", _rss(
        _item("Lucro & prejuízo da Petrobras surpreendem o mercado nesta semana - Exame", fonte="Exame"))),
    ("último item cortado", "PETR4", "", _rss(
        _item(_T1, guid="g1"), f"<item><title>{_T2}</title><link>https://x", fim="")),
    ("tags desencontradas", "PETR4", "", _rss(f"<item><title>{_T2}</title><link>https://x.com/a</link><b></item>")),
    ("entidade numérica e CDATA", "PETR4", "", _rss(
        _item("Petrobras &#8211; lucro recorde no trimestre surpreende analistas - Exame", fonte="Exame"),
        _item("<![CDATA[Petrobras fecha acordo bilionário com a Vale para exploração - Exame]]>", fonte="Exame"),
        fim="</channel>")),
    ("fonte com url", "PETR4", "", _rss(
        _item(_T2, fonte="Exame", fonte_url="https://exame.com/?a=1&amp;b=2"), fim="</rss")),
]

DATAS = [
    "Wed, 28 Oct 2026 10:00:00 GMT", "Wed, 28 Oct 2026 10:00:00 +0000", "Wed, 28 Oct 2026 10:00:00 -0300",
    "Wed, 28 Oct 2026 10:00:00 +0530", "Wed, 28 Oct 2026 10:00:00 EST", "Wed, 28 Oct 2026 10:00:00 EDT",
    "Wed, 28 Oct 2026 10:00:00 CST", "Wed, 28 Oct 2026 10:00:00 CDT", "Wed, 28 Oct 2026 10:00:00 MST",
    "Wed, 28 Oct 2026 10:00:00 MDT", "Wed, 28 Oct 2026 10:00:00 PST", "Wed, 28 Oct 2026 10:00:00 PDT",
    "Wed, 28 Oct 2026 10:00:00 AST", "Wed, 28 Oct 2026 10:00:00 ADT", "Wed, 28 Oct 2026 10:00:00 UT",
    "Wed, 28 Oct 2026 10:00:00 UTC", "Wed, 28 Oct 2026 10:00:00 Z", "Wed, 28 Oct 2026 10:00:00 gmt",
    "28 Oct 2026 10:00:00 GMT", "28 Oct 26 10:00:00 GMT", "28 Oct 99 10:00:00 GMT", "28 Oct 68 10:00:00 GMT",
    "28 Oct 69 10:00:00 GMT", "28 Oct 00 10:00:00 GMT", "28 Oct 26 10:00 GMT", "Wed, 28 Oct 2026 10:00 -0300",
    "Wed,28 Oct 2026 10:00:00 GMT", "Wed, 28 October 2026 10:00:00 GMT", "wed, 28 oct 2026 10:00:00 GMT",
    "Wed 28 Oct 2026 10:00:00 GMT", "Wed, 28-Oct-2026 10:00:00 GMT", "28-Oct-26 10:00:00 GMT",
    "Wed, 28 Oct 2026 10.00.00 GMT", "Wed, 28 Oct 2026 10.00 GMT", "Oct 28 2026 10:00:00 GMT",
    "Wed, 28 Oct 2026 10:00:00+0300", "Wed, 28 Oct 2026 10:00:00-0300", "Wed, 28 Oct 10:00:00 2026 GMT",
    "Wed, 28 Oct 2026, 10:00:00 GMT", "Wed, 28 Oct 2026 10:00:00, GMT", "Wed, 28 Oct 2026 10:00:00 +03",
    "Wed, 28 Oct 2026 10:00:00 +0075", "Wed, 28 Oct 2026 10:00:00 +2359", "Wed, 28 Oct 2026 10:00:00 -2359",
    "Wed, 28 Oct 2026 10:00:00 +2400", "Wed, 28 Oct 2026 10:00:00 +2500", "Wed, 28 Oct 2026 10:00:00 GMT+0100",
    "  Wed,   28  Oct 2026\t10:00:00 \n GMT ", "Wed, 29 Feb 2028 10:00:00 GMT", "Wed, 29 Feb 2026 10:00:00 GMT",
    "Wed, 31 Apr 2026 10:00:00 GMT", "Wed, 32 Oct 2026 10:00:00 GMT", "Wed, 00 Oct 2026 10:00:00 GMT",
    "Wed, 28 Oct 2026 24:00:00 GMT", "Wed, 28 Oct 2026 23:60:00 GMT", "Wed, 28 Oct 2026 23:59:60 GMT",
    "Wed, 28 Oct 2026 23:59:59 GMT", "Wed, 28 Oct 0001 00:00:00 GMT", "Wed, 28 Oct 9999 23:59:59 GMT",
    "Wed, 28 Oct 10000 10:00:00 GMT", "Wed, 28 Oct 2026 +10:00:00 GMT", "Wed, 28 Oct 2026 1_0:00:00 GMT",
    "Wed, 28 Oct 2026 10:0a:00 GMT", "Wed, 28 Oct 2026 10 GMT", "Wed, 28 Oct 2026 10:00:00:00 GMT",
    "Wed, 28 Oct 2026 10.00.00.00 GMT", "Wed, 28 Oct 2026", "Wed, 28 Oct", "Wed, 28 Xyz 2026 10:00:00 GMT",
    "Wed, 28 2026 Oct 10:00:00 GMT", "ontem às 10h", "lixo", "", "   ", ",", "Wed,",
    "Mon, 26 Oct 2026 23:59:59 -0200", "Wed, 28 Oct 2026 10:00:00 +0300 (BRT)",
    "Sun, 01 Jan 2023 00:00:00 +0000", "Sat, 31 Dec 1999 23:59:59 -0100",
]

BUSCAS = [
    ("PETR4", ""), ("VALE3", "Vale S.A."), ("TAEE11", ""), ("PETR4F", ""),
    ("AAPL34", "Apple Inc."), ("JNJB34", "Johnson & Johnson (JNJ)"), ("LORE34", "L'Oréal S.A."),
    ("PGCO34", "Procter & Gamble Co."), ("ATTB34", "AT&T Inc."), ("MSFT34", "Microsoft Corporation"),
    ("NVDC34", "NVIDIA Corp - Class A"), ("AMZO34", "Amazon.com, Inc."), ("ITLC34", "Intel (INTC) Corp"),
    ("BERK34", "Berkshire Hathaway Inc. Class B"), ("COCA34", "Coca-Cola Co"), ("DISB34", "Walt Disney Co (The)"),
    ("NFLX34", "Ação – Açúcar São João/Ñandú"), ("TSLA34", "Tesla"), ("GOGL34", "ab"), ("MELI34", "MercadoLibre"),
    ("PETR4", "Petróleo Brasileiro"), ("AAPL34", "Apple! * ~ _ . - Inc"),
]

QUOTES = [
    ("abc", "/"), ("a b", "/"), ("a/b", "/"), ("a/b", ""), ("a&b=c?d#e", "/"), ("\"x\" (y) 'z' !*", "/"),
    ("ção ñ é", "/"), ("\U0001F600", "/"), ("_.-~", "/"), ("%41", "/"), ("a,b;c:d@e", "/"), ("a,b;c", ",;"),
    ("", "/"), ("(\"PETR4\" OR \"Apple\" ações) when:7d", "/"),
]


_ID = "CBMiXYZ_abc-123"
_LINK = f"https://news.google.com/rss/articles/{_ID}?oc=5"
_URL_BATCH = nt.URL_DECODIFICAR


def _pagina(sg="SGVAL123", ts="1700000000"):
    partes = ["<html><body><c-wiz"]
    if sg is not None:
        partes.append(f' data-n-a-sg="{sg}"')
    if ts is not None:
        partes.append(f' data-n-a-ts="{ts}"')
    return "".join(partes) + "></c-wiz></body></html>"


def _batch(url, extra=""):
    interno = json.dumps(["garturlres", url, 1])
    return ")]}'\n\n" + json.dumps([["wrb.fr", "Fbv4je", interno, None, None, None, "generic"],
                                   ["di", 12], ["af.httprm", 12, "-123", 5]]) + "\n" + extra


def _r(status, texto):
    return {"status": status, "texto": texto}


DECODIFICAR = [
    ("link de fora do Google", "https://exemplo.com/artigo?a=1", []),
    ("articles fora do Google", "https://exemplo.com/articles/abc", []),
    ("sem /articles/", "https://news.google.com/home", []),
    ("página sem data-n-a-sg", _LINK, [_r(200, _pagina(sg=None))]),
    ("página sem data-n-a-ts", _LINK, [_r(200, _pagina(ts=None))]),
    ("página vazia", _LINK, [_r(200, "")]),
    ("página e resposta válidas", _LINK, [_r(200, _pagina()), _r(200, _batch("https://site.com/m"))]),
    ("sem query nem fragmento", f"https://news.google.com/rss/articles/{_ID}",
     [_r(200, _pagina()), _r(200, _batch("https://site.com/m"))]),
    ("com fragmento", f"https://news.google.com/rss/articles/{_ID}#x",
     [_r(200, _pagina()), _r(200, _batch("https://site.com/m"))]),
    ("link com articles no meio", f"https://news.google.com/rss/articles/{_ID}/extra?oc=5",
     [_r(200, _pagina()), _r(200, _batch("https://site.com/m"))]),
    ("status da página não é conferido", _LINK,
     [_r(404, _pagina()), _r(200, _batch("https://site.com/m"))]),
    ("sg com barra, aspas e acentos", _LINK,
     [_r(200, _pagina(sg="a\\b é\U0001F600\x7f+&=")), _r(200, _batch("https://site.com/m"))]),
    ("ts não numérico", _LINK, [_r(200, _pagina(ts="abc")), _r(200, _batch("https://site.com/m"))]),
    ("id com acento", "https://news.google.com/rss/articles/CBMié?oc=5",
     [_r(200, _pagina()), _r(200, _batch("https://site.com/m"))]),
    ("resposta com linhas de controle", _LINK,
     [_r(200, _pagina()), _r(200, _batch("https://site.com/m", '25\n[["e",4,null,null,0]]\n'))]),
    ("url http simples", _LINK, [_r(200, _pagina()), _r(200, _batch("http://site.com/m"))]),
    ("url que não começa com http", _LINK, [_r(200, _pagina()), _r(200, _batch("ftp://site.com/m"))]),
    ("url vazia", _LINK, [_r(200, _pagina()), _r(200, _batch(""))]),
    ("POST 500", _LINK, [_r(200, _pagina()), _r(500, "erro")]),
    ("POST 429", _LINK, [_r(200, _pagina()), _r(429, "devagar")]),
    ("POST 403", _LINK, [_r(200, _pagina()), _r(403, "negado")]),
    ("resposta sem linha em branco", _LINK, [_r(200, _pagina()), _r(200, ")]}'")]),
    ("resposta com poucos elementos", _LINK, [_r(200, _pagina()), _r(200, ")]}'\n\n" + json.dumps([["wrb.fr"]]))]),
]


def _decodificar(link, respostas):
    reais = [rede.Resposta(r["status"], texto=r["texto"], motivo=http.HTTPStatus(r["status"]).phrase)
             for r in respostas]
    cm, pedidos = rede.rede(reais)
    saida = {}
    with cm:
        try:
            saida["resultado"] = nt.decodificar_link(link)
        except Exception as e:  # noqa: BLE001 (qualquer erro vira o caso de referência)
            saida.update(rede.erro(e))
    return {"pedidos": pedidos, **saida}


def _ler_rss(xml, ticker, nome):
    antigo = nt.time
    nt.time = types.SimpleNamespace(time=lambda: base.AGORA)
    try:
        return nt.ler_rss(xml.encode("utf-8"), ticker, nome)
    finally:
        nt.time = antigo


def _data(txt):
    """Timestamp, nulo se o Python lança, ou `...` se a data é sem fuso (depende da máquina que gerou)."""
    try:
        d = parsedate_to_datetime(txt)
    except (TypeError, ValueError):
        return None
    return ... if d.tzinfo is None else d.timestamp()


def casos():
    out = [base.caso("tabela", "tabela_html5", None, dict(html5))]
    for nome, entrada in UNESCAPE:
        out.append(base.caso(nome, "unescape", entrada, pyhtml.unescape(entrada)))
    for item in PREVIAS:
        nome, doc = item[0], item[1]
        url = item[2] if len(item) > 2 else "https://site.com/materia"
        out.append(base.caso(nome, "ler_previa", {"html": doc, "url": url}, nt.ler_previa(doc, url)))
    for nome, doc, nomes in METAS:
        out.append(base.caso(nome, "meta", {"html": doc, "nomes": nomes}, nt._meta(doc, *nomes)))
    for nome, ticker, empresa, xml in RSS:
        entrada = {"xml": xml, "ticker": ticker, "nome": empresa, "agora": base.AGORA}
        out.append(base.caso(nome, "ler_rss", entrada, _ler_rss(xml, ticker, empresa)))
    for nome, ticker, empresa, xml in RSS + RSS_MALFORMADO:
        entrada = {"xml": xml, "ticker": ticker, "nome": empresa, "agora": base.AGORA}
        with rede.sem_modulo("xml.etree.ElementTree"):
            saida = _ler_rss(xml, ticker, empresa)
        sufixo = " (malformado)" if any(nome == m[0] for m in RSS_MALFORMADO) else ""
        out.append(base.caso(nome + sufixo, "ler_rss_regex", entrada, saida))
    for txt in DATAS:
        saida = _data(txt)
        if saida is not ...:
            out.append(base.caso(repr(txt), "data_rfc2822", txt, saida))
    for ticker, empresa in BUSCAS:
        url = nt.URL_RSS.format(q=quote(nt.consulta(ticker, empresa)))
        out.append(base.caso(f"{ticker} {empresa}".strip(), "url_busca", {"ticker": ticker, "nome": empresa}, url))
    for texto, seguro in QUOTES:
        out.append(base.caso(repr(texto), "quote", {"texto": texto, "seguro": seguro}, quote(texto, safe=seguro)))
    for nome, link, respostas in DECODIFICAR:
        out.append(base.caso(nome, "decodificar_link", {"link": link, "respostas": respostas},
                             _decodificar(link, respostas)))
    return out
