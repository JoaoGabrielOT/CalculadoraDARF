# Relatórios: ordem por leitura e destaques — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ativos da aba Relatórios em ordem positiva → mista → neutra → negativa, com os de "leitura positiva + consenso de compra" em destaque.

**Architecture:** Campos novos tolerantes no modelo (`relatorio.dart`), regras puras em `lib/nucleo/relatorios/destaques.dart`, e a vista (`vista_relatorio.dart`, `cartao_ativo.dart`) passa a usar a lista ordenada, a seção "Sinais mais favoráveis" e os selos.

**Tech Stack:** Flutter/Dart (app/), flutter_test, goldens.

**Spec:** `docs/superpowers/specs/2026-11-26-relatorios-destaques-design.md` (vale por inteiro; o `prompt.md` do repositório principal vale no resto).

## Global Constraints
- Paleta fixa do relatório (`PaletaRelatorio`), legível nos 3 temas (claro, moderno, terminal).
- Texto nunca diz "vai subir"; nota fixa: "Leitura positiva e especialistas indicando compra. Não é previsão nem recomendação."
- Modelo tolerante: campo ausente/tipo errado → null; nada lança exceção por campo novo.
- Fixtures: `../tests/fixtures/relatorio-abertura-2026-11-26.json` e `../tests/fixtures/relatorio-abertura-2026-11-27.json` (a partir de `app/`).
- Comandos de `app/`: `flutter test`, `flutter analyze`; goldens com `--update-goldens` só nos testes de relatórios e conferidos depois.

## Review Focus
1. Relatório antigo (26/11) sem `consenso`/`placar`/`classificacao`: destaques saem pelos textos de `recomendacao` (RENT3 1/1 antes de BPAC11 37/18/19) — teste no Task 1.
2. `placar` com valores não inteiros, negativos ou chaves faltando: vira null e cai para a contagem pelos itens — teste no Task 1.
3. `consenso` com valor desconhecido ("forte compra"): ignorado, segue para placar — teste no Task 1.
4. Nenhum destaque no relatório: a seção "Sinais mais favoráveis" não aparece — teste no Task 2.
5. Ticker repetido ou ativo sem preço na seção de destaques: sem chave duplicada, preço "—" — teste no Task 2.

---

### Task 1: Modelo e regras de destaque

**Files:**
- Modify: `app/lib/nucleo/relatorios/relatorio.dart` (`ItemEspecialista`, `Especialistas`)
- Create: `app/lib/nucleo/relatorios/destaques.dart`
- Test: `app/test/nucleo/relatorio_test.dart`, `app/test/nucleo/relatorios_destaques_test.dart`
- Test support: `app/test/nucleo/apoio/fixture_relatorio.dart` (acrescentar `fixtureRelatorio27()` lendo a fixture de 27/11)

**Interfaces:**
- Produces (modelo): `ItemEspecialista.classificacao: String?`, `ItemEspecialista.potencial: String?`; `Especialistas.consenso: String?` (texto cru, minúsculas e sem espaços nas pontas), `Especialistas.placar: Placar?`.
- Produces: `class Placar { final int compra, neutra, venda; int get total; }` (em `relatorio.dart`; `deJson` só aceita mapa com as 3 chaves inteiras ≥ 0, senão null; igualdade por valor).
- Produces (`destaques.dart`): `enum Consenso { compra, neutra, venda, dividido, semDados }`; `Consenso consensoDe(Especialistas e)`; `Placar placarDe(Especialistas e)`; `bool emDestaque(AtivoRelatorio a)`; `List<AtivoRelatorio> ordenarParaExibicao(List<AtivoRelatorio> ativos)`.

- [ ] **Step 1: Testes que falham**
  - `relatorio_test.dart`: com a fixture de 27/11, `BPAC11` tem `consenso == 'compra'`, `placar == Placar(compra: 2, neutra: 1, venda: 0)`, `itens[0].classificacao == 'compra'`; `LREN3.itens[0].potencial == '+39,7% até o alvo, com o preço de 26/11'`; placar `{"compra": 1.5, "neutra": 0, "venda": 0}`, `{"compra": -1, ...}` e `{"compra": 1}` → `placar == null`; fixture de 26/11 → `consenso == null`, `placar == null`.
  - `relatorios_destaques_test.dart`:
    - `consensoDe`: `consenso: "compra"` → compra; `"sem_dados"` → semDados; `"forte compra"` com placar 0/2/0 → neutra; sem consenso, placar 2/2/0 → dividido; sem consenso e placar, itens com classificação compra, compra, sem_classificacao → compra; só textos: "Compra" → compra, "Outperform" → compra, "Top Picks" → compra, "market perform" → neutra, "Underweight" → venda, "alvos elevados; só um indica compra" → não conta (resultado semDados), "37 compra / 18 manutenção / 19 venda" → compra.
    - `placarDe`: o do JSON quando existe; senão o contado (2 "Compra" + 1 "Neutra" → 2/1/0).
    - `emDestaque` + `ordenarParaExibicao` na fixture de 26/11: destaques `{BPAC11, RENT3}`; ordem completa `RENT3, BPAC11, T1TW34, VBBR3, BBDC4, CMIG4, PRIO3, PETR4, EMBJ3, VALE3, GOGL34, MGLU3, MBRF3, TIMS3, TAEE11, CPFE3, RURA11, CSNA3, BBAS3, LREN3, WEGE3, HAPV3`.
    - Fixture de 27/11: destaques `{EMBJ3, PRIO3}` (não WEGE3, LREN3, TIMS3); as 5 primeiras são `EMBJ3, PRIO3, TAEE11, VBBR3, TIMS3`; as 5 últimas `CSNA3, BBAS3, LREN3, VALE3, NVDC34`.
    - Desempate entre destaques: positiva 3/4 compra na posição 0 e positiva 2/2 na posição 1 → a 2/2 vem antes (fração maior); positiva 2/2 na posição 0 e positiva 4/4 na posição 1 → a 4/4 vem antes (mesma fração, mais casas); duas 2/2 → vale a posição.
