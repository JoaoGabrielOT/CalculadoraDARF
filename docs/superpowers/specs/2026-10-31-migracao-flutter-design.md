# Migração da Calculadora DARF para Flutter

Data: 31/10/2026 · Versão alvo: 2.0.0

## 1. Intenção e porquê

O app atual (Windows em CustomTkinter, Android em Flet, núcleo em Python, ~12,5 mil linhas) trava e tem bugs. Casos relatados pelo dono:

- PC, tela Notícias: a janela fica travada ao ser arrastada.
- Android, Radar: não dá para rolar a lista enquanto as ações carregam.
- Em algum dos apps as cotações não carregavam (aparelho e tela não lembrados).
- Outros bugs não lembrados.

Causa provável comum: rede, imagens e cálculos rodando na mesma linha de execução da interface.

O objetivo é reescrever o app inteiro, Windows e Android, em uma tecnologia adequada, com todas as funções atuais e um visual novo, mais bonito e moderno.

## 2. Decisões do dono

- **Escopo:** tudo entra. Todas as funções e features atuais, sem exceção (checklist na seção 8).
- **Planilha Google:** continua exatamente no formato atual. Qualquer versão, Python ou nova, lê e escreve a mesma planilha, e as duas convivem ao mesmo tempo, inclusive entre amigos.
- **Visual:** pode e deve ser redesenhado. O dono gostou das três direções mostradas e quer as três como temas selecionáveis (seção 5).
- **PC:** pode deixar de ser um .exe solto e virar app instalado, com instalador.
- **Linguagem:** escolha delegada.
- **Processo:** usar as skills superpowers e os agentes de `.claude/agents` (arquiteto, implementador, revisor, explorador).

## 3. Decisões minhas (podem ser revistas)

- **Tecnologia:** Flutter (Dart), um único código para Windows e Android. Motivos: desempenho nativo, isolates e async para tirar o trabalho pesado da interface, boa maturidade no Windows desktop, listas reordenáveis, gráficos e notificações prontos.
- **Tema padrão:** Automático.
- **Login:** tentar reaproveitar o token atual de cada aparelho. Se não der, a pessoa entra de novo uma vez.
- **Versão:** 2.0.0. O atualizador antigo compara versões por tupla e enxerga 2.0.0 como mais nova.
- **Repositório:** o app novo fica em uma pasta `app/` no mesmo repositório. O código Python continua no repo até a 2.0.0 ser publicada e validada; a remoção é uma etapa final separada.

## 4. Metas, não-metas e anti-metas

**Metas**
- Paridade total de funções com a versão 1.12.x (Windows e Android, o que existir em qualquer uma passa a existir nas duas, salvo quando não fizer sentido na plataforma).
- Interface que nunca congela: arrastar, rolar e clicar respondem durante qualquer carregamento.
- Resultados numéricos idênticos aos do Python (imposto, taxas, isenção, preço-alvo, sugestões, caixa, D+2).
- Transição automática pela atualização existente, sem o usuário reinstalar nada à mão.

**Não-metas**
- iOS, web, macOS e Linux.
- Mudar regras de cálculo ou o formato da planilha.
- Novas funcionalidades além do redesenho e dos temas.

**Anti-metas (falha mesmo que "funcione")**
- Qualquer gravação na planilha que a versão Python não leia igual, ou que apague dados escritos pela versão Python.
- Número diferente do Python em qualquer cálculo de imposto ou caixa.
- Perder dados locais na transição (operações ainda não sincronizadas, configurações, metas).
- Android pedir para desinstalar o app antigo (chave ou applicationId diferentes).
- Telas que travam durante carregamento.

## 5. Visual

Mesmo desenho no PC e no celular, adaptado à tela:
- Celular: barra de navegação inferior.
- PC: barra lateral; tabelas e painéis lado a lado aproveitando a largura; janelas atuais (gráfico, metas, amigos, formulários) viram diálogos ou painéis.

