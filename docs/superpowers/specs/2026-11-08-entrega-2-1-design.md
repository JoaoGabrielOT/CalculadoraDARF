# Entrega 2.1.0: vendas por quantidade, posições na apuração, imposto pela regra da Receita e sugestões explicáveis

Data: 08/11/2026 · Versão alvo: 2.1.0 (estável, "Latest") · Branch: `migracao-flutter` · Pedido de origem: `prompt.md` (local, fora do git), que vale como contrato. Cada requisito e critério de aceite dele está mapeado na seção 14.

## 1. Intenção e porquê

O app Flutter 2.0.0 tem paridade com a 1.12.x, e com ela herdou quatro problemas que o dono quer resolver agora:

1. **Venda presa a um lote.** Para vender 300 ações compradas em três ordens, hoje é preciso registrar três vendas, uma por compra (`Lote.vendas`, `form_venda.dart`).
2. **Posição que some.** As compras não vendidas só passam para o mês seguinte quando o mês é fechado (`fecharMes`, que copia o lote com `origem` e o id `<id>~<mês>`). A apuração mostra só os lotes do arquivo do mês: um mês sem arquivo, ou um mês aberto há tempos, esconde posições que existem.
3. **Imposto fora da regra.** O resultado de cada venda usa o custo do próprio lote, e só é day trade quando a venda sai do mesmo lote no mesmo dia (`calcularVendaQtd`: `dt = data == lote.dataCompra`). A Receita manda usar o custo médio ponderado e classificar o day trade pelo ativo e pelo dia, seja qual for a compra. O prejuízo também não passa de um mês para outro (pendência registrada no design da migração, §9).
4. **Alvos sem contexto.** O alvo de swing é `compra + 2·(compra − stop inicial)` = compra + 4·ATR14, ancorado no preço de compra e não na cotação. Isso gera casos como compra a R$ 5,93 com alvo de R$ 7,60 sem horizonte nem justificativa (`nucleo/sugestoes/sugestoes.dart`).

A entrega fecha com a publicação da 2.1.0 como versão estável. O atualizador da 1.12 passa então a levar todos os aparelhos para o app Flutter.

## 2. Decisões do dono (vinculantes)

1. **Alvo e canal:** o app Flutter sai como **2.1.0 estável (Latest)**. O atualizador da 1.12 migra todos os aparelhos para o Flutter, e não há volta para a 1.12. O workflow publica a 2.1.0 com `prerelease: false` e `make_latest: "true"` automaticamente na tag. Não existe `gh` nesta máquina e nenhuma credencial pode ser usada localmente.
2. **Imposto pela regra da Receita, só daqui para frente:**
   - Operações comuns: custo médio ponderado por ticker, com as despesas de aquisição incluídas.
   - Day trade: compra e venda do mesmo ativo no mesmo dia (mesma corretora, e o app tem uma só), qualquer que seja o lote, até a menor das duas quantidades, sem contar o estoque anterior (IN RFB 1.585/2015, art. 65, §§ 1º e 2º).
   - Meses fechados e DARFs pagas ficam como estão. O método novo vale a partir do primeiro mês aberto no momento da atualização.
   - Cada mês grava um marcador de método, para que todos os aparelhos concordem.
3. **Compensação de prejuízo entre meses:** separada para operações comuns e day trade, com o tratamento de ações e BDR que a Receita define, a partir do mês de corte.

## 3. Decisões minhas

Cada decisão traz o motivo e o custo se estiver errada. Podem ser revistas pelo dono.

