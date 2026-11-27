# Relatórios: ordem por leitura e destaques — design curto

Data: 26/11/2026. Base: 2.7.0 (aba Relatórios, `2026-11-26-relatorios-design.md`).

## Pedido do dono
- Ativos na ordem: positivas, mistas, neutras, negativas (tabela-resumo e cartões). Isto substitui o item h) do `prompt.md` ("em ordem de posicao"); dentro de cada leitura vale a `posicao`.
- Destacar os ativos com mais chance de subir segundo o relatório. O dono deixou o critério comigo.

## Abordagens consideradas
- **A) Leitura positiva + especialistas indicando compra** — escolhida: dois sinais do próprio relatório na mesma direção; hoje BPAC11 e RENT3.
- B) Maior distância até o preço-alvo — ruidosa: HAPV3 (negativa, alvo cortado) seria 2ª; RENT3 +89% parece alvo desatualizado.
- C) Todas as positivas — não distingue nada, já vão para o topo pela ordem.

## Campos novos do relatório (27/11, ainda schemaVersion 1)
O relatório de 27/11 (`tests/fixtures/relatorio-abertura-2026-11-27.json`, 23 ativos, termômetro 5/12/1/5) acrescenta, sem mudar a versão:
- `especialistas.consenso`: `"compra"`, `"neutra"`, `"venda"`, `"dividido"` ou `"sem_dados"`; `especialistas.consensoTexto` (igual ao `resumo`); `especialistas.placar` `{compra, neutra, venda}` (inteiros); `especialistas.fontePlacar` (`"casas"`).
- `itens[].classificacao`: `"compra"`, `"neutra"`, `"venda"` ou `"sem_classificacao"`; `itens[].potencial` (texto, ex.: "+39,7% até o alvo, com o preço de 26/11"), pode ser null.
Todos opcionais e tolerantes como o resto (ausente ou de tipo errado → null; consenso desconhecido → null). Relatórios antigos (26/11) não têm esses campos.

## Regras (núcleo puro, `lib/nucleo/relatorios/destaques.dart`)
- `consensoDe(Especialistas) → Consenso?` (enum `compra, neutra, venda, dividido, semDados`), nesta prioridade:
  1. `consenso` do JSON, quando é um dos valores conhecidos.
  2. Senão, `placar` do JSON: o maior valor estritamente acima dos outros dois decide; empate no topo → dividido; tudo zero → semDados.
  3. Senão, o placar contado pelos itens: `classificacao` quando existe (`sem_classificacao` não conta); sem ela, a `recomendacao` em minúsculas: começa com `compra`, `comprar`, `outperform`, `overweight`, `buy`, `top pick` ou `acima da média` (palavra inteira) → compra; `venda`, `vender`, `underperform`, `underweight`, `sell` → venda; `neutr`, `manter`, `manutenção`, `market perform`, `hold`, `in line` → neutra; o resto não conta. Item de consenso no formato "N compra / M manutenção / K venda" vira esse placar. Mesma regra do passo 2 sobre o placar resultante.
- `placarDe(Especialistas) → (compra, neutra, venda)`: o do JSON ou o contado no passo 3.
- `emDestaque(AtivoRelatorio)`: leitura positiva **e** consenso compra.
- `ordenarParaExibicao(List<AtivoRelatorio>)`: estável; leitura na ordem do enum (positiva, mista, neutra, negativa); dentro das positivas, os em destaque primeiro, entre eles maior fração de compra no placar e depois mais casas; o resto mantém a ordem recebida (`posicao`).
- Fixtures: 26/11 → destaques BPAC11, RENT3 (pelos itens de texto). 27/11 → EMBJ3, PRIO3 (positivas com consenso compra); WEGE3 (mista, 4/4 compra), LREN3 (negativa, compra) e TIMS3 (positiva, dividido) não entram.

## Tela
- Tabela-resumo, cartões e selos do termômetro usam `ordenarParaExibicao`.
- Seção nova **"Sinais mais favoráveis"** logo depois do termômetro (só quando há destaque): cartão com borda verde da paleta, uma linha por ativo com ★, ticker, descrição, preço e o resumo dos especialistas; nota "Leitura positiva e especialistas indicando compra. Não é previsão nem recomendação."
- Tabela: linha em destaque com ★ antes do ticker e fundo verde translúcido (legível nos 3 temas).
- Cartão do ativo: selo "★ Destaque" ao lado do selo da leitura e borda verde de 2 px.
- Cartão do ativo, campo Especialistas: abaixo do resumo, o placar em selos ("2 compra", "1 neutra", "0 venda" em verde, cinza e vermelho da paleta) quando há placar com algum valor; em cada item, o `potencial` depois do preço-alvo quando existe.
- Texto nunca diz "vai subir": a legenda do relatório afirma que a leitura não é previsão.

## Fora do escopo
Mudar o JSON ou a automação; ranking por preço-alvo; destaque nas leituras mistas.

## Release
2.8.0 com notas. De quebra, o passo "Atualizador Python 1.12 detecta a versão" do CI tenta de novo (3 vezes, 20 s) antes de falhar, porque a falha da 2.7.0 foi consulta passageira à API do GitHub.
