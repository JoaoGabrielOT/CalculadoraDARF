"""Referências de notícias: relevância, mesclagem, estado de lidas e textos (noticias.py:17-130, 178-195, 209-314, 460-470).

Funções (campo `funcao` de cada caso):
- titulo: entrada {titulo, alvos: [[ticker, nome]]}; saída {sem_acento, temas, chave, pertinentes: [bool]}.
- nome_busca: entrada {ticker, nome}; saída {nome_busca, consulta}.
- dominio: entrada {url}; saída {dominio, favicon} (favicon de um item com essa fonte_url).
- tempo_relativo: entrada {ts, agora}; saída {texto}.
- iniciais: entrada {ticker}; saída {iniciais, png: [url], svg}.
- mesclar: entrada {listas: [[item]]}; saída {itens}.
- textos_notificacao: entrada {novas: [item]}; saída {textos: [[título, corpo, link]]}.
- ler_estado: entrada {arquivo: texto | null}; saída {estado}.
- gravar_estado: entrada {estado}; saída {arquivo: texto gravado, vistos: [ids na ordem gravada]}.
- roteiro: entrada {estado_inicial: dict | null, passos: [passo]}; saída {passos: [resultado]}. Passos:
  {op: "buscar", agora, radar: [{ticker, nome}], respostas: {ticker: [item] | {erro}}},
  {op: "lidas", agora}. Resultado: {novas, textos, arquivo, nao_lidas, eh_nova, precisa: [bool]}
  (`precisa` = precisa_atualizar(estado, agora + deslocamento) para os deslocamentos do campo `deslocamentos`
  da entrada).
"""
import json

from . import base

nc = base.nc
import noticias as nt  # noqa: E402

AGORA = base.AGORA
DESLOCAMENTOS = [0.0, 599.0, 599.9, 600.0, 600.1, 3600.0]
ALVOS = [["PETR4", ""], ["AAPL34", "Apple Inc."], ["MSFT34", "Microsoft Corp"], ["ITUB34", "Itaú Unibanco Holding S.A."],
         ["NESN34", "Nestlé S.A."], ["ORST34", "Ørsted A/S"], ["BRFS34", "BRF S.A."]]

# ---------------------------------------------------------------- títulos

