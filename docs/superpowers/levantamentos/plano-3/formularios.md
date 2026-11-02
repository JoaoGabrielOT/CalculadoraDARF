# Levantamento: formulários de compra, venda e saldo

Origem Windows: `calculadora_darf.py` (FormBase 114-215, FormCompra 228-311, FormVenda 314-535, FormSaldo 538-580, chamada da venda 1636-1675). Origem Android: `android/main.py` (ResumoOrdem 251-285, CampoData 292-350, `form_compra` 1185-1300, `form_venda` 1302-1548, `editar_saldo` 1627-1681). O que só existe numa plataforma vale para as duas.

Tarefa 12 cobre os formulários; a chamada deles (botões, tabela, pergunta "Você já fez a venda de X?" do Android, 1294-1299) é da Tarefa 13.

## Estrutura comum

| Elemento | Windows | Android | Comportamento no app | Coberto por |
|---|---|---|---|---|
| Formato | janela modal de 360 px (py:117) | diálogo de 380 px (android:1291) | expandido: diálogo de 420 px; compacto: rota em tela cheia com barra de título | `expandido: diálogo de 420 px`; `compacto: tela cheia...` |
| Salvar / Cancelar | botões à direita (py:150-153) | `Salvar` e `Cancelar` (android:1295) | `Cancelar` fecha com nulo; `Salvar` valida e chama o serviço; os dois ficam desabilitados enquanto grava | `salvar devolve a visão nova...` |
| Enter / Esc | Enter salva, Esc cancela (py:164-165) | não existe | Enter e Enter do teclado numérico salvam, Esc cancela; ignorados enquanto grava | `salvar devolve a visão nova; Enter também salva`; `Esc cancela...` |
| Erro | rótulo vermelho no rodapé, janela não fecha (py:145-170) | texto vermelho; erros do serviço viravam aviso depois de fechar | erro de validação e erro do serviço no rodapé, formulário aberto; `PedidoSuperado` não aparece; texto por `textoErro` | `erro do serviço aparece no rodapé sem fechar` (3 formulários) |
| Foco inicial | ticker, ou quantidade se há ticker (py:271); preço na venda com ticker (py:366); valor no saldo (py:549) | sem foco forçado | mesmo do Windows | `iniciais preenchem os campos e focam a quantidade`; `lote e ticker iniciais vêm escolhidos` |
| Alvos de toque | n/a | n/a | botões com 48 dp em compacto | `compacto: tela cheia com botões de 48 dp` |
| Rótulos dos campos | maiúsculas acima do campo (`TICKER`, `QUANTIDADE`...) | rótulo flutuante com `*` | rótulo flutuante sem `*`, textos do Android sem o asterisco | captura visual |

## Resumo financeiro da ordem (`PainelResumoOrdem`)

| Elemento | Origem | Texto / comportamento | Coberto por |
|---|---|---|---|
| Título | py:180; android:261 | `RESUMO FINANCEIRO DA ORDEM` | `incompleto mostra traços...` |
| Linhas | py:181-188; android:262-264 | `Valor bruto`, `Taxas B3 (estimadas)`, `IRRF retido` (`R$ 0,00` quando zero) | `compra mostra valores, débito e liquidação` |
| Incompleto | py:202-205; android:269-273 | traços e `Preencha quantidade, preço e data.`; nota vazia | `incompleto mostra traços...`; `resumo muda ao digitar...` |
| Impacto | py:209-212; android:275-278 | `Será debitado da conta: …` (vermelho) ou `Será creditado na conta: …` (verde) | `compra mostra...`; `venda mostra crédito` |
| Liquidação | py:213; android:279 | `📅 Liquidação financeira: <dia, dd/mm/aaaa>` | `compra mostra...` |
| Nota da compra | py:270 | `Se vender no mesmo dia (day trade), a B3 liquida só o resultado do dia.` | `resumo muda ao digitar...` |
| Nota da venda | py:454-455; android:1336 | swing: `Swing trade: crédito do valor da venda menos as taxas da B3.` (o Android omitia `da B3`; vale o do Windows); day trade: `Day trade (compra e venda no mesmo dia): a B3 liquida só o resultado, já com o IRRF de 1% sobre o lucro.` | `a interface responde enquanto o preço sugerido não chega`; `venda no dia da compra é day trade` |
| Cálculo ao digitar | android:1233-1243 (Windows: ao soltar a tecla, py:259-266) | recalcula a cada mudança de quantidade, preço ou data com `resumoOrdem` do núcleo | `resumo muda ao digitar...` |

