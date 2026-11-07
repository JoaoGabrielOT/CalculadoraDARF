# Levantamento: Gráfico do ativo

Origem Windows: `calculadora_darf.py:3011-3232` (`JanelaGrafico`). Origem Android: `android/main.py:352-567` (`GraficoAtivo`). Código: `app/lib/app/telas/grafico/tela_grafico.dart`. Testes: `app/test/app/telas/grafico/tela_grafico_test.dart`. O serviço é `ServicosApp.grafico(ticker, periodo)`; a linha é o `GraficoLinha(interativo: true)` do Plano 3 (tocar, arrastar ou passar o mouse mostra o ponto mais próximo). O que só existe numa plataforma vale para as duas.

| Elemento | Windows | Android | Comportamento no app | Coberto por |
|---|---|---|---|---|
| Abertura | py:3014-3016 | android:355-358 | `abrirGrafico`: expandido (>= 840) diálogo de até 960×640 (em janela baixa o corpo rola); compacto, tela cheia. Abre no período 1D | `abre no 1D ...`; `compacto abre em tela cheia` |
| Cabeçalho | py:3020-3040 | android:379-386 | logo, ticker, nome (item ou Yahoo), preço `brl` ("—" sem preço) e "<fmtPct>  (<+>R$ var) hoje" na cor da variação; sem variação: "variação do dia indisponível" | `estatísticas ...`; `sem dados do ativo ...` |
| Períodos | py:3042-3050 | android:371, 417-419 | chips 1D, 5D, 1M, 6M, 1A, 5A, Máx (`periodosGrafico`); trocar pede o gráfico do período e mostra "Carregando…" | `abre no 1D ...` |
| Variação do período | py:3125-3131 | android:437-440 | "<fmtPct> hoje" (1D), "desde o início" (Máx), "em <período>"; último ponto contra a referência, na cor da variação | `abre no 1D ...` |
| Resposta atrasada | py:3128 (`periodo != self.periodo`) | android:432 | descartada por contador de geração | `resposta atrasada ...` |
| Erro | py:3116-3121 | android:428-430 | `textoErro` na cor de queda no lugar do gráfico; trocar de período tenta de novo | `erro mostra mensagemErro ...` |
| Linha e área | py:3133-3190 | android:442-490 | `GraficoLinha` (cor pela referência; no 1D a linha tracejada do fechamento anterior, com o texto "Fech. anterior R$ x" acima do gráfico) | `abre no 1D ...` |
| Eixo de preços e grade | py:3176-3180 | android:455-460 | 5 linhas de grade com o `brl` de cada nível (min a max dos pontos e, no 1D, da referência) à direita do gráfico; só nesta tela, o mini-gráfico do radar fica sem eixo | `eixo de preços tem 5 rótulos ...` |
| Posição dos pontos | py:3164-3165 | android:449 | por índice (x = i/(n-1)), como no Python: a marca de tempo escolhida por índice cai sempre sob o ponto, mesmo com vãos de fim de semana | `marcas de tempo ficam sob os pontos ...` |
| Cor da linha | py:3157 | android:441 | `último >= referência` em todos os períodos (empate é alta) | `cor da linha ...` |
| Rótulos de tempo | py:3133-3143 | android:443-450 | 4 marcas sob o gráfico, curtas (1D "HH:MM"; 5D "dd/mm"; 5A e Máx "mm/aaaa"; demais "dd/mm/aa"), com o desvio de fuso do gráfico | `rótulos de tempo ...` |
| Ponto tocado | py:3192-3232 | android:530-567 | "<tempo> · <brl> · <fmtPct vs referência>" (tempo longo: 1D "HH:MM", 5D "dd/mm HH:MM", 5A e Máx "mm/aaaa", demais "dd/mm/aaaa"); sem toque: "Toque no gráfico para ver o preço de cada ponto" (compacto) ou "Passe o mouse sobre o gráfico para ver o preço de cada ponto" (PC) | `tocar e arrastar ...` |
| Estatísticas | py:3068-3090 | android:387-401 | Fech. anterior, Mín./máx. do dia, Mín./máx. 52 sem., Média 6 meses (com % vs média), ATR (14) (com ATR%), Volume (`fmtVolume`); "—" sem valor | `estatísticas ...` |
| Ver notícias | py:3012, 3098 | android:403-404, 411 | fecha e abre Notícias filtrada pelo ticker (`EstadoApp.filtroNoticias`) | `Ver notícias, Comprar ...`; `radar abre o gráfico ...` |
| Comprar / Vender | py:3101-3105 | android:407-410 | fecha e chama os callbacks do radar; Vender só se o radar passa `aoVender` (ticker em custódia) | idem |
| Meu radar (importar) | py:3099-3100 | android:405-406 | só no radar de amigo e se o ticker não está no meu radar; fecha e importa | `amigo: importar ...` |
| Fechar | py:3095, 3107 | android:415 | botão e Esc | `Esc fecha ...` |
| Toque na linha do radar | py:854-856 | android:1866 | `TelaRadar` abre o gráfico sozinha quando não recebe `aoAbrirGrafico` | `radar abre o gráfico ...` |