TITULOS = [
    # Fato relevante
    "Petrobras divulga fato relevante sobre venda de campos maduros no Nordeste",
    "Comunicado ao Mercado: Vale informa retomada de operações em Mariana",
    "FATO RELEVANTE: Magazine Luiza altera calendário de eventos corporativos",
    # Resultado
    "Itaú tem lucro de R$ 10 bilhões no terceiro trimestre, acima do esperado",
    "Balanço do Bradesco mostra queda na margem financeira com clientes",
    "Prejuízo da Americanas aumenta e dívida preocupa analistas do mercado",
    "Ebitda da Suzano cresce 12% com alta do preço da celulose no período",
    "Receita líquida da WEG supera projeções dos bancos para o ano",
    "Guidance da Embraer é revisado para cima após entregas fortes no semestre",
    "Resultado do 3T24 da Vale vem acima do consenso de analistas do mercado",
    "Gerdau divulga 2T25 com geração de caixa robusta e dívida controlada",
    "Lucro da Ambev no 1 T25 fica estável frente ao mesmo período do ano passado",
    "Resultado da Cemig no 4t23 reflete efeito de provisões extraordinárias",
    "Trimestre fraco para o varejo derruba ações do setor na bolsa brasileira",
    "Empresa publica 3t245 como código interno de relatório de sustentabilidade",
    "Documento 4t2024 detalhado no site de relações com investidores da empresa",
    # Proventos
    "Taesa anuncia dividendos de R$ 0,50 por ação a pagar em dezembro próximo",
    "JCP da Petrobras será pago em duas parcelas; veja a data de corte e valor",
    "Juros sobre capital próprio: Banco do Brasil aprova R$ 2 bilhões em proventos",
    "Juros sobre o capital próprio da Itaúsa serão pagos em novembro deste ano",
    "Proventos da semana: veja as empresas que pagam dividendos e JCP em outubro",
    "Data-com de dividendos da Klabin é na próxima sexta-feira, diz comunicado",
    "Data com de proventos da Vivo: veja o calendário completo dos pagamentos",
    "Bonificação de ações da Sabesp aprovada em assembleia dos acionistas",
    # Recomendação
    "Banco eleva recomendação de Petrobras para compra e vê potencial de alta",
    "Itaú BBA rebaixa Magalu para neutro e corta preço-alvo da varejista",
    "Eleva preço-alvo da Vale para R$ 80 em relatório sobre mineradoras brasileiras",
    "Morgan Stanley faz downgrade de Natura e aponta riscos para a margem",
    "Upgrade de rating da Eletrobras pela agência reflete melhora de governança",
    "Comprar ou vender? Compra ou venda de ações do setor elétrico na semana",
    "Carteira recomendada de novembro traz Itaú, Vale e WEG entre os destaques",
    "Preço alvo da Raia Drogasil sobe e analistas mantêm recomendação de compra",
    "Rebaixamento da nota do Brasil por agência de risco afeta os ativos locais",
    # Fusão/aquisição
    "Aquisição da concorrente pela Localiza cria gigante do aluguel de carros",
    "Companhia vai adquirir fatia de 20% em empresa de energia renovável",
    "Fusão entre Marfrig e BRF forma gigante global de proteína animal",
    "Incorporação da controlada deve ser votada em assembleia extraordinária",
    "OPA da Eletrobras para fechamento de capital é aprovada pela CVM",
    "Desinvestimento de ativos não estratégicos avança na Petrobras em 2025",
    "Venda de ativo da Vale para investidor asiático é concluída com sucesso",
    "Venda de participação da Cosan na Raízen é avaliada por conselheiros",
    "Venda de subsidiária pela Gerdau na América do Norte é anunciada hoje",
    "Venda de refinaria da Petrobras é concluída e valor chega a US$ 1,6 bilhão",
    "Copa do Mundo de clubes movimenta o mercado de patrocínios esportivos",
    # Oferta/recompra
    "Programa de recompra de ações da Ambev autoriza até 100 milhões de papéis",
    "Follow-on da Azul levanta R$ 2 bilhões e diluição preocupa os acionistas",
    "Follow on de ações da Marfrig tem demanda acima da oferta, segundo fontes",
    "Oferta pública de ações da Caixa Seguridade atrai investidores institucionais",
    "Oferta subsequente de ações da Rede D'Or será precificada nesta semana",
    "Oferta de ações do Banco Master é cancelada após queda do mercado",
    "IPO da Nubank movimenta investidores brasileiros e estrangeiros em Nova York",
    "Tipo de investimento cresce entre pessoas físicas na bolsa de valores",
    "Emissão de debêntures da CCR soma R$ 3 bilhões e vai financiar investimentos",
    "Emissão de ações da Light para reforço de caixa divide opiniões no mercado",
    # Desdobramento
    "Desdobramento de ações da Weg será votado em assembleia geral extraordinária",
    "Grupamento de ações da Oi é aprovado e papéis passam a negociar no novo fator",
    "Split de ações da Nvidia anima investidores de BDRs na bolsa brasileira",
    "Inplit de ações da Americanas encerra período de ajuste dos papéis em carteira",
    # Governança
    "CEO da Petrobras fala sobre estratégia de investimentos para a próxima década",
    "Presidente da Vale deixa o cargo após dois anos e conselho inicia a sucessão",
    "Renúncia de diretor da Cemig surpreende o mercado na véspera do balanço",
    "Conselho de administração da Gol aprova novo plano de reestruturação financeira",
    "Diretor financeiro da Suzano passa a acumular a área de relações com investidores",
    "Assembleia de acionistas da Sabesp aprova mudança no estatuto da companhia",
    # Jurídico
    "CVM abre processo administrativo contra ex-diretores da Americanas por fraude",
    "Investigação da Polícia Federal sobre desvio em estatal atinge empreiteiras",
    "Multa de R$ 200 milhões aplicada pela ANP à refinaria é questionada na Justiça",
    "Recuperação judicial da Oi é prorrogada por mais 12 meses pelo juiz do caso",
    "Falência de varejista preocupa fornecedores e instituições financeiras credoras",
    "Processo seletivo da Petrobras abre vagas para engenheiros em todo o Brasil",
    "Operação da Polícia investiga fraude em licitações de empresa de saneamento",
    # Forte oscilação
    "Ibovespa dispara 3% com expectativa de corte de juros e fluxo estrangeiro",
    "Ações da Americanas desabam 40% após nova revelação sobre dívidas bilionárias",
    "Papéis da Gol despencam na bolsa depois de pedido de proteção judicial nos EUA",
    "Dólar derrete frente ao real com entrada forte de capital estrangeiro na bolsa",
    "Ação da Embraer salta 8% e atinge a maior cotação em uma década na B3",
    "Ações do varejo disparam com dados de consumo e esperança de queda de juros",
    "Bolsa tomba com cenário externo adverso e saída de investidores estrangeiros",
    "Petróleo tomba 5% e arrasta ações da Petrobras para o vermelho na sessão",
    "Maior queda do ano: Ibovespa recua 4% na pior sessão desde março passado",
    "Maior alta desde 2020: ações da Vale sobem forte após dados da China",
    "Circuit breaker é acionado na bolsa de Nova York após queda de 7% no S&P",
    "Recorde histórico do Ibovespa anima investidores e atrai novos recursos",
    # Sem tema (comuns)
    "Petrobras anuncia reajuste no preço da gasolina nas refinarias do país",
    "Vale inaugura novo terminal portuário no Maranhão com investimento de R$ 2 bi",
    "Itaú lança novo aplicativo para clientes de alta renda com foco em investimentos",
    "Magazine Luiza abre novas lojas no interior de São Paulo e Minas Gerais",
    "WEG apresenta nova linha de motores elétricos na feira industrial de Hannover",
    "Apple lança novo iPhone com câmera aprimorada e preço salgado no Brasil",
    "Microsoft anuncia parceria com empresa brasileira para inteligência artificial",
    "Nestlé investe em fábrica de chocolates em Marília e gera empregos na região",
    "Itaú Unibanco anuncia nova diretoria de tecnologia para o próximo ano",
    "Ørsted amplia projetos eólicos offshore na Europa e na costa dos Estados Unidos",
    "BRF S.A. inaugura centro de distribuição em Goiás com tecnologia de ponta",
    "Mercado financeiro aguarda ata do Copom e dados de inflação nesta semana",
    # Ruídos
    "PETR4: cotação e indicadores da ação da Petrobras hoje",
    "VALE3 - Resultados, dividendos, cotação e histórico da ação da Vale",
    "PETR4 (PETR4) - Trademap",
    "ITUB4 (ITUB4) - TradeMap: gráficos e análise",
    "Cotação e indicadores de MGLU3: preço, dividend yield e múltiplos",
    "Curto demais",
    "Dezenove caracteres",
    "Vinte caracteres exat",
    "   ",
    "",
    "A",
    # Bordas de padrões
    "Telefone publico e opa que bom! Copa do Mundo e Tipo de contrato",
    "O ceo disse que a empresa nao e ceo-friendly nem tem ceos demais na casa",
    "jcp, JCPs e djcp no texto do comunicado enviado ao mercado em 2025",
    "Rating de crédito: o Brasil mantém nota; ratings de empresas seguem estáveis",
    "Data.com é um site; datacom também é uma marca de equipamentos de rede",
    "Aquisições, adquirida, adquirente e fusões: palavras do mundo corporativo",
    "Salta de paraquedas; saltam as ações; saltou o preço — todos com mais de vinte letras",
    "Disparam as cotações; disparou o alarme; dispara o gatilho na segunda",
    "Tombaram as ações; tomba o dólar; tombo no preço; tombado pelo patrimônio histórico",
    "Eleva recomendação para compra; eleva o preço do ingresso; eleva preço-alvo",
    "Eleva\nrecomendação quebra de linha no meio do título para testar o ponto",
    "Preco alvo sem acento e preço.alvo com ponto e preço-alvo com hífen",
    "Venda de ativos pela estatal; venda de ativo da holding; venda de refinarias",
    "Oferta publica sem acento, oferta pública, oferta de acoes e oferta subsequente",
    "Emissao de debentures sem acento e emissão de ações com acento no título",
    "Recompra e follow-on e follow on e followon no mesmo título para conferir",
    "Receita líquida e receita liquida sem acento; receitas líquidas no plural",
    "Presidente Lula; presidenciável; vice-presidente; presidentes de bancos",
    "Falência, falências e falido; recuperação judicial e recuperações judiciais",
    "Processo, processos e processado; multa, multas e multado; cvm e CVMs",
    "Conselho de Administração; conselho administrativo; conselhos de administração",
    "T24 sozinho e 3 t24 com espaço e 3  t24 com dois espaços e 33t24 grudado",
]