## Compra

| Elemento | Origem | Texto / comportamento | Coberto por |
|---|---|---|---|
| Título e subtítulo | py:229-236; android:1291 | `Novo ativo` / `Dados da compra`; editando: `Editar compra` / `Já vendidas: N` (só com vendas) | `chips Frequentes...`; `editar: preenche os campos...` |
| Ticker | py:238-242; android:1197 | campo `Ticker`, dica `Ex.: PETR4`, maiúsculas | `validação local mostra a mensagem do Python...` |
| Chips | py:127-140; android:1275-1276 | título `Frequentes`, atalhos de `sugestoesTicker(mes)`; escolher preenche o ticker, mostra o tipo e foca a quantidade; o chip do ticker digitado fica marcado; sem sugestões nada aparece | `chips Frequentes preenchem...` |
| Tipo | py:272-274; android:1200-1203 | a partir de 5 caracteres: `Tipo: Ação (identificado pelo ticker)` | `chips Frequentes preenchem...` |
| Data da compra | py:277-280; android:1211 | `CampoData`; padrão hoje; máximo hoje, ou o dia da primeira venda quando editando uma compra com vendas | `editar: ... limita a data...` |
| Quantidade | py:281-282; android:1214 | dica `Ex.: 100` | `salvar devolve a visão nova...` |
| Preço unitário | py:283-284; android:1215 | rótulo `Preço unitário (R$)`, dica `Ex.: 32,50`; editando: `fmtNum` | `editar: preenche os campos...` |
| Preenchimento ao editar | py:231-236; android:1190-1194 | ticker, quantidade e preço da compra | `editar: preenche os campos...` |
| Valores iniciais | android:1185 (`ini`) | `iniciais` com `ticker`, `qtd`, `preco` | `iniciais preenchem...` |
| Validação | py:288-311 | `validarCompra` (Tarefa 11); data vazia/inválida/fora do período bloqueia o salvar (`Selecione a data da compra.`) e nunca usa a data anterior; data futura recusada (só no Windows; vale nas duas) | `data inválida bloqueia...`; `validação local...` |
| Salvar | py:306-311; android:1259-1274 | `registrarCompra(mes, …)` ou `editarCompra(mes, id, …)`; o serviço revalida contra o disco | `salvar devolve a visão nova...`; `editar: ...` |
| Mês fechado / amigo | android:1186 | `abrirFormCompra` devolve nulo se a visão não é editável | captura visual |

## Venda

