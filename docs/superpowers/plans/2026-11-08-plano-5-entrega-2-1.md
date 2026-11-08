# Plano 5: entrega 2.1.0 (Implementation Plan)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Entregar e publicar a 2.1.0 estável: posições por data de corte e indicadores na apuração, sugestões de saída explicáveis, venda por quantidade com alocação gerencial, imposto por custo médio com day trade por ativo e compensação de prejuízo a partir do mês de corte, migração com backup e release conferida pelos dois atualizadores.

**Architecture:** Primeiro as funções só de leitura (`nucleo/posicoes.dart`, `nucleo/indicadores_ativo.dart`, `nucleo/sugestoes/cenario.dart`), que leem `Apuracao` pelos campos opcionais do motor fiscal e por isso passam a mostrar o fiscal sozinhas quando ele chega. Depois a venda em várias compras (`nucleo/alocacao.dart`, N linhas `Venda` com id `grupo.k`, uma única `repo.salvar`). Por fim o motor fiscal (`nucleo/apuracao_medio.dart`), despachado por `apurar(d)` pelo marcador `metodo` do mês, com o método antigo intacto; marcador também na coluna 14 da aba Resumo; migração incremental `2.1-custo-medio` com backup antes de tudo. A release troca o `release.yml` para estável e acrescenta o job `conferir-atualizador`.

**Tech Stack:** Flutter 3.47.9 (Dart 3.13.7), `provider`, testes `flutter_test` (tags `golden`, `ida_e_volta`), GitHub Actions (`release.yml`, `softprops/action-gh-release@v2`), Python 3 só no CI para o atualizador da 1.12 (`atualizador.py`, `requests`).

**Spec:** `docs/superpowers/specs/2026-11-08-entrega-2-1-design.md`. Pedido de origem (contrato): `prompt.md` na raiz do repositório principal (`D:\.Minhas_Coisas\calculadora DARF\CalculadoraDARF\prompt.md`, local, fora do git). Executores leem os dois; as decisões D1 a D16 do spec valem como requisitos.

## Global Constraints

Do pedido (`prompt.md`), literalmente:
- "Implemente as melhorias abaixo sem perder funcionalidades existentes, preservar os dados ou comprometer os cálculos."
- "Trate a seleção de compras como alocação gerencial e rastreabilidade, não como mecanismo para alterar artificialmente o lucro tributável." "Não permita que a seleção manual contorne essas regras."
- "A confirmação deve ser transacional, impedir envio duplicado e preservar a consistência entre venda, compras consumidas, saldo e apuração."
- "Exibir uma posição não pode gerar movimentação, lucro realizado ou imposto naquele período." "Identifique explicitamente quando uma cotação é atual, para não apresentá-la como cotação histórica."
- "Não apresente percentuais fixos arbitrários como estratégia profissional ou garantia de resultado." "Uma meta financeira distante não deve virar automaticamente uma recomendação de venda." "Não simule análise intradiária usando apenas o preço de compra." "Não invente cotações, indicadores ou probabilidades de sucesso." "Respeite a variação mínima de preço do instrumento."
- "Não recomende novas compras para reduzir preço médio: isso está fora deste pedido." "Não conecte este trabalho a execução automática de ordens em corretora e não transforme uma sugestão em venda registrada sem confirmação."
- "Não use média simples de percentuais de operações como se fosse rentabilidade consolidada. Defina o denominador de cada indicador e trate divisões por zero e dados indisponíveis."
- "Não altere migrações já aplicadas; crie migrações incrementais quando necessário." "Teste a atualização de uma base antiga com operações reais representativas." "Não invente vínculos históricos entre compras e vendas quando eles não puderem ser reconstruídos com segurança."
- "Não adicione dependências ou serviços pagos sem justificar e obter aprovação." "Evite refatorações não relacionadas."
- "Descubra e execute os comandos reais de testes, lint, análise estática e build. Não invente comandos nem declare testes não executados como aprovados."
- "Publique a release como estável/principal, e não como rascunho ou pré-release". "Confirme que o atualizador realmente detecta a nova versão. Marcar uma release como principal, isoladamente, não é evidência suficiente." "Não faça force push, não reescreva histórico e não inclua arquivos ou alterações alheios ao trabalho." "Não exponha credenciais nem contorne assinatura ou verificações de integridade." "Não prometa rollback seguro quando uma migração impedir o uso da versão anterior. Priorize backup e recuperação documentada."

Do spec:
- §2: "O workflow publica a 2.1.0 com `prerelease: false` e `make_latest: "true"` automaticamente na tag." "Meses fechados e DARFs pagas ficam como estão. O método novo vale a partir do primeiro mês aberto no momento da atualização." "Cada mês grava um marcador de método".
- §4 anti-metas: "Mudar algum valor da aba Resumo de um mês fechado antes do corte." "Uma escolha manual de compras alterar o imposto, a classificação de day trade ou o prejuízo acumulado." "Gravar uma venda pela metade, ou duas vezes, por clique duplo." "Mostrar uma cotação atual como se fosse histórica, ou mostrar um alvo sem fonte, data e horizonte." "Perder dados locais na migração: o backup vem sempre antes."
- D6: "**Nenhuma coluna nova na aba Vendas.**" Ids `<grupo>.<k>` (k a partir de 1); venda de uma compra só mantém o id simples.
- D10: dinheiro em `double` com `arredondar`/`somaPython`; custo da posição fiscal "arredondado ao centavo a cada evento"; custo baixado `arredondar(q × custo/qtd, 2)`.
- §5.1: o `apurar` atual roda "**sem nenhuma mudança**" para meses sem marcador (os testes de paridade com o Python continuam passando).
- §9.3: `atrPeriodo = 14`, `janelaSr = 20`, `multStop = 2`, `rrMinimo = 1.5`, `limiteLiquidez = 0.05`; swing "5 a 20 pregões" com ≥ 21 pregões fechados; day trade "o pregão de hoje". Sem VWAP.
- §8: "—" significa dado indisponível ou divisão por zero, nunca zero.
- §12: versão `2.1.0`, versionCode 20100, notas em `docs/release/2.1.0.md` publicadas por `body_path`.

Do ambiente de execução:
- Trabalhar só no worktree `D:\.Minhas_Coisas\calculadora DARF\CalculadoraDARF\.claude\worktrees\migracao-flutter`, branch `migracao-flutter`. Nunca tocar a `main` nem o código Python (`calculadora_darf.py`, `android/`, `atualizador.py`, `nucleo.py`, `metas.py`, `sugestoes.py`, `mercado.py`, `noticias.py`, `tests/`). O CI pode **executar** `atualizador.py`, sem alterá-lo.
- Builds Windows locais falham sem o Modo Desenvolvedor: **não ativar**. Builds Windows/Android e o teste de integração rodam no CI: um push em `migracao-flutter` dispara `release.yml` sem publicar. Resultado lido nas páginas públicas da execução e nas anotações (sem `gh`, sem credenciais; API pública com limite de 60 req/h). O push é feito pelo controlador.
- Comandos locais, em `app/`: `flutter analyze`; `flutter test --exclude-tags golden`; `flutter test --tags golden test/app/goldens` (só Windows; quando uma tela mudar, regenerar com `flutter test --tags golden test/app/goldens --update-goldens` e inspecionar as imagens). Na raiz: `python -m unittest discover -s tests` (prova que o Python ficou intacto).
- Agentes à disposição dos executores: `implementador` (pode delegar a `terminal`, `testador`, `explorador`, `paridade`, `depurador`, `monitor-ci`), `revisor`, `conferidor-visual`, `monitor-ci`. Cada tarefa indica quando a conferência do `conferidor-visual` ou do `monitor-ci` é esperada.
- Convenções do código: ordenar com `ordenadoPor` (nunca `.sort(`); `dart:io` e plugins só em `app/lib/app/plataforma/`; núcleo puro e sem Flutter; textos em português; dinheiro com `arredondar`/`somaPython`/`maxPython`/`minPython` de `nucleo/compat/numeros.dart`.
- Toda nova chamada de `ServicosApp` (`app/lib/app/servicos/api.dart`) é implementada em `ServicosLocais`, encaminhada em `servicos_isolate.dart` (`_chamar`) e coberta em `test/app/apoio/servicos_falsos.dart` e `servicos_eco.dart`.
- A tag `2.1.0` é criada pelo controlador depois da revisão final; nenhuma tarefa cria tag nem publica.

## Review Focus

1. **Mês aberto com vendas já registradas na hora da migração:** a posição inicial derivada (D3) usa a `qtd` dos lotes levados (o saldo no início do mês), não o `restante` depois das vendas do próprio mês; senão a venda seria descontada duas vezes. Esperado: Σ restante dos lotes = quantidade da posição fiscal final (Tarefa 12, teste `posição inicial derivada usa a qtd levada, não o restante`).
2. **Clique duplo e reabertura do formulário de venda:** o mesmo grupo confirmado duas vezes grava uma vez; um formulário reaberto ganha grupo novo (Tarefa 8, testes `confirmação dupla grava uma vez` e `falha de gravação não deixa linhas parciais`; Tarefa 9, `botão desativado durante a gravação`).
3. **Chandelier acima da cotação** (ativo que caiu forte depois de uma máxima recente): o stop de referência nunca fica igual ou acima da âncora; nesse caso usa só `P − 2·ATR14`. Esperado: risco positivo, R/R calculável (Tarefa 5, teste `chandelier acima da âncora não vira stop`).
4. **Planilha regravada por um aparelho 1.12 depois da 2.1:** coluna 14 desalinhada ou com mês trocado é ignorada e o marcador local não se perde (Tarefa 14, testes `valor desalinhado ignorado` e `marcador é monotônico na mesclagem`).
5. **Ativo com cotação ausente ou fonte em falha no meio da lista** (sugestões e carteira atual): a linha mostra o estado, os outros ativos continuam, exposição vira "—" (Tarefa 4, teste `exposição indisponível com cotação ausente`; Tarefa 6, teste `falha da fonte em um ticker não quebra a tela`).

---