UNICODE = [
    "Itaú Unibanco anuncia dividendos extraordinários para os acionistas em dezembro",
    "ITAÚ UNIBANCO SALTA NA BOLSA APÓS BALANÇO ACIMA DO ESPERADO PELOS ANALISTAS",
    "Nestlé reporta lucro maior no trimestre e eleva recomendação de analistas",
    "NESTLÉ LUCRO RECORDE NO TERCEIRO TRIMESTRE E DIVIDENDOS EM ALTA NO PERÍODO",
    "Ørsted desaba na bolsa de Copenhague após cancelar projeto eólico nos EUA",
    "Ørsted: lucro cai no trimestre; Ørsted-Equinor ainda negociam parceria",
    "ØRSTED despenca com prejuízo bilionário em obras de parques eólicos offshore",
    "ﬁnanças pessoais: ﬂuxo de caixa e eﬃciência na gestão dos recursos do mês",
    "Ação sobe forte: ações da Vale têm valorização em Nova York nesta sessão",
    "AÇÃO DA PETROBRAS DISPARA COM ALTA DO PETRÓLEO E ANÚNCIO DE DIVIDENDOS",
    "Dividendos² e x² mais lucro³ do trimestre superam projeções de analistas",
    "x² + y² = z²: matemática no mercado financeiro e o cálculo do ebitda anual",
    "Lucro 🚀 da Nvidia 📈 dispara e anima investidores de BDRs na bolsa brasileira",
    "🚀🚀🚀 Dividendos 🚀🚀🚀 chegam com força nesta semana na bolsa de valores",
    "😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀 só emojis no título da matéria",
    "Ação ação AÇÃO aÇÃo: todas as variantes de acentuação da palavra com til",
    "Crédito de carbono: Cesp vende créditos; Cosan investe em açúcar e etanol",
    "Straße, Größe e Café: nomes alemães de empresas e dividendos em euros",
    "İstanbul İş Bankası divulga lucro e dividendos; İ maiúsculo com ponto turco",
    "Σίγμα τελικό: ΟΔΟΣ ΑΘΗΝΩΝ lucro dividendos no título em grego para o teste",
    "Привет, рынок: лучшие акции и дивиденды в России — lucro e dividendos",
    "日本株の配当と決算: lucro e dividendos no mercado japonês de ações hoje",
    "ไทย ผลประกอบการ lucro dividendos mercado tailandês com vogais sobrepostas",
    "हिन्दी बाजार lucro dividendos devanagari com sinais combinantes no texto",
    "Ｐｅｔｒｏｂｒａｓ ｄｉｖｉｄｅｎｄｏｓ em caracteres de largura total no título",
    "Ⅲ trimestre e ⑤ itens: numerais romanos e circulados no resultado trimestral",
    "ª ordem e º lugar: ordinais; ½ dividendo e ¼ de lucro no texto da matéria",
    "Café café CAFÉ: coffee; café com acento combinante no meio do título",
    "Lucro e dividendos com espaços não separáveis entre as palavras",
    "ǅ ǈ ǋ e ﬀ ﬃ ﬆ ligaduras no meio do texto de dividendos e lucro trimestral",
    "Apple lança iPhone; AAPL34 sobe; Apple's novo chip e Apple® marca registrada",
    "Maçã e Apple™: empresa da maçã mordida lança produtos e a ação sobe",
    "Microsoft® e MSFT34: Microsoft Corporation anuncia parceria em nuvem",
    "AAPL34é junto sem espaço, AAPL34ó e ÁAPL34 colados com letras acentuadas",
    "Lucro da Ørsted A/S sobe e Ørsted A S fica em destaque nas bolsas europeias",
    "Itaú Unibanco Holding S.A. anuncia lucro; Itaú Unibanco Holding lidera ranking",
    "Itaú Unibanco Holdings fecha acordo e Itaú Unibanco Holding, S.A. comenta",
    "BRF S.A. e BRF SA: BRF lucra, BRF. brf, BRF! e BRF-S comunicam resultado",
    "ΑΣ ΣΑΣ Σ ΑΣ. ΑΣ'Α ΑΣΑ Σ.Α .Σ Α.Σ.Α 1Σ Σ1 ΑΣ1 ΑΣ-ΑΣ: sigma final em contextos variados",
    "Nestlé S.A. lucra e Nestle sem acento também; NESTLÉ e nestlé em minúsculas",
]


