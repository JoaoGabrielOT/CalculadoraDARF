# Relatórios: especialistas para leigos — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Mostrar guiaLeigo, comparação preço × alvo, sub-cartões por casa e a explicação de preço-alvo, sem mudar relatórios antigos.

**Architecture:** Campos tolerantes em `relatorio.dart`; widgets novos num arquivo `app/lib/app/telas/relatorios/especialistas_ativo.dart` usado por `cartao_ativo.dart`; caixa do topo em `vista_relatorio.dart`.

**Tech Stack:** Flutter/Dart, flutter_test, goldens.

**Spec:** `docs/superpowers/specs/2026-11-27-relatorios-especialistas-guia-design.md`

## Global Constraints
- Texto literal do topo: "Preço-alvo é quanto a casa acha que a ação vai valer no prazo indicado (em geral 12 meses). Não é preço para comprar nem para vender."
- Rótulos: "Último preço", "Alvo médio", "Faixa dos alvos: ", "Motivo: ", selos "Compra" / "Manter" / "Venda" / "Sem classificação".
- Relatório sem os campos novos: cartão igual ao da 2.8.0 (goldens `relatorios_cartao_*` e `relatorios_destaques_*` não mudam).
- Fixtures a partir de `app/`: `../tests/fixtures/relatorio-abertura-2026-11-27-guia.json` (com os campos); 26/11 e 27/11 (sem).

## Review Focus
1. `precoAlvoValor` texto, NaN ou infinito → null, sem exceção — Task 1.
2. `fraseGuia` sem "Motivo:" ou com motivo diferente → frase inteira, motivo à parte — Task 1.
3. Item só com `motivo` (sem `fraseGuia`) → sub-cartão com o motivo e sem frase — Task 1.
4. `alvoMin` sem `alvoMax` → sem linha de faixa — Task 1.
5. URL insegura (`javascript:`) no item → sem link — Task 1.

---

### Task 1: Modelo, cartão e topo

**Files:** Modify `app/lib/nucleo/relatorios/relatorio.dart`, `app/lib/app/telas/relatorios/cartao_ativo.dart`, `app/lib/app/telas/relatorios/vista_relatorio.dart`; Create `app/lib/app/telas/relatorios/especialistas_ativo.dart`; Test `app/test/nucleo/relatorio_test.dart`, `app/test/app/telas/relatorios/vista_relatorio_test.dart`, `app/test/nucleo/apoio/fixture_relatorio.dart` (+ `fixtureRelatorioGuia()`); goldens novos `relatorios_guia_{claro,terminal}_{celular,pc}.png` (cartão do BPAC11 à vista).

**Interfaces:** Produces `Especialistas.{precoReferencia, alvoMedio, alvoMin, alvoMax, potencialMedio, guiaLeigo}: String?`; `ItemEspecialista.{precoAlvoValor: double?, moedaAlvo, prazoAlvo, motivo, fraseGuia: String?}`; `String fraseSemMotivo(String frase, String? motivo)` (pura, em `lib/nucleo/relatorios/`); `bool temGuia(Relatorio r)` (algum ativo com guiaLeigo, alvoMedio ou item com fraseGuia/motivo).

- [ ] **Step 1: testes que falham**
  - Modelo (fixture guia): BPAC11 `precoReferencia == 'R$ 56,90 em 26/11'`, `alvoMedio == 'R$ 67,67'`, `alvoMin == 'R$ 60,00'`, `alvoMax == 'R$ 72,00'`, `potencialMedio == '+18,9%'`, `guiaLeigo` começa com "2 de 3 casas indicam COMPRAR"; TAEE11 `itens[1].precoAlvoValor == 43.5`, `moedaAlvo == 'BRL'`, `prazoAlvo == 'fim de 2027'`; `precoAlvoValor: "43,5"` → null; fixture 26/11 → todos null; `temGuia` true na guia, false em 26/11 e 27/11.
  - `fraseSemMotivo('O X indica MANTER. Motivo: acha caro.', 'Acha caro.') == 'O X indica MANTER.'`; motivo diferente → frase inteira; motivo null → frase inteira.
  - Vista (fixture guia): `explicacao-preco-alvo` com o texto literal, abaixo do cabeçalho e acima de `secao-f`; `guia-BPAC11` com o guiaLeigo; `comparacao-BPAC11` mostra "Último preço", "R$ 56,90 em 26/11", "Alvo médio", "R$ 67,67", "+18,9%", "Faixa dos alvos: R$ 60,00 a R$ 72,00"; `comparacao-TAEE11` mostra "Faixa dos alvos: R$ 43,50"; `comparacao-CSNA3` ausente (sem alvo médio) e `guia-CSNA3` presente; `casa-BPAC11-0` mostra o selo "Compra", "Safra" e "Motivo: Mantém a visão positiva, embora tenha achado as despesas do trimestre um pouco negativas.", e "Motivo:" aparece uma vez só nesse sub-cartão; `placar-BPAC11` continua.
  - Vista sem os campos (fixtures 26/11 e 27/11): `explicacao-preco-alvo`, `guia-*`, `comparacao-*` e `casa-*` ausentes; as asserções já existentes passam sem mudança.
  - Review Focus 3–5 com mapas montados no teste.
- [ ] **Step 2:** `flutter test test/nucleo/relatorio_test.dart test/app/telas/relatorios` — FAIL.
- [ ] **Step 3:** implementar conforme a seção "Tela" da spec.
- [ ] **Step 4:** mesmo comando PASS; gerar só os goldens novos `relatorios_guia_*`; confirmar com `git status` que `relatorios_cartao_*` e `relatorios_destaques_*` não mudaram; abrir 1 PNG celular terminal e 1 PC claro; `flutter test --exclude-tags vivo` e `flutter analyze` PASS.
- [ ] **Step 5:** commit "Relatórios: especialistas explicados (guia, comparação, casas) e preço-alvo no topo".

### Task 2: Versão 2.9.0 (controlador)
- [ ] versão, testes de versão, goldens da Conta, notas `docs/release/2.9.0.md`, CI, tag.
