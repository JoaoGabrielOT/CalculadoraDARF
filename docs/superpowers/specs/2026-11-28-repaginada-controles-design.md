# Repaginada dos controles (PC e celular) — design

## Intenção

O dono acha os botões do app "caóticos, desorganizados, desalinhados" no PC e no celular. Ele aprovou o esboço `2026-11-28-repaginada-controles-esboco.png` (HTML em `…-esboco.html`), com a frase "bem melhor mesmo, siga por esse caminho para todas as páginas, tanto para o PC quanto para o celular". Ele citou dois incômodos fortes:

- a legenda de risco pelo ATR do Radar, em que a faixa verde sobe para a linha do título e fica desalinhada das outras no celular;
- o seletor "Meus dados / amigo", repetido dentro das páginas como dropdown sublinhado.

Ele pediu também que eu procure outros casos parecidos em todas as telas.

## Metas, não-metas e anti-metas

- **Metas:**
  - uma hierarquia clara de ações por área;
  - uma aparência distinta para cada tipo de controle;
  - linhas alinhadas, com a mesma altura;
  - o mesmo padrão no PC, no celular e nos três temas (Claro, Moderno, Terminal);
  - nada de overflow em 360 px.
- **Não-metas:**
  - cálculo, regras e dados;
  - navegação e abas;
  - paleta dos temas;
  - funcionalidades novas;
  - textos de mensagens e diálogos (só os rótulos dos controles mudam onde indicado).
- **Anti-metas:**
  - nenhuma ação pode deixar de ser alcançável;
  - ícone sem texto sempre ganha tooltip e `Semantics` com o rótulo antigo;
  - nada pode ficar mais apertado no celular do que hoje.

## Abordagens consideradas

1. **Remendar tela por tela:** rápido, mas os problemas voltam na próxima tela.
2. **Kit de controles com regras fixas, aplicado em todas as telas:** escolhida. O dono aprovou o esboço que segue esta abordagem.
3. **Redesign completo, com navegação e cores novas:** fora do pedido.

## Regras (valem para toda tela)

1. **Hierarquia.** Cada área (cabeçalho, barra da página, cartão) tem no máximo uma ação principal (`FilledButton` roxo com ícone). A secundária é contornada, com ícone. As demais viram ícone (`IconButton` com tooltip) ou ficam num menu "⋯". Ações destrutivas (Excluir, Remover) são ícone de lixeira na cor `queda`, nunca pílula igual às outras.
2. **Um visual por tipo de controle.**
   - Escolha única: botão segmentado, com as opções grudadas e ✓ na escolhida.
   - Filtro de múltipla escolha: `FilterChip` (como hoje).
   - Busca: campo com lupa.
   - Tipo e Ordenar: botão de menu contornado com ícone (`filter_list`, `swap_vert`). Ordenar é um botão só, "⇅ <campo> ↑/↓". O menu lista os campos e um item para inverter a ordem.
   - Seletor de valor (mês, ativo, "Dados", "Ordenar por" das Metas): caixa contornada com rótulo flutuante, nunca o dropdown sublinhado.
   - Selo de estado (Aberto, Fechado, Nova, leituras dos relatórios, faixas de risco): etiqueta chapada, sem borda e sem cara de botão.
3. **Altura e alinhamento.** Tudo que divide uma linha tem 40 px: botões, segmentados, campos densos e caixas de seleção. Cada linha alinha à esquerda; a ação principal fica na ponta direita. No celular, o que não cabe passa para a linha de baixo com a mesma largura, ou vira ícone. Nunca uma peça sozinha com tamanho diferente.
4. **Celular.**
   - Conteúdo rolável tem folga embaixo para o botão "+" flutuante não cobrir texto (hoje ele cobre o cartão "Day trade" da Apuração).
   - O "+" do Radar usa a cor `destaque`, como o resto.

## Peças comuns (novas)

Ficam em `app/lib/app/componentes/controles.dart`, com estilo vindo do tema (`temas.dart` ganha `segmentedButtonTheme` e campos densos de 40 px):

- **Botões:**
  - `BotaoPrincipal(icone, rotulo, onPressed)`;
  - `BotaoSecundario(icone, rotulo, onPressed)`;
  - `BotaoIcone(icone, tooltip, onPressed, {destrutivo})`;
  - `BotaoLeve(icone, rotulo, onPressed)`: botão de texto com ícone, para o cabeçalho.
- **Escolha e filtros:**
  - `Segmentado<T>(opcoes, valor, aoMudar)`;
  - `CampoBusca(controller, dica, aoMudar)`;
  - `BotaoMenu<T>(icone, rotulo, itens, aoEscolher)`;
  - `BotaoOrdenar(campos, campo, desc, aoMudar)`.
- **Seletores e selos:**
  - `SeletorCaixa<T>(rotulo, valor, itens, aoMudar)`;
  - `SeletorMes(mes, anterior, proximo, aoAbrir)`: setas ◂ ▸ e o mês no meio. Tocar no meio abre o seletor de mês atual. As setas seguem os mesmos meses que o seletor permite e ficam desabilitadas no limite;
  - `Selo(texto, cor)`.