def _titulos():
    base_ = TITULOS + UNICODE
    saida = list(base_)
    saida += [t.upper() for t in TITULOS]            # 3 caixas: original, maiúsculas e capitalizadas
    saida += [t.title() for t in TITULOS[:90]]
    return saida


def _caso_titulo(i, titulo, grupo):
    saida = {
        "sem_acento": nt.sem_acento(titulo),
        "temas": nt.temas(titulo),
        "chave": nt.chave_titulo(titulo),
        "pertinentes": [nt.pertinente(titulo, t, n) for t, n in ALVOS],
    }
    return base.caso(f"{grupo}_{i:03d}", "titulo", {"titulo": titulo, "alvos": ALVOS}, saida)


NOMES = [
    ("PETR4", ""), ("PETR4", "Petróleo Brasileiro S.A. - Petrobras"), ("AAPL34", "Apple Inc."), ("AAPL34", ""),
    ("AAPL34", None), ("MSFT34", "Microsoft Corporation"), ("MSFT34", "Microsoft Corp"),
    ("GOGL34", "Alphabet Inc. Class A"), ("AMZO34", "Amazon.com, Inc."), ("TSLA34", "Tesla, Inc."),
    ("NVDC34", "NVIDIA Corporation"), ("MELI34", "MercadoLibre, Inc."), ("BERK34", "Berkshire Hathaway Inc. Class B"),
    ("BRFS34", "BRF S.A."), ("BRFS34", "BRF SA"), ("ITUB34", "Itaú Unibanco Holding S.A."),
    ("NESN34", "Nestlé S.A."), ("ORST34", "Ørsted A/S"), ("ORST34", "Ørsted"), ("DISB34", "Walt Disney Company (The)"),
    ("COCA34", "Coca-Cola Co - Common Stock"), ("JNJB34", "Johnson & Johnson"), ("PGCO34", "Procter & Gamble Co"),
    ("BOAC34", "Bank of America Corp, Series L"), ("MCDC34", "McDonald's Corporation"), ("XPBR34", "XP Inc. Class A"),
    ("SAPP34", "SAP SE ADR"), ("TSMC34", "Taiwan Semiconductor Manufacturing Company Ltd"),
    ("ABCD34", "AB"), ("ABCD34", "Co."), ("ABCD34", "Ltd Inc Corp"), ("ABCD34", "  Foo  Bar  "),
    ("ABCD34", "Foo - Bar"), ("ABCD34", "Foo – Bar"), ("ABCD34", "Foo (Bar)"), ("ABCD34", "Foo, Bar"),
    ("ABCD34", "Foo-Bar"), ("ABCD34", "Holdings Foo Group"), ("ABCD34", "Foo.Bar Inc."), ("ABCD34", "Foo.Inc"),
    ("ABCD34", "日本電産 Corporation"), ("ABCD34", "Ünïcödé Plc"), ("ABCD34", " Foo Bar Inc"),
    ("ABCD34", "Foo Bar"), ("ABCD34", "Foo\x1cBar"), ("ABCD34", "a b c"), ("ABCD34", "Foo Pfd"),
    ("VALE3", "Vale S.A."), ("MGLU3", "Magazine Luiza"), ("ABCD4F", "Nome"), ("AAPL34F", "Apple Inc."),
    ("aapl34", "Apple Inc."), (" AAPL34 ", "Apple Inc."), ("XYZ", ""), ("", "Nome"),
]


def _caso_nome(i, ticker, nome):
    saida = {"nome_busca": nt.nome_busca(nome), "consulta": nt.consulta(ticker, nome or "")}
    return base.caso(f"nome_{i:03d}", "nome_busca", {"ticker": ticker, "nome": nome}, saida)


URLS = [
    "https://www.infomoney.com.br/mercados/", "https://valor.globo.com/financas/", "http://WWW.Exame.COM/a?b=c#d",
    "https://exame.com", "www.exame.com/a", "//www.uol.com.br/x", "https://user:senha@www.site.com:8080/p",
    "https://WWW.", "https://www.www.site.com/", "https://wwwsite.com/", "", "   ", "not a url", "mailto:a@b.com",
    "https://[::1]:80/x", "https://[::1/x", "https://::1]/x", "ftp://ftp.site.com/arq", "https://site.com?x=1",
    "https://site.com#frag", "\thttps://www.site.com/\n", "  https://www.site.com/a", "HTTPS://WWW.SITE.COM/A",
    "https://www.sítio.com.br/á", "1http://www.site.com/", "ht tp://www.site.com/", "http:/www.site.com/",
    "https:www.site.com/a", "https://[zzz]/x", "https://[1.2.3.4]/x", "https://[v1.x]/x", "https://[fe80::1%eth0]/x",
    "https://[]/x", "https://www.site.com:abc/x",
]


