# Inventário da versão Python 1.12.x

Levantamento somente leitura feito em 31/10/2026 para a migração Flutter. Referências: arquivo:linha.

## Arquivos (linhas)
calculadora_darf.py 3839 · android/main.py 2850 · nucleo.py 1211 · metas.py 781 · mercado.py 563 · noticias.py 511 · google_sync.py 456 · sugestoes.py 284 · componentes.py 261 · atualizador.py 139 · tema.py 49 · versao.py 1. Testes: test_metas.py 1209, test_sugestoes.py 310, test_venda_retroativa.py 104 (147 testes OK em 31/10/2026).

## Planilha
- Criação google_sync.py:300-313; abas faltantes `_garantir_abas` 315-334; formatação `_formatar` 336-393; localização `buscar_planilha` 282-289.
- Abas (google_sync.py:13-45), cabeçalho na linha 1, "oc." = coluna oculta:
  - Resumo (13): Mês ("MM/AAAA"), Status (Aberto/Fechado), Vendas de ações (swing), Isento (Sim/Não), Lucro bruto, Taxas B3, Imposto swing (15%), Imposto day trade (20%), IRRF retido, Lucro líquido, DARF meses anteriores, Total DARF, Modificado (oc.).
  - Compras (13): Mês, Ticker, Tipo, Data da compra, Quantidade, Preço unitário, Total, Qtd vendida, Qtd restante, Situação, ID (oc.), Origem (oc.), Modificado (oc.).
  - Vendas (17): Mês, Ticker, Tipo, Data da compra, Preço compra, Data da venda, Quantidade, Preço venda, Total venda, Operação, Taxas B3, Lucro bruto, Lucro após taxas, Imposto, ID (oc.), ID compra (oc.), Modificado (oc.).
  - Amigos (3): E-mail, Adicionado em, Modificado (oc.).
  - Radar (5): Ticker, Empresa, Adicionado em, Modificado (oc.), Posição (oc.).
  - Caixa (3): Saldo informado, Data do saldo, Modificado (oc.). Uma linha.
  - Metas (14): ID (oc.), Ticker, Tipo, ID compra (oc.), Quantidade, Preço-alvo (vazio no stop), Lucro desejado, Criada em (ISO texto), Status, Último erro, Execução (JSON), Modificado (oc.), Gatilho (alvo/stop), Detalhes (JSON, oc.).
  - Exclusões (4, aba oculta): Tipo (registro/amigos/radar/metas), Mês, ID ou chave, Excluído em (epoch).
- Valores: `numberValue` com ponto; bool "Sim"/"Não" (google_sync.py:76-83); datas serial do Sheets (nucleo.py:748, 751-762); moeda `"R$ "#,##0.00`, inteiro `#,##0` (google_sync.py:374-381); leitura UNFORMATTED_VALUE + SERIAL_NUMBER (436-441); Modificado epoch s com 3 casas (nucleo.py:40, 143); `mes_iso` (nucleo.py:765) exige "MM/AAAA".
- Montagem `montar_linhas` nucleo.py:797-834; `linha_meta` 781-795.
- Mesclagem: `salvar` nucleo.py:138-167 carimba `mod`; exclusões 200-226; `mesclar_tudo` 1171-1211 → `reconstruir` 837-911, `reconstruir_metas` 926-972, `mesclar_mes` 986, `mesclar_lista` 1041, `mesclar_metas` 1084 (executada > cancelada > mod), `resolver_oco` 1126, caixa por maior mod 1205, `deduplicar_auto` 1026; regravação por `escrever` google_sync.py:395-425 (updateCells sem endRowIndex — verificar limpeza de sobras).
- Ciclo de sincronização: calculadora_darf.py:2842-2877; android/main.py:2332-2390.
- Amigos: compartilhar google_sync.py:445-449 (reader, e-mail de notificação); remover 451-456; achar planilha do amigo 282-289; visão somente leitura calculadora_darf.py:2956, android/main.py:2228.

## Login Google
- `credentials.json` tipo "installed" (segredo GOOGLE_CREDENTIALS; release.yml:37, 81). Escopos google_sync.py:4-8: drive.file, drive.metadata.readonly, spreadsheets.readonly.
- Windows: InstalledAppFlow.run_local_server (google_sync.py:131-146). Android: `login_navegador` 148-244 (PKCE S256, loopback 127.0.0.1, troca de código com repetição).
- Token `dados/token.json` (authorized_user, google_sync.py:96); renovação 108-129; logout 252-258; e-mail via Drive about 246-250.
- Pastas de dados: Windows `BASE/dados` (calculadora_darf.py:42-44); Android `FLET_APP_STORAGE_DATA` ou `AQUI/dados` (android/main.py:33).

