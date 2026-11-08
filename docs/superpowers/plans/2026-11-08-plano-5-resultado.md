# Plano 5 (entrega 2.1 a 2.4): resultado, checklist do dono e passos da publicação da 2.4.0

Concluído em 08/11/2026 na branch `migracao-flutter` (cabeça `d4382a7`, já no `origin`). Spec: `docs/superpowers/specs/2026-11-08-entrega-2-1-design.md`. O registro tarefa a tarefa está em `.superpowers/sdd/2026-11-08-plano-5-entrega-2-1/` (local).

A entrega saiu em releases incrementais estáveis (pedido do dono, 08/11), não numa 2.1.0 única:

| Versão | Conteúdo | Commit da tag | Situação |
|---|---|---|---|
| 2.1.0 | posições na apuração e indicadores por ativo (T1-T4) e a infraestrutura de publicação estável (R1) | `d8ac884` | publicada, Latest na época |
| 2.2.0 | sugestões de saída (T5-T6) | `5e9b87a` | publicada |
| 2.3.0 | venda por quantidade (T7-T10) | `bf8c4cb` | tag existe; o build falhou no download do Gradle (incidente do GitHub); **sem release** |
| 2.3.1 | o mesmo conteúdo da 2.3.0, com cache e 3 tentativas no download do Gradle | `f747f35` (commit sobre `bf8c4cb`, só a tag foi ao origin) | publicada, **Latest** (exe 12853932 bytes, sha256 `e1abe78a…`; apk 44137536 bytes, sha256 `2e0a17f1…`; versionCode 20301) |
| 2.4.0 | imposto pela regra da Receita: custo médio, day trade por ativo, isenção só para ações, compensação de prejuízo (T11-T16) e correções da revisão final | `d4382a7` | **pendente: a publicar** (Step "Publicação da 2.4.0") |

## Implementado

- **2.1.0:** tick da B3 (`tickDe`, `pisoTick`, `tetoTick`); reconstrução de posições por cadeia de compra (`nucleo/posicoes.dart`, função pura, roda no isolate de serviços); seletor "Posição em dd/mm/aaaa" e "Carteira atual" na apuração, no PC e no Android, com selo de fonte e horário da cotação; indicadores por ativo (`nucleo/indicadores_ativo.dart`, painel de indicadores).
- **2.2.0:** sugestões de saída (aba Sugestões de Metas): ponto de equilíbrio, meta financeira, cenário de mercado swing e day trade, liquidez, consolidado por ativo, filtros e ordenação.
- **2.3.1 (2.3.0):** venda por quantidade com alocação por menor custo (`nucleo/alocacao.dart`), prévia da venda com resumo financeiro e aviso quando a seleção usa quantidade reservada por metas, grupos de venda editáveis, caixa e lista de vendas agrupadas.
- **2.4.0:** motor fiscal por custo médio (`nucleo/apuracao_medio.dart`), marcador de método/mês de corte/posição inicial/prejuízo anterior no JSON do mês e na coluna 14 da aba Resumo, mesclagem monotônica do marcador, fechamento que leva posição e prejuízo ao mês seguinte, migração `2.1-custo-medio` (`nucleo/migracoes.dart`) com backup `backup/pre-2.4.0-*`, e o campo "Prejuízo acumulado inicial" em Configurações.
- **Infraestrutura de release (R1, R3, T17):** o passo `publicar` do `release.yml` cria release estável (`prerelease: false`, `make_latest: "true"`) com `body_path` em `docs/release/<versão>.md`; o job `conferir-atualizador` confere `/releases/latest`, os dois assets (tamanho e sha256) e roda o atualizador Python 1.12 e o do Flutter contra o JSON vivo; cache e repetição do download do Gradle no job `android` (trazidos do `f747f35`); conferência do versionCode `>` só em tag e `>=` com aviso em push; teste do instalador estendido com `dados/` da 1.12, migração e backup.
- **Migração `2.1-custo-medio`:** o id ficou com esse nome, embora a migração só tenha sido publicada na 2.4.0 (o id nunca é editado depois de publicado). Backup antes de qualquer mudança; escolhe o mês de corte; grava marcador, posição inicial e prejuízo zerado; não reescreve lotes, vendas, `resumo` nem meses fechados.
- **Arquivos:** 39 arquivos de `app/lib` mudaram desde `bf8c4cb` (+1679/-58 linhas), entre eles os de `nucleo/` acima, `nucleo/planilha/{abas,mesclagem,montagem,reconstrucao}.dart`, `nucleo/fechamento.dart`, `nucleo/caixa.dart`, `nucleo/modelos/{mes,config}.dart`, `app/telas/formularios/*`, `app/telas/apuracao/*`, `app/telas/conta/tela_conta.dart` e `integracoes/sincronizacao/sincronizador.dart`. O Python (`calculadora_darf.py`, `android/`, `atualizador.py`, `nucleo.py` e demais) não mudou.