def _caso_url(i, url):
    saida = {"dominio": nt.dominio(url), "favicon": nt.url_favicon({"fonte_url": url})}
    return base.caso(f"url_{i:03d}", "dominio", {"url": url}, saida)


DIFS = [0, 0.4, 1, 30, 59, 59.999, 60, 61, 119.9, 120, 3599, 3599.9999999, 3600, 3600.0001, 3601, 7199, 7200, 43200,
        86399, 86399.9999999, 86400, 86401, 129599, 172799, 172800, 259200, 432000, 518400, 604799, 604799.9999, -5, -3600]


def _caso_tempo(i, dif):
    ts = AGORA - dif
    return base.caso(f"tempo_{i:03d}", "tempo_relativo", {"ts": ts, "agora": AGORA},
                     {"texto": nt.tempo_relativo(ts, AGORA)})


TICKERS_LOGO = ["PETR4", "VALE3", "AAPL34", "BOVA11", "KLBN11", "A", "", "123", "ABCDE1", "pe1tr", "BRK-B", "1ABC",
                "X", "ABCD", "ABCDEF3", "AB3C4", "TAEE11F", "ÁÉÍÓ3", "😀😀😀😀😀1", "IVVB11", "HGLG11"]


def _caso_logo(i, t):
    png, svg = nt.urls_logo(t)
    return base.caso(f"logo_{i:03d}", "iniciais", {"ticker": t}, {"iniciais": nt.iniciais(t), "png": png, "svg": svg})


# ---------------------------------------------------------------- itens, mesclagem

def item(id_, titulo, data, tickers, fonte="Fonte X", fonte_url="https://www.fonte.com.br/x", link=None):
    return {"id": id_, "titulo": titulo, "link": link or f"https://news.google.com/rss/articles/{id_}",
            "fonte": fonte, "fonte_url": fonte_url, "data": float(data), "tickers": list(tickers),
            "temas": nt.temas(titulo)}


def _t(n, tema=True):
    """Título distinto e longo; com `tema`, cita dividendos (tema Proventos)."""
    return f"Notícia número {n:04d} sobre o mercado" + (" e dividendos da empresa" if tema else " e outras coisas")


def _casos_mesclar():
    c = []
    a = item("a1", "Petrobras anuncia dividendos extraordinários para novembro", AGORA - 100, ["PETR4"])
    a2 = item("a2", "Petrobras anuncia DIVIDENDOS extraordinários para novembro!", AGORA - 50, ["VALE3"])
    b = item("b1", "Vale divulga balanço do trimestre com lucro menor", AGORA - 300, ["VALE3"])
    c.append(base.caso("mesclar_simples", "mesclar", {"listas": [[a, b], [a2]]}, {"itens": nt.mesclar([[a, b], [a2]])}))
    # a mesma matéria: primeiro item vence (campos), tickers somados sem repetir, ordem de chegada
    x1 = item("x1", "Gerdau tem lucro maior no trimestre", AGORA - 10, ["GGBR4", "PETR4"], fonte="Valor")
    x2 = item("x2", "Gerdau tem lucro maior no trimestre", AGORA - 5, ["PETR4", "VALE3", "GGBR4", "ABEV3"], fonte="InfoMoney")
    c.append(base.caso("mesclar_duplicada", "mesclar", {"listas": [[x1], [x2]]}, {"itens": nt.mesclar([[x1], [x2]])}))
    # empate: mesma data, ordem original (reverse=True mantém a ordem dos empates)
    emp = [item(f"e{i}", f"Título empatado número {i} sobre dividendos", AGORA - 60, ["PETR4"]) for i in range(8)]
    emp += [item("e8", "Título mais novo com data maior sobre dividendos", AGORA, ["PETR4"]),
            item("e9", "Título mais antigo com data menor sobre dividendos", AGORA - 120, ["PETR4"])]
    listas = [emp[:3], emp[3:6], emp[6:]]
    c.append(base.caso("empate_mesma_data", "mesclar", {"listas": listas}, {"itens": nt.mesclar(listas)}))
    listas = [list(reversed(emp[:5])), emp[5:]]
    c.append(base.caso("empate_mesma_data_invertida", "mesclar", {"listas": listas},
                       {"itens": nt.mesclar(listas)}))
    # chaves iguais por acento/caixa/pontuação; títulos só de emoji colidem na chave vazia
    k = [item("k1", "Ação sobe forte hoje com dividendos", AGORA - 1, ["A1"]),
         item("k2", "ACAO, sobe forte: hoje com dividendos!", AGORA - 2, ["B2"]),
         item("k3", "😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀", AGORA - 3, ["C3"]),
         item("k4", "🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀", AGORA - 4, ["D4"]),
         item("k5", "Ørsted desaba na bolsa de Copenhague", AGORA - 5, ["ORST34"]),
         item("k6", "ØRSTED desaba na bolsa de Copenhague", AGORA - 6, ["X"])]
    c.append(base.caso("mesclar_chaves", "mesclar", {"listas": [k]}, {"itens": nt.mesclar([k])}))
    # corte em 150 e chave truncada em 90 caracteres
    longo = "Título muito longo " + "palavra " * 20
    grande = [item(f"g{i}", f"{longo} {i:03d} final" if i % 2 else _t(i), AGORA - (i % 40) * 60, [f"T{i % 5}"])
              for i in range(200)]
    c.append(base.caso("mesclar_limite", "mesclar", {"listas": [grande[:100], grande[100:]]},
                       {"itens": nt.mesclar([grande[:100], grande[100:]])}))
    c.append(base.caso("mesclar_vazio", "mesclar", {"listas": []}, {"itens": nt.mesclar([])}))
    c.append(base.caso("mesclar_listas_vazias", "mesclar", {"listas": [[], []]}, {"itens": nt.mesclar([[], []])}))
    return c