## Seletor de dados global (decisão minha)

Hoje o dropdown "Meus dados / e-mail do amigo" aparece dentro da Apuração, da Caixa e do Radar (`SeletorVisao`), e o estado (`EstadoApp.amigo`) já é global. Ele sai das páginas e passa a existir num lugar só:

- **PC, cabeçalho:** `SeletorDados` vira um `BotaoLeve` com ícone `group` e o texto "Meus dados" ou o nome do amigo.
  - O menu lista "Meus dados" e os amigos, um divisor e "Gerenciar amigos…", que abre a tela Amigos.
  - Ele substitui o botão "Amigos".
  - Com um amigo aberto, ele usa a cor `aviso`. O subtítulo "Dados de X · somente leitura" continua.
  - O "Atualizar" dos dados do amigo vira um `BotaoIcone(refresh)` ao lado do seletor, só com amigo aberto.
- **Celular, AppBar:** o seletor fica como `BotaoIcone(group)` ao lado do ícone de sincronização, com o mesmo menu.
  - Com um amigo aberto, aparece uma faixa fina na cor `aviso` abaixo do AppBar: "Dados de X · somente leitura", com o ícone de atualizar e o botão "Voltar aos meus".
- **Comportamento:** o mesmo de hoje (`EstadoApp.trocarVisao`). Desabilitado enquanto os dados do amigo carregam. Se a lista de amigos não carregar, sobra "Meus dados" mais o amigo aberto.

## Cabeçalho do PC (casca)

O cabeçalho fica numa linha só, como no esboço:

- **À esquerda:** título e subtítulo.
- **À direita:**
  - o status de sincronização (texto pequeno com ponto colorido);
  - o saldo, como `BotaoLeve(wallet)`, que leva à Caixa;
  - "Meta de lucro · N", como `BotaoLeve(target)`;
  - `SeletorDados`;
  - o avatar redondo com a inicial do e-mail. Tocar nele chama `clicarConta`, com o mesmo diálogo de hoje.
- **Sem conta:** o avatar vira `BotaoSecundario` "Conectar Google".
- **Tooltip do avatar:** o e-mail.

## Telas

- **Apuração:**
  - **Barra, PC:** `SeletorMes`, o selo do estado do mês e, na ponta direita, `BotaoPrincipal(lock, 'Fechar mês')`.
  - **Barra, celular:** `SeletorMes`, o selo e o menu ⋮ de hoje.
  - **Cartão "Ativos comprados", PC:** título e contador. À direita: `BotaoIcone(edit, 'Editar')`, `BotaoIcone(delete, 'Excluir', destrutivo)`, `BotaoSecundario(sell, 'Registrar venda')` e `BotaoPrincipal(add, 'Novo ativo')`.
    - Na linha seguinte: `Segmentado` "Posição em dd/mm/aaaa | Carteira atual", com a cotação ("Cotação atual · Yahoo · …") como texto pequeno à direita.
    - Na linha de filtros: `Segmentado` Situação (Todos | Em aberto | Vendidos), `CampoBusca` "Buscar ticker…", `BotaoMenu` Tipo e `BotaoOrdenar`.
    - Editar e Excluir mantêm o comportamento atual, inclusive o aviso "Selecione…".
  - **"Vendas do mês" e "Posições":** seguem o mesmo padrão.
  - **Celular:** o mesmo conjunto, compacto.
    - Primeira linha: o segmentado de Situação.
    - Segunda linha: a busca expandida e os ícones de Tipo e Ordenar, com um ponto quando estão ativos.
    - Folga embaixo para o "+".
- **Caixa:**
  - "Aporte" é a ação principal, "Retirada" é secundária e "Definir saldo" vira `BotaoLeve(edit)`.
  - Os filtros de lançamentos (Todos | A liquidar | Liquidados) viram `Segmentado`, alinhado à direita na linha do título.
  - No celular, o "Editar" do cartão de saldo vira `BotaoIcone(edit)`.
- **Radar:**
  - **Topo, PC:** o campo "Adicionar ticker" de 40 px, `BotaoPrincipal(add, 'Adicionar')` e `BotaoIcone(refresh, 'Atualizar')`.
  - **Topo, celular:** o campo e o "+" roxo de 40 px na mesma linha; Atualizar fica no ícone do cartão, como hoje.
  - **Filtros:** `Segmentado` (Todos | Em alta | Em queda | Em carteira), com `BotaoOrdenar` à direita no PC e na linha de baixo no celular.
  - **Linhas da tabela no PC:** Comprar e Vender viram botões compactos (Comprar tonal, Vender contornado) e Remover vira `BotaoIcone(delete, destrutivo)`.
  - **Legenda "Risco pelo ATR%":**
    - fica não clicável, com ponto colorido + texto em vez de pílula;
    - o título fica numa linha própria;
    - no celular, as 4 faixas formam uma grade de 2 colunas de mesma largura, alinhadas à esquerda;
    - no PC, as 4 faixas ficam numa linha;
    - os textos das faixas continuam os mesmos.
