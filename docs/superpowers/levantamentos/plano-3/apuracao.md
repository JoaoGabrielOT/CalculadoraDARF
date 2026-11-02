# Levantamento: Apuração (cabeçalho, mês, Visualizando, indicadores, detalhamento e Fechar mês)

Origem Windows: `calculadora_darf.py` (barra 1279-1295, KPIs 1334-1345, Detalhamento 1408-1443, `atualizar` 1520-1612, `fechar_mes` 1733-1770, seletor de mês 1986-1990, Visualizando 2933-3010). Origem Android: `android/main.py` (`tela_apuracao` 725-866, `abrir_meses` 1086-1125, `fechar_mes` 1127-1184, compra nova 1304). As tabelas de compras e vendas, os filtros e as cotações são da Tarefa 14. O que só existe numa plataforma vale para as duas.

| Elemento | Windows | Android | Comportamento no app | Coberto por |
|---|---|---|---|---|
| Visualizando + seletor | py:1281-1285, 2933-2945 | android:766 | "Visualizando" com "Meus dados" e os e-mails dos amigos; desabilitado durante a carga do amigo | `o seletor Visualizando lista Meus dados e os amigos` |
| Atualizar | py:1286, 2988 (só com amigo) | não existe | só habilitado com amigo aberto; baixa os dados dele de novo | `Visualizando amigo: subtítulo e Atualizar habilitado`; `selo e botões: visão de amigo` |
| Subtítulo "Dados de <email> · somente leitura" | py:1521-1524 | n/a | já na casca (Tarefa 9) | `Visualizando amigo: subtítulo e Atualizar habilitado` |
| Botão do mês "<MM/AAAA>  ▾" | py:1525, 1986-1990 | android:739 (sem a seta) | mesmo texto nas duas; abre a grade de meses; meses com dados vêm do serviço (`mesesComDados`, do amigo se houver) | `trocar o mês pelo seletor recarrega; Mês atual volta` |
| "Mês atual" no seletor | py:SeletorMes | android:1118 | já no componente `escolherMes` | `trocar o mês pelo seletor recarrega; Mês atual volta` |
| Selo "● Aberto" / "Fechado" / "Somente leitura" | py:1527-1534 | android:730-737 | `Pilula`; "Somente leitura" na cor de aviso | `selo e botões por estado...` (3 testes) |
| Fechar mês (botão) | py:1295, 1536-1539 | menu "Fechar mês" no `⋮` (android:738) | PC: botão cheio; celular: item do menu. Desabilitado em mês fechado, visão de amigo, mês ilegível, durante a carga e durante o fechamento | `selo e botões por estado...`; `compacto: regimes... e FAB`; `compacto: mês fechado e amigo não têm FAB nem menu` |
| FAB "Nova compra" | n/a (botão na tabela, Tarefa 14) | android:704-711 | só no celular, só quando editável; `ControleApuracao.novaCompra` serve também ao botão da Tarefa 14 | `compacto: regimes... e FAB` |
| Pergunta "Você já fez a venda de X?" | não existe | android:1304 | depois de uma compra nova (não na edição): "Sim, registrar venda" abre a venda com o lote novo; "Ainda não" encerra | `compra nova pergunta se já houve a venda...`; `Ainda não encerra...` |
| Cartão de saldo | botão "Saldo" na casca | android:742-751 | celular: "Saldo disponível R$ X · projetado R$ Y" ou "Definir saldo em conta"; leva à aba Caixa; some na visão de amigo | `cartão de saldo mostra o caixa e leva à aba Caixa` |
| Cartão "Meta de lucro / Preço-alvo · N ativa(s)" | botão na casca | android:753-763 (770) | celular: abre as metas pelo callback `aoAbrirMetas` (o diálogo é de tarefa futura); some na visão de amigo | `cartão 'Meta de lucro / Preço-alvo · N ativas' abre as metas` |
| KPIs Lucro bruto / Lucro líquido / Imposto devido / Total da DARF | py:1334-1345, 1569-1592 | android:785-796 (blocos "Imposto a pagar" e "Resultado do mês") | PC: 4 colunas; celular: 2x2; verde/vermelho no resultado; Total da DARF em verde a partir de R$ 10 | `mostra KPIs e detalhamento...` |
| Subtextos "N venda(s) no mês", "após taxas e impostos", "IRRF já retido: ...", info da DARF | py:1584-1592 | android:781-796 | funções `textoVendasNoMes`, `textoIrrfRetido`, `textoInfoDarf` | `mostra KPIs e detalhamento...`; `acima do limite e sem IRRF` |
| "Inclui R$ X de meses anteriores" | não existe | android:783 | só no celular, abaixo da info da DARF | `compacto: regimes... e FAB` |
| Cartões Swing trade / Day trade | não existe | android:798-814 | só no celular: imposto, "Alíquota N% · X venda(s)", "Isento até R$ 20 mil em ações" / "Acima do limite de isenção", "Sem isenção" | `compacto: regimes... e FAB` |
| Detalhamento | lateral de 340 px (py:1408) | ExpansionTile recolhido (android:816) | PC: lateral à direita do conteúdo; celular: cartão recolhido abaixo | `mostra KPIs e detalhamento...` |
| LIMITE DE ISENÇÃO (AÇÕES · SWING) + "R$ x  de  R$ 20.000,00" + barra | py:1412-1421, 1594-1603 | android:819-824 | barra verde se isento, vermelha se acima; texto "Isento de IR em swing trade de ações" / "Acima do limite · lucro tributado em 15%" | `mostra KPIs e detalhamento...`; `acima do limite e sem IRRF` |
| Linhas Taxas B3 + corretagem, Imposto swing (15%), day trade (20%), IRRF retido (dedo-duro) com "- " na frente (R$ 0,00 sem sinal), DARF de meses anteriores | py:1422-1427, 1605-1610 | android:826-834 | iguais nas duas | `mostra KPIs e detalhamento...`; `acima do limite e sem IRRF` |
| "Imposto devido" no Detalhamento | não existe | android:829 | entra nas duas | `mostra KPIs e detalhamento...` (indireto: a linha segue o KPI) |
| "Total a pagar" + info da DARF | py:1428-1433, 1609 | n/a | entra nas duas | `mostra KPIs e detalhamento...` |
| Rodapé "Código da DARF: 6015 / Vencimento... / Taxas B3..." | py:1436-1443 | n/a | entra nas duas (no celular dentro do Detalhamento) | `mostra KPIs e detalhamento...` |
| Fechar mês: com metas ativas verifica antes | py:1738-1769 | android:1127-1160 | `prepararFechamento` só se há metas ativas; a tela segue viva durante a verificação | `executadas e inválidas...`; `sem metas ativas vai direto...` |
| Bloqueio: "Não foi possível fechar o mês" + motivo | py:1749-1750 | android:1143-1148 | diálogo; não pede confirmação | `bloqueio mostra Não foi possível fechar o mês` |
| Falha do preparo: "Falha ao verificar as metas antes de fechar: <texto>" (até 120 caracteres) | py:1766-1768 | android:1135-1137 | por `textoErro` | `falha do preparo mostra o motivo e não fecha` |
| "Metas verificadas antes de fechar": "T: venda de N registrada pela meta." / "T: meta inválida. <erro>" | py:1751-1759 | android:1149-1157 (avisos soltos) | um diálogo com as linhas; a tela recarrega antes | `executadas e inválidas...` |
| Resultado vale só se o mês não mudou | py:1747 | android:1142 | troca de mês durante a verificação descarta o resultado | `trocar de mês durante a verificação descarta o resultado` |
| Confirmação "Fechar MM/AAAA" com "Total da DARF" | py:1771-1777 | android:1163-1178 | botão "Fechar mês"; Cancelar não fecha | `sem metas ativas vai direto...`; `cancelar a confirmação não fecha` |
| "Mês fechado" com a mensagem do serviço | py:1778 | android:1171-1175 | diálogo; erro do serviço aparece como "Não foi possível fechar o mês" | `sem metas ativas vai direto...` |
| Mês ilegível | n/a | n/a | faixa de aviso com o texto do serviço; seletor de mês funciona; botões desabilitados | `mês ilegível mostra aviso e permite trocar de mês` |
| Erro ao carregar | n/a | n/a | faixa de aviso por `textoErro`; seletor continua | `erro ao carregar o mês aparece e o seletor continua` |
| Recarregar com `versaoDados` | py:agendar_sync/recarregar | android:`recarregar` | a tela recarrega sem bloquear; resposta antiga é descartada; a visão anterior fica até a nova chegar (exceto troca de mês ou visão) | `versaoDados mudando recarrega a tela`; `resposta antiga de um recarregamento é descartada`; `compacto: a lista rola enquanto o mês carrega` |