## Estrutura de arquivos

| Arquivo | Responsabilidade |
|---|---|
| `app/lib/nucleo/tick.dart` (novo) | Tabela de ticks da B3, `tickDe`, `pisoTick`, `tetoTick` |
| `app/lib/nucleo/posicoes.dart` (novo) | Reconstrução de posições por data de corte (cadeias `origem ?? id`), pura |
| `app/lib/nucleo/indicadores_ativo.dart` (novo) | Indicadores por ativo e `pontoEquilibrio` |
| `app/lib/nucleo/sugestoes/cenario.dart` (novo) | Cenário de mercado swing e day trade, meta financeira, liquidez, consolidado |
| `app/lib/nucleo/modelos/barras.dart`, `nucleo/mercado/chart.dart` | `BarraDiaria.volume` |
| `app/lib/nucleo/alocacao.dart` (novo) | Elegíveis, alocação automática/manual, prévia, `montarVendas`, `confirmarVenda`, `editarGrupo`, `grupoDe` |
| `app/lib/nucleo/modelos/mes.dart` | `metodo`, `posicaoInicial`, `prejuizoAnterior` (`PosicaoFiscal`, `PrejuizoAcumulado`) |
| `app/lib/nucleo/apuracao.dart` | Campos opcionais em `Apuracao`/`Operacao`; `apurar` despacha |
| `app/lib/nucleo/apuracao_medio.dart` (novo) | `apurarCustoMedio`, `posicaoInicialDerivada`, `mesDeCorte`, `marcarCustoMedio`, consistência |
| `app/lib/nucleo/fechamento.dart` | Leva posição e prejuízo; venda retroativa antes/depois do corte |
| `app/lib/nucleo/repositorio.dart` | Carimbo de `mod` quando os campos novos mudam |
| `app/lib/nucleo/planilha/{abas,montagem,reconstrucao,mesclagem}.dart` | Coluna 14 "Detalhes" da aba Resumo e mesclagem monotônica |
| `app/lib/nucleo/migracoes.dart` (novo) | Migração `2.1-custo-medio` e `Config.migracoes` |
| `app/lib/app/plataforma/backup.dart` (novo) | Backup `backup/pre-2.1.0-AAAAMMDD-HHMMSS/` com conferência |
| `app/lib/app/servicos/api.dart` e implementações | Chamadas novas (posições, cotações, sugestões, venda por quantidade, prejuízo inicial) |
| `app/lib/app/telas/apuracao/*` | Seletor "Posição em …"/"Carteira atual", indicadores, vendas agrupadas |
| `app/lib/app/telas/formularios/form_venda.dart` | Venda por quantidade, Automático/Manual, painel fiscal x gerencial |
| `app/lib/app/telas/metas/aba_sugestoes.dart` | Sugestões por ativo, filtros, ordenação, estados |
| `app/lib/app/telas/conta/tela_conta.dart` | Prejuízo acumulado inicial (Configurações) |
| `app/lib/nucleo/caixa.dart` | Lançamento único por grupo de venda |
| `app/lib/versao.dart`, `app/test/versao_test.dart`, `docs/release/2.1.0.md` (novo), `.github/workflows/release.yml`, `app/ci/testar_instalador.ps1`, `app/test/integracoes/atualizador/atualizador_vivo_test.dart` (novo) | Release estável e conferência dos atualizadores |
| `docs/superpowers/plans/2026-11-08-plano-5-resultado.md` (novo) | Resultado da entrega e passo exato de publicação |

---

## Parte A: leitura (posições, indicadores, sugestões)

### Task 1: Tabela de tick da B3 confirmada e funções de arredondamento

**Files:**
- Create: `app/lib/nucleo/tick.dart`
- Modify: `app/lib/nucleo/nucleo.dart` (exportar)
- Test: `app/test/nucleo/tick_test.dart`

**Interfaces:**
- Produces: `const List<({double ate, double tick})> faixasTick`; `double tickDe(String ticker, double preco)`; `double pisoTick(String ticker, double v)`; `double tetoTick(String ticker, double v)`. Todas lançam `ArgumentError` com NaN ou infinito (como `_finitoCentavos` em `sugestoes.dart`).

- [ ] **Step 1: Confirmar a tabela (D15).** Baixar com WebFetch o documento "Variação Mínima de Apregoação (Tick Size)" (13/10/2026) listado em https://b3.com.br/pt_br/solucoes/plataformas/puma-trading-system/para-participantes-e-traders/regras-e-parametros-de-negociacao/regras-de-negociacao/ e ler a faixa de ações, units e BDRs (lote padrão e fracionário). Se não for legível, buscar outra página oficial da B3 com a mesma tabela. Resultado: ou a tabela confirmada (faixas e ticks), ou a limitação registrada ("não confirmado; premissa R$ 0,01"). Anotar a URL, a data da consulta e a conclusão no comentário de topo de `tick.dart` e guardar o texto para o documento de resultado (Tarefa 18).
- [ ] **Step 2: Escrever o teste que falha**

```dart
test('tetoTick arredonda para cima ao tick', () {
  expect(tetoTick('PETR4', 7.601), 7.61);
  expect(tetoTick('PETR4', 7.60), 7.60);   // já no tick não sobe
  expect(tetoTick('AAPL34', 12.0036), 12.01);
});
test('pisoTick arredonda para baixo ao tick', () {
  expect(pisoTick('PETR4', 7.609), 7.60);
  expect(pisoTick('PETR4', 10.63333), 10.63);
});
test('tickDe da faixa única', () => expect(tickDe('VALE3', 63.2), 0.01));
test('valores não finitos lançam', () => expect(() => tetoTick('PETR4', double.nan), throwsArgumentError));
```
Se o Step 1 confirmar faixas diferentes, acrescentar um caso por faixa com os valores do documento.
- [ ] **Step 3: Rodar e ver falhar:** `flutter test test/nucleo/tick_test.dart` → FAIL (arquivo inexistente).
- [ ] **Step 4: Implementar** `tick.dart`: conta em número inteiro de ticks com tolerância de 1e-9 (mesmo padrão de `tetoCentavo`/`pisoCentavo` em `metas/preco_alvo.dart`), resultado devolvido com `arredondar(..., 2)`.
- [ ] **Step 5: Rodar:** `flutter test test/nucleo/tick_test.dart` → PASS; `flutter analyze` → `No issues found!`.
- [ ] **Step 6: Commit:** `git add app/lib/nucleo/tick.dart app/lib/nucleo/nucleo.dart app/test/nucleo/tick_test.dart` e `git commit -m "Plano 5, tarefa 1: tick da B3 (tickDe, pisoTick, tetoTick)"`.

### Task 2: Reconstrução de posições por data de corte (núcleo)

**Files:**
- Create: `app/lib/nucleo/posicoes.dart`
- Test: `app/test/nucleo/posicoes_test.dart`

**Interfaces:**
- Consumes: `restante`, `vendido` (`nucleo/apuracao.dart`), `Mes`, `Lote`, `Venda`.
- Produces:
  - `class CompraNaPosicao { final String loteId; final String mes; final String dataCompra; final int qtdOriginal; final int restante; final double preco; }`
  - `class PosicaoAtivo { final String ticker; final String tipo; final int qtd; final double custoGerencial; double? custoFiscal; bool get custoPorCompra => custoFiscal == null; double? get precoMedio; final List<CompraNaPosicao> compras; }` (`precoMedio` = `(custoFiscal ?? custoGerencial) / qtd`, `null` com qtd 0; `custoFiscal` fica `null` até a Tarefa 13).
  - `List<PosicaoAtivo> posicoesEm(Map<String, Mes> meses, String dataCorte)` (ordenada por ticker; `dataCorte` = `AAAA-MM-DD`).
  - `String dataCorteDoMes(String mes, String hoje)`: último dia do mês, ou `hoje` se `mes == hoje.substring(0, 7)`.

- [ ] **Step 1: Escrever os testes que falham** (meses montados à mão, ids fixos; copiar o padrão de `test/nucleo/fechamento_test.dart`):
  - `posição aberta aparece em mês sem movimentação e sem arquivo`: L1 PETR4 100 @ 10,00 em 2026-01-05 (jan fechado), cópia `L1~2026-02` (`origem: L1`, qtd 100) em fev; sem arquivo de março → `posicoesEm(meses, '2026-03-31')` tem PETR4 com `qtd == 100` e `custoGerencial == 1000.0`.
  - `cópias levadas não somam compra`: a mesma cadeia com cópias em fev, mar e abr → `qtd == 100`, não 300.
  - `compra futura ausente da posição anterior`: compra em 2026-02-10 → `posicoesEm(meses, '2026-01-31')` vazio.
  - `posição encerrada visível nos meses certos`: venda de 100 em 2026-03-05 na cópia de março → em `'2026-02-28'` qtd 100; em `'2026-03-31'` PETR4 ausente.
  - `venda parcial conta só até a data`: venda de 40 em 2026-02-15 → `'2026-02-10'` qtd 100; `'2026-02-28'` qtd 60 e `compras.single.restante == 60`.
  - `retroativo forma cadeia própria`: lote retroativo sem `origem`, comprado e vendido no mesmo mês → não aparece e não altera a quantidade da cadeia original.
  - `reconstrução sem efeitos`: `jsonPython` de todos os meses antes e depois iguais; nenhum arquivo novo no `ArmazenamentoMemoria`.
  - `dataCorteDoMes`: `('2026-02', '2026-11-07') == '2026-02-28'`, `('2024-02', ...) == '2024-02-29'`, `('2026-11', '2026-11-07') == '2026-11-07'`.
- [ ] **Step 2: Rodar e ver falhar:** `flutter test test/nucleo/posicoes_test.dart` → FAIL.
- [ ] **Step 3: Implementar** pelas regras do spec §7.1: chave da cadeia `origem ?? id`; compra da cadeia = `qtd` do lote com `id == chave`; vendas = todas as `Venda` dos lotes da cadeia, em qualquer mês, com `data ≤ dataCorte`; só cadeias com `dataCompra ≤ dataCorte`; cadeia sem lote raiz nos meses carregados usa a `qtd` do lote mais antigo da cadeia (dados de amigo parciais) e não inventa vínculo.
- [ ] **Step 4: Rodar:** `flutter test test/nucleo/posicoes_test.dart` → PASS.
- [ ] **Step 5: Commit:** `git commit -m "Plano 5, tarefa 2: posições por data de corte (núcleo)"`.