| # | Decisão | Motivo | Custo se errada |
|---|---|---|---|
| D1 | **Mês de corte** = primeiro mês não fechado (`repo.mesInicial()`) na primeira execução da 2.1, logo depois de uma sincronização bem-sucedida. Sem login ou sem rede, usa os dados locais. | É o "primeiro mês aberto na atualização" pedido pelo dono, e sincronizar antes reduz a chance de dois aparelhos escolherem meses diferentes. | Um aparelho offline que escolha outro mês: tratado pela regra de mesclagem do marcador (§5.3). Meses fechados nunca mudam de método. |
| D2 | **Marcador por mês** guardado no JSON do mês (`metodo: "custo_medio"`; ausente = método antigo "por compra") e na nova coluna 14 "Detalhes" da aba Resumo, oculta, com JSON compacto que traz o próprio mês. | Segue o precedente da coluna Detalhes das Metas. O mês embutido no JSON protege contra linhas desalinhadas por uma gravação da 1.12, que não limpa colunas além da 13ª nem linhas que sobram (`google_sync.py:395-425`). | Se a 1.12 regravar a planilha, a coluna 14 pode ficar órfã. A 2.1 ignora o valor quando o mês não confere, e o marcador local é monotônico, então não se perde. |
| D3 | **Posição fiscal inicial** do mês de corte = soma das compras em aberto no início do mês: cópias com `origem` e compras com data anterior ao mês, por `restante × preço × (1 + taxaB3Swing)`. Fica gravada no mês (`posicao_inicial`) e não é recalculada. | Antes do corte o custo era por compra, então o custo dos lotes restantes é a base legítima. Gravar evita que uma venda retroativa ou uma edição mude o passado. | Para quem já declarava por custo médio, a média inicial difere da dos controles pessoais. O dono aceitou tratar o passado como está. |
| D4 | **Prejuízo acumulado inicial** informado pelo usuário em Configurações, separado em comum e day trade (padrão R$ 0,00). Fica gravado no mês de corte (`prejuizo_anterior`) e pode ser editado enquanto o mês de corte estiver aberto. Depois disso fica só para leitura. | A Receita permite compensar perdas anteriores (art. 64 e art. 65 § 11). O app não tem como reconstruí-las com segurança, porque o passado foi apurado por compra. | Usuário que não informa o saldo paga a mais até corrigir. Usuário que perde a janela de edição precisa de um ajuste manual (pendência, §13). |
| D5 | **Saldos levados no fechamento**, como já é feito com `darf_anterior`: `fecharMes` grava no mês seguinte a `posicao_inicial` (por ticker: quantidade e custo total) e o `prejuizo_anterior` (comum e day trade). | Reusa o padrão existente. Cada mês fica determinístico a partir do próprio registro, e meses fechados nunca são recalculados por mudança em outro mês. | Uma correção num mês fechado não se propaga para outros meses fechados (aceito, ver D11). |
| D6 | **Venda em várias compras** = N linhas de `Venda`, uma por compra consumida, com id `<grupo>.<k>` (grupo = `novoId()`, k a partir de 1). Venda de uma compra só mantém o id simples. **Nenhuma coluna nova na aba Vendas.** | A 1.12 e o leitor da 2.0 já leem linhas por compra (coluna "ID compra"). O grupo viaja dentro do id, que todas as versões preservam como texto, e não sofre o desalinhamento de colunas extras. | Uma 1.12 ainda não atualizada mostra o grupo como vendas separadas, o que está correto por compra, e calcula o imposto pelo método antigo só na tela dela. |
| D7 | **Alocação gerencial separada da apuração fiscal.** A apuração usa só os totais por ticker e por dia (compras e vendas) e o custo médio, nunca a escolha de compras. A alocação (automática ou manual) serve só para rastreabilidade e para o resultado gerencial. | É o que o pedido e a Receita exigem: escolher compras mais baratas não pode reduzir o imposto. | Nenhum para o imposto. O resultado gerencial pode divergir do fiscal, e a tela explica por quê. |
| D8 | **Day trade na alocação:** a quantidade da venda até o saldo comprado no mesmo dia consome primeiro, e obrigatoriamente, as compras do dia (travadas no modo manual). Só o restante é distribuído entre as compras anteriores. | Cumpre "identificar o day trade antes de alocar em operações comuns", e o modo manual não altera a classificação. | Se uma compra do mesmo dia for registrada depois da venda, a apuração continua correta (usa os totais do dia), mas a alocação gerencial antiga não muda. A tela avisa. |
| D9 | **Resultado do day trade** no dia = quantidade de day trade × (preço médio das vendas do dia − preço médio das compras do dia), menos as taxas de day trade. | O app não tem horário dos negócios, então não dá para parear "1º negócio de compra com 1º de venda" (art. 65 § 3º). O preço médio do dia é determinístico e é o que as notas de corretagem costumam usar. | Quando as compras do dia superam as vendas a preços diferentes, o resultado pode diferir em centavos do pareamento por horário. Fica registrado como limitação. |
| D10 | **Dinheiro em `double`** com os auxiliares existentes (`arredondar`, `somaPython`). A posição fiscal guarda o custo total **arredondado ao centavo a cada evento**. O custo baixado numa venda é `arredondar(q × custo/qtd, 2)` e a sobra fica no saldo, de modo que vender tudo zera exatamente. | Trocar para centavos inteiros seria refatorar todo o núcleo e a planilha, fora do escopo. A paridade com o Python continua valendo no caminho antigo, que fica intacto. Arredondar a cada evento faz dois aparelhos chegarem ao mesmo JSON. | Diferença de até R$ 0,01 por evento frente a uma planilha sem arredondamento, dentro da tolerância de uma DARF. |
| D11 | **Venda retroativa:** continua só com uma compra e só em meses **anteriores ao corte**. Na posição fiscal do mês aberto, a venda baixa `q` unidades pelo custo médio. Em meses a partir do corte ela fica bloqueada, com mensagem. | Mexe em dois arquivos de mês, o que não é atômico, e meses por custo médio dependem de saldos levados. O caso é raro: mês fechado com tudo vendido. | Quem esquecer uma venda num mês já fechado depois do corte não consegue lançá-la pelo app (pendência, §13). |
| D12 | **Compra levada (com `origem`) num mês por custo médio** não pode ter quantidade nem preço editados (mensagem explicando). Compras novas do mês continuam editáveis. | A cópia representa o passado, que já está na `posicao_inicial` gravada. | Erro de digitação antigo só se corrige com ajuste manual. |
| D13 | **Confirmação transacional:** a venda inteira (N linhas) é montada em memória, validada contra o mês recarregado do disco e gravada numa única chamada `repo.salvar(mes)`, que grava num `.tmp` e renomeia. O botão fica desativado durante a gravação, e o grupo nasce quando o formulário abre (chave de idempotência): se ele já existe no mês, a segunda confirmação não grava nada. Todas as linhas recebem o mesmo `mod`. | Um arquivo por mês já é a unidade atômica do repositório. O mesmo `mod` faz o grupo inteiro vencer junto na mesclagem. | Uma edição concorrente de outro aparelho pode vencer linha a linha. Coberto por um aviso de saldo inconsistente (§5.6). |
| D14 | **Sugestões:** poucos critérios (ATR14, máxima e mínima de 20 pregões, pivôs do pregão anterior, volume financeiro médio de 20 pregões), ancorados na **cotação**, com horizonte explícito, relação risco/retorno mínima de 1,5 e "sem oportunidade identificada" quando não há base. Sem VWAP (§9). | É o conjunto mínimo que cobre volatilidade, suporte e resistência, liquidez e risco/retorno com os dados que o Yahoo já entrega. | Critério conservador demais mostra muitas vezes "sem oportunidade". Os parâmetros ficam em `const` documentadas. |
| D15 | **Tick** de R$ 0,01 para ações, units e BDRs, nos lotes padrão e fracionário, numa função `tickDe(ticker, preco)` com tabela de faixas (hoje uma faixa só). | É a premissa usual do mercado à vista da B3. O documento oficial foi localizado, mas não pôde ser lido aqui (§10). | Se houver faixa com tick diferente, só a tabela muda. A tarefa do plano confere o PDF antes de fechar. |
| D16 | **Tag 2.1.0** no commit verificado da `migracao-flutter`, como a 2.0.0. A integração na `main` fica para `finishing-a-development-branch`. | Mantém o fluxo da 2.0.0, que já foi exercitado. O workflow é o do commit marcado. | Nenhum para o usuário. A `main` continua com o código Python até a integração. |

## 4. Metas, não-metas e anti-metas

**Metas**
- Venda por ativo e quantidade, com alocação automática ou manual, revisão antes de confirmar e confirmação atômica e idempotente.
- Duas visões de posição na apuração: "Posição no encerramento do mês" e "Carteira atual".
- Imposto por custo médio e day trade pela regra da Receita a partir do mês de corte, com compensação de prejuízo entre meses.
- Sugestões explicáveis, com meta financeira, cenário de mercado e ponto de equilíbrio separados, e sugestão consolidada por ativo.
- Indicadores por ativo com fórmulas e denominadores documentados.
- Publicação da 2.1.0 estável, com evidência automática de que os dois atualizadores (1.12 e Flutter) a detectam.

**Não-metas**
- Execução de ordens em corretora e qualquer integração com corretora.
- Sugestão de compra, inclusive "comprar mais para baixar o preço médio".
- Recalcular meses fechados ou DARFs pagas.
- VWAP e análise intradiária.
- Venda retroativa em várias compras.
- Refatorar dinheiro para centavos inteiros e qualquer refatoração fora destes fluxos.

