# Levantamento: Apuração, Ativos comprados e Vendas do mês

Origem Windows: `calculadora_darf.py` (tabelas 1360-1407, filtro SITUAÇÃO e contagem 1497-1505, linhas 1541-1590, ações 1613-1732, timer de cotações 2578-2585). Origem Android: `android/main.py` (listas 828-859, filtros 867-955, itens e menus 957-1070). O que só existe numa plataforma vale para as duas. Código: `app/lib/app/telas/apuracao/` (`lista_lotes.dart`, `lista_vendas.dart`, `barra_filtros.dart`, `controle_apuracao.dart`). Testes: `app/test/app/telas/apuracao/listas_test.dart`.

| Elemento | Windows | Android | Comportamento no app | Coberto por |
|---|---|---|---|---|
| Título "Ativos comprados" + contagem | py:1356-1358, 1503-1505 | android:833-834, 918 | contagem "N"; com algum filtro fora do padrão "visíveis/total" | `expandido: ordena pelo título e filtra por situação com contagem 'visíveis/total'` |
| Tabela de ativos, 11 colunas | py:1384-1389 | n/a | TICKER, TIPO, COMPRA, QTD, PREÇO, ATUAL, TOTAL, GANHO/PERDA, VENDIDA, RESTANTE, SITUAÇÃO; ordenam ticker, compra, qtd, preço, atual, total, ganho/perda, restante | `expandido: tabela de ativos com as 11 colunas` |
| "Clique nos títulos das colunas para ordenar" | py:1383 | n/a | texto abaixo dos filtros (só expandido) | `expandido: tabela de ativos com as 11 colunas` |
| Botões "+  Novo ativo", "Registrar venda", "Editar", "Excluir" | py:1357-1364 | android:836-838 (só Registrar venda) | expandido: os quatro acima da tabela; compacto: "Registrar venda" no cabeçalho e FAB "Nova compra" (Tarefa 13); desabilitados/ausentes sem `visao.editavel` (amigo, mês fechado, erro de leitura) | `mês fechado, amigo ou erro de leitura: nada de gravar`; `visão de amigo: ...` |
| Filtro SITUAÇÃO (Todos / Em aberto / Vendidos) | py:1366-1374 | android:845-847 (chip) | expandido: botão segmentado; compacto: chip "Situação"; mesmo filtro nos dois | `expandido: ordena pelo título e filtra por situação...` |
| Busca de ticker | n/a | android:877-905 | chip de busca + campo "Buscar ticker" nas duas larguras; maiúsculas | `filtros da união (expandido/compacto): busca, tipo, ordem, inverter e Limpar nas compras` |
| Chip Tipo (Todos / Ação / BDR) | n/a | android:51, 846 | nas duas larguras, compras e vendas | idem; `filtros da união ... operação, tipo e busca nas vendas` |
| Chip Ordenar + inverter | n/a | android:45-49, 871-876, 898 | ordens do Android; escolher uma ordem define o sentido padrão (`descPadrao`); botão "Crescente ↑/Decrescente ↓" inverte | `filtros da união ... ordem, inverter` |
| Chip Limpar | n/a | android:900-902 | aparece com filtro fora do padrão; zera busca, tipo, situação/operação, ordem e sentido | `filtros da união ...` |
| Barra de filtros só com itens | py:(sempre) | android:844, 854 | só aparece com ao menos uma compra / venda no mês | `listas vazias mostram a mensagem do Python` |
| Linha: ATUAL "…" / preço / "—" | py:1553-1556 | android:979-985 | "…" até a cotação chegar, preço, "—" sem cotação ou vendido; no cartão "Atual: carregando…" / "sem cotação" | `cotação atual: '…' antes de chegar, preço depois, '—' em vendidos; ▲ verde e ▼ vermelho` |
| GANHO/PERDA com ▲/▼ e cor | py:1557-1561, 1574 | android:976-978 | ▲ verde (> 0,004), ▼ vermelho (< -0,004), "—" sem cotação | idem |
| Linha de venda: cor negativa | py:1583 | android:1030 | líquido negativo em vermelho | `cotação atual...` (cores) e tabela de vendas |
| Cotações da carteira | py:1565, 2578-2585 | android:862-863 | busca ao carregar o mês e a cada compra/venda gravada; a cada 60 s só com a aba Apuração visível e meus dados; falha vira "—" | `cotações só se repetem a cada 60 s...`; `falha das cotações vira "—"` |
| Duplo clique na compra | py:1386-1387 | n/a | abre Registrar venda com a compra | `duplo clique na compra abre Registrar venda com o lote` |
| Duplo clique na venda | py:1406-1407 | n/a | abre Editar venda | `duplo clique na venda abre Editar venda` |
| Nova compra e "Você já fez a venda de <T>?" | py:1622-1634 | android:1304 | `ControleApuracao.novaCompra` pergunta; "Sim, registrar venda" abre a venda com a compra | `nova compra pergunta 'Você já fez a venda de <T>?' e abre a venda no Sim` |
| "Não há compras em aberto neste mês." | py:1636-1644 | android | aviso do formulário (`abrirFormVenda`), uma só vez | `Registrar venda sem compra em aberto avisa uma vez só` |
| Aviso de venda retroativa | py:1655-1674 | android | aviso do formulário; o controle não repete | (Tarefa 12) |
| Editar compra | py:1678-1692 | android:1004-1006 | sem seleção: "Editar" / "Selecione uma compra na tabela de ativos comprados." | `expandido: botões sem seleção avisam com o texto do Python` |
| Editar venda | py:1693-1708 | android:1054-1057 | sem seleção: "Editar" / "Selecione uma venda na tabela de vendas." | idem |
| Excluir compra | py:1709-1721 | android:1065-1070 | "Excluir ativo" (expandido) ou "Excluir compra" (compacto); "Excluir <T>?" ou "Excluir <T> e todas as vendas dele?"; sem seleção: "Selecione um ativo na tabela de ativos comprados." | `excluir pede confirmação com o texto do Python`; `compacto: cartões com menu de item...` |
| Excluir venda | py:1722-1732 | android:1043-1050 | "Excluir venda" / "Excluir esta venda?"; sem seleção: "Selecione uma venda na tabela de vendas." | idem |
| Menu de item (compacto) | n/a | android:996-1010, 1052-1059 | compra: Registrar venda (só com restante), Editar compra, Excluir compra; venda: Editar venda, Excluir venda; ausente sem `editavel` | `compacto: cartões com menu de item...`; `compacto: mês fechado não tem menu de item` |
| Vazio das compras | py:1383 | android:836-843 | expandido: "Nenhum ativo neste mês. Clique em  +  Novo ativo  para começar."; compacto: "Nenhuma compra neste mês" + botão "Nova compra"; com filtro: "Nenhum ativo para esse filtro." | `listas vazias mostram a mensagem do Python` |
| Vazio das vendas | py:1403 | android:957-959 | "Nenhuma venda registrada neste mês." / "Nenhuma venda para esse filtro." | idem, `filtros da união ... vendas` |
| Rolagem durante o carregamento | n/a | n/a | tabela com altura limitada (lazy); cotações não bloqueiam | `lista rola enquanto as cotações da carteira carregam` (expandido e compacto) |