Três temas, escolhidos em Configurações, valendo na hora e salvos por aparelho. Substituem a chave "Modo escuro".
- **Terminal:** fundo preto azulado (#0d1117), linhas finas, denso, verde #3fb950 e vermelho #f85149.
- **Claro:** fundo #f6f7fb, cartões brancos arredondados com sombra leve, selos suaves (verde #14833b sobre #e3f6ea, vermelho #c62828 sobre #fde8e8).
- **Moderno:** gradiente escuro (#151a2e → #0b0e1a), cartões translúcidos, destaque em gradiente roxo/verde (#6c5ce7 → #00b894), alta #55efc4, queda #ff7675.
- **Automático:** Claro com o sistema em modo claro e Moderno com o sistema em modo escuro.

Mockups de referência: `.superpowers/brainstorm/777-1793457610/content/estilo-visual.html` (local, fora do git). Elemento novo visto nos mockups: mini-gráfico do dia em cada linha do radar.

O desenho detalhado de cada tela fica com o construtor, seguindo as três direções e o checklist da seção 8.

## 6. Restrições técnicas

### 6.1 Planilha (contrato congelado)

Fonte da verdade: `google_sync.py` (`ABAS` linhas 13-45, criação 300-313, `_garantir_abas` 315-334, `_formatar` 336-393, `escrever` 395-425, leitura 436-441) e `nucleo.py` (`montar_linhas` 797-834, `linha_meta` 781-795, `reconstruir` 837-911, `reconstruir_metas` 926-972, mesclagem 986-1211).

- Título "Calculadora DARF", locale pt_BR, fuso America/Sao_Paulo, 1000 linhas por aba, linha 1 congelada, cabeçalho na linha 1.
- Abas e colunas na ordem exata: Resumo (13), Compras (13), Vendas (17), Amigos (3), Radar (5), Caixa (3), Metas (14), Exclusões (4, aba oculta). Colunas "id"/"Modificado" ocultas como hoje.
- Números como `numberValue` com ponto decimal; booleanos como "Sim"/"Não"; datas como serial do Sheets (dias desde 30/12/1899); "Modificado" em epoch segundos com 3 casas; Mês como texto "MM/AAAA"; Execução e Detalhes das metas como JSON em texto.
- Leitura com `UNFORMATTED_VALUE` e `SERIAL_NUMBER`. Formatos de exibição (moeda `"R$ "#,##0.00`, inteiro `#,##0`, data dd/mm/yyyy) idênticos.
- Compatibilidade de leitura igual à atual: colunas faltantes completadas, Posição do radar opcional, aba Metas com 12 colunas aceita (sem stop).
- Mesclagem idêntica: maior `mod` vence; exclusão vence se exclusão ≥ mod; metas com precedência executada > cancelada > mod mais recente; OCO; venda automática com id `auto-<meta>` deduplicada entre meses; caixa por maior `mod`.
- Ponto a verificar antes de portar: `escrever` faz updateCells sem `endRowIndex`. Confirmar se linhas que sumiram são apagadas no Sheets e reproduzir o mesmo efeito final.
- Amigos: compartilhar com permissão `reader` para o e-mail (com e-mail de notificação); remover apaga só essa permissão; achar a planilha do amigo pela consulta do Drive `name='Calculadora DARF' and mimeType=spreadsheet and trashed=false and '<email>' in owners`, mais recente primeiro.

### 6.2 Login Google

- Mesmo cliente OAuth do tipo "installed" (`credentials.json`, segredo `GOOGLE_CREDENTIALS` no CI), mesmos escopos: `drive.file`, `drive.metadata.readonly`, `spreadsheets.readonly`. Os escopos não podem mudar, para não exigir nova verificação do app no Google nem perder acesso à planilha criada com `drive.file`.
- Fluxo: código de autorização com PKCE S256 e redirect loopback `http://127.0.0.1:<porta>/` (como `login_navegador`, google_sync.py:148-244), nas duas plataformas.
- Token salvo localmente com refresh. Importar o `token.json` antigo (formato authorized_user do google-auth) na primeira execução, quando existir.

### 6.3 Fontes externas (mesmas URLs)

- Cotações: Yahoo chart `https://query1.finance.yahoo.com/v8/finance/chart/{TICKER}.SA` (mercado.py:82, 264, 307; períodos 85-89 e 119-128). O Windows hoje também usa yfinance; a versão nova usa só a API direta nas duas plataformas e precisa entregar os mesmos campos (anterior, variação, mín./máx. 6 meses, média, máx./mín. do dia, 52 semanas, volume, ATR). Tratar HTTP 429 sem travar e sem apagar dados já exibidos.
- Notícias: Google News RSS, decodificação de link por batchexecute e `rss/articles`, prévia (og:image, og:description), relevância por palavras-chave (noticias.py).
- Logos: icones-b3 no GitHub, brapi SVG, favicon do Google; cache local com ausência lembrada por 7 dias.
- GitHub releases (atualizador).

### 6.4 Desempenho

- Nenhuma chamada de rede, leitura de disco grande, decodificação de imagem ou cálculo pesado na thread da interface. Parsing de RSS/HTML/JSON grande em isolate.
- Listas com rolagem sempre ativa; itens preenchem quando os dados chegam.
- Requisições ao Yahoo com limite de concorrência e repetição com espera em 429.

### 6.5 Distribuição e transição

**Windows**
- Instalador (Inno Setup ou equivalente) publicado na release com o nome `CalculadoraDARF.exe`, porque o atualizador Python (atualizador.py) só procura esse nome. Ele baixa o arquivo, troca o exe antigo por ele e o executa.
- Ao rodar, o instalador instala o app (pasta por usuário, sem exigir admin, atalho no menu Iniciar e opção na área de trabalho) e migra os dados da pasta `dados/` ao lado do exe antigo (o próprio local de onde o instalador foi executado): config.json, token.json, meses, notícias e logos.
- Decisão minha: a migração **copia** `dados/` (não move nem apaga a pasta antiga) e grava um marcador no destino. Se o instalador for executado de novo, por exemplo por um atalho antigo que agora aponta para ele, não migra outra vez por cima de dados novos; só abre o app instalado. Os arquivos locais do app novo não precisam ser legíveis pelo Python, porque a planilha é o meio de convivência.
- Atualizações seguintes: o app Flutter baixa o instalador novo, confere tamanho e sha256 do campo `digest` do asset e o executa em modo silencioso.

**Android**
- Mesmo applicationId da versão atual (provavelmente `io.github.joaogabrielot.calculadoradarf`; confirmar no APK publicado da 1.12.1, por exemplo com `aapt dump badging`) e mesma keystore (segredos `ANDROID_KEYSTORE_BASE64` e `ANDROID_KEYSTORE_PASSWORD`, alias `calculadoradarf`), para instalar por cima sem desinstalar.
- versionCode maior que o atual (fórmula M·10000 + m·100 + p mantida).
- Migrar os dados do armazenamento do Flet (`FLET_APP_STORAGE_DATA`) se ainda forem acessíveis; senão, reler da planilha e pedir login uma vez.
- Atualizador igual ao atual: baixa `CalculadoraDARF.apk` e abre o instalador do sistema.

**Lançamento (decisão do dono)**
- A 2.0.0 sai primeiro como **pré-release** (o atualizador Python ignora `prerelease`). O dono instala à mão e testa no PC e no celular Android dele, com dados reais, incluindo a transição a partir da 1.12.x (atualizador antigo → instalador → migração de dados; APK por cima do antigo).
- Só depois da aprovação do dono a release é marcada como oficial ("latest"). Correções depois disso saem como 2.0.x; não há volta para a 1.12.

**Login no Android:** o fluxo loopback atual já funciona no celular real com o app publicado (confirmado pelo dono), então não precisa de plano B.

**CI (`release.yml`)**
- Gatilho por tag igual ao atual. Jobs Windows (build Flutter + instalador) e Android (APK arm64-v8a e armeabi-v7a, assinado), e job de publicação com os dois arquivos.

## 7. Garantia de cálculos idênticos

- Portar `nucleo.py`, `metas.py`, `sugestoes.py` e as partes de cálculo de `mercado.py` como módulos Dart puros, sem dependência de interface.
- Portar os 147 testes Python (test_metas, test_sugestoes, test_venda_retroativa) para Dart.
- Gerar, com o código Python, arquivos de referência (entradas e saídas: apuração de meses, caixa, D+2, preço-alvo, sugestões, linhas da planilha montadas e reconstruídas, mesclagens) e testar que o Dart produz o mesmo resultado. Feriados da B3 iguais.
- Teste de ida e volta: planilha escrita pelo Dart lida pelo Python e vice-versa, sem diferenças.

## 8. Checklist de paridade

Fonte detalhada: `2026-10-31-inventario-python.md` (nesta pasta). Tudo abaixo existe nas duas plataformas na versão nova. O checklist é um resumo; a primeira etapa de cada tela é um levantamento exaustivo da tela correspondente no Python (calculadora_darf.py e android/main.py), e o resultado é a união das duas plataformas (exemplo: os filtros Tipo/Operação das vendas, hoje só no Android). Decisão minha: o dono pediu "literalmente tudo", então esse levantamento não precisa de validação dele.

- **Geral:** navegação Apuração, Caixa, Radar, Notícias, Conta/Configurações; status de sincronização; Conectar Google (e-mail da conta, Sair, Abrir planilha, Sincronizar agora); temas; Sobre com versão e Verificar atualização; aviso de nova versão com progresso e cancelar.
- **Apuração/DARF:** seletor Visualizando (meus dados ou amigo, somente leitura); seletor de mês com calendário e "Mês atual", liberando meses anteriores sem arquivo; selo Aberto/Fechado/Somente leitura; Fechar mês; indicadores Lucro bruto, Lucro líquido, Imposto devido, Total da DARF; detalhamento com limite de isenção; Ativos comprados (filtro de situação, busca, ordenação, inverter); Vendas do mês; novo ativo, editar, excluir, registrar venda (duplo clique no PC), editar e excluir venda; venda gravada no mês dela.
- **Formulários:** compra (ticker com chips Frequentes/Em carteira, quantidade, preço, data com Hoje/Ontem, resumo da ordem); venda (lote, data, quantidade, preço, Sugerir preço, confirmação "Você já fez a venda?"); saldo (Definir, Aporte, Retirada); confirmações de exclusão; aviso de mês fechado.
- **Caixa:** Visualizando; Disponível agora, A receber, A pagar, Saldo projetado; Retirada, Aporte, Definir saldo; próximas liquidações com saldo depois; lançamentos com filtro Todos/A liquidar/Liquidados; alerta de saldo negativo; saldo no cabeçalho levando ao Caixa.
- **Radar:** adicionar ticker; logo; cotação, variação do dia em cores, média 6 meses, ATR, risco; mini-gráfico; filtros Todos/Em alta/Em queda/Em carteira; ordenações (Minha ordem, maior alta, maior queda etc.); reordenar arrastando, sincronizado; Comprar, Vender, Remover; radar do amigo com "+ Meu radar" e "Importar todos"; gráfico com períodos 1D, 5D, 1M, 6M, 1A, 5A, Máx, toque para ver o preço, estatísticas, Ver notícias, Comprar, Vender.
- **Notícias:** Todas/Relevantes, filtro por ativo, Atualizar, cartões com prévia (imagem, resumo, fonte) em mural de tamanhos variados no PC, abrir matéria no navegador, selo de não lidas, chave "Notificar notícias relevantes", notificações do sistema com o app aberto ou minimizado.
- **Metas / preço-alvo:** aba Sugestões (alvo e stop swing e day trade, Criar meta de alvo, stop fixo, stop móvel, pergunta de OCO, alerta de 2% do patrimônio); aba Calculadora (quantidade, lote, lucro desejado, preço-alvo sugerido, criar venda automática); lista de metas com cancelar; Verificar agora; verificação e execução automática como hoje.
- **Amigos:** adicionar por e-mail (compartilha a planilha), ver, remover com confirmação.

## 9. Pendências conhecidas da 1.12.x

Comportamento a reproduzir como está, salvo bug evidente de travamento ou crash (CONTEXTO_SESSAO.md): barras anteriores à criação da meta ignoradas; IRRF projetado por operação e apurado por dia; editar compra abaixo da reserva de metas não bloqueado; sem exclusão de metas. O bug do Android em que `verificar_metas` devolve None e mostra "Verificação já em andamento" deve ser corrigido.

## 10. O que fica com o construtor

- Arquitetura interna do app Flutter (gerenciamento de estado, pacotes, organização de pastas).
- Desenho detalhado de cada tela dentro das três direções visuais.
- Ferramenta do instalador Windows e detalhes do modo silencioso.
- Ordem das etapas, desde que o núcleo de cálculo e a planilha sejam validados contra o Python antes das telas.
- Instalar o Flutter SDK na máquina de desenvolvimento (hoje não instalado) e o que mais for preciso para compilar e testar localmente.