### Regras de seleção de compras (venda por quantidade)
- Ordem por menor custo (pedido do dono). Quantidade reservada por metas é consumida só com aviso na prévia, sem bloquear.
- Venda que cobre mais de um lote vira um grupo (`grupo.k`, ids texto, lidos sem erro pelas versões antigas); venda de quantidade 0 é recusada.
- Em mês por custo médio, a venda retroativa em meses a partir do corte é recusada ("Meses apurados por custo médio não aceitam venda retroativa.").

### Indicadores (spec §8)
- Preço médio aplicável ao saldo = custo remanescente / Q; preço médio das vendas = Σ(q·p) / Σq; ganho por unidade = resultado realizado do mês / Σq vendida; **rentabilidade realizada = resultado realizado do mês / custo fiscal das unidades vendidas** (nunca média simples de percentuais); resultado não realizado = Q × cotação − custo remanescente; exposição = valor do ativo / Σ valor da carteira; ponto de equilíbrio = `teto_tick((custo/Q + corretagem/Q) / (1 − taxaB3Swing))`.
- Divisão por zero ou dado ausente mostra "—", nunca zero.

### Sugestões (spec §9, parâmetros)
`atrPeriodo = 14`, `janelaSr = 20`, `multStop = 2`, `rrMinimo = 1.5`, `limiteLiquidez = 0.05` (fração do volume financeiro médio de 20 pregões). Swing: exige 21 pregões fechados, alvo na resistência de 20 pregões (ou `P + 2·ATR14`), stop `max(P − 2·ATR14, Chandelier(22, 3))`, oportunidade só com R/R ≥ 1,5 e alvo acima do ponto de equilíbrio. Day trade: pivôs do pregão anterior, só com cotação atual. A meta financeira é o lucro desejado **líquido de IR**, como na Calculadora de metas (decisão do controlador na T5; spec e plano foram corrigidos). Sem probabilidade de acerto, sem VWAP, sem spread.

## Testado

Saídas de 08/11/2026 no commit `d4382a7`, árvore limpa, nesta máquina (Windows 11), executadas pelo agente `terminal`:

| Comando | Saída |
|---|---|
| `flutter analyze` (em `app/`) | `No issues found!` (4,4 s) |
| `flutter test --exclude-tags golden,vivo` (em `app/`) | `All tests passed!`: 29390 passaram, 0 puladas, 0 falhas (1 min 03,7 s) |
| `flutter test --tags golden test/app/goldens` (em `app/`) | `All tests passed!`: 64 passaram, 0 puladas, 0 falhas (21,8 s) |
| `python -m unittest discover -s tests` (raiz) | `Ran 147 tests ... OK` (Python intacto) |
| `git diff main...migracao-flutter --stat -- calculadora_darf.py android/ atualizador.py nucleo.py metas.py sugestoes.py mercado.py noticias.py tests/` | vazio |