### Task 3: Apuração com "Posição em dd/mm/aaaa" e "Carteira atual"

**Files:**
- Modify: `app/lib/app/servicos/api.dart`, `app/lib/app/servicos/locais/apuracao_local.dart`, `app/lib/app/servicos/locais/mercado_local.dart`, `app/lib/app/servicos/servicos_locais.dart`, `app/lib/app/servicos/servicos_isolate.dart`, `app/lib/app/telas/apuracao/{controle_apuracao,lista_lotes,tela_apuracao}.dart`
- Create: `app/lib/app/telas/apuracao/lista_posicoes.dart`
- Test: `app/test/app/telas/apuracao/posicoes_tela_test.dart`, `app/test/app/servicos/apuracao_local_test.dart`, goldens em `app/test/app/goldens/telas_golden_test.dart`; apoio `servicos_falsos.dart`, `servicos_eco.dart`

**Interfaces:**
- Consumes: `posicoesEm`, `dataCorteDoMes`, `PosicaoAtivo` (Tarefa 2).
- Produces:
  - `class CotacaoAtual { final double preco; final DataHora hora; final String fonte; }` (em `api.dart`; `fonte` = `'Yahoo'`, `hora` de `DadosAtivo.hora` no fuso de Brasília).
  - `class VisaoPosicoes { final String dataCorte; final bool corrente; final List<PosicaoAtivo> posicoes; final List<PosicaoAtivo> carteira; }`
  - `Future<VisaoPosicoes> posicoes(String mes, {String? amigo})` e `Future<Map<String, CotacaoAtual?>> cotacoesAtuais(Set<String> tickers)` em `ServicosApp`.
  - Textos fixos: `'Posição em $dd/$mm/$aaaa'`, `'Carteira atual'`, `'Cotação atual · Yahoo · $dd/$mm $hh:$mi'`, `'cotação histórica não disponível'`, `'custo por compra'`.

- [ ] **Step 1: Testes que falham.** Serviço: `posicoes('2026-03')` com março sem arquivo devolve a posição de `'2026-03-31'` e não cria `2026-03.json`. Tela (com `servicos_falsos`): seletor com os dois segmentos; mês histórico mostra `'cotação histórica não disponível'` e nenhum valor de mercado; mês corrente mostra o selo `'Cotação atual · Yahoo · 07/11 14:05'`; "Carteira atual" mantém os botões vender/editar/excluir dos lotes do mês aberto; padrão = "Carteira atual" quando o mês selecionado é o mês aberto, senão "Posição em …"; falha em `cotacoesAtuais` mostra a posição sem valor de mercado.
- [ ] **Step 2: Rodar e ver falhar:** `flutter test test/app/telas/apuracao test/app/servicos/apuracao_local_test.dart` → FAIL.
- [ ] **Step 3: Implementar.** A seção "Ativos comprados" (`lista_lotes.dart`) ganha um `SegmentedButton` com os dois segmentos. "Posição em …" usa `ListaPosicoes` (novo): por ativo, quantidade, custo e preço médio, compras expansíveis, só leitura. "Carteira atual" é a lista atual de lotes (filtros, ordenação e ações de hoje) alimentada pelo mês aberto (`mesInicial`), qualquer que seja o mês selecionado. O selo "Aberto" continua no mês de trabalho. Larguras de celular (cartões, sliver) e PC (tabela) como hoje.
- [ ] **Step 4: Rodar:** `flutter test --exclude-tags golden` → PASS; `flutter analyze` → sem problemas.
- [ ] **Step 5: Goldens:** acrescentar "apuração posição histórica" e "apuração carteira atual" (celular e PC, claro e escuro como os existentes); `flutter test --tags golden test/app/goldens --update-goldens`, depois `flutter test --tags golden test/app/goldens` → PASS. **Conferência do `conferidor-visual`** nas imagens novas e alteradas (barra lateral/inferior, texto cortado, selo de cotação legível, números alinhados).
- [ ] **Step 6: Commit:** `git commit -m "Plano 5, tarefa 3: posição no encerramento do mês e carteira atual na apuração"`.

### Task 4: Indicadores por ativo

**Files:**
- Create: `app/lib/nucleo/indicadores_ativo.dart`
- Modify: `app/lib/app/telas/apuracao/{lista_posicoes,detalhamento}.dart`, `app/lib/app/servicos/api.dart` (`VisaoPosicoes.indicadores`), `app/lib/app/servicos/locais/apuracao_local.dart`
- Test: `app/test/nucleo/indicadores_ativo_test.dart`, `app/test/app/telas/apuracao/posicoes_tela_test.dart`, goldens

**Interfaces:**
- Consumes: `PosicaoAtivo`, `apurar` (resultado por linha: `o.resultadoFiscal ?? o.liquido`; custo das unidades vendidas: `o.custoFiscal ?? o.compra`; os dois campos fiscais chegam na Tarefa 11 e são `null` até lá), `tetoTick`.
- Produces:
  - `double? pontoEquilibrio(String ticker, int qtd, double custoTotal)` = `tetoTick(ticker, (custoTotal / qtd + corretagemPorOrdem / qtd) / (1 - taxaB3Swing))`, `null` com qtd 0.
  - `class IndicadoresAtivo { ticker; int qtdAberta; double? custoRemanescente; bool custoPorCompra; double? precoMedioCompras; double? precoMedioVendasMes; double resultadoMes; double resultadoAcumulado; String desde; double? ganhoPorUnidade; double? rentabilidadeRealizada; double? naoRealizado; double? valorMercado; double? exposicao; double taxasMes; double? pontoEquilibrio; }`
  - `List<IndicadoresAtivo> indicadoresPorAtivo({required Map<String, Mes> meses, required String mes, required List<PosicaoAtivo> posicao, Map<String, CotacaoAtual?> cotacoes = const {}})`. Fórmulas e denominadores exatamente como na tabela do spec §8; `taxasMes = Σ(o.taxas + o.corretagem)` das linhas do ticker no mês; `resultadoAcumulado` = Σ dos meses ≤ `mes`, cada um por `apurar` (que despacha pelo método), `desde` = `MM/AAAA` do primeiro mês com dados.
  - `cotacoes` só é passado quando o mês é o corrente; com ele vazio, `naoRealizado`, `valorMercado` e `exposicao` são `null`.

- [ ] **Step 1: Testes que falham** (método antigo; `corretagemPorOrdem = 0`):
  - `médias ponderadas com taxas`: lotes A 100 @ 10,00 e B 200 @ 13,00 de PETR4, venda de 50 de A a 12,00 no mês → `qtdAberta == 250`, `custoRemanescente == 3100.0`, `precoMedioCompras == 12.40`, `pontoEquilibrio == 12.41`, `precoMedioVendasMes == 12.00`, `resultadoMes == closeTo(99.67, 1e-9)`, `ganhoPorUnidade == closeTo(1.9934, 1e-9)`, `rentabilidadeRealizada == closeTo(0.19934, 1e-9)`, `taxasMes == closeTo(0.33, 1e-9)`.
  - `resultado negativo`: venda de 50 de A a 9,00 → `resultadoMes == closeTo(-50.285, 1e-9)` e `rentabilidadeRealizada < 0`.
  - `sem vendas no mês dá "—" e não zero`: `precoMedioVendasMes`, `ganhoPorUnidade`, `rentabilidadeRealizada` são `null`.
  - `saldo zerado`: tudo vendido → `qtdAberta == 0`, `precoMedioCompras == null`, `pontoEquilibrio == null`.
  - `rentabilidade não é média simples de percentuais`: duas vendas (+10% sobre 100 e −50% sobre 1000) → `rentabilidadeRealizada == (10 − 500) / 1100`.
  - `exposição indisponível com cotação ausente`: dois ativos, cotação só de um → `exposicao == null` nos dois e `valorMercado` só no cotado.
  - `acumulado desde o primeiro mês`: jan +100, fev −30 → em fev `resultadoAcumulado == 70` e `desde == '01/2026'`.
- [ ] **Step 2: Rodar e ver falhar:** `flutter test test/nucleo/indicadores_ativo_test.dart` → FAIL.
- [ ] **Step 3: Implementar** o núcleo e a exibição: na visão "Posição" cada ativo expande os indicadores com rótulos que separam "no mês"/"acumulado desde MM/AAAA", "realizado"/"não realizado", "gerencial"/"fiscal" (enquanto `custoPorCompra`, rótulo "por compra") e R$/%; "—" para `null`. No detalhamento do mês, as mesmas linhas por ativo vendido. "Não realizado", "valor de mercado" e "exposição" só no mês corrente, com o selo de cotação da Tarefa 3. Cada rótulo tem `Tooltip` com a fórmula e o denominador.
- [ ] **Step 4: Rodar:** `flutter test --exclude-tags golden` → PASS; `flutter analyze`.
- [ ] **Step 5: Goldens** atualizados e inspecionados; **conferência do `conferidor-visual`** (largura de celular sem overflow nas linhas de indicador).
- [ ] **Step 6: Commit:** `git commit -m "Plano 5, tarefa 4: indicadores por ativo na apuração"`.

### Task 5: Cenário de mercado, meta financeira e consolidado (núcleo)

**Files:**
- Modify: `app/lib/nucleo/modelos/barras.dart` (`final double? volume;` em `BarraDiaria`), `app/lib/nucleo/mercado/chart.dart` (ler `indicators.quote[0].volume`)
- Create: `app/lib/nucleo/sugestoes/cenario.dart`
- Test: `app/test/nucleo/cenario_test.dart`, `app/test/nucleo/yahoo_test.dart` (volume)

