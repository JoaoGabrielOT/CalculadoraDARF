# Relatórios e Apuração: análises complementares — design

Data: 27/11/2026. Base: 2.9.0. Pedido completo: `prompt.md` (raiz do repositório principal, 27/11 16:55), seções 1–6. Plano aprovado pelo dono com as propostas do controlador ("faça do jeito que achar melhor, aprovo tudo"), mais um esclarecimento: no item 1, o "Resumo por ativo" no **celular** deve mostrar tudo **sem arrastar para o lado** (hoje a tabela rola na horizontal).

## Decisões aprovadas
- Itens 1–4 na aba **Relatórios**: "Resumo por ativo" = tabela-resumo (seção g); "Ativos" = lista de cartões (h); "relatório completo" = cartão do ativo.
- Itens 5–6 na **Apuração**: "Vendas do mês" e "Ativos comprados" (lotes com saldo > 0).
- Preço máximo/mínimo: cotações **diárias do Yahoo** (máxima das `alta`, mínima das `baixa`). Item 5: mês inteiro da venda (até hoje, se for o mês atual). Item 6: da data da compra do lote até hoje.
- Resultado: **líquido estimado**, com a mesma fórmula da apuração (`calcularResultado`/`ResultadoVenda`: taxas B3 swing ou day trade e corretagem), trocando só o preço de venda. Nunca altera resultado oficial, imposto ou DARF.
- Item 6 **por lote** (cada compra com sua data e preço), como a seção já mostra.
- Notificação **só dentro do app** (badge na aba Relatórios + faixa na aba). Sem notificação do sistema.
- Gráficos sem dependência nova: `GraficoLinha` existente + `GraficoBarras` novo por `CustomPainter`.
- Dinheiro em `double`, como o projeto inteiro. Datas `AAAA-MM-DD` e meses `AAAA-MM`, como o resto.
- **Sem commit e sem push** até o dono revisar (restrição do prompt). Checkpoints por `git add` (staging) entre tasks.

## 1. Resumo por ativo (celular sem rolagem lateral) + resumo dos especialistas
- Largura compacta (`!expandido(context)`): a tabela vira **lista de linhas empilhadas**, uma por ativo, sem `SingleChildScrollView` horizontal: linha 1 = ★ (se destaque) + ticker em negrito + selo da leitura à direita; linha 2 = último preço (`textoPreco`); linha 3 = resumo dos especialistas (`resumo`) em texto que quebra. Expandido: tabela atual inalterada.
- Bloco **"Resumo dos especialistas"** logo abaixo da tabela/lista (Key `secao-resumo-especialistas`), recolhível por ativo (`ExpansionTile` ou equivalente), na ordem de exibição: título = ticker + consenso ("Maioria compra", "Maioria manter", "Maioria venda", "Opiniões divididas", "Sem análise"); aberto = uma linha por casa: classificação (selo), casa, data curta, motivo (ou recomendação quando não há motivo) e link "Ver fonte" se seguro. Consenso `dividido` → selo âmbar "Opiniões divididas" e todas as casas listadas, sem escolher uma. Sem itens → "Nenhuma análise de especialista disponível para este ativo". Nada inventado: só campos do JSON.
- Cabe em 360 px de largura sem overflow horizontal.

## 2. Filtro e pesquisa
- Barra acima dos cartões "Ativos" (Key `filtros-ativos`): campo de busca (ticker, empresa, descrição; sem acento e sem caixa), chips de **tipo** (valores de `tipoAtivo` presentes no relatório; rótulos: acao→"Ações", bdr→"BDRs", fii→"FIIs", fiagro→"Fiagro", outro→o texto cru), chips de **status**: Positivas, Mistas, Neutras, Negativas, "Em destaque", "Com análise", "Sem análise", "Na minha carteira" (tickers com posição aberta no mês atual, via `ServicosApp.posicoes`). Seleção múltipla dentro de cada grupo = OU; entre grupos = E. Sem filtro = lista atual.
- O filtro vale para tabela/lista do item 1, bloco dos especialistas e cartões; termômetro e destaques continuam com todos. Contagem "N de M ativos" e "Limpar filtros". Resultado vazio → "Nenhum ativo com esses filtros".
- **Período** na lista "Relatórios anteriores": chips "7 dias", "30 dias", "90 dias", "Todos" (padrão Todos), pela data do nome do arquivo.
- Filtro puro em `lib/nucleo/relatorios/filtros_relatorio.dart`; estado no widget (sem recarregar a página).

## 3. Gráficos no cartão do ativo
- Cartão ganha abas **"Relatório" | "Gráficos"** (Relatório selecionada). A aba Gráficos só monta e só busca dados ao ser tocada (o conteúdo não existe na árvore antes).
- Gráficos: (a) linha do fechamento diário dos últimos 3 meses (Yahoo, via novo `ServicosApp.barrasDiarias(ticker, {String? desde})`); (b) barras "Último preço × Alvo médio × Alvo mín × Alvo máx" quando o relatório tiver `alvoMedio` com moeda comparável (mesmo prefixo de moeda do `precoReferencia`); (c) se houver posição aberta do ativo: barras "Preço médio de compra × Último preço" e linha do resultado bruto da posição (qtd × (fechamento − custo médio)) desde a compra mais antiga.
- Cada gráfico com título, legenda textual e `Semantics` com o resumo ("Fechamento de R$ X a R$ Y entre dd/mm e dd/mm"). Menos de 2 pontos → "Dados insuficientes para o gráfico". Carregando → indicador; erro → mensagem + "Tentar de novo". BDR/FII com ticker que o Yahoo não conhece → erro tratado.
- `barrasDiarias` implementado em serviços locais, proxy do isolate e Web (Web usa o mesmo caminho das outras cotações do Yahoo), reaproveitando cache.