def _casos_textos():
    ts = ["PETR4", "VALE3", "ITUB4", "BBDC4", "ABEV3", "WEGE3", "MGLU3", "B3SA3", "RENT3"]
    novas = [item(f"n{i}", f"Dividendos e lucro número {i} no trimestre {i}", AGORA - i, ts[i:i + 1 + i % 5],
                  fonte="Valor" if i % 2 == 0 else "") for i in range(8)]
    novas[3]["temas"] = ["Resultado", "Proventos"]
    c = []
    for n in (0, 1, 2, 3, 4, 8):
        c.append(base.caso(f"textos_{n}_noticias", "textos_notificacao", {"novas": novas[:n]},
                           {"textos": nt.textos_notificacao(novas[:n])}))
    dois = [item("d1", "Dividendos da Petrobras", AGORA, ["PETR4", "VALE3", "ITUB4", "BBDC4", "ABEV3"]),
            item("d2", "Fato relevante da Vale", AGORA, ["VALE3", "PETR4"])]
    c.append(base.caso("textos_2_tickers", "textos_notificacao", {"novas": dois},
                       {"textos": nt.textos_notificacao(dois)}))
    quatro = [item("q1", "Dividendos da Petrobras", AGORA, ["PETR4", "VALE3", "PETR4"]),
              item("q2", "Fato relevante da Vale", AGORA, ["VALE3", "PETR4", "ITUB4"]),
              item("q3", "Resultado do Itaú no trimestre", AGORA, ["ITUB4", "ITUB4"]),
              item("q4", "Balanço do Bradesco no trimestre", AGORA, ["BBDC4"])]
    c.append(base.caso("textos_4_tickers", "textos_notificacao", {"novas": quatro},
                       {"textos": nt.textos_notificacao(quatro)}))
    oito = [item(f"o{i}", f"Dividendos da empresa {i} no trimestre", AGORA, [f"AAA{i}"]) for i in range(8)]
    c.append(base.caso("textos_8_tickers", "textos_notificacao", {"novas": oito},
                       {"textos": nt.textos_notificacao(oito)}))
    seis = oito[:4] + [item("s5", "Dividendos 5", AGORA, ["AAA4", "AAA5"])]
    c.append(base.caso("textos_resumo_seis_tickers", "textos_notificacao", {"novas": seis},
                       {"textos": nt.textos_notificacao(seis)}))
    return c


# ---------------------------------------------------------------- estado

def _ler(arquivo):
    """Estado como o Python lê de um arquivo com esse texto (None = sem arquivo)."""
    with base.pasta_dados():
        if arquivo is not None:
            nt._arquivo().write_text(arquivo, encoding="utf-8")
        return nt.ler_estado()


def _casos_ler_estado():
    c = []
    completo = {"itens": [item("i1", _t(1), AGORA, ["PETR4"])], "vistos": {"i1": AGORA - 5.5}, "conhecidos": ["PETR4"],
                "hora": AGORA - 700.25, "lidas_ate": AGORA - 90.5, "erros": {"VALE3": "Too Many Requests"}}
    for nome, arq in [("ausente", None), ("vazio", ""), ("corrompido", "{nao é json"), ("objeto_vazio", "{}"),
                      ("completo", json.dumps(completo, ensure_ascii=False)),
                      ("parcial", json.dumps({"itens": [], "hora": 5.0})),
                      ("inteiros", json.dumps({"hora": 3, "lidas_ate": 7, "vistos": {"a": 1}}))]:
        c.append(base.caso(f"ler_estado_{nome}", "ler_estado", {"arquivo": arq}, {"estado": _ler(arq)}))
    return c


def _gravar(estado):
    with base.pasta_dados():
        nt.gravar_estado(estado)
        return nt._arquivo().read_text(encoding="utf-8"), list(estado["vistos"])


def _estado_vazio():
    return {"itens": [], "vistos": {}, "conhecidos": [], "hora": 0.0, "lidas_ate": 0.0, "erros": {}}


def _casos_gravar():
    c = []
    e = _estado_vazio()
    e["itens"] = [item("i1", _t(1), AGORA, ["PETR4", "VALE3"])]
    e["vistos"] = {"i1": AGORA}
    e["conhecidos"] = ["PETR4", "VALE3"]
    e["hora"], e["lidas_ate"], e["erros"] = AGORA, AGORA - 1.5, {"ABEV3": "Erro: ação com acento ç"}
    arq, ordem = _gravar(json.loads(json.dumps(e)))
    c.append(base.caso("gravar_simples", "gravar_estado", {"estado": e}, {"arquivo": arq, "vistos": ordem}))
    for nome, n, valores in [("limite_exato", 3000, [1000.0 + i for i in range(3000)]),
                             ("corte_3005_empates", 3005, [2000.0 + (i % 7) for i in range(3005)]),
                             ("corte_3005_todos_iguais", 3005, [5.0] * 3005),
                             ("corte_3005_ordem_crescente", 3005, [1000.0 + i for i in range(3005)]),
                             ("corte_3005_ordem_decrescente", 3005, [9000.0 - i for i in range(3005)])]:
        e = _estado_vazio()
        e["vistos"] = {f"v{i:04d}": float(valores[i]) for i in range(n)}
        arq, ordem = _gravar(json.loads(json.dumps(e)))
        c.append(base.caso(f"gravar_{nome}", "gravar_estado", {"estado": e}, {"arquivo": arq, "vistos": ordem}))
    return c