**Interfaces:**
- Consumes: `calcularAtr`, `calcularChandelier` (`mercado/indicadores.dart`), `pisoTick`/`tetoTick`, `pontoEquilibrio` (Tarefa 4), `PosicaoAtivo`, `ehDiaUtil`/calendário de `datas.dart`.
- Produces:
  - Constantes documentadas: `atrPeriodo = 14`, `janelaSr = 20`, `multStop = 2`, `rrMinimo = 1.5`, `limiteLiquidez = 0.05`, `minPregoesSwing = 21`, `minutosCotacaoAtual = 20`.
  - `enum Horizonte { swing, dayTrade }`; `const textoHorizonte = {Horizonte.swing: '5 a 20 pregões', Horizonte.dayTrade: 'o pregão de hoje'}`.
  - `class CotacaoInfo { final double preco; final DataHora hora; final String fonte; final bool atual; }` e `CotacaoInfo cotacaoInfo(double preco, DataHora hora, String fonte, DataHora agoraBr)` (atual = do último pregão e, durante o pregão, com menos de 20 min). A Tarefa 6 converte cada `CotacaoAtual` (Tarefa 3) com esta função.
  - `bool barrasDesatualizadas(List<BarraDiaria> barras, String hoje)`.
  - `class CenarioMercado { Horizonte horizonte; double? ancora; String? rotuloAncora; double? stop; double? alvo; double? faixaMin; double? faixaMax; String? rotuloAlvo; double? potencial; double? risco; double? rr; bool oportunidade; String? motivo; double? vfm; String? baseData; List<String> avisos; }`
  - `CenarioMercado cenarioSwing({required String ticker, required List<BarraDiaria> barras, required String hoje, CotacaoInfo? cotacao, double? pontoEquilibrio, required int qtd})`
  - `CenarioMercado cenarioDayTrade({required String ticker, required List<BarraDiaria> barras, required String hoje, CotacaoInfo? cotacao, required bool pregaoAberto, double? pontoEquilibrio, required int qtd})`
  - `double metaFinanceira(String ticker, int qtd, double precoMedio, double lucroDesejado, {bool dayTrade = false})` = `tetoTick(ticker, (G + Q·PM·(1+t) + C) / (Q·(1−t)))`.
  - `class CenarioSaida { final String rotulo; final int qtd; final double preco; final double resultado; final double? resultadoPct; }` e `class ConsolidadoAtivo { ticker; int qtd; double custo; double? precoMedio; double? pontoEquilibrio; List<CenarioSaida> cenarios; }`
  - `ConsolidadoAtivo consolidar(PosicaoAtivo p, CenarioMercado c, {double? meta, int? qtdDigitada})`: cenários 25%, 50%, 100% e a quantidade digitada, nos preços alvo, stop e meta; resultado líquido de taxas B3 do regime e do IR estimado do regime (15% swing, 20% day trade, só sobre ganho); `%` sobre `qtd × precoMedio`.
  - Textos fixos: `'resistência de 20 pregões'`, `'projeção pela volatilidade (sem resistência recente acima)'`, `'Sem oportunidade identificada'`, motivos `'relação risco/retorno abaixo de 1,5'`, `'alvo abaixo do ponto de equilíbrio'`, `'dados insuficientes'`, `'Análise intradiária indisponível: sem cotação atual'`, `'Quantidade grande frente ao volume médio: a saída pode mover o preço'`, `'Liquidez indisponível'`, `'Spread: indisponível (o Yahoo não fornece livro de ofertas)'`, `'Meta acima do cenário de mercado para o horizonte'`.
  - **Decisão deste plano:** quando `Chandelier(22, 3) ≥ P`, o stop é `pisoTick(P − 2·ATR14)` (o stop precisa ficar abaixo da âncora). `sugerir`/`avaliar` de `sugestoes.dart` ficam intactos (testes portados do Python); a aba deixa de usá-los na Tarefa 6.

- [ ] **Step 1: Testes que falham** (barras sintéticas com um auxiliar `barras(n, {alta, baixa, fech, volume})` no teste):
  - `swing sem oportunidade por R/R`: 25 barras `alta 10.5, baixa 9.5, fech 10.0` → `stop == 8.00`, `alvo == 10.50`, `faixaMin == 10.01`, `faixaMax == 10.50`, `rr == closeTo(0.25, 1e-9)`, `oportunidade == false`, `motivo == 'relação risco/retorno abaixo de 1,5'`.
  - `alvo ancorado na cotação, não na compra`: as mesmas barras com `pontoEquilibrio` de uma compra a 5,93 e de outra a 4,00 → mesmos `alvo` e `stop`; nunca `5.93 + 4·ATR`.
  - `projeção pela volatilidade acima da máxima`: cotação atual acima da máxima dos 20 pregões fechados → `alvo == pisoTick(P + 2·ATR14)` e `rotuloAlvo == 'projeção pela volatilidade (sem resistência recente acima)'`.
  - `chandelier acima da âncora não vira stop`: máxima de 22 recente muito acima de P → `stop < ancora` e `risco > 0`.
  - `dados insuficientes`: 20 barras → `oportunidade == false`, `motivo == 'dados insuficientes'`.
  - `alvo abaixo do ponto de equilíbrio`: R/R bom mas `pontoEquilibrio` acima do alvo → `motivo == 'alvo abaixo do ponto de equilíbrio'`.
  - `day trade pelos pivôs`: barra anterior `alta 10.5, baixa 9.5, fech 10.2`, ATR14 1,0, cotação atual 10,00 → `stop == 9.63`, `alvo == 10.63`, `rr == closeTo(0.63 / 0.37, 1e-9)`, `oportunidade == true`.
  - `day trade sem cotação atual não simula`: `cotacao: null` → `motivo == 'Análise intradiária indisponível: sem cotação atual'`, `alvo == null`, `stop == null`.
  - `liquidez`: VFM = Σ(fech·volume)/20; `qtd·P > 0.05·VFM` gera o aviso de quantidade; uma barra sem volume gera `'Liquidez indisponível'`; o aviso de spread sempre presente.
  - `meta financeira`: `metaFinanceira('PETR4', 100, 10.00, 100) == 11.01`; acima do alvo do cenário → aviso `'Meta acima do cenário de mercado para o horizonte'` e `oportunidade` inalterada.
  - `consolidado ponderado por quantidade`: compras 100 @ 10,00 e 300 @ 6,00 → `precoMedio == 7.00` (não 8,00).
  - `cotação desatualizada`: hora da cotação de dois pregões atrás → `atual == false`; durante o pregão, 25 min atrás → `false`; 5 min → `true`.
  - `yahoo_test`: `volume` lido das barras diárias; ausente vira `null`.
- [ ] **Step 2: Rodar e ver falhar:** `flutter test test/nucleo/cenario_test.dart test/nucleo/yahoo_test.dart` → FAIL.
- [ ] **Step 3: Implementar** pelo spec §9.1 a §9.4 (âncora = cotação se atual, senão último fechamento; alvo e stop para baixo no tick, ponto de equilíbrio e meta para cima).
- [ ] **Step 4: Rodar:** os dois arquivos → PASS; `flutter test test/nucleo/sugestoes_test.dart` continua PASS (paridade).
- [ ] **Step 5: Commit:** `git commit -m "Plano 5, tarefa 5: cenário de mercado, meta financeira e consolidado (núcleo)"`.

### Task 6: Tela de sugestões por ativo

**Files:**
- Modify: `app/lib/app/servicos/api.dart` (`VisaoSugestoes`), `app/lib/app/servicos/locais/mercado_local.dart` (`sugestoesMetas`), `app/lib/app/telas/metas/{aba_sugestoes,controle_metas}.dart`, apoio de testes
- Test: `app/test/app/telas/metas/sugestoes_test.dart`, `app/test/app/servicos/mercado_local_test.dart`, goldens

**Interfaces:**
- Consumes: Tarefa 5 inteira, `posicoesEm` (carteira de hoje), `cotacoesAtuais` (Tarefa 3).
- Produces:
  - `enum EstadoDados { ok, semDados, desatualizado, falha }`
  - `class SugestaoAtivo { final String ticker; final EstadoDados estado; final String? mensagem; final CotacaoInfo? cotacao; final List<BarraDiaria> barras; final PosicaoAtivo? posicao; }` (o cenário e o consolidado são recalculados na tela por funções puras a partir de `barras`, sem nova requisição).
  - `class VisaoSugestoes { final List<SugestaoAtivo> ativos; final List<LinhaCard> rodape; }` (substitui `itens`).
  - `Future<VisaoSugestoes> sugestoesMetas({bool incluirRadar = false})`.
  - **Decisão deste plano:** "Só posições abertas" (ligado por padrão) esconde os tickers do radar sem posição; desligado, eles entram só com o cenário (sem consolidado) e só então são buscados.

- [ ] **Step 1: Testes que falham** (tela com `servicos_falsos`, `tester.pump(const Duration(milliseconds: 300))` para a espera):
  - `agrupa por ativo e expande as compras` (rótulo "gerencial" nas compras).
  - `filtros de horizonte, posições abertas e dados`.
  - `ordena por R/R, distância até o alvo, liquidez e ticker, sem dado no fim`.
  - `recalcula ao mudar quantidade, preço e horizonte sem nova requisição` (contador de chamadas do falso fica em 1).
  - `falha da fonte em um ticker não quebra a tela`: um ticker lança, o outro mostra o cenário; a linha com falha mostra a mensagem.
  - `dados desatualizados mostram data e hora`.
  - `meta financeira separada do cenário`: três blocos com rótulos "Ponto de equilíbrio", "Meta financeira (simulação)" e "Cenário de mercado"; meta acima do alvo mostra o aviso e não vira recomendação.
  - `sem oportunidade desativa "Criar meta de alvo e stop"`; com oportunidade, a meta criada usa `alvo` e `stop` do cenário (`criarMetaAlvo`/`criarStop` recebem esses valores).
  - `horizonte e fonte sempre visíveis no alvo` (`'5 a 20 pregões'`, `'Yahoo'`, data e hora).
  - Serviço: uma requisição por ticker ao abrir, reusando o cache do Yahoo.