**Anti-metas (falha mesmo que "funcione")**
- Mudar algum valor da aba Resumo de um mês fechado antes do corte.
- Uma escolha manual de compras alterar o imposto, a classificação de day trade ou o prejuízo acumulado.
- Exibir uma posição gerar movimentação, resultado realizado ou imposto.
- Gravar uma venda pela metade, ou duas vezes, por clique duplo.
- Mostrar uma cotação atual como se fosse histórica, ou mostrar um alvo sem fonte, data e horizonte.
- Publicar a release sem confirmar que `/releases/latest` devolve a 2.1.0 com os dois arquivos e os digests corretos.
- Perder dados locais na migração: o backup vem sempre antes.

## 5. Motor fiscal por custo médio (núcleo)

### 5.1 Despacho por método

- `apurar(Mes d)` passa a despachar pelo método: `d.metodo == 'custo_medio'` chama `apurarCustoMedio(d)` (arquivo novo `nucleo/apuracao_medio.dart`); senão chama o `apurar` atual, **sem nenhuma mudança** (os testes de paridade com o Python continuam passando).
- `Apuracao` ganha campos opcionais, nulos no método antigo: `metodo`, `compensadoComum`, `compensadoDt`, `prejuizoComumFinal`, `prejuizoDtFinal`, `posicaoFinal` (por ticker: qtd e custo) e, por operação, `qtdDt`, `custoFiscal`, `resultadoFiscal`.
- Todo consumidor de `apurar` (tela, `montarLinhas`, fechamento, metas e caixa, se usar) passa a receber o resultado do método certo sem mudar de chamada.

### 5.2 Algoritmo de um mês por custo médio

Entrada: o mês, com `lotes`, `posicao_inicial {ticker: {qtd:int, custo:double}}` e `prejuizo_anterior {comum, day_trade}`.

1. **Eventos por ticker e por dia.**
   - Compras do mês: lotes sem `origem` com `dataCompra` dentro do mês. Os lotes com `origem`, ou com data anterior ao mês, são estoque anterior e já estão na `posicao_inicial`.
   - Vendas: todas as `Venda` dos lotes do ticker, agrupadas por `data`.
2. **Dia D**, em ordem cronológica, com `B` = quantidade comprada no dia e `S` = quantidade vendida no dia:
   - `dt = min(B, S)` (IN 1.585, art. 65 §§ 1º e 2º).
   - Preço médio das compras do dia `pc = Σ(q·p)/B` e das vendas `pv = Σ(q·p)/S`.
   - Resultado do day trade no dia: `dt·pv − dt·pc − (dt·pv + dt·pc)·taxaB3Daytrade − corretagem do day trade`.
   - Compras restantes (`B − dt`) entram na posição: `custo += arredondar((B−dt)·pc·(1 + taxaB3Swing) + corretagem das compras, 2)`, `qtd += B − dt`.
   - Vendas restantes (`S − dt`) saem da posição: `custoBaixado = arredondar((S−dt) · custo/qtd, 2)`, resultado comum = `(S−dt)·pv − custoBaixado − (S−dt)·pv·taxaB3Swing − corretagem da venda comum`, `custo −= custoBaixado`, `qtd −= S − dt`.
   - Corretagem: hoje `corretagemPorOrdem = 0` em produção. A regra fica definida para os testes: uma ordem por compra (lote) e uma por venda (grupo), rateadas por quantidade entre day trade e comum (art. 56 § 4º).
   - Se `S − dt > qtd` (venda acima da posição, só possível com dados inconsistentes), a apuração **não** inventa custo. Ela marca o ticker como inconsistente, apura a parte coberta e mostra o aviso da §5.6.
3. **Atribuição às linhas de venda** (exibição e planilha): cada linha do dia D recebe a fração `dt/S` como day trade, e o resto como comum, proporcional à quantidade. Regime da linha: "Day trade" (fração 1), "Swing" ou "Swing (isento)" (fração 0) e "Misto" (fração entre 0 e 1). O custo fiscal e o resultado da linha são as frações do resultado do dia.
4. **Isenção (Lei 11.033/2004, art. 3º, I; IN 1.585, art. 59, I e § 2º, I; art. 65 § 15):** `vendasAcoesSt` = soma do valor da parte comum das vendas de `Ação`. Isento quando ≤ R$ 20.000,00. BDR não é isento, e day trade nunca é.
5. **Base comum do mês:** `baseComum = (isento ? min(resAcoesComum, 0) : resAcoesComum) + resBdrComum`. É a mesma fórmula do método atual: a perda de ações num mês isento entra (art. 59 § 1º só exige declarar as vendas isentas para compensar perdas), e o ganho isento não consome o prejuízo.
6. **Compensação comum (art. 64; perdas comuns não abatem day trade, art. 64, parágrafo único):** se `baseComum > 0`, `compComum = min(baseComum, prejComumAnterior)`, tributável = `baseComum − compComum` e `prejComumFinal = prejComumAnterior − compComum`. Senão, tributável = 0 e `prejComumFinal = prejComumAnterior − baseComum`.
7. **Day trade (art. 65 §§ 10 e 11):** `baseDt` = soma dos resultados de day trade do mês, ações e BDR juntos. A compensação usa a mesma fórmula com `prejDtAnterior`.
8. **Imposto:** `impSt = tributávelComum × 15%` e `impDt = tributávelDt × 20%`. O IRRF fica como hoje, com a parte comum das vendas por dia (0,005%, retido só acima de R$ 1) e o resultado de day trade por dia (1%, só acima de R$ 1). `darfMes`, `darfAnterior` e `darf` também ficam como hoje.
9. **Saídas para o fechamento:** `posicaoFinal` (a posição depois do último dia; tickers zerados saem) e `prejuizoComumFinal` e `prejuizoDtFinal`.

### 5.3 Marcador de método, mês de corte e mesclagem

- **JSON do mês:** campos novos opcionais `metodo`, `posicao_inicial` e `prejuizo_anterior`. Ausentes significam o método antigo. `Mes.fromJson`/`toJson` mantêm a ordem de chaves existente e acrescentam esses campos só quando presentes.
- **Planilha:** coluna 14 da aba Resumo, `ColunaAba('Detalhes', 'id', 80)`, oculta. Valor `{"mes":"AAAA-MM","metodo":"custo_medio","posicao_inicial":{...},"prejuizo_anterior":{...}}` em JSON compacto (`jsonPython(..., compacto: true)`), vazio no método antigo. `reconstruir` lê a coluna 14 com `_completar(..., 14)` e aceita o valor **só se `mes` conferir com a coluna 0**. Planilha com 13 colunas é aceita (o `appendDimension` de colunas já existe no gravador).
- **Regra efetiva do método de um mês m:**
  - fechado com marcador: custo médio;
  - fechado sem marcador: método antigo, para sempre;
  - aberto: custo médio se m ≥ mês de corte, onde mês de corte = o menor mês com marcador.
