# Relatórios e Apuração: análises complementares — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Implementar os itens 1–6 do `prompt.md` (resumo por ativo sem rolagem no celular + resumo dos especialistas, filtros, gráficos, aviso de relatório novo, extremos nas vendas e nos lotes abertos).

**Architecture:** Regras puras em `lib/nucleo/` (filtros, extremos), um método novo em `ServicosApp` (`barrasDiarias`), widgets novos em `lib/app/telas/relatorios/` e `lib/app/componentes/`, e ajustes nas listas da Apuração.

**Tech Stack:** Flutter/Dart, provider, flutter_test, goldens.

**Spec:** `docs/superpowers/specs/2026-11-27-relatorios-apuracao-analises-design.md` (o `prompt.md` do repositório principal vale no resto).

## Global Constraints
- **Não fazer commit nem push.** Ao terminar a task, deixar as mudanças no working tree; o controlador faz `git add` como checkpoint. Não incluir/alterar `app/lib/nucleo/armazenamento_chave_valor.dart` (já modificado, alheio). Se `dart format` mexer em arquivos fora da task, desfazer só a formatação desses arquivos (sem apagar trabalho).
- Sem dependência nova. Dinheiro em `double`. Datas `AAAA-MM-DD`.
- Textos exatos: "Resumo dos especialistas", "Nenhuma análise de especialista disponível para este ativo", "Opiniões divididas", "Nenhum ativo com esses filtros", "Limpar filtros", "Relatório", "Gráficos", "Dados insuficientes para o gráfico", "Tentar de novo", "Melhor possível", "Pior possível", "Maior lucro possível até agora", "Maior perda possível até agora", "Indisponível", "Abrir", "Dispensar".
- Tudo funciona em 360 px de largura sem overflow; tema claro, moderno e terminal.
- Comandos de `app/`: `flutter test <arquivos>`, `flutter test --exclude-tags vivo`, `flutter analyze`; goldens só os afetados, com `--update-goldens --plain-name <nome>`, e conferidos abrindo os PNGs.

## Review Focus
1. Relatório com 0 ativos ou todos filtrados fora → mensagens de vazio, sem exceção — Task 2.
2. Ticker que o Yahoo não conhece (BDR, Fiagro) → gráficos e extremos "Indisponível"/erro tratado, sem travar a lista — Tasks 3, 5.
3. Venda no mês atual → só barras até hoje; venda em mês sem barras → "Indisponível" — Task 5.
4. Primeiro uso do aviso de relatório novo não avisa o que já existe; reabrir o app não repete o aviso — Task 4.
5. Lote com saldo 0 não ganha métricas de "até agora"; lote comprado hoje usa o próprio dia — Task 6.

---

### Task 1: Resumo por ativo no celular + resumo dos especialistas
**Files:** `app/lib/app/telas/relatorios/vista_relatorio.dart` (`_TabelaResumo`); Create `app/lib/app/telas/relatorios/resumo_especialistas.dart`; Test `app/test/app/telas/relatorios/vista_relatorio_test.dart`; goldens `relatorios_*_celular` afetados.
- [ ] Testes: em 360 px (compacto), a seção g não tem `Scrollable` horizontal e cada ativo aparece numa linha empilhada (`linha-resumo-<ticker>`) com ticker, preço, selo e resumo; em PC a tabela atual continua. `secao-resumo-especialistas` abaixo da seção g: item de BPAC11 (fixture guia `relatorio-abertura-2026-11-27-guia.json`) mostra "Maioria compra" e, aberto, as casas com selo, casa, data e motivo; BBDC4 mostra "Opiniões divididas" e as 2 casas; T1TW34 mostra "Nenhuma análise de especialista disponível para este ativo"; fixture 26/11 (sem classificação) funciona pela regra de texto. Sem overflow em 360 px.
- [ ] Implementar conforme spec §1. Reusar `consensoDe`, `votoDoItem`, `dataCurta`, `LinkRelatorio`, `linkSeguro`, selos já existentes.
- [ ] Testes, goldens afetados, `flutter analyze` PASS. Relatório em `task-1-report.md`.