- [ ] **Step 2: Rodar e ver falhar:** `flutter test test/app/telas/metas test/app/servicos/mercado_local_test.dart` → FAIL.
- [ ] **Step 3: Implementar** a aba pelo spec §9.5; avisos `avisoSugestao`, `avisoProventos` e `avisoGap` continuam no rodapé; "Atualizar" manual; nada é gravado.
- [ ] **Step 4: Rodar:** `flutter test --exclude-tags golden` → PASS; `flutter analyze`.
- [ ] **Step 5: Goldens** da aba (celular e PC; um ativo com oportunidade, um sem, um com falha) atualizados e inspecionados; **conferência do `conferidor-visual`**.
- [ ] **Step 6: Commit:** `git commit -m "Plano 5, tarefa 6: sugestões por ativo com filtros, ordenação e estados"`.

## Parte B: venda em várias compras

### Task 7: Alocação gerencial (núcleo)

**Files:**
- Create: `app/lib/nucleo/alocacao.dart`
- Test: `app/test/nucleo/alocacao_test.dart`

**Interfaces:**
- Consumes: `restante`, `apurar`, `Mes`, `Lote`, `Venda`, `ErroValidacao`.
- Produces:
  - `class ItemAlocacao { final Lote lote; final int qtd; final bool travado; }` (`travado` = compra do mesmo dia, parte obrigatória de day trade).
  - `List<Lote> comprasElegiveis(Mes d, String ticker, String dataVenda)` (`dataCompra ≤ dataVenda`, `restante > 0`).
  - `double custoUnitarioEfetivo(Lote l)` = `l.preco * (1 + taxaB3Swing) + corretagemPorOrdem / l.qtd`.
  - `List<ItemAlocacao> alocarAutomatico(List<Lote> elegiveis, int qtd, String dataVenda)`: compras do dia primeiro (travadas), depois menor custo efetivo, desempate por `dataCompra` mais antiga e depois `id` (`compararTexto`); lança `ErroValidacao('Quantidade indisponível: só há $disp ações de $ticker nessa data.')`.
  - `String? validarManual(List<Lote> elegiveis, List<ItemAlocacao> selecao, int qtd, String dataVenda)`; mensagens: `'A soma das compras escolhidas ($s) é diferente da quantidade da venda ($q).'`, `'A compra de $dd/$mm/$aaaa tem só $r ações disponíveis.'`, `'As compras de hoje entram primeiro (day trade, regra da Receita).'`, `'Compra fora das disponíveis nessa data.'`.
  - `class LinhaPrevia { final ItemAlocacao item; final double custoEfetivo; final double resultadoGerencial; }` e `class PreviaVenda { final List<LinhaPrevia> linhas; final double gerencial; final double fiscal; final int qtdDt; final int qtdComum; }`
  - `PreviaVenda previa(Mes d, List<ItemAlocacao> selecao, double preco, String dataVenda)`: gerencial por linha `q·preco − q·custoEfetivo − q·preco·taxa` (taxa do regime da parte); `fiscal` = `apurar(cópia com a venda) − apurar(d)` em `lucroLiquido`, via o despacho (antes da Tarefa 12 sai pelo método antigo; depois, pelo custo médio, sem mudar esta função).
  - `List<Venda> montarVendas(List<ItemAlocacao> selecao, String grupo, String data, double preco, double mod)`: uma linha por item; id `grupo` com um item, `'$grupo.$k'` (k = 1..n) com vários; todas com o mesmo `mod`.
  - `String grupoDe(String vendaId)`: o prefixo antes de `.k` quando casa `^(.+)\.(\d+)$`, senão o próprio id.

- [ ] **Step 1: Testes que falham:**
  - `automático escolhe o menor custo efetivo`: A 100 @ 12,00 (01-05), B 100 @ 10,00 (01-10), C 100 @ 11,00 (01-03); venda de 150 em 02-10 → `[(B, 100), (C, 50)]`.
  - `desempate por data e depois por id`: B e C a 10,00, C mais antiga → C primeiro; mesma data e preço → id menor primeiro.
  - `compras do dia primeiro e travadas`: D 50 @ 13,00 em 02-10; venda de 120 em 02-10 → `[(D, 50, travado), (B, 70)]`.
  - `venda parcial e várias compras` (soma confere, consumo parcial do último).
  - `quantidade insuficiente lança` com a mensagem exata.
  - `validarManual`: soma diferente, item acima do disponível, compra do dia sem a quantidade obrigatória, lote fora das elegíveis → mensagens exatas; seleção válida → `null`.
  - `montarVendas`: um item → id `'g'`; três itens → `'g.1'`, `'g.2'`, `'g.3'`, mesmo `mod`; `grupoDe('g.2') == 'g'`, `grupoDe('auto-m1') == 'auto-m1'`.
  - `prévia gerencial muda com a alocação` (A × B dão gerenciais diferentes).
- [ ] **Step 2: Rodar e ver falhar:** `flutter test test/nucleo/alocacao_test.dart` → FAIL.
- [ ] **Step 3: Implementar** com `ordenadoPor`.
- [ ] **Step 4: Rodar:** → PASS.
- [ ] **Step 5: Commit:** `git commit -m "Plano 5, tarefa 7: alocação gerencial de vendas (núcleo)"`.

### Task 8: Confirmação atômica, idempotente, e edição de grupo (núcleo e serviço)

**Files:**
- Modify: `app/lib/nucleo/alocacao.dart`, `app/lib/app/servicos/api.dart`, `app/lib/app/servicos/locais/apuracao_local.dart`, `servicos_locais.dart`, `servicos_isolate.dart`, apoio de testes
- Test: `app/test/nucleo/alocacao_test.dart`, `app/test/app/servicos/apuracao_local_test.dart`

**Interfaces:**
- Consumes: Tarefa 7.
- Produces:
  - `class NovaVendaQtd { final String ticker; final String data; final int qtd; final double preco; final String grupo; final List<(String loteId, int qtd)>? selecao; }` (`selecao == null` = automático).
  - `({Mes mes, bool duplicada}) confirmarVenda(Repositorio repo, String mes, NovaVendaQtd v)`: recarrega o mês do disco; se já existe venda com id `v.grupo` ou `'${v.grupo}.k'`, devolve `duplicada: true` sem gravar; valida (alocação ou `validarManual`) contra o mês recarregado; acrescenta as linhas e chama `repo.salvar` **uma vez**.
  - `Mes editarGrupo(Repositorio repo, String mes, String grupo, NovaVendaQtd v)`: libera a quantidade do grupo, refaz a alocação, as linhas que somem vão para `excluidos` pelo carimbo de `salvar`, as novas usam `k` ainda não usados no grupo (nem em `excluidos`).
  - Serviço: `Future<String> novoGrupoVenda()` (usa `ambiente.novoId()`; o formulário pede um ao abrir), `Future<List<Lote>> comprasElegiveis(String mes, String ticker, String data)`, `Future<PreviaVenda> previaVenda(String mes, NovaVendaQtd v)`, `Future<VendaRegistrada> registrarVendaQtd(String mes, NovaVendaQtd v)` (duplicada → `VendaRegistrada.aviso == 'Essa venda já foi registrada.'`), `Future<VisaoMes> editarGrupoVenda(String mes, String grupo, NovaVendaQtd v)`; `excluirVenda(mes, id)` passa a apagar todas as linhas de `grupoDe(id)`.
  - Venda retroativa continua por `registrarVenda` (uma compra, D11).

- [ ] **Step 1: Testes que falham:**
  - `confirmação dupla grava uma vez`: duas chamadas com o mesmo grupo → uma gravação (contador num `Armazenamento` de teste), segunda `duplicada == true`.
  - `falha de gravação não deixa linhas parciais`: `Armazenamento` que lança em `gravar` → exceção propagada e `repo.carregar(mes)` sem nenhuma linha do grupo.
  - `valida contra o mês recarregado`: outra gravação consome o saldo entre a prévia e a confirmação → `ErroValidacao` de quantidade indisponível.
  - `editar grupo reusa índices novos`: grupo `g.1`,`g.2`; edição para 3 compras → `g.3`,`g.4`,`g.5` (ou os não usados), `excluidos` contém `g.1`,`g.2` se sumiram.
  - `excluir uma linha do grupo apaga o grupo inteiro`.
  - `venda de uma compra só tem id simples`.
  - Serviço: `registrarVendaQtd` devolve a visão com as N linhas e dispara `_gravou()` uma vez.
- [ ] **Step 2: Rodar e ver falhar:** `flutter test test/nucleo/alocacao_test.dart test/app/servicos/apuracao_local_test.dart` → FAIL.
- [ ] **Step 3: Implementar.**
- [ ] **Step 4: Rodar:** → PASS; `flutter test --exclude-tags golden` → PASS (inclui `servicos_isolate_test`).
- [ ] **Step 5: Commit:** `git commit -m "Plano 5, tarefa 8: confirmação atômica e idempotente da venda em várias compras"`.

### Task 9: Formulário de venda por quantidade (Windows e Android)

**Files:**
- Modify: `app/lib/app/telas/formularios/{form_venda,abrir_formulario}.dart`, `app/lib/app/regras/formularios.dart`
- Test: `app/test/app/telas/formularios/form_venda_test.dart`, `app/test/app/regras/formularios_test.dart`, goldens

**Interfaces:**
- Consumes: chamadas da Tarefa 8.
- Produces: textos fixos `'Automático'`, `'Manual'`, `'Primeiro as compras de hoje (day trade, regra da Receita). Depois as de menor custo por ação, incluindo as taxas de compra; em empate, a mais antiga.'`, `'Selecionado $x de $y'`, `'Resultado pelas compras escolhidas (gerencial): R$ …'`, `'Resultado fiscal da operação (custo médio): R$ …'` (antes do corte: `'(por compra)'`), `'Day trade: $n ações; comum: $m ações'`, e o texto fixo do spec §6.2 que começa por "A escolha das compras organiza o seu controle".