def _roteiro(nome, estado_inicial, passos):
    """Executa os passos no Python (rede substituída pelas `respostas`) e devolve o caso com cada resultado."""
    resultados = []
    original = nt.buscar_ticker
    with base.pasta_dados():
        if estado_inicial is not None:
            nt._arquivo().write_text(json.dumps(estado_inicial, ensure_ascii=False), encoding="utf-8")
        try:
            for p in passos:
                if p["op"] == "buscar":
                    respostas = p["respostas"]

                    def falso(ticker, nome_="", respostas=respostas):
                        r = respostas[ticker]
                        if isinstance(r, dict):
                            raise RuntimeError(r["erro"])
                        return json.loads(json.dumps(r))

                    nt.buscar_ticker = falso
                    _, novas = nt.atualizar(p["radar"], agora=p["agora"])
                else:
                    nt.marcar_lidas(agora=p["agora"])
                    novas = []
                d = nt.ler_estado()
                resultados.append({
                    "novas": novas,
                    "textos": nt.textos_notificacao(novas),
                    "arquivo": nt._arquivo().read_text(encoding="utf-8"),
                    "nao_lidas": nt.nao_lidas(d),
                    "eh_nova": [nt.eh_nova(d, i) for i in d["itens"]],
                    "precisa": [nt.precisa_atualizar(d, p["agora"] + dz) for dz in DESLOCAMENTOS],
                })
        finally:
            nt.buscar_ticker = original
    return base.caso(nome, "roteiro", {"estado_inicial": estado_inicial, "passos": passos,
                                       "deslocamentos": DESLOCAMENTOS}, {"passos": resultados})


def _buscar(agora, tickers, respostas):
    return {"op": "buscar", "agora": float(agora), "radar": [{"ticker": t, "nome": ""} for t in tickers],
            "respostas": respostas}