| Elemento | Origem | Texto / comportamento | Coberto por |
|---|---|---|---|
| Título e subtítulo | py:315; android:1356 | `Registrar venda` / `Editar venda`; subtítulo `Mês MM/AAAA` (`fmtMes`) | `ao escolher o ticker...` |
| Sem compras em aberto | py:1642-1644; android:1313 | aviso `Registrar venda`: `Não há compras em aberto neste mês.`, formulário não abre | `sem compras em aberto avisa...` |
| Ticker | py:337-340 | campo `Ticker`; digitar seleciona o ticker; editando fica desabilitado | `editar: compra e ticker fixos...` |
| Chips | py:341; android:1322, 1431 | atalhos de `sugestoesTicker(mes, soCustodia: true)`; título `Em carteira` (Android; o Windows usava `Frequentes`, mas a lista é só do que está em carteira); editando: sem chips | `ao escolher o ticker...`; `editar: ...` |
| Compra | py:342-352, 370-379 | lista `dd/mm/aaaa  ·  R$ preço  ·  N disp.`; rótulos repetidos ganham ` (2)`, ` (3)`...; a primeira é escolhida (ou a do lote inicial) | `ao escolher o ticker...`; `rótulos repetidos...`; `lote e ticker iniciais...` |
| Sem opção | py:381-383; android:1393-1396 | lista desabilitada com `Escolha um ticker` (ticker vazio) ou `Nenhuma compra em aberto desse ticker`; quantidade volta a `Quantidade`; resumo incompleto | `ao escolher o ticker...` |
| Informação | py:395-398; android:1366-1369 | `<tipo>  ·  Custo R$ x  ·  Disponível: N`; mais `Não há data válida para vender essa compra neste mês.` quando o período é vazio | `ao escolher o ticker...` |
| Quantidade | py:399-400; android:1370-1371 | rótulo `Quantidade (máx. N)`; preenchida com o disponível ao escolher a compra | `ao escolher o ticker...` |
| Data da venda | py:322, 354-358, 401-404; android:1360, 1372-1375 | `CampoData` com mínimo = data da compra (editando: o maior entre ela e o início do mês), máximo = menor entre fim do mês e hoje; se a data atual sai dos limites é apagada; sem data e hoje válido: hoje | `ao escolher o ticker...`; `datas: ...` |
| Dias permitidos | py:407-415 | mês aberto sempre; meses anteriores só se não estão em `mesesSemVendaRetroativa(mesAberto)`; editando só o mês aberto (sem consultar os meses); enquanto a lista não chega, só o mês aberto | `datas: ...`; `datas na edição: ...` |
| Preço unitário | py:359-362; android:1316 | dica `Ex.: 35,10`; editando: `fmtNum` do preço da venda | `editar: ...` |
| Sugerir preço | py:462-503; android:1338-1365 | ao ter compra e data (e não editando): `precoVenda(ticker, data)`; `Buscando cotação…`; chegou: preenche (`precoTexto`) e mostra `<origem> · pode alterar`; falhou: `Não foi possível buscar a cotação. Informe o preço.`; não sobrescreve preço digitado (nem com a resposta chegando depois); resposta de pedido antigo ignorada; mesmo pedido não repete | `Sugerir preço: ...`; `preço digitado enquanto a cotação carrega...`; `cotação que falha pede o preço` |
| Responsividade | spec | o `Future` do preço não bloqueia; digitar atualiza o resumo | `a interface responde enquanto o preço sugerido não chega` |
| Editar | py:343-358, 1696-1701; android:1312-1317, 1431-1438 | compra fixa (`semVenda`), ticker e compra desabilitados, data/quantidade/preço da venda, `editarVenda` | `editar: compra e ticker fixos...` |
| Validação | py:505-533 | `validarVenda` (Tarefa 11), com `editando: true` ao editar e `reservadoEmMetas` consultado só para venda retroativa nova | `validações da venda...`; `meta ativa na compra recusa...` |
| Venda retroativa | py:1651-1673 | depois de gravar, aviso `Venda registrada` com o texto devolvido pelo serviço; o chamador não repete | `venda retroativa mostra o aviso devolvido` |
| Salvar | android:1469-1490 | `registrarVenda(mes, …)` ou `editarVenda(mes, vendaId, …)`; mudança concorrente é revalidada pelo serviço | `salvar registra a venda...`; `editar: ...` |

## Saldo

| Elemento | Origem | Texto / comportamento | Coberto por |
|---|---|---|---|
| Título | py:545 | `Aporte`, `Retirada` ou `Saldo em conta` (pelo modo inicial; o Android sempre usava `Saldo em conta`) | `modo inicial aporte...` |
| Subtítulo | py:544; android:1672 | com saldo: `Saldo disponível hoje: R$ x`; sem: `Informe o saldo livre na conta da corretora hoje.` | `sem saldo definido...`; `com saldo definido...` |
| Operação | py:546-553; android:1629-1631 | `Definir saldo` / `Aporte` / `Retirada`; sem saldo definido só `Definir saldo` | `sem saldo definido só 'Definir saldo'` |
| Valor | py:554-555; android:1632-1633 | dica `Ex.: 10.000,00`; definir com saldo: preenchido com `precoTexto(disponível)`; aporte/retirada: vazio | `com saldo definido...`; `modo inicial aporte...` |
| Rótulo e ajuda por modo | py:559-568; android:1639-1647 | definir: `Saldo disponível hoje (R$)` + `Use o saldo livre que a corretora mostra hoje, já com as liquidações de hoje.`; aporte: `Valor do aporte (R$)` + `Soma ao saldo disponível.`; retirada: `Valor do retirada (R$)` (concordância errada igual ao Python e ao Android) + `Desconta do saldo disponível.`; trocar para aporte/retirada apaga o valor | `trocar o modo muda rótulo e ajuda` |
| Validação | py:570-580 | `validarSaldo`: `Valor inválido.`, `Informe um valor maior que zero.` | `validações: valor inválido...` |
| Salvar | android:1660-1669 | `alterarSaldo(modo, valor)`, devolve a `VisaoCaixa` | `salvar chama alterarSaldo...` |