- [ ] **Step 1: Testes que falham:**
  - `caminho geral abre em Automático`; `duplo clique num lote abre em Manual com o lote selecionado e o ativo preenchido`.
  - `alternar modos não grava` (contador de `registrarVendaQtd` em 0); ao passar para Manual a seleção automática é o ponto de partida.
  - `manual mostra data, quantidade original, disponível e custo`; campo limitado ao disponível; compras do dia travadas.
  - `Confirmar só habilita com a soma exata`.
  - `botão desativado durante a gravação` (Completer no falso; segundo toque não chama de novo).
  - `venda duplicada mostra "Essa venda já foi registrada."`.
  - `painel fiscal x gerencial` com os quatro textos; prévia recalculada 300 ms depois da última tecla.
  - `mês fechado e venda retroativa seguem com uma compra` (fluxo atual intacto).
  - `editar venda em grupo abre o grupo inteiro`.
- [ ] **Step 2: Rodar e ver falhar:** `flutter test test/app/telas/formularios/form_venda_test.dart` → FAIL.
- [ ] **Step 3: Implementar** (`SegmentedButton`, "Você já fez a venda?" mantido, indicador no botão).
- [ ] **Step 4: Rodar:** `flutter test --exclude-tags golden` → PASS; `flutter analyze`.
- [ ] **Step 5: Goldens** do formulário (Automático e Manual, celular e PC) atualizados e inspecionados; **conferência do `conferidor-visual`**.
- [ ] **Step 6: Commit:** `git commit -m "Plano 5, tarefa 9: formulário de venda por quantidade, automático e manual"`.

### Task 10: Lista de vendas e caixa agrupados, verificação no CI

**Files:**
- Modify: `app/lib/app/telas/apuracao/lista_vendas.dart`, `app/lib/nucleo/caixa.dart`, `app/integration_test/app_test.dart` (captura do formulário novo)
- Test: `app/test/app/telas/apuracao/listas_test.dart`, `app/test/nucleo/caixa_test.dart`, goldens

**Interfaces:**
- Consumes: `grupoDe` (Tarefa 7).
- Produces: a lista mostra um grupo numa linha (quantidade total, preço, resultado somado) expansível para as linhas por compra; o Caixa soma as linhas do grupo num lançamento só, sem mudar `resumoOrdem` por linha.

- [ ] **Step 1: Testes que falham:** `grupo aparece numa linha e expande`; `venda simples continua igual`; `caixa soma o grupo num lançamento` com valor = Σ dos `resumoOrdem` das linhas; `caixa_test` existentes continuam (paridade).
- [ ] **Step 2: Rodar e ver falhar:** `flutter test test/app/telas/apuracao/listas_test.dart test/nucleo/caixa_test.dart` → FAIL.
- [ ] **Step 3: Implementar**; acrescentar ao teste de integração uma captura do formulário de venda em Automático.
- [ ] **Step 4: Rodar:** `flutter test --exclude-tags golden` → PASS; goldens atualizados e inspecionados; `flutter analyze`.
- [ ] **Step 5: Commit:** `git commit -m "Plano 5, tarefa 10: vendas em grupo na lista e no caixa"`.
- [ ] **Step 6: CI:** pedir ao controlador o push de `migracao-flutter`; **`monitor-ci`** acompanha a execução de `release.yml` e confirma jobs `testes`, `android` e `windows` verdes (teste de integração e contagem de capturas nas anotações). Falha → `superpowers:systematic-debugging` antes de corrigir.

## Parte C: motor fiscal

### Task 11: Campos de método no mês e na apuração

**Files:**
- Modify: `app/lib/nucleo/modelos/mes.dart`, `app/lib/nucleo/apuracao.dart` (só classes `Apuracao`/`Operacao`), `app/lib/nucleo/repositorio.dart`
- Test: `app/test/nucleo/modelos_test.dart`, `app/test/nucleo/repositorio_test.dart`

**Interfaces:**
- Produces:
  - `const metodoCustoMedio = 'custo_medio';`
  - `class PosicaoFiscal { int qtd; double custo; }` (JSON `{"qtd", "custo"}`), `class PrejuizoAcumulado { double comum; double dayTrade; }` (JSON `{"comum", "day_trade"}`).
  - Em `Mes`: `String? metodo; Map<String, PosicaoFiscal>? posicaoInicial; PrejuizoAcumulado? prejuizoAnterior;` (chaves `metodo`, `posicao_inicial`, `prejuizo_anterior`, emitidas só quando não nulas, depois de `mod`/`resumo` na ordem nova e na ordem lida quando já existiam).
  - Em `Apuracao` (opcionais, `null` no método antigo): `metodo`, `compensadoComum`, `compensadoDt`, `prejuizoComumFinal`, `prejuizoDtFinal`, `Map<String, PosicaoFiscal>? posicaoFinal`, `List<String> inconsistentes` (vazia por padrão). Em `Operacao`: `int? qtdDt`, `double? custoFiscal`, `double? resultadoFiscal`, `String? regime` (`'Day trade'`, `'Swing'`, `'Swing (isento)'`, `'Misto'`).
  - `Repositorio.salvar` carimba `d.mod` também quando `metodo`, `posicao_inicial` ou `prejuizo_anterior` diferem do arquivo (comparação profunda).

- [ ] **Step 1: Testes que falham:** `mês antigo faz ida e volta idêntica` (JSON das referências sem os campos novos sai byte a byte igual); `campos novos fazem ida e volta`; `salvar carimba mod quando o marcador muda`; `Apuracao do método antigo tem os campos novos nulos`.
- [ ] **Step 2: Rodar e ver falhar:** `flutter test test/nucleo/modelos_test.dart test/nucleo/repositorio_test.dart` → FAIL.
- [ ] **Step 3: Implementar.**
- [ ] **Step 4: Rodar:** → PASS; `flutter test test/nucleo` inteiro → PASS (paridade intacta).
- [ ] **Step 5: Commit:** `git commit -m "Plano 5, tarefa 11: marcador de método no mês e campos fiscais na apuração"`.

### Task 12: `apurarCustoMedio` e despacho de `apurar`

**Files:**
- Create: `app/lib/nucleo/apuracao_medio.dart`
- Modify: `app/lib/nucleo/apuracao.dart` (`apurar` despacha; o corpo antigo vira `apurarPorCompra`, sem mudança de linha alguma além da assinatura), `app/lib/nucleo/nucleo.dart`
- Test: `app/test/nucleo/apuracao_medio_test.dart`, `app/test/nucleo/alocacao_test.dart`

**Interfaces:**
- Consumes: Tarefa 11.
- Produces:
  - `Apuracao apurar(Mes d)` → `d.metodo == metodoCustoMedio ? apurarCustoMedio(d) : apurarPorCompra(d)`.
  - `Apuracao apurarCustoMedio(Mes d)`: algoritmo do spec §5.2, passos 1 a 9, sem desvios.
  - `Map<String, PosicaoFiscal> posicaoInicialDerivada(Mes d)` (D3): lotes com `origem` ou `dataCompra` anterior ao mês, por ticker, `qtd += l.qtd` e `custo += arredondar(l.qtd * l.preco * (1 + taxaB3Swing), 2)`. **Decisão deste plano:** usa `l.qtd` (o saldo levado, no início do mês), não `restante(l)`: as vendas do próprio mês são eventos do algoritmo.
  - `String? mesDeCorte(Iterable<Mes> meses)` (menor mês com `metodo`), `bool usaCustoMedio(Mes m, String? corte)` (regra efetiva do §5.3), `void marcarCustoMedio(Mes d, {PrejuizoAcumulado? prejuizo})` (grava `metodo`, `posicaoInicialDerivada(d)` e o prejuízo, padrão zero).
  - Texto: `'Saldo inconsistente em $ticker: confira as vendas'`.

- [ ] **Step 1: Testes que falham** (`closeTo(..., 1e-9)`; `corretagemPorOrdem = 0` salvo indicação):
  - `comum por custo médio, isento`: posição inicial PETR4 `{100, 1000.30}`; compra 100 @ 12,00 em 03-10; venda de 100 @ 13,00 em 03-20 → custo baixado 1100.33, resultado 199.28, `isento == true`, `impSt == 0`, `posicaoFinal['PETR4'] == {100, 1100.33}`.
  - `comum tributável com compensação`: VALE3 `{1000, 50015.00}`, prejuízo comum anterior 1000; venda de 500 @ 60,00 → resultado 4983.50, `compensadoComum == 1000`, `impSt == 597.525`, `irrf == 1.50`, `prejuizoComumFinal == 0`.
  - `day trade com compras de lotes diferentes e estoque anterior desconsiderado`: PETR4 `{100, 1000.00}`; em 03-10 compras X 100 @ 10,00 e Y 100 @ 11,00, vendas 100 (da cópia antiga) + 50 (de X) @ 12,00 → resultado DT 224.22375, as duas linhas `regime == 'Day trade'`, `impDt == 44.84475`, posição final `{150, 1525.16}`.
  - `misto`: o mesmo com vendas de 150 + 100 → DT 298.965, comum 99.82, linhas `regime == 'Misto'` com `qtdDt` proporcional, posição final `{50, 500.00}`.
  - `compensações separadas`: prejuízo DT 300 no caso DT → `compensadoDt == 224.22375`, `prejuizoDtFinal == 75.77625`, `impDt == 0`; prejuízo comum 500 no caso DT → `impDt == 44.84475` e `prejuizoComumFinal == 500`.
  - `mês isento com perda de ações e ganho de BDR`: ITUB4 `{100, 3000.00}` vendida a 29,00 (−100.87) e AAPL34 `{100, 5000.00}` a 53,00 (298.41) → `isento == true`, `impSt == closeTo(197.54 * 0.15, 1e-9)`, `vendasAcoesSt == 2900`.
  - `vender tudo zera o custo exatamente`: `{3, 10.00}` vendida 1 a 1 em três dias → ticker fora de `posicaoFinal` e Σ custo baixado == 10.00.
  - `venda acima da posição não inventa custo`: `{10, ...}` e venda de 20 → `inconsistentes == ['PETR4']`.
  - `posição inicial derivada usa a qtd levada, não o restante`: cópia levada de 100 com venda de 40 no mês → derivada `qtd == 100`; depois de apurar, Σ restante dos lotes (60) == `posicaoFinal` (60).
  - `método antigo intacto`: `apuracao_test.dart` e `fechamento_test.dart` existentes sem edição → PASS.
  - Em `alocacao_test.dart`: `fiscal igual para alocações diferentes da mesma venda` (mês marcado; seleção A × B → `previa.gerencial` difere, `previa.fiscal` igual) e `seleção manual não muda a classificação de day trade`.
