# Relatórios: especialistas explicados para leigos — design curto

Data: 27/11/2026. Base: 2.8.0. Pedido do dono (literal): mostrar os campos novos de `especialistas` e dos itens; "guiaLeigo em destaque; uma comparação em 2 colunas (Último preço | Alvo médio com potencial colorido | Faixa dos alvos); um sub-cartão por casa com selo, casa, data, fraseGuia, "Motivo:" em itálico e link. No topo da aba, explique: "Preço-alvo é quanto a casa acha que a ação vai valer no prazo indicado (em geral 12 meses). Não é preço para comprar nem para vender." Sem esses campos (relatórios antigos), mantenha a exibição atual. Inclua testes com e sem os campos."

## Campos (todos opcionais, ainda schemaVersion 1; tolerantes como o resto)
- `especialistas`: `precoReferencia`, `alvoMedio`, `alvoMin`, `alvoMax`, `potencialMedio`, `guiaLeigo` — textos (ex.: "R$ 56,90 em 26/11", "R$ 67,67", "+18,9%").
- `itens[]`: `precoAlvoValor` (número), `moedaAlvo` ("BRL"/"USD"), `prazoAlvo`, `motivo`, `fraseGuia` — textos, exceto o número.
- Fixture com os campos: `tests/fixtures/relatorio-abertura-2026-11-27-guia.json` (23 ativos, termômetro 8/10/2/3). Sem os campos: as fixtures de 26/11 e `relatorio-abertura-2026-11-27.json` (não mudam).

## Abordagens
Uma só faz sentido: estender o modelo e a caixa Especialistas do cartão, com fallback para a exibição atual por campo. Descartada: tela de detalhe separada por ativo (mais navegação, nada pedido).

## Tela (decisões do controlador, corrigíveis)
- **Topo da aba:** caixa azul (paleta `azulFundo`/`azulTexto`) com o texto literal do pedido, logo depois do cabeçalho (a), **só quando** algum ativo tem `guiaLeigo`, `alvoMedio` ou item com `fraseGuia`/`motivo`. Key `explicacao-preco-alvo`.
- **guiaLeigo:** caixa azul em destaque no início do campo Especialistas do cartão, no lugar do `resumo` (a tabela-resumo continua com `resumo`). Sem guiaLeigo: `resumo` como hoje. Key `guia-<ticker>`.
- **Comparação** (só com `alvoMedio`): duas colunas lado a lado — "Último preço" (`precoReferencia`, ou `textoPreco(preco)` se faltar) | "Alvo médio" (`alvoMedio`) com `potencialMedio` num selo colorido (começa com "+" → paleta positiva; "-" ou "−" → negativa; outro → neutra). Abaixo das colunas, "Faixa dos alvos: <min> a <max>" quando os dois existem e são diferentes; iguais → "Faixa dos alvos: <min>"; algum faltando → a linha some. Key `comparacao-<ticker>`.
- **Placar** (selos da 2.8.0) continua, abaixo do guia e da comparação.
- **Sub-cartão por casa** (item com `fraseGuia` ou `motivo`): borda fina do tema; linha 1 = selo da classificação ("Compra" verde, "Manter" cinza, "Venda" vermelho, "Sem classificação" neutro; sem `classificacao`, pelo texto da recomendação com a regra da 2.8.0, senão sem selo) + casa em negrito + data curta (`dataCurta`); depois `fraseGuia` sem o trecho final " Motivo: …" quando ele repete o `motivo` (comparação sem caixa, sem espaços nas pontas e sem ponto final); depois "Motivo: <motivo>" em itálico; depois o link da fonte (`LinkRelatorio`) se houver URL segura. Item sem `fraseGuia` e sem `motivo`: a linha atual da 2.8.0. Key `casa-<ticker>-<índice>`.
- Paleta fixa nas caixas e selos (legível nos 3 temas); textos do tema fora delas.

## Fora do escopo
Recalcular potencial ou faixa no app (vale o texto do JSON); converter moedas; mudar a regra de destaque da 2.8.0.

## Release
2.9.0 com notas.