- **Mesclagem (`mesclarMes`):** os campos novos vêm do vencedor por `mod`, como `darf_anterior`, com uma exceção monotônica: se só um dos lados tem `metodo: custo_medio` e o mês não está fechado sem marcador no vencedor, o marcador (com `posicao_inicial` e `prejuizo_anterior`) é mantido. A regra cobre a planilha regravada por uma 1.12 e a gravação concorrente da migração em dois aparelhos.
- **Conflito de corte entre aparelhos** (os dois migraram offline em meses diferentes): vale a regra efetiva acima. Um mês fechado pelo método antigo nunca muda, e meses abertos a partir do menor marcador passam para o custo médio. A `posicao_inicial` de um mês aberto sem marcador próprio, mas posterior ao corte, é derivada como na D3 no momento em que ele for marcado.

### 5.4 Fechamento (`fecharMes`)

Para um mês por custo médio, além do que já faz hoje (cópia dos lotes com `origem`, `darf_anterior`), grava no mês seguinte, se ele não estiver fechado:
- `metodo = custo_medio`;
- `posicao_inicial = r.posicaoFinal`;
- `prejuizo_anterior = {comum: r.prejuizoComumFinal, day_trade: r.prejuizoDtFinal}`.

O mês fechado guarda o próprio marcador e o `resumo`. A mensagem de fechamento ganha uma linha com o prejuízo levado, quando houver.

### 5.5 Venda retroativa (D11)

`mesAceitaVendaRetroativa` passa a recusar meses ≥ mês de corte. Mensagem: "Meses apurados por custo médio não aceitam venda retroativa." Em meses anteriores ao corte o fluxo atual fica igual, com uma regra a mais: se o mês aberto `d` usa custo médio, `d.posicao_inicial[ticker]` perde `q` unidades e `arredondar(q · custo/qtd, 2)` de custo. A posição deve existir, senão a venda é recusada.

### 5.6 Consistência

Por ticker, no mês aberto:
- a soma de `restante` dos lotes (visão gerencial) deve ser igual à quantidade da posição fiscal final (visão fiscal);
- nenhum lote pode ficar com `restante < 0`.

Se alguma das duas falhar, o que pode acontecer depois de uma mesclagem com vendas concorrentes, a apuração mostra o aviso "Saldo inconsistente em TICKER: confira as vendas" e o fechamento do mês fica bloqueado até corrigir.

## 6. Venda por quantidade (requisito 1)

### 6.1 Núcleo (`nucleo/alocacao.dart`, puro)

- `comprasElegiveis(Mes d, String ticker, String dataVenda)`: lotes do ticker com `dataCompra ≤ dataVenda` e `restante > 0`.
- `custoUnitarioEfetivo(Lote l) = l.preco · (1 + taxaB3Swing) + corretagemPorOrdem / l.qtd`, a despesa de aquisição atribuível.
- `alocarAutomatico(eligiveis, qtd, dataVenda)`:
  1. Parte de day trade obrigatória: `dtQtd = min(qtd, Σ restante das compras do dia)`, consumida das compras com `dataCompra == dataVenda`.
  2. O restante vai para as demais elegíveis, por **menor custo unitário efetivo**, com desempate por **data de compra mais antiga** e depois **id do lote** (texto). Com um mesmo preço de venda, isso dá o maior resultado gerencial, ou a menor perda.
  3. Consumo parcial permitido.
  4. Erro tipado se `Σ restante < qtd`.
- `validarManual(eligiveis, selecao, qtd)`:
  - soma igual a `qtd`;
  - cada item ≤ `restante`;
  - as compras do dia consumidas exatamente pela quantidade de day trade obrigatória (travadas);
  - nenhum lote fora das elegíveis.
- `previa(selecao, preco, dataVenda)`:
  - por linha: data, quantidade original, disponível, consumida, custo unitário efetivo e resultado gerencial `q·preco − q·custoEfetivo − q·preco·taxa` (taxa do regime da parte);
  - total gerencial;
  - **resultado fiscal estimado da operação**, chamando `apurarCustoMedio` sobre uma cópia do mês com a venda incluída e tirando a diferença;
  - classificação (day trade e comum).
- `montarVendas(selecao, grupo, data, preco, mod)` produz as `Venda` com ids `grupo.k`, ou o id simples quando só há uma compra.
- `confirmarVenda(repo, mes, grupo, ...)` faz a confirmação atômica da D13: recarrega o mês, verifica idempotência e saldo, acrescenta as linhas, chama `repo.salvar` uma vez e devolve o mês salvo.

### 6.2 Tela (`form_venda.dart`, Windows e Android)

- **Campos:** ativo (chips "Em carteira" já existentes), quantidade total, preço, data (Hoje/Ontem). Ao abrir pelo duplo clique ou pelo botão de um lote, o ativo vem preenchido e o modo manual vem com esse lote selecionado. No caminho geral, o modo padrão é Automático.
- **Alternância Automático/Manual** com `SegmentedButton`: só muda o estado do formulário, nunca grava. Ao passar para Manual, a seleção automática vira o ponto de partida.
- **Automático:** tabela das compras selecionadas (data, quantidade consumida, custo unitário efetivo, resultado gerencial) e o texto da regra: "Primeiro as compras de hoje (day trade, regra da Receita). Depois as de menor custo por ação, incluindo as taxas de compra; em empate, a mais antiga."
- **Manual:** lista das elegíveis com data, quantidade original, disponível, custo unitário e um campo de quantidade limitado ao disponível. As compras do dia aparecem travadas. Mostra o contador "Selecionado X de Y". O botão Confirmar só habilita com a soma exata.
- **Painel "Fiscal x gerencial":**
  - "Resultado pelas compras escolhidas (gerencial): R$ …";
  - "Resultado fiscal da operação (custo médio): R$ …";
  - "Day trade: N ações; comum: M ações";
  - o texto fixo: "A escolha das compras organiza o seu controle, mas não muda o imposto: a Receita usa o custo médio. Vender agora as compras mais baratas aumenta o resultado desta venda e reduz o das próximas; o resultado da posição inteira não muda."