## Fontes externas
- Yahoo chart `query1.finance.yahoo.com/v8/finance/chart/{T}.SA` (mercado.py:82, 264, 307; períodos 85-89, 119-128). Windows também yfinance (248-298, 378-382), `auto_adjust=False`.
- Google News RSS (noticias.py:17), batchexecute (24), rss/articles (347), prévia `baixar_pagina`/`detalhar` (384-431).
- Logos: icones-b3 (noticias.py:18), brapi SVG (19, Android), favicon Google (20); cache dados/logos, ausência 7 dias (32, 473-503).
- Drive v3 e Sheets v4 (google_sync.py:10-11). GitHub releases latest (atualizador.py:14).

## Atualizador
- `verificar` atualizador.py:40-60 (ignora draft e prerelease, compara tupla, exige asset pelo nome; sha256 do `digest`, 57-60, 92-97).
- Windows: `<exe>.novo.exe` + script `%TEMP%\CalculadoraDARF_atualizar.cmd` com `move /y` e reabertura (101-139); disparo calculadora_darf.py:1271-1273, 2673-2686.
- Android: baixa `CalculadoraDARF-<versao>.apk` no cache e abre o instalador via FileProvider `<pacote>.provider` (android/main.py:80-91, 2819-2829).

## CI e Android
- release.yml: tag `v*`/`[0-9]*` ou manual; job windows (PyInstaller onefile), job android (flet build apk, arm64-v8a e armeabi-v7a, 3 tentativas, build number M·10000+m·100+p), job publicar (exe + apk).
- Assinatura: keystore base64 (ANDROID_KEYSTORE_BASE64), senha ANDROID_KEYSTORE_PASSWORD, alias calculadoradarf.
- android/pyproject.toml: org io.github.joaogabrielot, name calculadoradarf, min_sdk 24, permissões INTERNET, REQUEST_INSTALL_PACKAGES, POST_NOTIFICATIONS.

## Funcionalidades por tela
Windows (calculadora_darf.py):
- Cabeçalho (1279-1332): navegação Apuração/DARF, Caixa, Radar, Notícias; "Saldo" leva ao Caixa; Meta de lucro; Amigos; Conectar Google (e-mail, Sair, Abrir planilha, Sincronizar agora); Modo escuro; status de sincronização.
- Apuração (1346-1410): Visualizando; Atualizar; Mês com calendário; selo Aberto/Fechado/Somente leitura; Fechar mês; KPIs; detalhamento com isenção; Ativos comprados (filtro SITUAÇÃO, ordenação por cabeçalho, duplo clique registra venda; Novo ativo, Editar, Excluir, Registrar venda); Vendas do mês (Editar, Excluir).
- Diálogos: FormCompra (chips Frequentes/Em carteira, quantidade, preço, data, resumo); FormVenda (lote, data, quantidade, preço, Sugerir preço, "Você já fez a venda?", 1632); FormSaldo (Definir, Aporte, Retirada); confirmações; "Mês fechado".
- Caixa: Visualizando; Disponível agora, A receber, A pagar, Saldo projetado; Retirada, Aporte, Definir saldo (1809-1815); próximas liquidações; lançamentos com filtro Todos/A liquidar/Liquidados; alerta de saldo negativo.
- Radar (1991-2060): ordenação; filtro; Atualizar; Importar todos (amigo); adicionar ticker; linhas arrastáveis; Comprar, Vender, Remover, "+ Meu radar"; JanelaGrafico (1D a Máx, Ver notícias, Comprar, Vender).
- Notícias (2083-2140): Todas/Relevantes, filtro por ativo, Atualizar, chave de notificação, mural de cartões, abrir matéria.
- JanelaMetas (3304-3720): Sugestões (Atualizar, meta de alvo, stop fixo, stop móvel, OCO) e Calculadora (quantidade, lote, lucro, preço-alvo, criar venda automática); lista com Cancelar; Verificar agora.
- DialogoAmigos (3721-3835); aviso de nova versão e DialogoAtualizacao com progresso e Cancelar.

Android (android/main.py):
- Barra inferior Apuração, Caixa, Radar, Notícias, Conta; AppBar com sincronização (617-623); FAB Nova compra (712).
- Apuração: "Meta de lucro / Preço-alvo · N ativas" (770); Fechar mês (743); seletor de mês com "Mês atual" (1086); busca, ordenação, inverter, filtros Tipo/Operação das vendas (867-913); menus de item (1024-1070).
- Formulários: compra (1194), venda com Sugerir preço (1320), chips Hoje/Ontem (308), ResumoOrdem.
- Caixa (1549-1680) com Agenda financeira e edição de saldo (1627).
- Radar (1682-1862): busca/adicionar, filtros, ordenação, reordenar (1768), importar do amigo (1781-1797), Comprar/Vender/Remover, GraficoAtivo (352) com toque para ver preço.
- Notícias (1868-1997): chave de notificação, cartões, selo.
- Conta (2070-2111): Google, Sincronizar, Abrir planilha, Sair, Modo escuro, Amigos (2112-2187), Sobre com Verificar atualização.
- Metas `dialogo_metas` (2442-2768).
- Notificações (94-139).