## 4. Aviso de relatório novo
- Ao listar/atualizar relatórios, se aparecer relatório cujo nome é mais novo que o último já avisado: badge com a contagem na aba Relatórios (como Notícias) e faixa no topo da aba: "Novo relatório de abertura: <data por extenso>, gerado às HH:MM" (de `geradoEm` quando houver no índice; senão sem hora) com "Abrir" (abre o relatório) e "Dispensar". Abrir ou dispensar marca como avisado. O último avisado fica salvo localmente (mesmo armazenamento dos relatórios) → sem duplicar entre aberturas. Primeira execução: o relatório mais novo existente vira o "último avisado" sem avisar (evita aviso falso na instalação).

## 5. Vendas do mês — melhor e pior resultado possível
- Para cada venda (linha agrupada atual): "Melhor possível" = resultado líquido se vendida pela máxima do mês; "Pior possível" = pela mínima. Mostra também a referência: "máx R$ X (dd/mm) · mín R$ Y (dd/mm), <mês/ano>, cotações diárias". Sem barras no mês → "Indisponível".
- Expandido: duas colunas novas na tabela + referência em tooltip; compacto: linhas novas no cartão. Carregamento sob demanda das barras por ticker (uma busca por ticker e mês), com estado "Carregando…" e erro → "Indisponível".

## 6. Ativos comprados — maior lucro e maior perda até agora
- Para cada lote com saldo > 0: "Maior lucro possível até agora" = resultado líquido de vender o saldo pela máxima desde `dataCompra` até hoje; "Maior perda possível até agora" = pela mínima. Referência com as datas dos extremos. Sem dados → "Indisponível". Mesmo padrão de layout e carregamento do item 5.
- Cálculo puro em `lib/nucleo/extremos.dart`: `Extremos extremosDe(List<BarraDiaria>, String desde, String ate)` (máx/mín com datas, null sem barras) e funções de resultado que reutilizam a fórmula de `apuracao.dart`.

## Fora do escopo
Notificação do sistema/push; novas fontes de especialistas; mudanças fiscais; nova dependência.

## 7. Compartilhar a pasta de relatórios com os amigos (pedido do dono, 27/11)
Decisões do dono: escopo `https://www.googleapis.com/auth/drive` **só para a conta dona da pasta**; compartilhar **sem e-mail de aviso**.
- **Quem é dono:** `files.get(pastaRelatorios, fields=capabilities(canShare),owners(emailAddress))` com o token atual (drive.readonly basta). `canShare == true` → modo dono. Outros usuários: nada muda, nada aparece.
- **Permissão:** no modo dono sem o escopo `drive` no token, a tela de Amigos mostra um aviso "Para compartilhar a pasta de relatórios automaticamente com seus amigos, entre de novo com o Google e permita o acesso ao Drive." com o botão "Permitir". O botão faz o login de novo (mesma conta, como o "entrar de novo" da 2.7.0) pedindo `escoposGoogle` + `drive` (`include_granted_scopes=true`). No Windows/Android pelo fluxo de `login.dart`; na Web por `web_servidor/api/auth/inicio.js` com um parâmetro opcional (ex.: `extra=drive`) que só aceita esse valor. `escoposGoogle` padrão não muda (os outros usuários não pedem `drive`).
- **Compartilhar:** `POST https://www.googleapis.com/drive/v3/files/{pastaRelatorios}/permissions?sendNotificationEmail=false` com `{"role":"reader","type":"user","emailAddress":<email>}`. Antes, `GET .../permissions?fields=permissions(emailAddress,role,type)` (paginado) para não duplicar: e-mail que já tem qualquer papel (reader/writer/owner) não é tocado. Comparação de e-mails sem caixa e sem espaços.
- **Quando:** (a) ao adicionar um amigo (depois de salvar o amigo; falha no compartilhamento não desfaz a adição — mostra aviso "Amigo adicionado, mas a pasta de relatórios não foi compartilhada: <motivo>"); (b) ao abrir a tela de Amigos e após o "Permitir": reconcilia todos os amigos atuais que ainda não têm acesso. Mostra "Pasta de relatórios compartilhada com N amigo(s)" quando compartilhar alguém. Remover amigo **não** revoga o acesso (fora do escopo; o dono revoga no Drive).
- **Erros:** 403 sem escopo → volta ao aviso "Permitir"; e-mail sem conta Google (400/`invalidSharingRequest`) → lista esse e-mail no aviso, sem travar os outros; sem internet → silêncio na reconciliação, aviso só na adição.
- Serviços: novos métodos em `ServicosApp` (ex.: `Future<EstadoCompartilhamento> estadoCompartilhamento()`, `Future<ResultadoCompartilhamento> compartilharRelatorios()`, `Future<void> permitirCompartilhamento()`) em local, isolate e Web; integração em `lib/integracoes/google/` (novo `compartilhamento.dart`), com testes de cliente HTTP falso.
- Controlador: depois, adicionar o escopo `.../auth/drive` em Google Cloud > Acesso a dados (tela de consentimento), como foi feito com `drive.readonly`.