- **Confirmação:** mantém o "Você já fez a venda?" de hoje. O botão fica desativado com indicador durante a gravação. Se a mesma venda chegar duas vezes, aparece "Essa venda já foi registrada."
- **Mês fechado e venda retroativa:** seguem as regras atuais, com uma compra só (D11).
- **Editar uma venda em grupo:**
  - abre o grupo inteiro com a quantidade dele liberada e repete a alocação;
  - ao salvar, as linhas que somem vão para `excluidos` com o mesmo instante, e as novas usam índices `k` ainda não usados no grupo;
  - excluir apaga todas as linhas do grupo.
- **Lista de vendas e caixa:** a lista de vendas mostra o grupo numa linha só, expansível. O Caixa soma as linhas do grupo num lançamento só, sem mudar o cálculo por linha de `resumoOrdem`.

### 6.3 Metas e venda automática

As metas continuam por compra (`loteId`) e a venda automática continua com uma linha `auto-<meta>`. O imposto dessas vendas passa a sair do motor fiscal do mês, como qualquer venda.

## 7. Posições na apuração (requisito 2)

### 7.1 Reconstrução (`nucleo/posicoes.dart`, puro, roda no isolate de serviços)

- **Entrada:** todos os meses do repositório (ou do amigo, somente leitura) e uma data de corte C.
- **Cadeias:** a chave da cadeia é `origem ?? id`. A quantidade comprada da cadeia é a `qtd` do lote cuja `id == chave`, a compra original. Cópias e lotes retroativos com `origem` não somam compra. As vendas da cadeia são todas as `Venda` dos lotes da cadeia, em qualquer mês. Os lotes retroativos sem `origem` (raiz no mês atual) formam uma cadeia própria, comprada e vendida, o que mantém a soma certa sem inventar vínculos.
- **Posição na data C:** só as cadeias com data de compra ≤ C, com `restante(C)` = compra − vendas com `data ≤ C`. Agregada por ticker, com a lista de compras expansível.
- **Custo:** o gerencial é `Σ restante(C) × preço`. O fiscal, para meses por custo médio, é a `posicao_inicial` do mês de C mais os eventos até C, pelo mesmo algoritmo da §5.2. Para meses anteriores ao corte o custo fica "por compra" e o rótulo diz isso.
- **Função pura sem efeitos:** não grava nada e não gera movimentação, resultado ou imposto (teste explícito).

### 7.2 Tela da apuração

Adaptação mínima: a seção "Ativos comprados" ganha um seletor de duas visões.
- **"Posição em dd/mm/aaaa"** (último dia do mês selecionado, ou hoje no mês corrente): só leitura. Por ativo mostra quantidade, custo e preço médio, com as compras expansíveis. Meses históricos não mostram valor de mercado ("cotação histórica não disponível"). No mês corrente o valor de mercado aparece com o selo "Cotação atual · Yahoo · dd/mm hh:mm".
- **"Carteira atual"**: posições abertas hoje, seja qual for o mês da compra ou o mês consultado. Mantém as ações de hoje (vender, editar, excluir) sobre os lotes do mês aberto, com os filtros e a ordenação existentes, e a cotação atual com fonte e horário.
- **Mês sem arquivo** (posterior ao mês aberto e até hoje): a posição aparece, reconstruída pelas cadeias, e o selo "Aberto" continua indicando o mês de trabalho.

## 8. Indicadores por ativo (requisito 5)

Ficam na visão "Posição" e no detalhamento do mês, com rótulos que diferenciam **mês e acumulado**, **realizado e não realizado**, **gerencial e fiscal**, e **R$ e %**. "—" significa dado indisponível ou divisão por zero, nunca zero.

| Indicador | Fórmula | Denominador e regras |
|---|---|---|
| Quantidade em aberto (Q) | Σ restante(C) | — |
| Custo remanescente | fiscal: custo da posição fiscal em C; meses anteriores ao corte: Σ restante × preço (rótulo "por compra") | — |
| Preço médio das compras aplicável ao saldo | custo remanescente / Q | Q = 0 → "—" |
| Preço médio das vendas no mês | Σ(q·p das vendas do mês) / Σq | Σq = 0 → "—" |
| Resultado realizado no mês (fiscal) | Σ resultado fiscal das linhas do ticker no mês, depois das taxas e antes do imposto | — |
| Resultado realizado acumulado até C | Σ resultado realizado dos meses ≤ C, cada mês pelo próprio método, com o rótulo "desde MM/AAAA" | — |
| Ganho ou perda por unidade vendida | resultado realizado no mês / Σq vendida no mês | Σq = 0 → "—" |
| Rentabilidade realizada | resultado realizado no mês / custo fiscal das unidades vendidas no mês | custo = 0 → "—". **Nunca** média simples de percentuais |
| Resultado não realizado | Q × cotação atual − custo remanescente | só com cotação atual; selo de fonte e horário |
| Valor de mercado e exposição | Q × cotação; exposição = valor do ativo / Σ valor da carteira | cotação ausente em algum ativo → exposição "—" |
| Taxas e despesas consideradas | Σ taxas B3 e corretagem das vendas do mês; as taxas de compra entram no custo | — |
| Ponto de equilíbrio | `teto_tick((custo/Q + corretagemPorOrdem/Q) / (1 − taxaB3Swing))` | Q = 0 → "—" |

## 9. Sugestões de saída (requisitos 3 e 4)

### 9.1 Dados

- **Barras diárias do Yahoo** já usadas (`chart`, pregões fechados). Passa a interpretar também `indicators.quote[0].volume`, que hoje fica de fora nas barras diárias: `BarraDiaria.volume` opcional, com ausente tratado como "liquidez indisponível".
- **Cotação atual:** `regularMarketPrice` e `regularMarketTime` (fonte "Yahoo", data e hora de Brasília).
- **Dados atuais:** a cotação é atual quando `regularMarketTime` é do último pregão (calendário de feriados de `datas.dart`) e, durante o pregão, tem menos de 20 min. Senão aparece "desatualizada", com a data e a hora.
- **Barras desatualizadas:** quando a última barra é anterior ao último pregão fechado esperado.

### 9.2 Três números com rótulos distintos

- **Ponto de equilíbrio** (sempre que houver custo): fórmula da §8, arredondada **para cima** no tick.
- **Meta financeira** (só quando o usuário informa o lucro desejado): fórmula atual de `preco_alvo.dart`, `P = (G + Q·PM·(1+t) + C)/(Q·(1−t))`, arredondada para cima no tick. É **simulação**: nunca vira recomendação e, quando fica acima do cenário de mercado, aparece "Meta acima do cenário de mercado para o horizonte".
- **Cenário de mercado:** a metodologia da §9.3.