### Task 2: Filtros e pesquisa
**Files:** Create `app/lib/nucleo/relatorios/filtros_relatorio.dart`, `app/lib/app/telas/relatorios/barra_filtros_relatorio.dart`; Modify `vista_relatorio.dart`, `tela_relatorios.dart`/`controle_relatorios.dart` (posições e período); Test `app/test/nucleo/relatorios_filtros_test.dart`, testes de vista e tela.
- **Interfaces:** `class FiltroAtivos { final String texto; final Set<String> tipos; final Set<Leitura> leituras; final bool? comAnalise; final bool soDestaque; final bool soCarteira; bool get vazio; }`; `List<AtivoRelatorio> filtrarAtivos(List<AtivoRelatorio>, FiltroAtivos, {Set<String> carteira = const {}})`; `List<ItemRelatorio> filtrarPorPeriodo(List<ItemRelatorio>, int? dias, String hoje)`.
- [ ] Testes puros: busca "itau" acha ITUB pela empresa com acento; "bpac" pelo ticker; tipo `bdr` na fixture guia só traz BDRs; leituras OU; tipo E leitura; "Com análise" exclui T1TW34; carteira {PETR4} → só PETR4; filtro vazio = lista igual; período 7 dias com hoje 2026-11-27 inclui 2026-11-20 e exclui 2026-11-19.
- [ ] Testes de widget: digitar no campo filtra tabela, especialistas e cartões; "N de M ativos"; "Limpar filtros"; vazio → "Nenhum ativo com esses filtros"; chips de período na lista de anteriores; tudo em 360 px.
- [ ] Implementar (spec §2). Carteira: tickers com `qtd > 0` em `posicoes(mesAtual)`; falha ao carregar → chip "Na minha carteira" oculto.
- [ ] Testes, goldens afetados, analyze PASS.

### Task 3: Serviço `barrasDiarias` e aba Gráficos
**Files:** `app/lib/app/servicos/api.dart` (+ `Future<Diarias> barrasDiarias(String ticker, {String? desde})`), `servicos_locais.dart`, `servicos_isolate.dart`, `servicos_web.dart`, ecos/fakes de teste que implementam `ServicosApp`; Create `app/lib/app/componentes/grafico_barras.dart`, `app/lib/app/telas/relatorios/graficos_ativo.dart`; Modify `cartao_ativo.dart`; Tests de serviço (padrão dos testes de `grafico`), de `GraficoBarras` e do cartão.
- [ ] Testes: serviço local e isolate devolvem as barras do Yahoo falso e usam o cache; cartão começa na aba "Relatório" e **não** chama `barrasDiarias` antes do toque em "Gráficos"; após o toque, chama uma vez e mostra o gráfico de linha; com 1 barra → "Dados insuficientes para o gráfico"; erro → mensagem e "Tentar de novo"; barras de alvo só com `alvoMedio` na mesma moeda (BPAC11 sim; NVDC34 em US$ com preço em US$ sim; EMBJ3 item em US$ não entra porque usa só os campos agregados); posição aberta → barras preço médio × último; `Semantics` com o resumo.
- [ ] Implementar (spec §3).
- [ ] Testes, analyze PASS.

### Task 4: Aviso de relatório novo
**Files:** `relatorios_local.dart` (último avisado), `api.dart`/serviços se precisar expor (ex.: `VisaoRelatorios.novos`), `estado_app.dart`, `casca.dart` (badge), `tela_relatorios.dart` (faixa); Tests correspondentes.
- [ ] Testes: primeira listagem só grava o mais novo como avisado, sem badge; relatório mais novo aparece → badge 1 e faixa com data e "Abrir"/"Dispensar"; "Abrir" abre o relatório e zera; "Dispensar" zera; recriar serviço/estado com o mesmo armazenamento → sem novo aviso; dois novos → badge 2 e a faixa cita o mais recente.
- [ ] Implementar (spec §4).
- [ ] Testes, goldens afetados (casca), analyze PASS.

