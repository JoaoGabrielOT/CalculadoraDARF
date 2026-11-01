"""Referências da parte HTML das notícias (noticias.py:363-381): entidades, `_meta` e `ler_previa`.

Funções (campo `funcao` de cada caso):
- unescape: entrada texto; saída `html.unescape(texto)`.
- tabela_html5: entrada nula; saída o dict `html.entities.html5` inteiro.
- meta: entrada {html, nomes}; saída texto de `_meta`.
- ler_previa: entrada {html, url}; saída {img, resumo}.
"""
import html as pyhtml
from html.entities import html5

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
    return out