def _casos_roteiros():
    c = []
    t0 = AGORA
    # 1. primeira busca marca tudo como visto; depois novidades na janela de 24 h
    p1 = [item("p1", "Petrobras anuncia dividendos extraordinários hoje", t0 - 3600, ["PETR4"]),
          item("p2", "Petrobras muda diretoria e conselho de administração", t0 - 7200, ["PETR4"])]
    v1 = [item("v1", "Vale divulga balanço do trimestre com lucro maior", t0 - 1800, ["VALE3"])]
    p3 = item("p3", "Petrobras aprova recompra de ações no valor de R$ 1 bilhão", t0 + 500 - 1000, ["PETR4"])
    p4 = item("p4", "Petrobras antiga: fato relevante de ontem à noite fora da janela", t0 + 500 - 90000, ["PETR4"])
    p5 = item("p5", "Petrobras inaugura nova plataforma sem tema importante algum", t0 + 500 - 100, ["PETR4"])
    v2 = item("v2", "Vale tem prejuízo no trimestre e ebitda cai", t0 + 500 - 200, ["VALE3"])
    c.append(_roteiro("roteiro_primeira_busca", None, [
        _buscar(t0, ["PETR4", "VALE3"], {"PETR4": p1, "VALE3": v1}),
        _buscar(t0 + 650, ["PETR4", "VALE3"], {"PETR4": p1 + [p3, p4, p5], "VALE3": v1 + [v2]}),
        _buscar(t0 + 1300, ["PETR4", "VALE3"], {"PETR4": p1 + [p3, p4, p5], "VALE3": v1 + [v2]}),
    ]))
    # 2. ativo com erro mantém os itens antigos; erro some quando volta
    c.append(_roteiro("roteiro_ativo_com_erro", None, [
        _buscar(t0, ["PETR4", "VALE3"], {"PETR4": p1, "VALE3": v1}),
        _buscar(t0 + 650, ["PETR4", "VALE3"], {"PETR4": p1 + [p3], "VALE3": {"erro": "Too Many Requests"}}),
        _buscar(t0 + 1300, ["PETR4", "VALE3"], {"PETR4": {"erro": "HTTPSConnectionPool: tempo esgotado"},
                                                  "VALE3": v1 + [v2]}),
        _buscar(t0 + 1950, ["PETR4", "VALE3"], {"PETR4": {"erro": "x" * 250}, "VALE3": {"erro": "y"}}),
        _buscar(t0 + 2600, ["PETR4", "VALE3"], {"PETR4": p1 + [p3], "VALE3": v1 + [v2]}),
    ]))
    # 3. ativo novo (estreia) e ativo removido do radar; matéria em dois ativos
    comum = item("c1", "Setor de petróleo e gás tem dividendos recordes no ano", t0 + 500 - 300, ["PETR4", "PRIO3"])
    comum2 = item("c2", "Setor de petróleo e gás tem DIVIDENDOS recordes no ano", t0 + 500 - 290, ["PRIO3"])
    n1 = item("n1", "Prio tem lucro recorde e dividendos no trimestre", t0 + 500 - 400, ["PRIO3"])
    c.append(_roteiro("roteiro_ativo_novo_e_removido", None, [
        _buscar(t0, ["PETR4", "VALE3"], {"PETR4": p1, "VALE3": v1}),
        _buscar(t0 + 650, ["PETR4", "PRIO3"], {"PETR4": p1 + [comum], "PRIO3": [comum2, n1]}),
        _buscar(t0 + 1300, ["PRIO3"], {"PRIO3": [comum2, n1]}),
        _buscar(t0 + 1950, [], {}),
    ]))
    # 4. limite de 150 itens e muitas notificações (resumo)
    grandes = [item(f"m{i:03d}", _t(i, tema=i % 3 != 0), t0 + 1000 - (i % 60) * 10 - i, ["PETR4"]) for i in range(170)]
    c.append(_roteiro("roteiro_limite_150", None, [
        _buscar(t0, ["PETR4"], {"PETR4": grandes[:5]}),
        _buscar(t0 + 650, ["PETR4"], {"PETR4": grandes}),
        _buscar(t0 + 1300, ["PETR4"], {"PETR4": grandes[10:] + [item("novo", _t(999), t0 + 1300, ["PETR4"])]}),
    ]))
    # 5. lidas_ate e não lidas
    c.append(_roteiro("roteiro_lidas", None, [
        _buscar(t0, ["PETR4", "VALE3"], {"PETR4": p1, "VALE3": v1}),
        _buscar(t0 + 650, ["PETR4", "VALE3"], {"PETR4": p1 + [p3], "VALE3": v1}),
        {"op": "lidas", "agora": t0 + 700.5},
        _buscar(t0 + 1300, ["PETR4", "VALE3"], {"PETR4": p1 + [p3, p5], "VALE3": v1 + [v2]}),
        {"op": "lidas", "agora": t0 + 1400.25},
        _buscar(t0 + 1500, ["PETR4", "VALE3"], {"PETR4": p1 + [p3, p5], "VALE3": v1 + [v2]}),
    ]))
    # 6. empates de data nas notícias e mesclagem na busca
    emp = [item(f"t{i}", f"Dividendos empatados número {i} no mesmo instante", t0 - 100, ["PETR4"]) for i in range(6)]
    emp_v = [item(f"u{i}", f"Dividendos empatados número {i} no mesmo instante", t0 - 100, ["VALE3"]) for i in range(3)]
    emp_v += [item("u9", "Lucro empatado da Vale no mesmo instante exato", t0 - 100, ["VALE3"])]
    c.append(_roteiro("empate_mesma_data_busca", None, [
        _buscar(t0, ["PETR4", "VALE3"], {"PETR4": emp[:2], "VALE3": emp_v[:1]}),
        _buscar(t0 + 650, ["PETR4", "VALE3"], {"PETR4": emp, "VALE3": emp_v}),
        _buscar(t0 + 1300, ["VALE3", "PETR4"], {"PETR4": list(reversed(emp)), "VALE3": emp_v}),
    ]))
    # 7. estado inicial pronto (lidas_ate zerado, vistos, conhecidos) e acentos
    ini = {"itens": [item("z1", "Ação da Nestlé sobe com dividendos", t0 - 5000, ["NESN34"])],
           "vistos": {"z1": t0 - 4000.5}, "conhecidos": ["NESN34"], "hora": t0 - 5000.0, "lidas_ate": 0.0, "erros": {}}
    z2 = item("z2", "Nestlé reporta lucro maior; Ação sobe", t0 - 60, ["NESN34"], fonte="Valor Econômico")
    z3 = item("z3", "Ørsted despenca e Itaú Unibanco divulga balanço", t0 - 30, ["NESN34"], fonte="")
    c.append(_roteiro("roteiro_estado_inicial", ini, [
        _buscar(t0, ["NESN34"], {"NESN34": ini["itens"] + [z2, z3]}),
        _buscar(t0 + 20, ["NESN34"], {"NESN34": ini["itens"] + [z2, z3]}),
    ]))
    # 8. hora de busca passada, janela exata de 24 h
    j1 = item("j1", "Dividendos exatamente na borda da janela de vinte e quatro horas", t0 - 86400, ["PETR4"])
    j2 = item("j2", "Dividendos um segundo além da borda da janela de vinte e quatro horas", t0 - 86401, ["PETR4"])
    j3 = item("j3", "Dividendos um segundo dentro da borda da janela de vinte e quatro horas", t0 - 86399, ["PETR4"])
    c.append(_roteiro("roteiro_janela_24h", None, [
        _buscar(t0 - 5, ["PETR4"], {"PETR4": p1}),
        _buscar(t0, ["PETR4"], {"PETR4": p1 + [j1, j2, j3]}),
    ]))
    return c


# ---------------------------------------------------------------- casos

def casos():
    c = []
    for i, t in enumerate(_titulos()):
        c.append(_caso_titulo(i, t, "titulo"))
    # grupo `unicode` (Review Focus 4): cada título de UNICODE também entra com o nome do grupo
    for i, t in enumerate(UNICODE):
        c.append(_caso_titulo(i, t, "unicode"))
    c += [_caso_nome(i, t, n) for i, (t, n) in enumerate(NOMES)]
    c += [_caso_url(i, u) for i, u in enumerate(URLS)]
    c += [_caso_tempo(i, d) for i, d in enumerate(DIFS)]
    c += [_caso_logo(i, t) for i, t in enumerate(TICKERS_LOGO)]
    c += _casos_mesclar()
    c += _casos_textos()
    c += _casos_ler_estado()
    c += _casos_gravar()
    c += _casos_roteiros()
    return c