- [ ] **Step 2: Rodar e ver falhar:** `flutter test test/nucleo/apuracao_medio_test.dart` → FAIL.
- [ ] **Step 3: Implementar** (`arredondar` a cada evento do custo; atribuição às linhas por fração `dt/S`; `Operacao.dt = fracaoDt == 1`, `liquido = resultadoFiscal`, `compra = custoFiscal`).
- [ ] **Step 4: Rodar:** `flutter test test/nucleo` → PASS (todas as referências Python continuam).
- [ ] **Step 5: Commit:** `git commit -m "Plano 5, tarefa 12: apuração por custo médio, day trade por ativo e compensação"`.

### Task 13: Fechamento, venda retroativa, edição travada e consistência

**Files:**
- Modify: `app/lib/nucleo/fechamento.dart`, `app/lib/nucleo/apuracao.dart` (`mensagemFechamento`, `erroEdicaoLote`), `app/lib/nucleo/posicoes.dart` (`custoFiscal`), `app/lib/app/servicos/locais/apuracao_local.dart` (marcar mês aberto ≥ corte ao carregar; bloquear fechamento com inconsistência; aviso na visão)
- Test: `app/test/nucleo/fechamento_test.dart` (casos novos, sem editar os antigos), `app/test/nucleo/posicoes_test.dart`, `app/test/app/servicos/apuracao_local_test.dart`, `app/test/app/telas/apuracao/tela_apuracao_test.dart`

**Interfaces:**
- Consumes: Tarefas 11 e 12.
- Produces:
  - `fecharMes` de um mês por custo médio grava no seguinte (se não fechado): `metodo`, `posicaoInicial = r.posicaoFinal`, `prejuizoAnterior = (r.prejuizoComumFinal, r.prejuizoDtFinal)`; `mensagemFechamento` ganha a linha `'Prejuízo levado para o próximo mês: comum R$ …; day trade R$ …'` quando algum for > 0.
  - `mesAceitaVendaRetroativa(repo, mes, mesAtual)` recusa `mes ≥ corte`; mensagem `'Meses apurados por custo médio não aceitam venda retroativa.'`. Antes do corte, com o mês aberto por custo médio, `registrarVendaRetroativa` baixa `q` e `arredondar(q · custo/qtd, 2)` de `posicaoInicial[ticker]`; sem posição, `ErroValidacao`.
  - `erroEdicaoLote`: lote com `origem` em mês por custo médio não aceita mudança de `qtd` nem `preco`: `'Compra levada de um mês anterior: quantidade e preço fazem parte da posição inicial e não podem ser editados.'`.
  - `posicoesEm` preenche `custoFiscal` quando o mês da data de corte usa custo médio (posição inicial do mês + eventos até a data, mesmo algoritmo).
  - `prepararFechamento` recusa com `r.inconsistentes` não vazio (mensagem com o aviso da Tarefa 12); a visão do mês mostra o aviso.
  - Mês aberto ≥ corte sem marcador é marcado (`marcarCustoMedio`) e salvo ao carregar os próprios dados; dados de amigo usam a mesma marcação só em memória.

- [ ] **Step 1: Testes que falham:** `fechamento leva posição e prejuízo`; `mês seguinte fechado não é alterado`; `retroativa antes do corte baixa a posição inicial`; `retroativa a partir do corte é recusada` (mensagem exata); `cópia levada não edita qtd nem preço`; `compra nova do mês continua editável`; `posição fiscal na data de corte` (custo médio no rótulo, `custoPorCompra == false`); `inconsistência bloqueia o fechamento e aparece na tela`; `mês aberto posterior ao corte é marcado ao carregar`.
- [ ] **Step 2: Rodar e ver falhar:** `flutter test test/nucleo/fechamento_test.dart test/nucleo/posicoes_test.dart test/app/servicos/apuracao_local_test.dart` → FAIL.
- [ ] **Step 3: Implementar.**
- [ ] **Step 4: Rodar:** `flutter test --exclude-tags golden` → PASS; `flutter analyze`.
- [ ] **Step 5: Commit:** `git commit -m "Plano 5, tarefa 13: fechamento, venda retroativa e consistência no custo médio"`.

### Task 14: Coluna 14 "Detalhes" da aba Resumo e mesclagem monotônica

**Files:**
- Modify: `app/lib/nucleo/planilha/{abas,montagem,reconstrucao,mesclagem}.dart`
- Test: `app/test/nucleo/{planilha_montagem_test,planilha_reconstrucao_test,mesclagem_test,ida_e_volta_test}.dart`

**Interfaces:**
- Consumes: Tarefa 11.
- Produces: `ColunaAba('Detalhes', 'id', 80)` como 14ª coluna (índice 13) da aba Resumo, oculta como a das Metas; valor `jsonPython({'mes', 'metodo', 'posicao_inicial', 'prejuizo_anterior'}, compacto: true)` só em meses com marcador, vazio nos outros; `reconstruir` lê com `_completar(..., 14)` e aceita só se `mes` == coluna 0; `mesclarMes`: campos novos do vencedor por `mod`, com a exceção monotônica do spec §5.3.

- [ ] **Step 1: Testes que falham:** `coluna 14 gravada e lida`; `planilha de 13 colunas aceita`; `valor desalinhado ignorado` (mês trocado); `meses sem marcador têm as 13 primeiras células idênticas às de hoje e a 14ª vazia`; `marcador é monotônico na mesclagem` (local com marcador × remoto sem e com `mod` maior → marcador mantido; mês fechado sem marcador no vencedor → sem marcador); `conflito de corte entre aparelhos` (os dois marcadores em meses diferentes → regra efetiva). Em `ida_e_volta_test` (tag `ida_e_volta`): fixture com grupo `g.1`/`g.2` e coluna 14.
- [ ] **Step 2: Rodar e ver falhar:** `flutter test test/nucleo/planilha_montagem_test.dart test/nucleo/planilha_reconstrucao_test.dart test/nucleo/mesclagem_test.dart` → FAIL.
- [ ] **Step 3: Implementar.**
- [ ] **Step 4: Rodar:** `flutter test test/nucleo` → PASS; `flutter test --tags ida_e_volta` e, na raiz, `python ferramentas/conferir_ida_e_volta.py` → o `reconstruir` do Python lê a planilha da 2.1 com as mesmas compras e vendas (saída de sucesso da ferramenta); `python -m unittest discover -s tests` → OK.
- [ ] **Step 5: Commit:** `git commit -m "Plano 5, tarefa 14: marcador na coluna Detalhes do Resumo e mesclagem monotônica"`.

### Task 15: Migração `2.1-custo-medio` com backup e teste de base antiga

**Files:**
- Create: `app/lib/nucleo/migracoes.dart`, `app/lib/app/plataforma/backup.dart`, `app/test/nucleo/apoio/base_2_0.dart`
- Modify: `app/lib/nucleo/modelos/config.dart` (`List<String> get migracoes` / `set` sobre `extras['migracoes']`), `app/lib/app/servicos/servicos_locais.dart` (`iniciar`), `app/lib/app/servicos/api.dart` (`EventoMigracao` em `eventos.dart`), `app/lib/app/app.dart` (aviso)
- Test: `app/test/nucleo/migracoes_test.dart`, `app/test/app/plataforma/backup_test.dart`

**Interfaces:**
- Consumes: `marcarCustoMedio`, `mesDeCorte` (Tarefa 12), `Repositorio.mesInicial`.
- Produces:
  - `const idMigracaoCustoMedio = '2.1-custo-medio';`
  - `class ResultadoMigracaoDados { final bool aplicada; final String? corte; final String? erro; }`
  - `Future<ResultadoMigracaoDados> migrarCustoMedio(Repositorio repo, {required String Function() fazerBackup, required Future<void> Function() sincronizar})`: já aplicada → nada; `fazerBackup` lança → não migra e devolve `erro`; `sincronizar` (erro de rede ou sem login é ignorado) → corte = `repo.mesInicial()` → `marcarCustoMedio` nele e nos meses abertos posteriores existentes que ainda não têm marcador → grava `migracoes`. Nunca reescreve lotes, vendas, `resumo` nem meses fechados.
  - `String fazerBackup(String pastaDados, DateTime agora)` (`dart:io`): copia todos os `*.json` para `backup/pre-2.1.0-AAAAMMDD-HHMMSS/`, confere quantidade e tamanhos e devolve a pasta; diferença → `FileSystemException`.
  - Aviso na partida com erro: `'Não foi possível fazer o backup dos dados; o cálculo por custo médio não foi ativado. Feche outros programas que usem a pasta de dados e abra o app de novo.'`.

- [ ] **Step 1: Testes que falham:**
  - `base_2_0.dart` monta, a partir dos formatos de `app/test/referencias`: jan e fev fechados (com `resumo` e cópias levadas), um mês retroativo, venda `auto-<meta>`, BDR, mês isento com perda, day trade, várias compras do mesmo ticker e abril aberto com a cópia VALE3 1000 @ 50,00 vendida 500 @ 60,00 em 04-20.
  - `migração de base antiga`: linhas Resumo de jan e fev (13 primeiras células) idênticas às de antes; abril marcado com `posicaoInicial['VALE3'] == {1000, 50015.00}` e apuração com resultado 4983.50, `impSt == 747.525`, `irrf == 1.50`; `config.migracoes == ['2.1-custo-medio']`; backup chamado antes de qualquer gravação (ordem registrada pelo falso).
  - `rodar de novo não muda nada` (JSON de todos os arquivos igual).
  - `backup que falha impede a migração` (nenhum mês marcado, `erro` preenchido).
  - `sem rede usa os dados locais`.
  - `backup_test` (pasta temporária): copia, confere tamanhos, não toca a origem.