- Testes `vivo` (rede real) não rodaram aqui por desenho.
- Windows e Android não compilam localmente nesta máquina (Modo Desenvolvedor negado); build, instalador e APK são verificados só pelo CI.
- CI de `d4382a7` na branch: execução 42490755125 (https://github.com/JoaoGabrielOT/CalculadoraDARF/actions/runs/42490755125), conclusão Success. A execução anterior, 42489279895 (`d86e861`), confirmou: migração `2.1-custo-medio` registrada e backup `pre-2.4.0-…` com os mesmos arquivos; versionCode 20400 > 20301. Detalhe de jobs e anotações da 42490755125: conforme a página pública (sem `gh` e sem login nesta máquina).
- **Revisão final** (opus, faixa `bf8c4cb..d86e861`, 2.4.0 = T11-T17): veredito "With fixes", 2 Important (marcador velho na coluna 14 aceito depois de a 1.12 fechar o mês pelo método antigo; venda retroativa que zera o ticker some com a chave e a mesclagem a ressuscita) e minors 3-6. Correções em `d4382a7`; re-revisão "ready to tag": I1, I2, M3, M4/M5 e M6 resolvidos. Restou um minor: `numOuPadrao` aceita "mod" em texto, sem efeito. Declinado pelo revisor: prejuízo comum abatendo day trade (a separação estrita é decisão do dono, conservadora).

### Fontes fiscais e técnicas (consultadas em 08/11/2026)

**IN RFB 1.585/2015.** Os artigos foram lidos no espelho https://www.normaslegais.com.br/legislacao/instrucao-normativa-1585-2015.htm. A página oficial da Receita (https://normas.receita.fazenda.gov.br/sijut2consulta/link.action?idAto=67494&visao=original, IN RFB nº 1585/2015, DOU 02/09/2015, seção 1, p. 37) só entrega uma página em JavaScript (Angular) e o texto não pôde ser lido por download nem por WebFetch; o DOU (`in.gov.br`) deu "socket hang up". A conferência no texto oficial **não foi feita**: ficou pendente para o dono (ver checklist). Conferido no espelho (texto original da norma; o espelho não indica alterações posteriores):
- art. 56 § 4º: "mais de uma operação no mesmo dia ... os custos e despesas totais ... poderão ser rateados entre as operações executadas, **proporcionalmente ao valor financeiro** de cada operação". O spec (§5.2) rateia a corretagem **por quantidade** entre day trade e comum dentro da mesma ordem; com preço único da ordem é equivalente, e a corretagem é zero em produção. Anotado, sem efeito hoje.
- art. 58: ganho líquido = diferença positiva entre o valor de alienação e o custo de aquisição "calculado pela média ponderada dos custos unitários" (mercado à vista). Confere.
- art. 59, I: isenção de ações no mercado à vista se o total das alienações do mês não exceder R$ 20.000,00; § 1º dispensa declarar as isentas, exceto para compensar perdas; § 2º, I: não vale para day trade. Confere (BDR fora da isenção: o inciso I fala só em ações).
- art. 64 e parágrafo único: perdas compensáveis no mês e nos seguintes, inclusive em anos seguintes; perdas de day trade só com ganhos da mesma espécie; as perdas comuns não abatem day trade. Confere.
- art. 65: § 1º (day trade: mesmo dia, mesmo ativo, mesma instituição, quantidade liquidada total ou parcialmente), § 2º (estoque anterior desconsiderado), § 3º (ordem: primeira compra com primeira venda), § 10 (perda de day trade só com day trade do mês), § 11 (positivo a 20%; negativo compensável nos meses seguintes) e § 15 (limite de isenção do art. 59 não se aplica a day trade). Confere. O § 3º trata a ordem dos negócios; o app usa o preço médio do dia (decisão D9, limitação aceita).
- Lei 11.033/2004, art. 3º, I; Receita Federal, páginas "Compensações" e "Isenções" (URLs na §10 do spec).

**Tick da B3 (Tarefa 1).** O documento "Variações Mínimas de Apregoação" de Nov/2021 foi lido: ações (vista e fração), units, BDRs patrocinados e não patrocinados e BDR de ETF têm tick único de R$ 0,01, sem faixas. O documento de 13/10/2026 listado na página de regras só traz derivativos e não repete a tabela do mercado à vista. Conclusão: R$ 0,01 (premissa D15 confirmada pela versão de 2021; a de 2026 não a contradiz). Detalhe e links em `app/lib/nucleo/tick.dart`.

**Estratégias de saída (StockCharts ChartSchool):** ATR (Wilder, 14), Chandelier Exit (22, 3), Pivot Points e VWAP (fora, por exigir intradiário com volume); URLs na §10 do spec.

## Publicado

- 2.1.0, 2.2.0 e 2.3.1 estão publicadas como releases estáveis (detectadas pelo atualizador Python 1.12 e pelo do Flutter na conferência do CI; execuções 42445754739, 42448924589 e 42469694908). A 2.3.1 é a Latest hoje.
- A tag 2.3.0 existe sem release. O build falhou duas vezes no download do Gradle 9.3.1 (incidente do GitHub, "Increase in timeouts for some unauthenticated users", resolvido em 08/11 12:32 UTC); a tag não pôde ser reenviada. A 2.3.1 saiu de um commit novo sobre `bf8c4cb`, com a tentativa repetida; o dono reexecutou os jobs que falharam.
- **A 2.4.0 não está publicada.** Nenhuma tag 2.4.0 foi criada neste plano.

## Pendente

1. Publicar a 2.4.0 (passo exato abaixo, feito pelo controlador).
2. Conferir os artigos da IN RFB 1.585/2015 no texto oficial (Receita ou DOU), que não pôde ser lido por download; no espelho tudo confere.
3. Checklist do dono (abaixo).
4. Fora do escopo, registrado: prejuízo editado em A volta a 0 se B alterar o mês de corte antes de sincronizar (last-writer-wins por mês); o campo de prejuízo só aparece depois da primeira gravação numa instalação nova; primeira sessão de instalação nova usa o método antigo (nas notas); filtros empilhados no PC e "100% no alvo" quebrando linha no celular (minors visuais da T6); proposta separada: ajuste manual de posição ou prejuízo com trilha de auditoria e VWAP com barras de 5 min.

## Limitações e recuperação (spec §11, §13)

- Venda retroativa em meses por custo médio é bloqueada (D11). Prejuízo inicial só editável com o mês de corte aberto (D4). Day trade pelo preço médio do dia (D9). Sem horário dos negócios, sem livro de ofertas e sem VWAP. Corretora única, taxas B3 constantes (`taxaB3Swing` 0,03%, `taxaB3Daytrade` 0,023%), corretagem zero em produção, preços do Yahoo sem ajuste por proventos. Bruto da linha usa o preço médio do dia numa venda com preços diferentes (nas notas).
- Aparelhos 1.12 e 2.0 que gravarem depois da migração recalculam a aba Resumo pelo método antigo; o marcador é monotônico e a 2.4.0 recompõe tudo na próxima gravação. Nas notas: atualizar todos os aparelhos antes de fechar o próximo mês.
- **Sem rollback seguro.** O instalador Windows recusa rebaixar e o Android exige desinstalar (perde os dados locais). Recuperação: fechar o app, copiar os arquivos de `backup/pre-2.4.0-*/` de volta para a pasta de dados e reinstalar a versão anterior (Windows); no Android o backup fica na pasta privada e some ao desinstalar, mas os dados voltam da planilha depois do login. O backup é único por versão, feito na primeira abertura da 2.4.0 com dados.

## Checklist do teste do dono

- PC, transição real 1.12.x para a versão atual (2.3.1 ou 2.4.0): na pasta do exe antigo (com `dados/` real), deixar o app atualizar. Esperado: o app abre com os meses, radar, metas, amigos e o login do Google; o backup `backup/pre-2.4.0-*` existe; a pasta antiga continua intacta.
- Celular, transição real: instalar o APK por cima do app anterior sem desinstalar; os dados aparecem (migrados ou da planilha depois do login).
- **Prejuízo inicial:** em Configurações, informar o prejuízo acumulado comum e de day trade do mês anterior ao corte, com o mês de corte ainda aberto; conferir que depois de fechar o mês o campo trava.
- **Uma DARF por custo médio:** pegar uma venda real do mês de corte e conferir o custo médio, o resultado, a isenção, a compensação e o imposto contra a nota de corretagem e o programa da Receita (ou o cálculo à mão); conferir também a linha "Misto" quando houver day trade parcial.
- Conferir a posição atual e os indicadores contra a custódia da corretora (quantidade e preço médio).
- Venda por quantidade: vender parte de dois lotes e conferir a prévia, o aviso de meta reservada e a linha agrupada na lista e no caixa.
- Sugestões: conferir um ativo real (ponto de equilíbrio, alvo, stop, R/R, aviso de liquidez) e que a falta de cotação mostra "indisponível" sem quebrar a tela.
- Planilha real: a coluna 14 oculta aparece na aba Resumo depois da primeira sincronização da 2.4.0 e o app Python de um amigo continua lendo os dados.
- Conferir os artigos 56 § 4º, 58, 59, 64 e 65 da IN RFB 1.585/2015 no texto oficial, se quiser fechar a pendência 2.

## Publicação da 2.4.0 (feita pelo controlador; pendente)

1. Confirmar CI verde no commit `H = d4382a7` (cabeça de `migracao-flutter` no `origin`): execução 42490755125, Success.
2. `git tag -a 2.4.0 -m "Calculadora DARF 2.4.0" d4382a7` e `git push origin 2.4.0` (sem force push; a tag não foi criada neste plano).
3. **`monitor-ci`** acompanha a execução da tag até `publicar` e `conferir-atualizador` verdes e lê o `::notice` dos atualizadores. Se o job `android` falhar no download do Gradle de novo, reexecutar os jobs que falharam (a tentativa repetida já está no workflow).
4. Conferir que https://github.com/JoaoGabrielOT/CalculadoraDARF/releases/latest redireciona para a 2.4.0, com `CalculadoraDARF.exe` e `CalculadoraDARF.apk`, e que o corpo traz `docs/release/2.4.0.md`.
5. Se faltar permissão no CI: registrar o bloqueio exato e não afirmar que publicou.