### 9.3 Metodologia do cenário de mercado

Parâmetros em `const` documentadas: `atrPeriodo = 14`, `janelaSr = 20`, `multStop = 2`, `rrMinimo = 1.5` e `limiteLiquidez = 0.05`, a fração do volume financeiro médio.

**Swing** (horizonte: **5 a 20 pregões**; exige ≥ 21 pregões fechados):
- Âncora P = último fechamento, ou a cotação atual se for atual. Nunca o preço de compra.
- Stop de referência = `piso_tick(max(P − 2·ATR14, Chandelier(22, 3)))`, o mesmo stop protetor de hoje, agora ancorado em P.
- Resistência R = máxima dos últimos 20 pregões fechados. Se R ≥ P + 1 tick, o alvo é R e a faixa é `[max(P + tick, R − 0,5·ATR14), R]`, com o rótulo "resistência de 20 pregões". Se o preço está acima da máxima, o alvo é `P + 2·ATR14`, com o rótulo "projeção pela volatilidade (sem resistência recente acima)". Os dois são arredondados **para baixo** no tick.
- Potencial = alvo − P, risco = P − stop, R/R = potencial / risco.
- **Oportunidade** só se R/R ≥ 1,5 e o alvo ficar acima do ponto de equilíbrio. Senão aparece "Sem oportunidade identificada", com o motivo: "relação risco/retorno abaixo de 1,5", "alvo abaixo do ponto de equilíbrio" ou "dados insuficientes".

**Day trade** (horizonte: **o pregão de hoje**; só para compras de hoje e com cotação atual):
- Níveis de referência = pivôs clássicos do pregão anterior (PP, R1, S1) e ATR14.
- Âncora P = cotação atual.
- Stop = `piso_tick(max(S1, P − ATR14))` se ficar abaixo de P; alvo = R1 se R1 > P.
- Mesma regra de R/R ≥ 1,5.
- Sem cotação atual, ou fora do pregão: "Análise intradiária indisponível: sem cotação atual"; só ponto de equilíbrio e meta financeira. **Nunca** simular o intradiário com o preço de compra.
- Sem VWAP: o app não tem barras intradiárias com volume confiáveis neste fluxo. Fica como limitação documentada.

**Liquidez:** volume financeiro médio de 20 pregões, `VFM = Σ(fech·volume)/20`.
- Quando `Q·P > 5% do VFM`: aviso "Quantidade grande frente ao volume médio: a saída pode mover o preço".
- Sem volume: "Liquidez indisponível".
- **Spread:** sempre "indisponível (o Yahoo não fornece livro de ofertas)".

**Custos:** potencial e risco em R$ já líquidos das taxas B3 do regime e do IR estimado do regime, como a `projetar` atual. Os percentuais usam como denominador o custo das unidades simuladas.

**Proibido:** probabilidade de acerto, percentuais fixos como estratégia, inventar cotação. Os avisos atuais (`avisoSugestao`, `avisoProventos`, `avisoGap`) continuam.

**Metas automáticas:** "Criar meta de alvo e stop" usa o alvo e o stop do cenário. Fica desativado quando não há oportunidade, mas a meta financeira continua disponível na aba Calculadora. As metas existentes não mudam.

### 9.4 Consolidado por ativo

- **Entradas:** Q total, custo fiscal remanescente, preço médio ponderado por quantidade (nunca média simples dos preços), ponto de equilíbrio.
- **Cenários:** saída de 25%, 50%, 100% ou de uma quantidade digitada, nos preços alvo do cenário, stop e meta financeira.
- **Resultado:** em R$ e em %, sobre o custo médio das unidades simuladas.
- **Por compra:** as sugestões de cada compra aparecem expansíveis, com o custo da compra e o rótulo "gerencial".

### 9.5 Tela (aba Sugestões de Metas, Windows e Android)

- Agrupada por ativo, expansível para as compras.
- **Filtros:** horizonte (Swing ou Day trade), "Só posições abertas" e dados (Com dados, Sem dados ou desatualizados).
- **Ordenação:** R/R, distância até o alvo (%), liquidez (VFM) e ticker. Itens sem dado vão para o fim.
- Mudar quantidade, preço ou horizonte recalcula na hora, com funções puras e espera de 300 ms entre teclas, sem nova requisição.
- **Estados por ativo:** carregando, sem dados, desatualizado (com data e hora) e falha da fonte (mensagem na linha). A tela não quebra e os outros ativos continuam.
- **Requisições:** uma por ticker ao abrir, reusando o cache e o limite de concorrência do Yahoo (design da migração §6.4); "Atualizar" é manual.
- Nada é gravado sem a confirmação do formulário de venda.

## 10. Pesquisa: fontes, premissas e limitações

Consultadas em 08/11/2026.

**Regras fiscais**
- IN RFB 1.585/2015, texto em https://www.normaslegais.com.br/legislacao/instrucao-normativa-1585-2015.htm (texto oficial no DOU: https://www.in.gov.br/materia/-/asset_publisher/Kujrw0TZC2Mb/content/id/32827203/do1-2015-09-02-instrucao-normativa-n-1-585-de-31-de-agosto-de-2015-32827199). Artigos usados:
  - art. 56 § 4º: rateio de custos das operações do dia;
  - art. 58: custo médio ponderado no mercado à vista;
  - art. 59, I, § 1º e § 2º, I: isenção de R$ 20 mil para ações, declaração para compensar perdas, e a isenção não vale para day trade;
  - art. 64 e parágrafo único: compensação de perdas comuns no mês e nos meses seguintes, sem abater day trade;
  - art. 65 §§ 1º, 2º, 3º, 10, 11 e 15: definição de day trade, estoque anterior desconsiderado, ordem dos negócios, perdas só com day trade, prejuízo do mês levado aos meses seguintes, sem isenção.
- Lei 11.033/2004, art. 3º, I: https://www.planalto.gov.br/ccivil_03/_ato2004-2006/2004/lei/L11033compilado.htm.
- Receita Federal, "Compensações": https://www.gov.br/receitafederal/pt-br/assuntos/meu-imposto-de-renda/pagamento/renda-variavel/bolsa-de-valores-1/compensacoes
- Receita Federal, "Isenções": https://www.gov.br/receitafederal/pt-br/assuntos/meu-imposto-de-renda/pagamento/renda-variavel/bolsa-de-valores-1/isencoes