- [ ] **Step 2: Rodar e ver falhar:** `flutter test test/nucleo/migracoes_test.dart test/app/plataforma/backup_test.dart` → FAIL.
- [ ] **Step 3: Implementar**; `iniciar` chama a migração depois de `corrigirTiposMes` e antes de devolver o `EstadoInicial`.
- [ ] **Step 4: Rodar:** `flutter test --exclude-tags golden` → PASS; `flutter analyze`.
- [ ] **Step 5: Commit:** `git commit -m "Plano 5, tarefa 15: migração 2.1-custo-medio com backup e teste de base antiga"`.

### Task 16: Prejuízo acumulado inicial em Configurações

**Files:**
- Modify: `app/lib/app/servicos/api.dart`, `app/lib/app/servicos/locais/apuracao_local.dart`, `servicos_locais.dart`, `servicos_isolate.dart`, `app/lib/app/telas/conta/tela_conta.dart`, apoio de testes
- Test: `app/test/app/telas/conta/tela_conta_test.dart`, `app/test/app/servicos/apuracao_local_test.dart`, goldens

**Interfaces:**
- Consumes: `mesDeCorte`, `PrejuizoAcumulado`.
- Produces: `class PrejuizoInicial { final String? mesCorte; final double comum; final double dayTrade; final bool editavel; }`; `Future<PrejuizoInicial> prejuizoInicial()`; `Future<void> definirPrejuizoInicial(double comum, double dayTrade)` (grava `prejuizoAnterior` do mês de corte; `ErroValidacao('O mês de corte já foi fechado; o prejuízo inicial não pode mais ser alterado.')` quando fechado; valores negativos recusados). Texto na tela: `'Prejuízo acumulado antes de MM/AAAA (para compensar no imposto)'`, campos "Operações comuns" e "Day trade".

- [ ] **Step 1: Testes que falham:** `edita enquanto o mês de corte está aberto` (apuração do mês recalculada com a compensação); `fica só leitura depois do fechamento`; `sem corte (antes da migração) o campo não aparece`.
- [ ] **Step 2: Rodar e ver falhar.**
- [ ] **Step 3: Implementar.**
- [ ] **Step 4: Rodar:** `flutter test --exclude-tags golden` → PASS; goldens de Configurações atualizados e inspecionados, **conferência do `conferidor-visual`**; `flutter analyze`.
- [ ] **Step 5: Commit:** `git commit -m "Plano 5, tarefa 16: prejuízo acumulado inicial em Configurações"`.

## Parte D: release

### Task 17: Versão 2.1.0, notas, workflow estável e conferência dos atualizadores

**Files:**
- Modify: `app/lib/versao.dart` (`2.1.0`), `app/test/versao_test.dart` (espera `2.1.0`), `.github/workflows/release.yml`, `app/ci/testar_instalador.ps1`
- Create: `docs/release/2.1.0.md`, `app/test/integracoes/atualizador/atualizador_vivo_test.dart`
- Modify: `app/dart_test.yaml` (tag `vivo`)

**Interfaces:**
- Consumes: `verificarAtualizacao(ClienteHttp, {required String nomeAsset, String versaoAtual})` (`integracoes/atualizador/atualizador.dart`; não existe `interpretar`, o teste usa esta função com o cliente HTTP real) e `atualizador.verificar(nome_asset)` do Python (lê `VERSAO` do módulo `versao`).
- Produces:
  - `release.yml`, passo "Publicar a release": `prerelease: false`, `make_latest: "true"`, `body_path: docs/release/${{ needs.versao.outputs.versao }}.md` (sem `body`), comentários atualizados; job `publicar` ganha `actions/checkout@v4` para ler as notas.
  - Job `conferir-atualizador` (`needs: [versao, publicar]`, mesmo `if:` de tag, `permissions: contents: read`, só `GITHUB_TOKEN` automático): (1) até 10 tentativas, 30 s entre elas, em `https://api.github.com/repos/JoaoGabrielOT/CalculadoraDARF/releases/latest` exigindo `tag_name == versão`, `prerelease == false`, `draft == false`; (2) baixa os artefatos `android` e `windows` e exige os assets `CalculadoraDARF.exe` e `CalculadoraDARF.apk` com `size` igual e `digest == "sha256:" + sha256sum`; (3) `python -c` na raiz com `requests`: `import atualizador; atualizador.VERSAO = "1.12.1"` e exige `verificar("CalculadoraDARF.exe")["versao"] == versão` e o mesmo para `"CalculadoraDARF.apk"`; (4) `flutter test --tags vivo test/integracoes/atualizador/atualizador_vivo_test.dart --dart-define=VERSAO_ESPERADA=<versão>`. Qualquer falha: `::error` e job vermelho; sucesso: `::notice title=Atualizadores::…` com a versão, tamanhos e digests.
  - `atualizador_vivo_test.dart` (tag `vivo`, fora do `flutter test` comum: `dart_test.yaml` ganha `vivo:` e o job `testes` passa a usar `--exclude-tags golden,vivo`): para `CalculadoraDARF.exe` e `.apk`, `verificarAtualizacao(..., versaoAtual: '2.0.0')` devolve `versao == VERSAO_ESPERADA`, `sha256` com 64 hex e `tamanho > 0`.
  - `testar_instalador.ps1`: a pasta `dados/` falsa da 1.12 ganha `2026-10.json` aberto com uma compra; depois da instalação e da abertura do app, exige `backup\pre-2.1.0-*` com os mesmos arquivos e `migracoes` contendo `2.1-custo-medio` no `config.json` do destino.
  - `docs/release/2.1.0.md`: funcionalidades; corte fiscal (`a partir do primeiro mês aberto na atualização, custo médio e compensação de prejuízo; informe o prejuízo acumulado em Configurações`); `atualize todos os aparelhos antes de fechar o próximo mês`; downgrade sem rollback seguro e a recuperação do spec §11 (fechar o app, copiar `backup/pre-2.1.0-*/` de volta para a pasta de dados, reinstalar a versão correspondente).

- [ ] **Step 1: Teste que falha:** `versao_test` esperando `2.1.0` → `flutter test test/versao_test.dart` FAIL.
- [ ] **Step 2: Implementar** versão, notas, workflow, teste vivo e script do instalador. Conferir o YAML: `python -c "import yaml,sys; yaml.safe_load(open('.github/workflows/release.yml', encoding='utf-8'))"` sem erro (se `yaml` não estiver instalado, conferir na página da execução do CI).
- [ ] **Step 3: Rodar local:** `flutter test test/versao_test.dart` → PASS; `flutter test --exclude-tags golden,vivo` → PASS; `flutter analyze`. Sem rede de release ainda, o teste vivo não roda localmente (só no job).
- [ ] **Step 4: Commit:** `git commit -m "Plano 5, tarefa 17: versão 2.1.0, notas e publicação estável com conferência dos atualizadores"`.
- [ ] **Step 5: CI:** pedir o push ao controlador; **`monitor-ci`** confirma `testes`, `android` (versionCode 20100 na anotação), `windows` (teste de integração e instalador com a migração 2.1 e o backup) verdes, `publicar` e `conferir-atualizador` pulados (não é tag).

### Task 18: Verificação final e documento de resultado

**Files:**
- Create: `docs/superpowers/plans/2026-11-08-plano-5-resultado.md`

- [ ] **Step 1: Rodar e anotar as saídas reais:** em `app/`: `flutter analyze`; `flutter test --exclude-tags golden,vivo`; `flutter test --tags golden test/app/goldens`. Na raiz: `python -m unittest discover -s tests`; `git diff main...migracao-flutter --stat -- calculadora_darf.py android/ atualizador.py nucleo.py metas.py sugestoes.py mercado.py noticias.py tests/` → vazio.
- [ ] **Step 2: Revisão dos artigos fiscais no DOU** (spec §10, última limitação): conferir no texto oficial da IN RFB 1.585/2015 os arts. 56 § 4º, 58, 59, 64 e 65 usados; divergência → parar e reportar ao controlador.
- [ ] **Step 3: Escrever `2026-11-08-plano-5-resultado.md`** no formato do resultado do plano 4, separando explicitamente **implementado**, **testado** (com comandos e saídas), **publicado** (nada até a tag) e **pendente**: funcionalidades; arquivos e a migração `2.1-custo-medio`; regras de seleção de compras, indicadores (fórmulas e denominadores) e sugestões (parâmetros); fontes fiscais e técnicas com datas, e o resultado da Tarefa 1 sobre o tick; execução do CI (número, commit, jobs, anotações); limitações e recuperação (§11, §13 do spec); checklist do dono (transição real 1.12 → 2.1 no PC e no celular, prejuízo inicial em Configurações, conferência de uma DARF por custo médio contra a nota de corretagem).
- [ ] **Step 4: Passo exato de publicação** no documento (feito pelo controlador depois da revisão final do `revisor`):
  1. Confirmar CI verde no commit `H` (cabeça de `migracao-flutter` no `origin`).
  2. `git tag -a 2.1.0 -m "Calculadora DARF 2.1.0" H` e `git push origin 2.1.0` (sem force push).
  3. **`monitor-ci`** acompanha a execução da tag até `publicar` e `conferir-atualizador` verdes e lê o `::notice` dos atualizadores.
  4. Conferir que https://github.com/JoaoGabrielOT/CalculadoraDARF/releases/latest redireciona para a 2.1.0, com os dois arquivos.
  5. Se faltar permissão no CI: registrar o bloqueio exato e não afirmar que publicou.
- [ ] **Step 5: Commit:** `git add docs/superpowers/plans/2026-11-08-plano-5-resultado.md` e `git commit -m "Plano 5, tarefa 18: verificação final e resultado da entrega 2.1.0"`.