### Task 5: Extremos nas Vendas do mês
**Files:** Create `app/lib/nucleo/extremos.dart`; Modify `controle_apuracao.dart`, `lista_vendas.dart`; Tests `app/test/nucleo/extremos_test.dart`, testes de lista de vendas.
- **Interfaces:** `class Extremo { final double preco; final String data; }`; `class Extremos { final Extremo maximo, minimo; }`; `Extremos? extremosDe(List<BarraDiaria> barras, String desde, String ate)`; `double resultadoHipotetico(Lote lote, int qtd, Extremo e)` = `calcularVendaQtd(lote, qtd, e.preco, e.data).liquido`.
- [ ] Testes puros: máx das altas e mín das baixas só dentro de [desde, ate]; barras fora ignoradas; lista vazia ou sem barra no intervalo → null; resultado igual a `calcularVendaQtd(...).liquido` (lucro e prejuízo); day trade quando a data do extremo = data de compra.
- [ ] Testes de widget: venda de PETR4 com barras falsas mostra "Melhor possível" e "Pior possível" formatados com sinal como a coluna Resultado e a referência "máx R$ … (dd/mm) · mín R$ … (dd/mm)"; sem barras → "Indisponível"; mês atual usa só até hoje; compacto em 360 px.
- [ ] Implementar (spec §5): uma busca de barras por ticker e mês, cacheada no controle; erros → "Indisponível".
- [ ] Testes, goldens afetados, analyze PASS.

### Task 6: Extremos nos Ativos comprados (lotes abertos)
**Files:** `lista_lotes.dart`, `controle_apuracao.dart`; Tests de lista de lotes.
- [ ] Testes: lote com saldo > 0 mostra "Maior lucro possível até agora" e "Maior perda possível até agora" (barras desde `dataCompra` até hoje, saldo restante, preço do lote, `resultadoHipotetico`); lote com saldo 0 não mostra; sem barras → "Indisponível"; compra hoje usa o próprio dia; 360 px sem overflow.
- [ ] Implementar (spec §6), reaproveitando o carregamento da Task 5.
- [ ] Suíte inteira `flutter test --exclude-tags vivo`, analyze PASS.

### Task 7: Compartilhar a pasta de relatórios com os amigos
**Files:** Create `app/lib/integracoes/google/compartilhamento.dart`; Modify `app/lib/integracoes/google/constantes.dart` (+ `escopoDrive`), `login.dart`, `login_web.dart`, `web_servidor/api/auth/inicio.js` (+ testes JS existentes), `app/lib/app/servicos/api.dart`, `servicos_locais.dart`/`locais/conta_local.dart`, `servicos_isolate.dart`, `servicos_web.dart`, ecos de teste, `app/lib/app/telas/amigos/tela_amigos.dart`; Tests: integração com cliente HTTP falso, serviço, tela de amigos, `web_servidor` (node --test).
- [ ] Testes: `canShare` false → estado "não dono", nada aparece na tela; dono sem escopo → aviso com "Permitir"; dono com escopo → lista permissões (2 páginas) e cria só para quem falta, com `sendNotificationEmail=false`, `role=reader`, `type=user`; e-mail já com papel (maiúsculas diferentes) não é recriado; adicionar amigo com sucesso no compartilhamento → amigo salvo + mensagem; falha (403) → amigo salvo + aviso de não compartilhado; e-mail inválido no meio de 3 → os outros 2 compartilhados e o inválido listado; `inicio.js` com `extra=drive` inclui o escopo e com outro valor ignora; login pedindo o extra exige a mesma conta (regra da 2.7.0).
- [ ] Implementar (spec §7).
- [ ] Testes Dart e `node --test` em `web_servidor`, analyze PASS.