**Variação mínima de preço**
- B3, "Variação Mínima de Apregoação (Tick Size)", documento de 13/10/2026, listado em https://b3.com.br/pt_br/solucoes/plataformas/puma-trading-system/para-participantes-e-traders/regras-e-parametros-de-negociacao/regras-de-negociacao/
- O PDF foi baixado, mas não pôde ser lido nesta máquina. **Premissa D15 (R$ 0,01) a confirmar na primeira tarefa do plano.**

**Estratégias de saída**
- StockCharts ChartSchool, consultado em 08/11/2026:
  - Average True Range: https://chartschool.stockcharts.com/table-of-contents/technical-indicators-and-overlays/technical-indicators/average-true-range-atr (ATR de Wilder, 14 períodos, medida absoluta de volatilidade)
  - Chandelier Exit: https://chartschool.stockcharts.com/table-of-contents/technical-indicators-and-overlays/technical-overlays/chandelier-exit (máxima de 22 períodos − 3·ATR22)
  - Pivot Points: https://chartschool.stockcharts.com/table-of-contents/technical-indicators-and-overlays/technical-overlays/pivot-points (P = (H+L+C)/3, R1 = 2P − L, S1 = 2P − H; pivôs diários servem ao intradiário)
  - VWAP: https://chartschool.stockcharts.com/table-of-contents/technical-indicators-and-overlays/technical-overlays/volume-weighted-average-price-vwap (exige dados intradiários com volume, por isso fica de fora)

**Premissas**
- Corretora única.
- Taxas B3 com as constantes atuais (`taxaB3Swing` 0,03%, `taxaB3Daytrade` 0,023%).
- Corretagem zero em produção.
- Preços do Yahoo sem ajuste por proventos.
- Day trade pelo preço médio do dia (D9).

**Limitações**
- Sem horário dos negócios, sem livro de ofertas (spread) e sem VWAP.
- O cenário de mercado é uma estimativa sem probabilidade associada.
- Resistência e suporte vêm só de máximas e mínimas recentes e dos pivôs.
- A regra fiscal foi lida de um texto consolidado não oficial e conferida contra as páginas da Receita. Antes do release, a tarefa de revisão confere os artigos no DOU.

## 11. Dados: migração, backup, sincronização e downgrade

- **Esquema versionado:** `config.json` ganha `migracoes: [...]` (lista de ids aplicados, nas `extras`, que já são preservadas). Migrações incrementais, em ordem, idempotentes e **nunca editadas depois de publicadas**.
- **Migração `2.1-custo-medio`** (primeira execução da 2.1, no isolate de serviços, antes de abrir a apuração):
  1. **Backup:** copia todos os `*.json` da pasta de dados para `backup/pre-2.1.0-AAAAMMDD-HHMMSS/` e confere quantidade e tamanhos. Se o backup falhar, a migração **não roda** e o app avisa.
  2. Se houver login, sincroniza (puxa e mescla).
  3. Escolhe o mês de corte (D1) e grava nele `metodo`, `posicao_inicial` (D3) e `prejuizo_anterior` zerado. Faz o mesmo nos meses abertos posteriores que já existirem.
  4. Registra o id em `migracoes`. **Não reescreve lotes, vendas, `resumo` nem meses fechados.**
  5. A próxima sincronização grava a coluna 14.
- **Teste de atualização de base antiga** (fixture montada a partir de `app/test/referencias`): meses fechados com cópias levadas, mês retroativo, venda automática `auto-`, BDR, mês isento com perda, day trade, várias compras do mesmo ticker e mês aberto com vendas. Ele confere que:
  - as linhas de Resumo dos meses fechados ficam idênticas, byte a byte, às da 2.0;
  - o mês aberto é recalculado com os valores esperados à mão;
  - o backup existe;
  - rodar de novo não muda nada.
- **Convivência com aparelhos antigos** (1.12 e 2.0):
  - eles leem a planilha da 2.1 sem erro: colunas extras são ignoradas, e os ids `grupo.k` são texto;
  - se gravarem, recalculam a aba Resumo pelo método antigo e podem deixar a coluna 14 desalinhada;
  - a 2.1 recompõe tudo na próxima gravação, e o marcador local é monotônico;
  - como a 2.1 é Latest, a 1.12 oferece a atualização ao abrir (`calculadora_darf.py:1273`, `android/main.py:633`);
  - nas notas: "atualize todos os aparelhos antes de fechar o próximo mês".
- **Downgrade (sem rollback seguro):**
  - O instalador Windows recusa rebaixar (plano 4), e o Android exige desinstalar para instalar um versionCode menor, o que perde os dados locais.
  - Se a 2.0 abrisse dados da 2.1, descartaria os campos novos do mês ao salvar e apuraria pelo método antigo: **inseguro**.
  - A 1.12 não lê os arquivos locais do Flutter. Ela convive só pela planilha, com a ressalva acima.
  - **Recuperação documentada:** fechar o app, copiar `backup/pre-2.1.0-*/` de volta para a pasta de dados e reinstalar a versão correspondente. Os dados da planilha continuam com as compras e vendas, que todas as versões leem.

## 12. Release 2.1.0

1. `app/lib/versao.dart` vira `2.1.0`, e `app/test/versao_test.dart` passa a esperar `2.1.0`. O versionCode sai pela fórmula do workflow: 20100.
2. Notas em `docs/release/2.1.0.md`:
   - funcionalidades;
   - corte fiscal ("a partir de MM/AAAA, custo médio e compensação de prejuízo; informe o prejuízo acumulado em Configurações");
   - aviso para atualizar todos os aparelhos;
   - limites de downgrade e recuperação.

   O passo de publicar usa `body_path`.
3. `release.yml`, passo "Publicar a release": `prerelease: false` e `make_latest: "true"`, com comentários atualizados. Também ganha um job `conferir-atualizador` depois de `publicar`, só na tag, sem segredos além do `GITHUB_TOKEN` automático e só leitura, que faz quatro coisas:
   - busca `https://api.github.com/repos/JoaoGabrielOT/CalculadoraDARF/releases/latest`, com até 10 tentativas espaçadas, e exige `tag_name == versão`, `prerelease == false` e `draft == false`;
   - exige os dois assets `CalculadoraDARF.exe` e `CalculadoraDARF.apk`, com `size` igual ao dos arquivos do artefato e `digest == "sha256:" + sha256sum` local;
   - roda o **atualizador Python** real (`atualizador.verificar()` com a versão do módulo trocada para `1.12.1`) e exige uma oferta da 2.1.0;
   - roda um teste Dart do atualizador do app (`interpretar` do `atualizador.dart`) contra o JSON vivo, com a versão local `2.0.0`, e exige a oferta.

   Qualquer falha marca o job como vermelho com `::error`.