- [ ] **Step 2:** `flutter test test/nucleo/relatorio_test.dart test/nucleo/relatorios_destaques_test.dart` — FAIL (campos/arquivo inexistentes).
- [ ] **Step 3:** Implementar conforme a seção "Regras" da spec. Reconhecimento por texto: minúsculas, `trim`, começa com o termo seguido de fim ou caractere não-letra. Consenso no formato "N compra / M manutenção / K venda": regex de números antes das palavras. Ordenação com `ordenadoCom` (estável) de `lib/nucleo/compat/ordenacao.dart`.
- [ ] **Step 4:** Mesmo comando — PASS; `flutter analyze` sem avisos novos.
- [ ] **Step 5:** Commit "Relatórios: consenso, placar e regras de destaque".

### Task 2: Tela — ordem, seção de destaques, selos e placar

**Files:**
- Modify: `app/lib/app/telas/relatorios/vista_relatorio.dart`, `app/lib/app/telas/relatorios/cartao_ativo.dart`, `app/lib/app/telas/relatorios/paleta_relatorio.dart` (se precisar de um widget de selo reutilizável)
- Test: `app/test/app/telas/relatorios/vista_relatorio_test.dart`; goldens `relatorios_*` em `app/test/app/goldens/`

**Interfaces:**
- Consumes: `emDestaque`, `ordenarParaExibicao`, `placarDe`, `Placar` do Task 1.
- Keys: seção `Key('secao-destaques')`; linha `Key('destaque-<ticker>')`; selo no cartão `Key('selo-destaque-<ticker>')`; ★ na tabela `Key('estrela-tabela-<ticker>')`; placar no cartão `Key('placar-<ticker>')`. Com ticker repetido, a chave fica num invólucro sem chave (mesmo padrão de `_SeloTermometro`).

- [ ] **Step 1: Testes que falham** (`vista_relatorio_test.dart`, fixture de 27/11 salvo indicação):
  - Seção `secao-destaques` existe, título "Sinais mais favoráveis", contém `destaque-EMBJ3` antes de `destaque-PRIO3`, e o texto "Leitura positiva e especialistas indicando compra. Não é previsão nem recomendação."; fica abaixo de `secao-f` e acima de `secao-g` (posição vertical).
  - Sem destaque (todos os ativos com leitura negativa): `secao-destaques` ausente.
  - Cartões: `cartao-EMBJ3` acima de `cartao-TAEE11`, que fica acima de `cartao-T1TW34` (mista), e `cartao-NVDC34` é o último; `selo-destaque-EMBJ3` existe com texto "★ Destaque"; `selo-destaque-WEGE3` não existe.
  - Tabela: `estrela-tabela-PRIO3` existe; `estrela-tabela-RENT3` não (mista em 27/11).
  - Placar: `placar-GOGL34` mostra "3 compra", "1 neutra", "0 venda"; `placar-RURA11` ausente (placar 0/0/0). Potencial: o cartão de `LREN3` mostra "+79,6% até o alvo, com o preço de 26/11".
  - Fixture de 26/11: destaques RENT3 e BPAC11, nessa ordem; sem placar do JSON, o placar contado aparece (`placar-RENT3` mostra "1 compra").
  - Ativo em destaque sem preço: linha da seção mostra "—"; dois ativos com o mesmo ticker em destaque não quebram (sem exceção).
- [ ] **Step 2:** `flutter test test/app/telas/relatorios/vista_relatorio_test.dart` — FAIL.
- [ ] **Step 3:** Implementar conforme a seção "Tela" da spec: lista ordenada calculada uma vez no `build` e usada por termômetro, tabela e cartões; linha da tabela em destaque com fundo `PaletaRelatorio.positivaTexto` a 12% de opacidade; borda verde de 2 px no cartão em destaque; selos do placar com as cores de positiva/neutra/negativa da paleta.
- [ ] **Step 4:** Mesmo comando — PASS. Atualizar só os goldens de relatórios (`flutter test --update-goldens test/app/goldens/telas_golden_test.dart --plain-name relatorios` ou equivalente) e rodar a suíte inteira `flutter test` + `flutter analyze` — PASS.
- [ ] **Step 5:** Commit "Relatórios: ordem por leitura, destaques e placar dos especialistas".

### Task 3: Versão 2.8.0 e notas (controlador)

**Files:** `app/lib/versao.dart`, `docs/release/2.8.0.md`, testes/goldens que mostram a versão.
- [ ] Trocar para 2.8.0, escrever as notas (ordem nova, destaques e critério, placar/potencial, CI), rodar `flutter test`, commit, push da branch, CI verde, tag `2.8.0`.