- **Notícias:**
  - `Segmentado` Todas | Relevantes, `SeletorCaixa` "Ativo" e `BotaoIcone(refresh, 'Atualizar')`, iguais no PC e no celular.
  - O selo "Nova" fica sempre logo após o título da notícia.
- **Relatórios:**
  - No painel "Relatórios anteriores", o título ganha `BotaoIcone(refresh)` e o período vira `Segmentado` 7 dias | 30 dias | 90 dias | Todos, numa linha.
  - No celular, "Anteriores" é `BotaoSecundario` e Atualizar é ícone.
  - Os selos de leitura viram etiquetas chapadas. Os filtros de múltipla escolha continuam `FilterChip`.
- **Conta:**
  - Tema: `Segmentado` no PC e `SeletorCaixa` "Tema" no celular, porque 4 opções não cabem em 360 px.
  - "Salvar prejuízo" vira `BotaoPrincipal`, alinhado aos campos de 40 px.
  - "Abrir amigos" é secundário.
  - Na lista de amigos, "Ver" é `BotaoSecundario` compacto e "Remover" é `BotaoIcone(delete, destrutivo)`.
- **Amigos (tela):** mesma regra da lista: "Ver" é secundário compacto e Remover é ícone.
- **Metas (diálogo):**
  - A troca Sugestões | Calculadora | Metas vira `Segmentado`, igual no PC e no celular.
  - "Verificar agora" é `BotaoSecundario`, na mesma linha e com a mesma altura.
  - "Dados" e "Ordenar por" viram `SeletorCaixa`.
  - Swing / Day trade / Só posições abertas continuam `FilterChip`, com largura do conteúdo.
  - Atualizar vira `BotaoIcone`.
- **Formulários:**
  - As ações do rodapé seguem a regra: Cancelar como texto e a principal cheia.
  - Os campos de seleção ficam como caixa densa.

## Testes e prova

- **Testes de widget:** passam a achar os controles pelos novos rótulos e tooltips. Todo comportamento existente continua coberto, inclusive o seletor de dados, agora na casca.
- **Testes novos:**
  - o kit (alturas de 40 px, tooltip e semântica dos ícones, `SeletorMes` com limites);
  - `SeletorDados` no PC e no celular;
  - legenda do Radar em 2 colunas em 360 px.
- **Goldens:** todos os afetados são regenerados nos três temas, PC e celular, e conferidos pelo `conferidor-visual` contra estas regras.
- **Suíte:** `flutter test --exclude-tags vivo` e `flutter analyze` sem falhas.

## Decisões complementares (respostas à revisão do design)

1. **"Dados" nas Metas (Sugestões)** é um filtro próprio (Todos / Com dados / Sem dados ou desatualizados), não o seletor meus/amigo. Continua independente e vira `SeletorCaixa`.
2. **Segmentados em 360 px.**
   - `Segmentado` tem o modo `compacto` (celular): sem o ✓ e com padding horizontal de 10 px. Os rótulos não são abreviados.
   - Se um teste de 360 px mostrar overflow mesmo assim, aquela tela usa `SeletorCaixa` no celular, como o Tema.
   - Radar (4 opções) e Relatórios (7 | 30 | 90 dias | Todos) devem caber no modo compacto. Cada um ganha um teste de 360 px sem overflow.
3. **Ordenar já existe.**
   - Apuração: "Ordenar: Cadastro" + "Crescente ↑".
   - Radar: "Ordenar: Minha ordem".
   - Metas: "Ordenar por".
   - `BotaoOrdenar` só junta campo e direção num botão. Mantém os mesmos campos, o mesmo padrão inicial e as mesmas regras, como "Para arrastar, use Ordenar: Minha ordem e o filtro Todos". O rótulo do botão é "<campo> ↑" ou "<campo> ↓" e o tooltip é "Ordenar". No Radar, "Minha ordem" não tem direção e mostra só o campo.
4. **Faixa do amigo no celular.** Ocupa espaço fixo abaixo do AppBar, empurra o conteúdo e some ao voltar para "Meus dados".
5. **Cabeçalho do PC em janelas estreitas.**
   - O PC começa em 840 px (`larguraExpandida`).
   - O texto do `SeletorDados` tem no máximo 180 px, com reticências.
   - Abaixo de 1200 px de largura de janela:
     - "Meta de lucro · N" e o `SeletorDados` mostram só o ícone, com um contador ou ponto e tooltip com o texto;
     - o status de sincronização vira só o ponto colorido, com o texto em tooltip.
   - O saldo e o avatar ficam sempre visíveis.
   - Teste: cabeçalho sem overflow a 840 px e a 1366 px.
6. **Cores.** `CoresApp` já tem `destaque`, `queda`, `alta` e `aviso` nos três temas. Nenhuma cor nova.

## Fica a cargo de quem implementa

- Ícones exatos onde não indicados.
- Espaçamentos finos, dentro de 8, 12 e 16 px.
- O texto do tooltip, quando não existir rótulo antigo.
- A ordem interna dos itens dos menus.