4. **Sequência:**
   - CI verde no commit H da branch;
   - revisão final (`revisor`);
   - `git tag -a 2.1.0 -m "Calculadora DARF 2.1.0" H` e `git push origin 2.1.0` (o controlador, autorizado pelo prompt);
   - acompanhar a execução com o agente `monitor-ci`;
   - conferir em https://github.com/JoaoGabrielOT/CalculadoraDARF/releases/latest que a página redireciona para a 2.1.0.

   Sem force push e sem reescrever histórico.
5. **Teste de atualização a partir da versão estável anterior** (1.12.1), coberto no CI:
   - o teste do instalador do plano 4 é estendido para uma pasta `dados/` da 1.12 seguida da 2.1.0, com a migração `2.1-custo-medio` e o backup conferidos;
   - o APK é conferido contra o certificado publicado.

   Fica no checklist do dono: transição real no PC e no celular.
6. **Bloqueios possíveis:** se faltarem permissões no CI, prepara-se o máximo, informa-se o bloqueio exato e não se afirma que foi publicado.

## 13. Pendências e riscos aceitos

- Venda retroativa em meses por custo médio bloqueada (D11).
- Prejuízo inicial editável só com o mês de corte aberto (D4).
- Day trade pelo preço médio do dia (D9).
- Tick a confirmar no PDF da B3 (D15).
- Aparelhos 1.12 e 2.0 que gravarem depois da 2.1 recalculam a aba Resumo pelo método antigo até a próxima gravação da 2.1.
- Proposta separada, fora desta entrega: ajuste manual de posição ou prejuízo com trilha de auditoria; VWAP com barras de 5 min.

## 14. Rastreabilidade do pedido e critérios de aceite (testes)

Os testes ficam em `app/test/nucleo` e `app/test/app`, no padrão existente.

**Vendas** (`alocacao_test.dart`, `apuracao_medio_test.dart`, `form_venda_test.dart`):
- seleção automática entre custos diferentes, com desempate por data e por id;
- venda parcial que consome várias compras;
- seleção manual e alternância sem gravar;
- quantidade insuficiente, soma diferente e item acima do disponível;
- fiscal igual para alocações diferentes da mesma venda (gerencial muda, fiscal não);
- day trade com compras de lotes diferentes no mesmo dia;
- estoque anterior desconsiderado;
- day trade obrigatório travado no manual;
- confirmação dupla com o mesmo grupo grava uma vez;
- falha de gravação não deixa linhas parciais.

**Apuração e fiscal** (`apuracao_medio_test.dart`, `posicoes_test.dart`, `fechamento_test.dart`, `migracao_test.dart`):
- posição aberta em meses sem movimentação e em meses sem arquivo;
- compra futura ausente da posição de um mês anterior;
- posição encerrada visível nos meses certos;
- carteira atual separada do retrato mensal;
- reconstrução sem efeitos (repositório intocado, nenhum imposto);
- médias ponderadas com taxas, saldo zerado e resultados negativos;
- compensação de prejuízo comum e de day trade entre meses, separadas;
- mês isento com perda de ações e ganho de BDR;
- fechamento levando posição e prejuízo;
- marcador e mesclagem (monotônico, mês embutido conferido);
- método antigo intacto nos meses fechados, com as referências do Python continuando a passar;
- migração de uma base antiga com backup e idempotência;
- venda retroativa antes e depois do corte.

**Planilha** (`planilha_montagem_test.dart`, `planilha_reconstrucao_test.dart`, `ida_e_volta_test.dart`):
- coluna 14 gravada e lida;
- planilha de 13 colunas aceita;
- valor desalinhado ignorado;
- `reconstruir` do Python lendo uma planilha da 2.1 com os mesmos dados de compras e vendas.

**Sugestões e interface** (`sugestoes_test.dart`, `aba_sugestoes_test.dart`):
- dados insuficientes e desatualizados;
- meta financeira diferente do cenário de mercado, e meta acima do cenário não recomendada;
- consolidado ponderado por quantidade;
- arredondamento ao tick (alvo para baixo, ponto de equilíbrio para cima, stop para baixo);
- "sem oportunidade identificada" com R/R abaixo de 1,5;
- falha da fonte sem quebrar a tela;
- recálculo ao mudar quantidade, preço e horizonte;
- goldens nas larguras de celular e de PC.

**Comandos reais** (plano 4):
- `flutter analyze` e `flutter test` em `app/`;
- `python -m unittest discover -s tests` na raiz, com o Python intacto;
- builds e instalador no CI (`release.yml`).

Mapa do pedido:

| Requisito do pedido | Seções |
|---|---|
| 1. Venda por quantidade | 6, D6 a D8, D13 |
| Separação gerencial e fiscal | 5, 6.2, D7 |
| 2. Posições na apuração | 7 |
| 3. Sugestões | 9.1 a 9.4, 10 |
| 4. Tela de sugestões | 9.5 |
| 5. Indicadores | 8 |
| Integridade e migrações | 11 |
| Release e atualizador | 12 |

## 15. Foco da revisão (entradas mais arriscadas)

1. **Despacho de `apurar` por método e `montarLinhas`:** qualquer mês fechado antes do corte que mude na aba Resumo é uma falha grave. Testar contra as referências do Python.
2. **Algoritmo de day trade por dia (§5.2, passo 2)**, sobretudo com compras levadas do mesmo ticker e vendas em lotes diferentes no mesmo dia.
3. **Mesclagem do marcador e da coluna 14:** regra monotônica, mês embutido, conflito entre aparelhos e planilha regravada pela 1.12.
4. **Idempotência e atomicidade de `confirmarVenda`**, e a edição e exclusão de vendas em grupo (ids `grupo.k`, `excluidos`, `mod` comum).
5. **Migração:** backup antes de tudo, nenhuma reescrita de dados aplicados, idempotência e a escolha do corte depois da sincronização.
6. **Arredondamento da posição fiscal** (D10): vender tudo zera o custo exatamente.
7. **Sugestões:** âncora na cotação e não na compra, rótulos de fonte, data e hora, sem intradiário falso, e tick.
8. **Workflow:** troca para estável e o job `conferir-atualizador` (sem credenciais locais e só leitura).
