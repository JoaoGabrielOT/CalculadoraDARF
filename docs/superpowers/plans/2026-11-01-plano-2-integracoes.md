# Plano 2: integrações (Yahoo, Google, notícias, logos, atualizador) em Dart (Implementation Plan)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Portar para Dart (pasta `app/lib/integracoes/`) toda a camada de rede da versão Python 1.12.x (Yahoo, login e planilha Google, ciclo de sincronização, Google Notícias, prévias, imagens, logos e atualizador), com os mesmos pedidos HTTP, as mesmas mensagens e o mesmo efeito na planilha, testada só com clientes HTTP falsos.

**Architecture:** Cada serviço recebe um `http.Client` (embrulhado por `ClienteHttp`, que põe tempo limite, User-Agent, conversão de falhas para os erros do núcleo, repetição em 429 e limite de concorrência) e, quando decodifica algo grande, uma função `Executar` (padrão `Isolate.run`). O parsing (RSS, HTML, JSON do chart, montagem dos pedidos do Sheets) fica em funções puras que recebem tudo por parâmetro. Os pedidos e respostas são conferidos contra referências geradas pelo próprio código Python 3.12 com uma rede falsa que grava o que ele enviaria. Telas, `url_launcher`, `path_provider`, notificações e execução do instalador ficam para os planos 3 e 4; aqui só as interfaces injetadas.

**Tech Stack:** Dart 3 / Flutter 3.47.9 (sem widgets), `http` 1.6.0, `crypto` 3.0.7, `xml` 6.6.1, `image` 4.12.0, `dart:io` (`HttpServer` loopback, arquivos); Python 3.12 para gerar referências.

**Spec:** `docs/superpowers/specs/2026-10-31-migracao-flutter-design.md` (seções 4, 6.1 a 6.5) e `docs/superpowers/specs/2026-10-31-inventario-python.md`. Notas do plano 1: `docs/superpowers/plans/2026-10-31-plano-1-resultado.md`. A fonte da verdade de cada função é o arquivo Python citado em cada tarefa (arquivo:linha).

## Global Constraints

Do spec:
- Anti-meta: "Qualquer gravação na planilha que a versão Python não leia igual, ou que apague dados escritos pela versão Python." Os corpos dos pedidos ao Sheets/Drive são os mesmos do Python (google_sync.py:282-456).
- Planilha: título "Calculadora DARF", locale pt_BR, fuso America/Sao_Paulo, 1000 linhas por aba, linha 1 congelada, abas e colunas de `esquemaAbas` (núcleo) na ordem exata; aba Exclusões oculta; colunas "id" ocultas; moeda `"R$ "#,##0.00`, inteiro `#,##0`, data dd/mm/yyyy; leitura com `UNFORMATTED_VALUE` e `SERIAL_NUMBER`.
- Amigos: compartilhar com permissão `reader` (com e-mail de notificação); remover apaga só essa permissão; planilha do amigo pela consulta `name='Calculadora DARF' and mimeType=spreadsheet and trashed=false and '<email>' in owners`, mais recente primeiro.
- Login: mesmo cliente OAuth "installed" (`credentials.json`), escopos exatos `drive.file`, `drive.metadata.readonly`, `spreadsheets.readonly` ("não podem mudar"); código de autorização com PKCE S256 e redirect loopback `http://127.0.0.1:<porta>/` nas duas plataformas; token salvo localmente com refresh; importar o `token.json` antigo (formato authorized_user do google-auth).
- Fontes externas com as mesmas URLs: Yahoo chart `https://query1.finance.yahoo.com/v8/finance/chart/{TICKER}.SA`; Google News RSS, batchexecute e `rss/articles`; icones-b3, brapi SVG, favicon do Google, cache local com ausência lembrada por 7 dias; GitHub releases latest.
- Só a API direta do Yahoo nas duas plataformas, entregando anterior, variação, mín./máx. 6 meses, média, máx./mín. do dia, 52 semanas, volume, ATR. "Tratar HTTP 429 sem travar e sem apagar dados já exibidos."
- "Nenhuma chamada de rede, leitura de disco grande, decodificação de imagem ou cálculo pesado na thread da interface. Parsing de RSS/HTML/JSON grande em isolate." "Requisições ao Yahoo com limite de concorrência e repetição com espera em 429."
- Atualizador: ignora draft e prerelease, compara versão por tupla, asset `CalculadoraDARF.exe` no Windows (o instalador é publicado com esse nome, spec §6.5) e `CalculadoraDARF.apk` no Android; confere tamanho e sha256 do campo `digest`. Versão alvo 2.0.0.
- Mensagens visíveis ao usuário em português, idênticas às do Python (as tarefas citam cada texto).

Do plano 1 (continuam valendo para todo arquivo em `app/lib/nucleo/`, que as Tarefas 3 e 12 alteram): núcleo sem Flutter, sem rede e com `dart:io` só em `armazenamento_arquivos.dart`; `arredondar`/`fixoPython`/`somaPython`/`maxPython`/`ordenadoPor` no lugar de `round`/`sum`/`max`/`sort`; referências com `double` comparado por `==`; `ambiente` como relógio.

Decisões deste plano (valem para todas as tarefas):
- `app/lib/integracoes/**` não importa `package:flutter/material.dart`, `widgets.dart`, `cupertino.dart` nem `dart:ui`; `package:flutter/services.dart` só em `google/credenciais_asset.dart`. O núcleo não importa `integracoes/`. Também valem ali as proibições de `.sort(` e `.round(` (usar `ordenadoPor` e `arredondar`).
- Pacotes novos, com versão exata no `pubspec.yaml`: `http: 1.6.0`, `crypto: 3.0.7`, `xml: 6.6.1`, `image: 4.12.0`. Nenhum outro (sem `pool`, `fake_async`, `html`, `html_unescape`). `url_launcher` 6.3.3 e `path_provider` 2.1.6 entram no plano 3.
- Rede sempre injetada. Testes usam `ClienteFalso` (Tarefa 2) e `executarDireto`; nenhum teste acessa a internet (a Tarefa 8 usa só o loopback 127.0.0.1 da própria máquina).
- Relógio de caches, validade do token e prazos: `ambiente.agora()` / `ambiente.hoje()` do núcleo. Esperas (429, repetição do login): função `Esperar` injetada.
- Funções puras de parsing recebem tudo por parâmetro, inclusive `agora`: `ambiente` é global por isolate e um `Isolate.run` vê o relógio padrão.
- Erros: falha de transporte (`SocketException`, `ClientException`, `HandshakeException`, `TlsException`, `HttpException`, `TimeoutException`) vira `ErroConexao(<texto original>)`; no Google, `Offline(<texto>)`. HTTP 429 vira `LimiteConsultas('Too Many Requests')`. Outro status ≥ 400 vira `ErroHttp` com o texto do `raise_for_status` do requests: `'<status> Client Error: <motivo> for url: <url>'` (4xx) ou `'... Server Error: ...'` (5xx).
- Tempos limite do Python: Yahoo 20 s, Google 30 s, RSS/páginas/imagens 20 s, logos 15 s, GitHub 15 s (consulta) e 30 s por bloco (download).
- User-Agents do Python: Yahoo `Mozilla/5.0` (mercado.py:83); notícias e logos `Mozilla/5.0 (CalculadoraDARF)` (noticias.py:21); páginas e imagens `uaNavegador` (noticias.py:22-23, copiar literalmente, com `Accept-Language: pt-BR,pt;q=0.9`); GitHub `CalculadoraDARF` (atualizador.py:44).
- JSON lido do Yahoo e do Sheets nunca é convertido int↔double (o `jsonDecode` já preserva como o `json.loads`).
- Arquivos locais com os nomes e chaves do Python (`token.json`, `noticias_detalhes.json`, `logos/`, `logos/fontes/`, `noticias_img/`), porque o plano 4 migra a pasta `dados/`. Texto via `Armazenamento` do núcleo; binário via `CacheBinario` (Tarefa 15).
- Referências: módulos novos em `ferramentas/referencias/`, gerados com `py -3.12 ferramentas/gerar_referencias.py <area>`; a rede do Python é trocada por `ferramentas/referencias/_rede_falsa.py` (Tarefa 4). Os JSON são commitados. Regenerar uma área existente não pode mudar o JSON dela.
- Cada tarefa exporta seus arquivos públicos no barril `app/lib/integracoes/integracoes.dart`.
- Comandos `flutter` rodam em `app/` (`C:\src\flutter\bin` no PATH); `py` na raiz do repositório. Commits em português: `Plano 2, tarefa N: ...`.

## Review Focus

1. Planilha que encolheu (registro excluído, venda desfeita, linhas a mais coladas à mão): a gravação limpa os valores das linhas que sobraram nas colunas do esquema, sem apagar linhas, sem tocar colunas à direita nem a formatação, igual ao Python. Teste: `escrever sem endRowIndex: as linhas que sobram são limpas` (Tarefa 9, casos `escrever_encolheu` e `escrever_vazio`).
2. Rajada de 429 do Yahoo ao atualizar radar e carteira: espera e repete; persistindo, `LimiteConsultas` com a mensagem do Python; o preço já conhecido não some. Testes: `429 repete com as esperas e devolve a última resposta` (Tarefa 2) e `mantém o preço anterior quando a consulta falha` (Tarefa 5).
3. Rede caindo no meio de qualquer chamada (DNS, TLS, tempo esgotado, conexão recusada): o usuário nunca vê "Exception:" nem "SocketException"; Yahoo mostra "Sem conexão com a internet.", Google fica offline sem apagar o token. Testes: `falhas de transporte viram ErroConexao` (Tarefa 2) e `sem rede na renovação → Offline e token.json intacto` (Tarefa 7).
4. Login no Android com o app em segundo plano quando o Google redireciona, e o navegador pedindo `/favicon.ico` ao servidor loopback: a espera continua, a troca do código repete a cada 2 s até o prazo. Testes: `favicon.ico recebe 404 e o login continua esperando` e `troca do código sem rede repete a cada 2 s` (Tarefa 8).
5. Arquivo local com NaN/Infinity (relido pelo `jsonPythonDecode` do plano 1) chegando à planilha: a sincronização termina com status erro e mensagem, nada é enviado e não há exceção não tratada. Testes: `json com NaN → ErroGoogle sem nenhum pedido` (Tarefa 7) e `escrever com NaN não envia nada` (Tarefa 10).

## Verificação do `escrever` sem `endRowIndex` (spec §6.1)

Verificado na documentação oficial da API Sheets v4 (developers.google.com, em 01/11/2026):
- `UpdateCellsRequest.range`: "The range to write data to. If the data in rows does not cover the entire requested range, the fields matching those set in `fields` will be cleared." (página `spreadsheets/request`).
- `GridRange`: "Missing indexes indicate the range is unbounded on that side." Exemplo da própria página: `Sheet1!A5:B == sheetId: 123456, startRowIndex: 4, startColumnIndex: 0, endColumnIndex: 2` (página `spreadsheets/other`).

Conclusão: o pedido do Python (google_sync.py:419-422) tem `startRowIndex: 1`, `startColumnIndex: 0`, `endColumnIndex: n` e nenhum `endRowIndex`, com `fields: "userEnteredValue"`. O intervalo vai da linha 2 até o fim da grade, nas colunas A até a n-ésima. Tudo o que `rows` não cobre nesse intervalo tem o `userEnteredValue` apagado: as linhas que sobraram de uma gravação anterior e as células finais de uma linha mais curta (`celula` devolve `{}` para vazio). As linhas não são removidas (a grade só cresce, por `appendDimension`), a formatação e as faixas alternadas ficam, e colunas além de n não são tocadas. O Dart reproduz o mesmo efeito enviando o mesmo pedido, campo por campo, conferido contra o pedido que o Python monta (Tarefas 9 e 10). Confirmação em planilha real fica para o teste manual da pré-release (plano 4).

## Decisões registradas

- **Inteiros do chart (nota do plano 1):** o Yahoo pode mandar preço inteiro (`35` no JSON). O `_dados_api` do Python guarda os valores crus e faz `sum(cl)` e `sum(trs[:n])`, que no 3.12 somam inteiros sem compensação. Decisão: preservar o tipo do JSON e portar o `sum()` misto (`somaPythonNum`), usado na média e no ATR do `dadosAtivoDeChart` (Tarefa 3). As outras funções do Python (`historico_desde`, `barras_diarias`, `grafico`, `cotacao`, `fechamento`) já convertem com `float()`, então não mudam.
- **429:** o Python não repete. O spec pede repetição: até 2 repetições no Yahoo, esperando o `Retry-After` (segundos, limitado a 30 s) ou 2 s e depois 5 s; persistindo, `LimiteConsultas`. Notícias, Google e GitHub não repetem (o erro de um ativo não apaga as notícias antigas dele, `aplicarBusca`).
- **Concorrência:** no máximo 3 pedidos simultâneos ao Yahoo (o Python serializava `dados` com uma trava); notícias e prévias no máximo 4 (o `enriquecer` do Python usa 4 threads).
- **Token:** o `token.json` continua no formato authorized_user do google-auth, lido e gravado pelo Dart. A importação do token antigo é só copiar o arquivo (plano 4), sem conversão. A margem de renovação é a do google-auth (`REFRESH_THRESHOLD` = 3 min 45 s).
- **Renovação com 5xx/429 do Google:** no Python vira `RefreshError` → `LoginNecessario` → o app apaga o token. Decisão: só 400/401 contam como sessão expirada; 5xx e 429 viram `Offline` (token preservado).
- **Página sem charset:** o requests decodifica `text/html` sem charset como ISO-8859-1 (acentos quebrados). Decisão: charset do cabeçalho quando houver, senão UTF-8 tolerante.
- **RSS malformado:** no Windows o Python usa ElementTree e falha o ativo; no Android (sem pyexpat) usa a leitura por expressões regulares. Decisão: XML primeiro; se o parser falhar, a leitura por expressões regulares (a do Android).
- **Entidades HTML:** `html.unescape` do Python 3.12 portado com a tabela HTML5 gerada do próprio Python (`html.entities.html5`, 2231 entradas) em um arquivo Dart gerado. Assim não depende do `html_unescape` (exige SDK < 3.0) nem do `package:html`.
- **Asset `credentials.json`:** `app/assets/google/credentials.json`, fora do git (o `.gitignore` da raiz já ignora `credentials.json` em qualquer pasta); a pasta é declarada no `pubspec.yaml` com um `.gitkeep`. O CI do plano 4 grava o arquivo a partir do segredo `GOOGLE_CREDENTIALS`.
- **Versão:** `app/lib/versao.dart` com `const versaoApp = '2.0.0';`, sobrescrito pelo CI do plano 4 a partir da tag.

---

### Task 1: Base das integrações (dependências, versão, executor e regras)

**Files:**
- Modify: `app/pubspec.yaml` (dependências; `flutter: assets: - assets/google/`)
- Create: `app/assets/google/.gitkeep`, `app/lib/versao.dart`, `app/lib/integracoes/integracoes.dart`, `app/lib/integracoes/executor.dart`
- Test: `app/test/integracoes/regras_test.dart`, `app/test/integracoes/executor_test.dart`, `app/test/versao_test.dart`

**Interfaces:**
- Consumes: nada.
- Produces:
  - `const String versaoApp = '2.0.0';` (`lib/versao.dart`)
  - `typedef Executar = Future<R> Function<R>(FutureOr<R> Function() tarefa);`
  - `Future<R> executarEmIsolate<R>(FutureOr<R> Function() tarefa)` (chama `Isolate.run`) e `Future<R> executarDireto<R>(FutureOr<R> Function() tarefa)` (para testes).
  - Barril `package:calculadoradarf/integracoes/integracoes.dart`.

- [ ] **Step 1: Adicionar as dependências (em `app/`)**

Run: `flutter pub add http:1.6.0 crypto:3.0.7 xml:6.6.1 image:4.12.0`
Expected: `Changed N dependencies!`. Conferir no `pubspec.yaml` as versões exatas, sem `^`. Se a resolução falhar por conflito com o SDK, parar e reportar (não trocar de pacote).

- [ ] **Step 2: Escrever os testes que falham**

`regras_test.dart` (mesmo estilo de `test/nucleo/regras_test.dart`):
```dart
test('integracoes não importa widgets, material, cupertino nem dart:ui', ...);
test('package:flutter só em google/credenciais_asset.dart e só services.dart', ...);
test('integracoes não usa .sort( nem .round(', ...);
test('núcleo não importa integracoes', ...);   // nenhum arquivo de lib/nucleo contém 'integracoes/'
```
`executor_test.dart`:
```dart
test('executarEmIsolate devolve o resultado e propaga a exceção', () async {
  expect(await executarEmIsolate(() => 2 + 3), 5);
  expect(() => executarEmIsolate<int>(() => throw const FormatException('x')), throwsFormatException);
});
test('executarDireto roda na hora', () async => expect(await executarDireto(() => 'a'), 'a'));
```
`versao_test.dart`: `expect(RegExp(r'^\d+\.\d+\.\d+$').hasMatch(versaoApp), isTrue); expect(versaoApp, '2.0.0');`

- [ ] **Step 3: Rodar e ver falhar**

Run: `flutter test test/integracoes test/versao_test.dart`
Expected: FAIL (arquivos não existem).

- [ ] **Step 4: Criar `versao.dart`, `executor.dart`, o barril (exportando `executor.dart`) e `assets/google/.gitkeep`; declarar a pasta de assets no `pubspec.yaml`**

- [ ] **Step 5: Conferir que a credencial fica fora do git**

Run (raiz): `git check-ignore app/assets/google/credentials.json`
Expected: imprime o caminho (ignorado).

- [ ] **Step 6: Rodar testes e análise**

Run: `flutter test test/integracoes test/versao_test.dart test/nucleo/regras_test.dart` e `flutter analyze`
Expected: `All tests passed!` e `No issues found!`.

- [ ] **Step 7: Commit**

```bash
git add app/pubspec.yaml app/pubspec.lock app/assets/google/.gitkeep app/lib/versao.dart app/lib/integracoes app/test/integracoes app/test/versao_test.dart
git commit -m "Plano 2, tarefa 1: dependências, versão, executor e regras das integrações"
```

---

### Task 2: Cliente HTTP base

Porta o comportamento comum de `requests.get(..., headers=UA, timeout=...)`, `raise_for_status` e do tratamento de 429 (mercado.py:105-116, noticias.py:198-204, google_sync.py:264-280), mais a repetição e o limite que o spec pede.

**Files:**
- Create: `app/lib/integracoes/http/erros.dart`, `app/lib/integracoes/http/semaforo.dart`, `app/lib/integracoes/http/cliente.dart`, `app/lib/integracoes/http/json.dart`
- Create (apoio de teste): `app/test/integracoes/apoio/cliente_falso.dart`
- Test: `app/test/integracoes/http/cliente_test.dart`, `app/test/integracoes/http/semaforo_test.dart`

**Interfaces:**
- Consumes: `ErroConexao`, `LimiteConsultas`, `ErroNucleo`, `mensagemErro` (núcleo); `Executar` (Tarefa 1).
- Produces:
  - `class ErroHttp extends ErroNucleo { ErroHttp(this.status, String mensagem); final int status; }`
  - `void conferirStatus(int status, Uri url, {String? motivo})`: 429 → `LimiteConsultas('Too Many Requests')`; ≥ 400 → `ErroHttp` com o texto do requests (Global Constraints); senão nada.
  - `class Semaforo { Semaforo(int maximo); Future<T> usar<T>(Future<T> Function() acao); int get emUso; }`
  - `typedef Esperar = Future<void> Function(Duration duracao);` e `const esperas429 = [Duration(seconds: 2), Duration(seconds: 5)];` (a última se repete se houver mais tentativas).
  - `class ClienteHttp { ClienteHttp(http.Client cliente, {String? userAgent, Map<String, String> cabecalhos = const {}, Duration tempoLimite = const Duration(seconds: 20), int? maxSimultaneas, int repeticoes429 = 0, Esperar? esperar}); Future<http.Response> enviar(String metodo, Uri url, {Map<String, String>? cabecalhos, Object? corpo, Duration? tempoLimite}); Future<RespostaContinua> abrir(String metodo, Uri url, {Map<String, String>? cabecalhos, Duration? tempoLimite}); void fechar(); }` — `corpo`: `String`, `Map<String, String>` (formulário) ou `List<int>`. Não lança por status: quem chama decide (cada função do Python trata status de um jeito).
  - `class RespostaContinua { final int status; final String? motivo; final Map<String, String> cabecalhos; final Uri urlFinal; final Stream<List<int>> blocos; }` — `urlFinal` vem de `BaseResponseWithUrl` quando a resposta tem (IOClient segue redirecionamentos), senão é a URL pedida; cada bloco também respeita o tempo limite.
  - `const limiteJsonDireto = 64 * 1024;` e `Future<Object?> decodificarJson(List<int> corpo, Executar executar)` (UTF-8 + `jsonDecode`; acima do limite, via `executar`).
  - Apoio de teste: `class PedidoGravado { String metodo; Uri url; Map<String, String> cabecalhos; List<int> corpo; String get texto; Object? get json; Map<String, String> get formulario; }`, `class RespostaFalsa { RespostaFalsa(int status, {Object? json, String? texto, List<int>? bytes, List<List<int>>? blocos, Map<String, String> cabecalhos = const {}, Uri? urlFinal, Duration atraso = Duration.zero, Object? erro, String? motivo}); }`, `class ClienteFalso extends http.BaseClient { ClienteFalso(FutureOr<RespostaFalsa> Function(PedidoGravado) responder); ClienteFalso.fila(List<RespostaFalsa> respostas); final List<PedidoGravado> pedidos; int get maxSimultaneos; }` — devolve `StreamedResponseV2` quando `urlFinal` é dado; `erro` é lançado no lugar da resposta; `atraso` segura a resposta.

- [ ] **Step 1: Escrever os testes que falham**

```dart
test('envia User-Agent e cabeçalhos extras', ...);                    // pedidos[0].cabecalhos['user-agent'] == 'Mozilla/5.0'
test('falhas de transporte viram ErroConexao', () async {             // SocketException, ClientException, HandshakeException, TimeoutException
  for (final erro in [...]) {
    final e = await capturar(() => cliente(RespostaFalsa(0, erro: erro)).enviar('GET', url));
    expect(e, isA<ErroConexao>());
    expect(mensagemErro(e), 'Sem conexão com a internet.');
  }
});
test('resposta mais lenta que o tempo limite vira ErroConexao', ...);   // atraso 200 ms, tempoLimite 50 ms
test('429 repete com as esperas e devolve a última resposta', () async {
  // repeticoes429: 2, fila [429, 429, 200] -> status 200; esperas gravadas == [2 s, 5 s]
});
test('429 com Retry-After: 3 espera 3 s; Retry-After: 120 espera 30 s', ...);
test('conferirStatus: 429 persistente vira LimiteConsultas', () {
  final e = capturarSinc(() => conferirStatus(429, url));
  expect(e, isA<LimiteConsultas>()); expect(e.toString(), 'Too Many Requests');
  expect(mensagemErro(e), 'Limite de consultas do Yahoo atingido. Tente em alguns minutos.');
});
test('conferirStatus: 404 e 500 com o texto do requests', () {
  // 'https://x.com/a?b=1', motivo 'Not Found' -> '404 Client Error: Not Found for url: https://x.com/a?b=1'
  // 500, motivo 'Internal Server Error' -> '500 Server Error: Internal Server Error for url: ...'
});
test('abrir: blocos em fluxo, cabeçalhos e urlFinal', ...);
test('abrir: bloco mais lento que o tempo limite vira ErroConexao', ...);
test('decodificarJson preserva int e double', () async {
  final j = await decodificarJson(utf8.encode('{"a": 35, "b": 35.0}'), executarDireto) as Map;
  expect(j['a'], isA<int>()); expect(j['b'], isA<double>());
});
test('decodificarJson acima de 64 KiB passa pelo executar', ...);       // executar falso conta chamadas
```
`semaforo_test.dart`: `test('10 tarefas com máximo 3 nunca passam de 3 ao mesmo tempo', ...)` e `test('exceção libera a vaga', ...)`.

- [ ] **Step 2: Rodar e ver falhar**

Run: `flutter test test/integracoes/http`
Expected: FAIL (tipos não definidos).

- [ ] **Step 3: Implementar `erros.dart`, `semaforo.dart`, `cliente.dart`, `json.dart` e o apoio `cliente_falso.dart`**

Tempo limite: `http.AbortableRequest` com `abortTrigger` que completa no prazo, mais `.timeout()` no envio e em cada bloco; `TimeoutException` e `RequestAbortedException` viram `ErroConexao`. O semáforo envolve o pedido inteiro, incluindo as esperas de 429. `motivo` = `reasonPhrase` (vazio se nulo).

- [ ] **Step 4: Rodar e ver passar**

Run: `flutter test test/integracoes/http` e `flutter analyze`
Expected: `All tests passed!`, `No issues found!`.

- [ ] **Step 5: Commit**

```bash
git add app/lib/integracoes app/test/integracoes
git commit -m "Plano 2, tarefa 2: cliente HTTP com tempo limite, 429, concorrência e erros do núcleo"
```

---

### Task 3: Inteiros do chart do Yahoo no núcleo (`sum()` misto do Python)

Fecha a nota do plano 1 sobre `somaPython` (mercado.py:347-362, 22-31; CPython 3.12 `builtin_sum_impl`).

**Files:**
- Modify: `app/lib/nucleo/compat/numeros.dart` (nova `somaPythonNum`), `app/lib/nucleo/mercado/indicadores.dart` (`calcularAtr` aceita `List<num>`), `app/lib/nucleo/mercado/chart.dart` (`dadosAtivoDeChart` guarda os valores crus)
- Create: `ferramentas/referencias/soma_mista.py`, `ferramentas/referencias/yahoo_inteiros.py`
- Create (gerado): `app/test/referencias/soma_mista.json`, `app/test/referencias/yahoo_inteiros.json`
- Test: `app/test/nucleo/compat/soma_mista_test.dart`, `app/test/nucleo/yahoo_inteiros_test.dart`

**Interfaces:**
- Consumes: `carregarCasos`, `conferir` (apoio do plano 1); `dadosAtivoDeChart` (núcleo).
- Produces: `num somaPythonNum(Iterable<num> valores)` (devolve `int` quando todos são `int`); `double? calcularAtr(List<num> maximas, List<num> minimas, List<num> fechamentos, [int n = 14])` (mesma assinatura de antes, alargada).

- [ ] **Step 1: Gerar as referências**

`soma_mista.py`: com `random.Random(7)`, 400 listas de 0 a 40 itens misturando `int` (−10⁶ a 10⁶) e `float` (inclusive frações como 0.1, 1e-9, 1e16), mais os fixos `[]`, `[30, 31]`, `[0.1]*10`, `[1, 0.1, 0.2, 2, 0.3]`, `[0.1, 1, 1e16, 1, -1e16]`; saída `sum(lista)` com o tipo do Python. `yahoo_inteiros.py`: 30 respostas sintéticas de chart (como `yahoo.py` monta para `dados_api`, com `mk._get_chart` trocado e `time.time` congelado em `AGORA`) em que `high`/`low`/`close` e `regularMarketPrice` têm inteiros misturados a floats; saída = dict de `_dados_api`.

Run: `py -3.12 ferramentas/gerar_referencias.py soma_mista yahoo_inteiros`
Expected: `soma_mista: 405 casos`, `yahoo_inteiros: 30 casos`.

- [ ] **Step 2: Escrever os testes que falham**

```dart
for (final caso in carregarCasos('soma_mista')) {
  test('sum misto: ${caso.nome}', () {
    final atual = somaPythonNum((caso.entrada! as List).cast<num>());
    conferir(atual, caso.saida);
    expect(atual is int, caso.saida is int);       // int só quando o Python devolve int
  });
}
for (final caso in carregarCasos('yahoo_inteiros')) {
  test('dados_api com inteiros: ${caso.nome}', () { /* dadosAtivoDeChart(..., hora: 1761000000.123).toJson() == saida */ });
}
```

- [ ] **Step 3: Rodar e ver falhar**

Run: `flutter test test/nucleo/compat/soma_mista_test.dart test/nucleo/yahoo_inteiros_test.dart`
Expected: FAIL (`somaPythonNum` não definida; casos com inteiros divergem no último bit).

- [ ] **Step 4: Implementar**

`somaPythonNum` segue o 3.12 (fase inteira exata; na primeira parcela `double`, `f = i.toDouble() + x`; depois, `double` com Neumaier e `int` somado sem compensação):
```dart
var i = 0; var f = 0.0; var c = 0.0; var real = false;
for (final x in valores) {
  if (!real) { if (x is int) { i += x; continue; } real = true; f = i.toDouble() + x; continue; }
  if (x is double) { final t = f + x; c += f.abs() >= x.abs() ? (f - t) + x : (x - t) + f; f = t; }
  else { f += x.toDouble(); }
}
if (!real) return i;
return (c != 0.0 && c.isFinite) ? f + c : f;
```
`calcularAtr`: `trs` como `num` (`maxPython` aceita `num`) e `somaPythonNum(trs.take(n)) / n`. `dadosAtivoDeChart`: `hi`, `lo`, `cl` como `List<num>` crus; `media = somaPythonNum(cl) / cl.length`; `min6m`/`max6m`/`anteriorDe` recebem os valores convertidos com `toDouble()` (o valor é o mesmo).

- [ ] **Step 5: Rodar a suíte inteira do núcleo**

Run: `flutter test test/nucleo` e `flutter analyze`
Expected: `All tests passed!` (inclusive `yahoo.json`, `mercado.json` e `sugestoes.json` do plano 1, que provam que o caso só-double não mudou).

- [ ] **Step 6: Commit**

```bash
git add app/lib/nucleo ferramentas/referencias/soma_mista.py ferramentas/referencias/yahoo_inteiros.py app/test/referencias/soma_mista.json app/test/referencias/yahoo_inteiros.json app/test/nucleo
git commit -m "Plano 2, tarefa 3: sum() misto do Python para preços inteiros do chart do Yahoo"
```

---

### Task 4: Yahoo, interpretação sem rede e rede falsa do gerador

Porta a parte sem rede de `cotacao` (mercado.py:265-284), `fechamento` (293-325), `preco_venda` (287-291) e `grafico` (441-466), e os parâmetros de `_dados_api` (339-345).

**Files:**
- Create: `ferramentas/referencias/_rede_falsa.py`, `ferramentas/referencias/yahoo_rede.py`
- Modify: `ferramentas/gerar_referencias.py` (`areas_disponiveis` ignora módulos que começam com `_`)
- Create (gerado): `app/test/referencias/yahoo_rede.json`
- Create: `app/lib/integracoes/yahoo/interpretacao.dart`
- Test: `app/test/integracoes/yahoo/interpretacao_test.dart`

**Interfaces:**
- Consumes: `valido`, `periodosGrafico`, `DataHora`, `fmtData`, `somarDias`, `ordenadoPor`, `SemDados` (núcleo).
- Produces (Python, usado pelas Tarefas 9, 12, 13, 14 e 16): `_rede_falsa.Resposta(status=200, json=None, texto=None, conteudo=None, cabecalhos=None, url=None, motivo="OK")` com `status_code`, `content`, `text`, `json()`, `headers`, `url`, `encoding`, `iter_content(n)`, `raise_for_status()` (texto do requests) e uso como context manager; `_rede_falsa.rede(respostas) -> (context manager, pedidos)` que instala um módulo `requests` falso em `sys.modules` (`get`, `post`, `ConnectionError`, `Timeout`, `HTTPError`, `RequestException`) e grava cada pedido como `{"metodo", "url", "params": {k: [str]}, "cabecalhos", "dados", "json"}`; `_rede_falsa.sem_modulo(nome)` (faz o `import` falhar com `ImportError`, para `yfinance` e `xml.etree.ElementTree`); `_rede_falsa.google_falso()` (cria `google.auth.exceptions` com `RefreshError` e `TransportError` se não houver google-auth); `_rede_falsa.erro(e) -> {"erro": tipo, "mensagem": str(e)}` com `RuntimeError("Too Many Requests")` → `"LimiteConsultas"` e `HTTPError` → `"ErroHttp"`.
- Produces (Dart):
  - `const urlChart = 'https://query1.finance.yahoo.com/v8/finance/chart/{t}.SA';`, `const diasHistorico = 180;`, `Uri uriChart(String ticker, Map<String, String> params)`
  - `Map<String, String> paramsDados(double agora)` → `{'period1': '${agora.truncate() - 180 * 86400}', 'period2': '${agora.truncate()}', 'interval': '1d'}`
  - `Map<String, String> paramsCotacao()` → `{'range': '5d', 'interval': '1d'}`
  - `Map<String, String> paramsFechamento(String dia)` → period1 = meia-noite UTC de `dia − 10`, period2 = meia-noite UTC de `dia + 1` + 86400, interval `1d`
  - `Map<String, String> paramsGrafico(String periodo)` → `{'range', 'interval', 'includePrePost': 'false'}` de `periodosGrafico`
  - `double cotacaoDeChart(String ticker, Map<String, Object?> resultado)` → lança `SemDados('Sem cotação para $ticker.')`
  - `(double, String) fechamentoDeChart(String ticker, Map<String, Object?> resultado, String dia)` → `(preço, data real)`; sem fechamento até o dia: `SemDados('Sem fechamento de $ticker até ${fmtData(dia)}.')`
  - `class Grafico { final String ticker, periodo; final List<(int, double)> pontos; final double referencia; final int desvio; final bool intradiario; Map<String, Object?> toJson(); }` (chaves do dict do Python, `pontos` como `[[ts, v]]`)
  - `Grafico graficoDeChart(String ticker, String periodo, Map<String, Object?> resultado)` → menos de 2 pontos: `SemDados('Sem dados de $periodo para $ticker.')`; 1D: referência `previousClose`, senão `chartPreviousClose`, senão o primeiro ponto (falsos como no `or` do Python), e último ponto trocado pelo `regularMarketPrice` válido; `intradiario = intervalo.endsWith('m')`.

- [ ] **Step 1: Escrever `_rede_falsa.py` e `yahoo_rede.py` e gerar**

`yahoo_rede.py` (dentro de `sem_modulo("yfinance")`, `base.congelar()` e `rede(...)`, um `Mercado()` novo por caso): funções `cotacao`, `fechamento`, `preco_venda` (dia de hoje e dia passado; hoje = 2026-10-28) e `grafico` (os 7 períodos, 1D com e sem `previousClose`, com `regularMarketPrice` inválido); respostas 200 com resultado, 200 com `result: []`, 404, 429 e 500; saída `{"pedidos": [...], "resultado": ...}` ou `{"pedidos": [...], "erro": ..., "mensagem": ...}`; entrada `{"ticker", "dia"|"periodo", "respostas": [{"status", "json"}]}`.

Run: `py -3.12 ferramentas/gerar_referencias.py yahoo_rede` e depois `py -3.12 ferramentas/gerar_referencias.py yahoo mercado` seguido de `git diff --exit-code app/test/referencias/yahoo.json app/test/referencias/mercado.json`
Expected: `yahoo_rede: N casos`; o diff das áreas antigas vazio.

- [ ] **Step 2: Escrever o teste que falha**

```dart
for (final caso in carregarCasos('yahoo_rede').where(status200ComResultado)) {
  test('${caso.funcao}: ${caso.nome}', () {
    // o pedido gravado pelo Python tem os params de paramsCotacao/paramsFechamento/paramsGrafico
    // e a saída é a da função pura correspondente (preco_venda no dia de hoje fica para a Tarefa 5)
  });
}
test('paramsDados: period1 = fim − 180·86400', () =>
    expect(paramsDados(1761000000.9), {'period1': '1745448000', 'period2': '1761000000', 'interval': '1d'}));
```

- [ ] **Step 3: Rodar e ver falhar**

Run: `flutter test test/integracoes/yahoo/interpretacao_test.dart`
Expected: FAIL.

- [ ] **Step 4: Implementar `interpretacao.dart`**

`fechamentoDeChart` ordena os pares `(data, fechamento)` com `ordenadoPor` (como o `sorted` de tuplas) e usa o `gmtoffset`, igual ao Python.

- [ ] **Step 5: Rodar e ver passar**

Run: `flutter test test/integracoes/yahoo` e `flutter analyze`
Expected: `All tests passed!`.

- [ ] **Step 6: Commit**

```bash
git add ferramentas app/test/referencias/yahoo_rede.json app/lib/integracoes app/test/integracoes
git commit -m "Plano 2, tarefa 4: interpretação do chart (cotação, fechamento, gráfico) e rede falsa do gerador"
```

---

### Task 5: Serviço Yahoo (HTTP, caches, histórico das metas e cotações da carteira)

Porta `_get_chart` (mercado.py:105-116), `Mercado` (233-466, só o caminho da API, sem yfinance) e `Cotacoes` (469-509), e conecta `BuscarHistorico`/`BuscarDiarias`/`CacheDiarias` do núcleo.

**Files:**
- Create: `app/lib/integracoes/yahoo/yahoo.dart`, `app/lib/integracoes/yahoo/cotacoes.dart`
- Test: `app/test/integracoes/yahoo/yahoo_test.dart`, `app/test/integracoes/yahoo/cotacoes_test.dart`

**Interfaces:**
- Consumes: `ClienteHttp`, `conferirStatus`, `decodificarJson` (Tarefa 2); Tarefa 4 inteira; `ObterChart`, `dadosAtivoDeChart`, `historicoDesde`, `CacheDiarias`, `DadosAtivo`, `HistoricoIntradiario`, `Diarias`, `DataHora`, `ambiente`, `ordenadoPor` (núcleo).
- Produces:
  - `class ServicoYahoo { ServicoYahoo(ClienteHttp http, {CacheDiarias? cacheDiarias, Executar executar = executarEmIsolate}); static ClienteHttp clientePadrao(http.Client c);` (UA `Mozilla/5.0`, 20 s, `maxSimultaneas: 3`, `repeticoes429: 2`)
  - `Future<Map<String, Object?>> obterChart(String ticker, Map<String, String> params)` — compatível com `ObterChart`; 404 ou `result` vazio → `SemDados('Sem dados para $ticker no Yahoo Finance.')`; 429 → `LimiteConsultas`; outro erro → `ErroHttp`.
  - `Future<DadosAtivo> dados(String ticker, {String nomeConhecido = ''})` — guarda o `chart.result[0]` por ticker por 60 s (`agora − hora > 60` refaz, como o Python); `hora` do resultado = `ambiente.agora()` da chamada. `void limpar()`.
  - `Future<double> cotacao(String ticker)`; `Future<(double, String)> fechamento(String ticker, String dia)` — 404 ou vazio → `SemDados('Sem cotação para $ticker.')`.
  - `Future<(double, String)> precoVenda(String ticker, String dia)` → `(cotação, 'Cotação atual')` se `dia >= ambiente.hoje()`, senão `(preço, 'Fechamento de ${fmtData(dataReal)}')`.
  - `Future<Grafico> grafico(String ticker, String periodo)` — cache por (ticker, período) com a validade de `periodosGrafico`.
  - `Future<HistoricoIntradiario> historico(String ticker, DataHora desde)` (é um `BuscarHistorico`); `Future<Diarias> diarias(String ticker, String desde)` (é um `BuscarDiarias`); `Future<Diarias> barrasDiarias(String ticker, {String? desde})` (sugestões, sem `desde`). }
  - `class CacheCotacoes { static const validade = 60; CacheCotacoes(Future<double> Function(String ticker) cotacao); double? preco(String ticker); List<String> pendentes(Iterable<String> tickers); bool get rodando; Future<bool> atualizar(Iterable<String> tickers); }` — `atualizar` devolve `false` na hora se nada venceu ou se já está rodando; senão busca um a um, mantém o preço anterior quando a consulta falha e devolve `true` ao terminar.

- [ ] **Step 1: Escrever os testes que falham**

```dart
for (final caso in carregarCasos('yahoo_rede')) {
  test('repetição do Python: ${caso.funcao} ${caso.nome}', () async {
    // ClienteFalso.fila com as respostas do caso; mesmos pedidos (URL sem query + params) e mesma saída/erro
  });
}
test('dados: cache de 60 s por ticker', ...);           // agora t, t+60 -> 1 pedido; t+61 -> 2 pedidos; hora == agora da chamada
test('dados: period1 = fim − 180·86400 e interval 1d', ...);
test('limpar esvazia o cache de dados', ...);
test('grafico: cache de 60 s no 1D e 3600 s no 5A', ...);
test('historico e diarias chegam ao HTTP com os params de historicoDesde e rangeDiarias', ...);
test('429 três vezes: LimiteConsultas e mensagemErro do Yahoo', ...);   // esperar falso; 3 pedidos
test('8 dados ao mesmo tempo: no máximo 3 pedidos abertos', ...);
test('404 → SemDados("Sem dados para PETR4 no Yahoo Finance.")', ...);
test('preco do chart inteiro chega como int ao dadosAtivoDeChart', ...); // corpo '"regularMarketPrice": 35'
```
`cotacoes_test.dart`:
```dart
test('mantém o preço anterior quando a consulta falha', ...);   // 1ª ok 10.5; 2ª (t+61) lança LimiteConsultas -> preco == 10.5
test('pendentes: só os vencidos há mais de 60 s, em ordem alfabética, sem repetir', ...);
test('chamada durante outra em andamento devolve false', ...);
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `flutter test test/integracoes/yahoo`
Expected: FAIL.

- [ ] **Step 3: Implementar `yahoo.dart` e `cotacoes.dart`**

Corpo do chart decodificado com `decodificarJson` (preserva `int`). `cotacao` e `fechamento` usam um caminho interno com a mensagem própria de 404/vazio. `ambiente` é o relógio dos caches.

- [ ] **Step 4: Rodar e ver passar**

Run: `flutter test test/integracoes/yahoo` e `flutter analyze`
Expected: `All tests passed!`.

- [ ] **Step 5: Commit**

```bash
git add app/lib/integracoes app/test/integracoes
git commit -m "Plano 2, tarefa 5: serviço Yahoo com caches, histórico das metas e cotações da carteira"
```

---

### Task 6: Google, erros, credenciais e token

Porta `SCOPES`/`SHEETS`/`DRIVE` (google_sync.py:4-11), os erros (48-63), `caminho_credencial` (86-91), a leitura do cliente (`login_navegador`, 166-167) e o formato/renovação do token (`carregar_token`, 104-129; google-auth `Credentials.to_json`/`from_authorized_user_info`).

**Files:**
- Create: `app/lib/integracoes/google/constantes.dart`, `app/lib/integracoes/google/erros.dart`, `app/lib/integracoes/google/credenciais.dart`, `app/lib/integracoes/google/credenciais_asset.dart`, `app/lib/integracoes/google/token.dart`
- Test: `app/test/integracoes/google/credenciais_test.dart`, `app/test/integracoes/google/token_test.dart`

**Interfaces:**
- Consumes: `ClienteHttp` (Tarefa 2); `Armazenamento`, `ErroNucleo`, `ambiente` (núcleo).
- Produces:
  - `const escoposGoogle = ['https://www.googleapis.com/auth/drive.file', 'https://www.googleapis.com/auth/drive.metadata.readonly', 'https://www.googleapis.com/auth/spreadsheets.readonly'];`, `const urlSheets = 'https://sheets.googleapis.com/v4/spreadsheets';`, `const urlDrive = 'https://www.googleapis.com/drive/v3';`
  - `class ErroGoogle extends ErroNucleo { ErroGoogle([String mensagem = '', this.status = 0]); final int status; }`; `class SemCredencial extends ErroGoogle`, `class LoginNecessario extends ErroGoogle`, `class Offline extends ErroGoogle` (mesmos construtores).
  - `class ClienteOAuth { final String clientId, clientSecret, authUri, tokenUri; factory ClienteOAuth.deTexto(String texto); }` — tira o BOM; usa `installed`, senão `web`, senão a raiz; `client_secret` ausente vira `''`; JSON inválido ou sem `client_id`/`auth_uri`/`token_uri` → `SemCredencial('Arquivo credentials.json não encontrado.')`.
  - `const caminhoCredenciais = 'assets/google/credentials.json';` e `Future<ClienteOAuth> carregarClienteOAuth([AssetBundle? pacote])` (padrão `rootBundle`; asset ausente → `SemCredencial('Arquivo credentials.json não encontrado.')`).
  - `const arquivoToken = 'token.json';`, `const margemRenovacao = 225;` (segundos)
  - `class TokenGoogle { String? token; String? refreshToken; String tokenUri; String clientId; String clientSecret; List<String> scopes; DateTime? expiry; factory TokenGoogle.fromJson(Map<String, Object?> json); Map<String, Object?> toJson(); bool valido(double agora); }` — `fromJson` exige `refresh_token`, `client_id` e `client_secret` (senão `LoginNecessario('Faça login com o Google.')`), lê `expiry` como o google-auth (`rstrip("Z").split(".")[0]`, `%Y-%m-%dT%H:%M:%S`, UTC) e `scopes` em lista ou texto separado por espaço; `toJson` grava as chaves `token, refresh_token, token_uri, client_id, client_secret, scopes, universe_domain, account, expiry` nessa ordem, sem nulos, `universe_domain`/`account` preservados (padrão `'googleapis.com'`/`''`), `expiry` como `AAAA-MM-DDTHH:MM:SS[.ffffff]Z`; `valido`: `token != null` e (`expiry == null` ou `agora < expiry − 225 s`).
  - `TokenGoogle? lerToken(Armazenamento a)` (`null` sem arquivo; JSON inválido → `LoginNecessario('Faça login com o Google.')`), `void gravarToken(Armazenamento a, TokenGoogle t)`.
  - `Future<TokenGoogle> renovarToken(ClienteHttp http, TokenGoogle t)` — POST formulário `{grant_type: refresh_token, client_id, client_secret, refresh_token}` no `tokenUri`; novo `token`, `expiry = agora + expires_in`, `refresh_token` da resposta ou o antigo; sem `refreshToken`, 400 ou 401 → `LoginNecessario('Sessão expirada. Faça login novamente.')`; `ErroConexao` → `Offline(mensagem)`; 429 e 5xx → `Offline('O Google não respondeu (HTTP <status>). Tente de novo mais tarde.')`.

- [ ] **Step 1: Escrever os testes que falham**

Token de exemplo no formato do google-auth (fixo no teste):
```json
{"token": "ya29.a", "refresh_token": "1//r", "token_uri": "https://oauth2.googleapis.com/token",
 "client_id": "c.apps.googleusercontent.com", "client_secret": "s",
 "scopes": ["https://www.googleapis.com/auth/drive.file", "https://www.googleapis.com/auth/drive.metadata.readonly",
            "https://www.googleapis.com/auth/spreadsheets.readonly"],
 "universe_domain": "googleapis.com", "account": "", "expiry": "2026-10-20T22:40:00.123456Z"}
```
```dart
test('lê o token.json do google-auth e regrava no mesmo formato', ...);   // toJson == original (mesma ordem de chaves)
test('token da 1.12 sem universe_domain/account e com scopes em texto', ...);
test('expiry sem microssegundos e sem expiry', ...);                       // sem expiry: valido == (token != null)
test('sem refresh_token, client_id ou client_secret → LoginNecessario("Faça login com o Google.")', ...);
test('JSON inválido → LoginNecessario("Faça login com o Google.")', ...);
test('valido: faltando menos de 3 min 45 s conta como vencido', ...);       // expiry − 224 s inválido; − 226 s válido
test('renovarToken: corpo do formulário e novo expiry', ...);
test('renovarToken mantém o refresh_token antigo quando a resposta não traz', ...);
test('renovarToken: 400 invalid_grant → LoginNecessario("Sessão expirada. Faça login novamente.")', ...);
test('renovarToken: sem rede → Offline; 503 → Offline', ...);
test('credenciais: installed, web, raiz e BOM', ...);
test('credenciais ausentes ou inválidas → SemCredencial("Arquivo credentials.json não encontrado.")', ...);
test('carregarClienteOAuth lê do AssetBundle; asset ausente → SemCredencial', ...);   // AssetBundle falso
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `flutter test test/integracoes/google`
Expected: FAIL.

- [ ] **Step 3: Implementar os cinco arquivos**

- [ ] **Step 4: Rodar e ver passar**

Run: `flutter test test/integracoes` e `flutter analyze`
Expected: `All tests passed!` (inclusive o teste de regras com o `services.dart` permitido só em `credenciais_asset.dart`).

- [ ] **Step 5: Commit**

```bash
git add app/lib/integracoes app/test/integracoes
git commit -m "Plano 2, tarefa 6: erros, credenciais e token do Google no formato do google-auth"
```

---

### Task 7: Sessão Google (pedidos autenticados, e-mail e saída)

Porta `carregar_token` (google_sync.py:104-129), `_iniciar` (246-250), `sair` (252-258), `_req` (260-280) e o refresh automático do `AuthorizedSession`.

**Files:**
- Create: `app/lib/integracoes/google/sessao.dart`
- Test: `app/test/integracoes/google/sessao_test.dart`

**Interfaces:**
- Consumes: Tarefas 2 e 6; `Armazenamento`, `ambiente`.
- Produces: `class SessaoGoogle { SessaoGoogle({required ClienteHttp http, required Armazenamento armazenamento, Executar executar = executarEmIsolate}); String? get email; bool temToken(); Future<String> carregarToken(); Future<String> iniciar(TokenGoogle token); Future<Map<String, Object?>> req(String metodo, String url, {Map<String, Object>? params, Object? json}); void sair(); }`
  - `carregarToken`: sem arquivo → `LoginNecessario('Faça login com o Google.')`; token inválido → renova (Tarefa 6) e grava `token.json`; depois `iniciar`.
  - `iniciar`: guarda o token, `GET $urlDrive/about?fields=user(emailAddress)` e devolve o e-mail em minúsculas.
  - `req`: sem token → `LoginNecessario('Faça login com o Google.')`; renova antes se `!valido`; `Authorization: Bearer`; `json` codificado antes de abrir conexão (`JsonUnsupportedObjectError`, ex.: NaN → `ErroGoogle('Há um valor inválido (NaN ou infinito) nos dados; nada foi enviado ao Google.')`); 401 → renova e repete uma vez; 401 de novo → `LoginNecessario('Sessão expirada. Faça login novamente.')`; ≥ 400 → `ErroGoogle(error.message do JSON, ou os 300 primeiros caracteres do texto, status)`; `ErroConexao` → `Offline`; corpo vazio → `{}`; corpo decodificado com `decodificarJson`. `params`: valores `String`, `int` ou `List<String>` (lista repete a chave, como o requests). Tempo limite 30 s.
  - `sair`: apaga `token.json`, esquece token e e-mail.

- [ ] **Step 1: Escrever os testes que falham**

```dart
test('carregarToken sem arquivo → LoginNecessario("Faça login com o Google.")', ...);
test('token válido: só o GET do about; e-mail em minúsculas; Bearer no cabeçalho', ...);
test('token vencido: renova, grava token.json novo e então pede o about', ...);
test('sem rede na renovação → Offline e token.json intacto', ...);          // Review Focus 3
test('req: 401 renova e repete uma vez; 401 de novo → LoginNecessario("Sessão expirada. Faça login novamente.")', ...);
test('req: 400 com JSON usa error.message; 500 em texto usa os 300 primeiros caracteres; status preservado', ...);
test('req: SocketException → Offline', ...);
test('json com NaN → ErroGoogle sem nenhum pedido', ...);                    // Review Focus 5; pedidos vazio
test('req: params com lista repetem a chave', ...);                         // ranges=a&ranges=b
test('sair apaga token.json e esquece o e-mail', ...);
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `flutter test test/integracoes/google/sessao_test.dart`
Expected: FAIL.

- [ ] **Step 3: Implementar `sessao.dart`**

- [ ] **Step 4: Rodar e ver passar**

Run: `flutter test test/integracoes/google` e `flutter analyze`
Expected: `All tests passed!`.

- [ ] **Step 5: Commit**

```bash
git add app/lib/integracoes app/test/integracoes
git commit -m "Plano 2, tarefa 7: sessão Google com renovação automática e erros do Python"
```

---

### Task 8: Login no navegador com PKCE e loopback

Porta `login_navegador` (google_sync.py:148-244) para Windows e Android.

**Files:**
- Create: `app/lib/integracoes/google/login.dart`
- Test: `app/test/integracoes/google/login_test.dart`

**Interfaces:**
- Consumes: `ClienteOAuth`, `TokenGoogle`, `gravarToken`, `escoposGoogle`, erros (Tarefa 6); `SessaoGoogle.iniciar` (Tarefa 7); `ClienteHttp`, `Esperar` (Tarefa 2); `ambiente`.
- Produces:
  - `typedef AbrirUrl = Future<void> Function(Uri url);` (no app, `url_launcher`, plano 3)
  - `({String verificador, String desafio}) gerarPkce([Random? aleatorio])` — 64 bytes aleatórios em base64url sem `=` (86 caracteres, como `secrets.token_urlsafe(64)`); `String desafioPkce(String verificador)` = base64url(sha256(ascii)) sem `=`.
  - `Uri urlAutorizacao(ClienteOAuth cliente, {required String redirect, required String desafio, required String estado})` — `auth_uri` + query na ordem `client_id, redirect_uri, response_type=code, scope` (escopos separados por espaço), `access_type=offline, prompt=consent, code_challenge, code_challenge_method=S256, state`.
  - `const paginaLoginConcluido` = o HTML literal de google_sync.py:178-179.
  - `Future<String> loginNavegador(SessaoGoogle sessao, ClienteOAuth cliente, ClienteHttp http, AbrirUrl abrirUrl, {Duration tempoLimite = const Duration(seconds: 600), Esperar? esperar})` — `HttpServer.bind(InternetAddress.loopbackIPv4, 0)`; redirect `http://127.0.0.1:<porta>/`; caminho sem `code=` nem `error=` → 404 e continua; com eles → 200 `text/html; charset=utf-8` com a página e para de esperar; estado = 16 bytes base64url. Erros: tempo esgotado ou sem retorno → `ErroGoogle('O login não foi concluído.')`; `error=access_denied` → `ErroGoogle('O login foi cancelado.')`; outro `error` → `ErroGoogle('O login não foi concluído: <error>')`; `state` diferente ou sem `code` → `ErroGoogle('O login não foi concluído.')`. Troca do código: POST formulário `{code, client_id, client_secret, redirect_uri, grant_type: authorization_code, code_verifier}` no `token_uri` (30 s); `ErroConexao` → espera 2 s e repete enquanto `ambiente.agora()` < prazo, depois `Offline`; status ≥ 400 ou sem `access_token` → `ErroGoogle('O login não foi concluído: <error_description ou error ou status>')`. Token: `expiry = agora + expires_in (padrão 3600) − 60`, `scopes = escoposGoogle`; grava `token.json`; `sessao.iniciar` com a mesma repetição em `Offline` até o prazo; devolve o e-mail. O servidor é fechado em qualquer saída.

- [ ] **Step 1: Escrever os testes que falham**

```dart
test('desafio PKCE do RFC 7636', () => expect(
    desafioPkce('dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk'), 'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM'));
test('gerarPkce: verificador de 86 caracteres base64url sem "="', ...);
test('URL de autorização com os parâmetros do Python', ...);       // queryParameters == mapa esperado; scheme/host/path do auth_uri
test('fluxo completo: recebe o código em 127.0.0.1, troca e devolve o e-mail', ...);
  // abrirUrl falso faz GET (dart:io HttpClient) em redirect_uri?code=abc&state=<estado>; resposta 200 contém 'Login concluído';
  // formulário da troca == mapa esperado; token.json gravado com expiry = agora + expires_in − 60
test('favicon.ico recebe 404 e o login continua esperando', ...);  // Review Focus 4
test('error=access_denied → "O login foi cancelado."', ...);
test('error=invalid_scope → "O login não foi concluído: invalid_scope"', ...);
test('state errado → "O login não foi concluído."', ...);
test('sem retorno no tempo limite → "O login não foi concluído." e porta liberada', ...);   // tempoLimite 200 ms
test('troca do código sem rede repete a cada 2 s', ...);            // Review Focus 4; 2 SocketException e depois 200; esperas == [2 s, 2 s]
test('troca sem rede até o prazo → Offline', ...);                  // esperar falso avança o relógio do ambiente
test('token endpoint 400 → "O login não foi concluído: Bad Request"', ...);   // error_description do corpo
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `flutter test test/integracoes/google/login_test.dart`
Expected: FAIL.

- [ ] **Step 3: Implementar `login.dart`**

- [ ] **Step 4: Rodar e ver passar**

Run: `flutter test test/integracoes/google` e `flutter analyze`
Expected: `All tests passed!`.

- [ ] **Step 5: Commit**

```bash
git add app/lib/integracoes app/test/integracoes
git commit -m "Plano 2, tarefa 8: login Google no navegador com PKCE S256 e loopback"
```

---

### Task 9: Pedidos da planilha (sem rede) e referências do Google

Porta a montagem dos corpos de `buscar_planilha` (google_sync.py:282-289), `criar_planilha` (300-313), `_garantir_abas` (315-334), `_formatar` (336-393), `escrever` (395-425) e `ler` (427-441), usando `esquemaAbas` e `celula` do núcleo.

**Files:**
- Create: `ferramentas/referencias/google_pedidos.py`
- Create (gerado): `app/test/referencias/google_pedidos.json`
- Create: `app/lib/integracoes/google/pedidos.dart`
- Test: `app/test/integracoes/google/pedidos_test.dart`

**Interfaces:**
- Consumes: `esquemaAbas`, `esquemaDe`, `nomePlanilha`, `celula`, `Linha` (núcleo); `_rede_falsa` (Tarefa 4).
- Produces:
  - `Map<String, double> rgb(String hex)`; `String letra(int n)` (`chr(64 + n)`); `String consultaPlanilha(String dono)` (escapa `\` e `'` como o Python).
  - `class PropriedadesAba { PropriedadesAba({required this.sheetId, required this.titulo, this.linhas, this.colunas}); final int sheetId; final String titulo; final int? linhas; final int? colunas; }`
  - `Map<String, Object?> corpoCriacao()`; `Map<String, Object?> pedidoAbasFaltantes(List<String> faltando)` (`{"requests": [addSheet...]}`); `List<Map<String, Object?>> pedidosFormatacao(Map<String, int> ids)` (na ordem de `ids`); `List<Map<String, Object?>> pedidosEscrita(Map<String, PropriedadesAba> abas, Map<String, List<Linha>> dados)` (na ordem de `dados`; `rowCount` ausente vale 1000 e `columnCount` ausente vale n, como os `.get` do Python); `List<String> rangesLeitura(Map<String, int> colunasPorAba)` (abas do esquema presentes, na ordem do esquema; `"'Aba'!A2:<letra(min(n, colunas))>"`; `columnCount` ausente vale 26).
  - Saída do gerador (usada também na Tarefa 10): casos `{"funcao", "entrada": {"respostas": [{"status", "json"|"texto"}], ...argumentos}, "saida": {"pedidos": [{"metodo", "url", "params", "json"}], "resultado"|"erro"}}`.

- [ ] **Step 1: Escrever `google_pedidos.py` e gerar**

Com `_rede_falsa.google_falso()`, um `Google(pasta_tmp, pasta_tmp)` cuja `sessao` é uma sessão falsa (`request(metodo, url, timeout, params=None, json=None)`, que grava o pedido e devolve a próxima `Resposta`) e `email = "eu@exemplo.com"`. Casos: `criar_planilha`; `garantir_abas_completa`; `garantir_abas_faltando` (planilha sem Caixa, Metas e Exclusões); `escrever_simples` (as 8 abas, com `None`, `""`, `True`, `False`, `0`, `-0.0`, `0.1`, `1761000000.123`, texto com acento); `escrever_crescer` (`rowCount` 10 e 12 linhas → `appendDimension` de 203); `escrever_metas_12_colunas` (`columnCount` 12 → 2 colunas a mais e `hiddenByUser` só na coluna Detalhes); `escrever_encolheu` (menos linhas que na gravação anterior); `escrever_vazio` (Compras `[]`); `ler` (Metas com 12 colunas e linhas curtas); `ler_sem_abas`; `buscar_planilha_me`; `buscar_planilha_aspas` (dono `o'bri\en@x.com`); `buscar_planilha_nada`; `planilha_existe` (ok, `trashed`, 404, 500); `compartilhar`; `descompartilhar` (dono com o mesmo e-mail, leitor em maiúsculas, outro e-mail); `erro_401`; `erro_400_json`; `erro_500_texto`. `params` gravados como `{k: [str(v), ...]}`.

Run: `py -3.12 ferramentas/gerar_referencias.py google_pedidos`
Expected: `google_pedidos: N casos` (N ≥ 23).

- [ ] **Step 2: Escrever o teste que falha**

```dart
for (final caso in carregarCasos('google_pedidos')) {
  test('corpos do Python: ${caso.nome}', () {
    // criar_planilha: pedidos[0].json == corpoCriacao(); pedidos[1].json == {'requests': pedidosFormatacao(ids da resposta)}
    // garantir_abas_faltando: pedidos[1].json == pedidoAbasFaltantes([...]); pedidos[2] == formatação das novas
    // escrever_*: último pedido == {'requests': pedidosEscrita(props da resposta do GET, dados)}
    // ler: params['ranges'] == rangesLeitura(...); buscar_planilha_*: params['q'] == [consultaPlanilha(dono)]
  });
}
test('escrever sem endRowIndex: as linhas que sobram são limpas', () {   // Review Focus 1
  final reqs = pedidosEscrita({'Compras': PropriedadesAba(sheetId: 7, titulo: 'Compras', linhas: 1000, colunas: 13)},
                              {'Compras': []});
  final dados = reqs.last['updateCells']! as Map;
  expect(dados['range'], {'sheetId': 7, 'startRowIndex': 1, 'startColumnIndex': 0, 'endColumnIndex': 13});
  expect(dados['rows'], isEmpty); expect(dados['fields'], 'userEnteredValue');
});
```

- [ ] **Step 3: Rodar e ver falhar**

Run: `flutter test test/integracoes/google/pedidos_test.dart`
Expected: FAIL.

- [ ] **Step 4: Implementar `pedidos.dart`**

Comentário no `pedidosEscrita` citando a seção "Verificação do `escrever`" deste plano e as duas frases da documentação.

- [ ] **Step 5: Rodar e ver passar**

Run: `flutter test test/integracoes/google` e `flutter analyze`
Expected: `All tests passed!`.

- [ ] **Step 6: Commit**

```bash
git add ferramentas/referencias/google_pedidos.py app/test/referencias/google_pedidos.json app/lib/integracoes app/test/integracoes
git commit -m "Plano 2, tarefa 9: pedidos da planilha iguais aos do Python (criação, formatação, escrita, leitura)"
```

---

### Task 10: Planilha Google (Sheets e Drive)

Porta o `Google` de google_sync.py:282-456 sobre a sessão da Tarefa 7.

**Files:**
- Create: `app/lib/integracoes/google/planilha.dart`
- Test: `app/test/integracoes/google/planilha_test.dart`

**Interfaces:**
- Consumes: `SessaoGoogle` (Tarefa 7); Tarefa 9 inteira; `normalizarLeitura`, `Linha` (núcleo).
- Produces: `class PlanilhaGoogle { PlanilhaGoogle(SessaoGoogle sessao); Future<String?> buscarPlanilha([String dono = 'me']); Future<bool> planilhaExiste(String sid); Future<String> criarPlanilha(); Future<Map<String, PropriedadesAba>> garantirAbas(String sid); Future<void> escrever(String sid, Map<String, List<Linha>> dados); Future<Map<String, List<Linha>>> ler(String sid); Future<void> compartilhar(String sid, String email); Future<void> descompartilhar(String sid, String email); }` e `String linkPlanilha(String sid)` → `'https://docs.google.com/spreadsheets/d/$sid'`.
  - `buscarPlanilha`: `GET $urlDrive/files` com `q`, `fields: files(id)`, `orderBy: modifiedTime desc`, `pageSize: 5`, `spaces: drive`; primeiro id ou `null`.
  - `planilhaExiste`: 404 → `false`; `trashed` → `false`; outro erro propaga.
  - `ler`: devolve `normalizarLeitura(...)`, preservando `int`/`double`/`bool`/texto como vieram.
  - `compartilhar`: `emailMessage` = `'${sessao.email} compartilhou as operações da Calculadora DARF com você.'`; `descompartilhar` compara e-mail em minúsculas e nunca remove `owner`.

- [ ] **Step 1: Escrever os testes que falham**

```dart
for (final caso in carregarCasos('google_pedidos')) {
  test('repetição do Python: ${caso.nome}', () async {
    // ClienteFalso.fila com as respostas do caso, sessão com token válido;
    // pedidos (método, URL sem query, queryParametersAll, json) == saida['pedidos'];
    // resultado == saida['resultado'] ou erro {tipo, mensagem, status} == saida['erro']
  });
}
test('escrever com NaN não envia nada', ...);   // Review Focus 5: só o GET do garantirAbas; lança ErroGoogle; nenhum batchUpdate
test('ler preserva int, double, bool e texto', ...);
test('linkPlanilha', () => expect(linkPlanilha('abc'), 'https://docs.google.com/spreadsheets/d/abc'));
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `flutter test test/integracoes/google/planilha_test.dart`
Expected: FAIL.

- [ ] **Step 3: Implementar `planilha.dart`**

- [ ] **Step 4: Rodar e ver passar**

Run: `flutter test test/integracoes/google` e `flutter analyze`
Expected: `All tests passed!`.

- [ ] **Step 5: Commit**

```bash
git add app/lib/integracoes app/test/integracoes
git commit -m "Plano 2, tarefa 10: planilha Google (Drive e Sheets) com os pedidos do Python"
```

---

### Task 11: Fachada Google e orquestração da sincronização

Porta o ciclo de calculadora_darf.py:2736-2919 (`conectar_token`, `pos_login`, `sincronizar`, `mesclar_e_enviar`, `sync_ok`, `erro_sync`, `tick_sync`) e android/main.py:2277-2406 (`conectar_token`, `conectar`, `agendar_sync`, `_sincronizar`, `laco`), com a visão do amigo (calculadora_darf.py:2946-2956).

**Files:**
- Create: `app/lib/integracoes/google/google.dart`, `app/lib/integracoes/sincronizacao/dados_sincronizacao.dart`, `app/lib/integracoes/sincronizacao/sincronizador.dart`
- Test: `app/test/integracoes/google/google_test.dart`, `app/test/integracoes/sincronizacao/sincronizador_test.dart`

**Interfaces:**
- Consumes: Tarefas 6 a 10; `Repositorio`, `Config`, `sincronizarLinhas`, `ResultadoSincronizacao`, `reconstruir`, `DadosPlanilha`, `Linha`, `ambiente` (núcleo).
- Produces:
  - `abstract interface class ContaGoogle { String? get email; bool get temCredencial; bool temToken(); Future<String> carregarToken(); Future<String> login(AbrirUrl abrirUrl); void sair(); Future<String?> buscarPlanilha([String dono = 'me']); Future<bool> planilhaExiste(String sid); Future<String> criarPlanilha(); Future<Map<String, List<Linha>>> ler(String sid); Future<void> escrever(String sid, Map<String, List<Linha>> dados); Future<void> compartilhar(String sid, String email); Future<void> descompartilhar(String sid, String email); }`
  - `class Google implements ContaGoogle { Google({required SessaoGoogle sessao, required PlanilhaGoogle planilha, required ClienteHttp httpLogin, ClienteOAuth? cliente}); }` — `login` sem cliente → `SemCredencial('Arquivo credentials.json não encontrado.')`.
  - `abstract interface class DadosSincronizacao { Future<String?> planilhaDe(String email); Future<void> definirPlanilha(String email, String? sid); Future<bool> pendente(); Future<void> definirPendente(bool valor); Future<ResultadoSincronizacao> mesclar(Map<String, List<Linha>> abasLidas); }` e `class DadosSincronizacaoLocal implements DadosSincronizacao { DadosSincronizacaoLocal(Repositorio repo); }` (cada operação relê `repo.lerConfig()`, altera e grava com `gravarConfig`; `mesclar` chama `sincronizarLinhas`). O plano 3 implementa a mesma interface sobre o isolate do núcleo.
  - `enum StatusSync { off, login, sync, ok, pendente, offline, erro }`
  - `class Sincronizador { Sincronizador({required ContaGoogle conta, required DadosSincronizacao dados, void Function(StatusSync)? aoMudarStatus, void Function()? aoMudarDados, void Function(String)? aoAvisar, Duration atrasoAgendamento = const Duration(milliseconds: 1500)}); StatusSync get status; String get ultimoErro; double get ultimaPuxada; double? get ultimaSync; bool get rodando; Future<void> conectarComToken(); Future<void> conectar(AbrirUrl abrirUrl); Future<String> prepararPlanilha(); Future<void> sincronizar(); Future<void> agendar(); Future<void> tick(); void sair(); Future<DadosPlanilha> lerAmigo(String email); }`
    - `prepararPlanilha` (`pos_login`): planilha do e-mail; se existir e `!planilhaExiste` → esquece; senão `buscarPlanilha('me')`; senão `criarPlanilha()`; grava em `planilhas[email]`.
    - `sincronizar` (`_sincronizar` do Android): sem conta → nada; rodando → marca nova rodada e volta; status `sync`; sem planilha → `prepararPlanilha`; laço: lê → `mesclar` → `mudou` chama `aoMudarDados` → cada aviso vira `aoAvisar('Ajuste manual necessário: $texto')` → escreve as linhas; repete enquanto houve pedido novo. No fim: `definirPendente(false)`, `ultimaSync`/`ultimaPuxada` = `ambiente.agora()`, `ultimoErro = ''`, status `ok`. `LoginNecessario` → `conta.sair()`, status `off`, `aoAvisar('Sessão expirada. Conecte sua conta Google novamente.')`; `Offline` → status `offline` (pendente continua); outro erro → se `ErroGoogle` com status 404, `definirPlanilha(email, null)`; `ultimoErro = e.toString()`; status `erro`.
    - `agendar`: `definirPendente(true)`; sem conta → só isso; com conta → status `pendente` e sincroniza depois do atraso (chamadas seguidas reiniciam o atraso; uma sincronização só).
    - `tick` (`tick_sync`/`laco`): com conta, se (pendente ou `agora − ultimaPuxada > 300`) e não rodando → `sincronizar` (que prepara a planilha quando falta); sem conta e com token → `conectarComToken`.
    - `conectarComToken`: status `sync`; `carregarToken`; `Offline` → `offline`; outro erro → `conta.sair()` e `off`; ok → `prepararPlanilha` e `sincronizar`.
    - `conectar`: status `login`; erro → `off` e `aoAvisar(e.toString().isEmpty ? 'O login não foi concluído.' : e.toString())`; ok → `aoAvisar('Conectado como $email.')`, `prepararPlanilha`, `sincronizar`.
    - `lerAmigo`: sem planilha → `ErroGoogle('$email ainda não compartilhou a planilha com você. Peça para ele adicionar ${conta.email} em Amigos.')`; senão `reconstruir(await conta.ler(sid))` (o `ler` já normaliza).

- [ ] **Step 1: Escrever os testes que falham**

`ContaGoogleFalsa` no próprio teste (grava chamadas, falhas programadas, planilha em memória); dados com `DadosSincronizacaoLocal(Repositorio(ArmazenamentoMemoria()))` e `ambiente = Ambiente.fixo(...)`.
```dart
test('ciclo completo: lê, mescla e grava as linhas montadas', ...);    // escrever recebe montarLinhas(repo...); pendente false; status ok
test('sem planilha: procura a do usuário e cria se não houver; grava planilhas[email]', ...);
test('planilha do cfg apagada: procura de novo', ...);
test('pedido durante a sincronização refaz o ciclo antes de limpar pendente', ...);
test('LoginNecessario: sai da conta, status off e aviso de sessão expirada', ...);
test('Offline: status offline e pendente continua true', ...);
test('404: esquece a planilha do e-mail, status erro e ultimoErro', ...);
test('avisos da mesclagem viram "Ajuste manual necessário: ..."', ...);   // DadosSincronizacao falsa com avisos
test('mudou chama aoMudarDados', ...);
test('agendar: sem conta só marca pendente; com conta uma sincronização para várias chamadas', ...);   // atraso 20 ms
test('tick: pendente ou mais de 300 s sem puxar dispara; sem conta e com token conecta', ...);
test('conectarComToken: Offline → offline; outro erro → sair e off', ...);
test('conectar: "Conectado como x@y.com." e sincroniza; falha → off e aviso com a mensagem', ...);
test('lerAmigo sem planilha compartilhada → mensagem do Python', ...);
```
`google_test.dart`: `test('login sem credencial → SemCredencial', ...)`, `test('temCredencial reflete o cliente', ...)`.

- [ ] **Step 2: Rodar e ver falhar**

Run: `flutter test test/integracoes/sincronizacao test/integracoes/google/google_test.dart`
Expected: FAIL.

- [ ] **Step 3: Implementar os três arquivos**

- [ ] **Step 4: Rodar e ver passar**

Run: `flutter test test/integracoes` e `flutter analyze`
Expected: `All tests passed!`.

- [ ] **Step 5: Commit**

```bash
git add app/lib/integracoes app/test/integracoes
git commit -m "Plano 2, tarefa 11: fachada Google e sincronizador com o ciclo do Python"
```

---

### Task 12: Notícias, HTML (entidades, Open Graph e URL relativa)

Porta `html.unescape` do Python 3.12, `_meta` e `ler_previa` (noticias.py:363-381) e `urljoin`. Torna pública a tradução de expressões do `re` do Python que o núcleo já tem.

**Files:**
- Create: `app/lib/nucleo/compat/regex_python.dart` (move `_er`, `_palavra` e `_espaco` de `noticias/texto.dart` para `RegExp erPython(String padrao, {bool ignorarCaixa = false})`, `palavraPython`, `espacoPython`)
- Modify: `app/lib/nucleo/noticias/texto.dart` (usa `erPython`; comportamento igual), `app/lib/nucleo/nucleo.dart` (exporta)
- Create: `ferramentas/gerar_entidades_html5.py`, `app/lib/integracoes/noticias/entidades_html5.dart` (gerado), `ferramentas/referencias/noticias_rede.py`
- Create (gerado): `app/test/referencias/noticias_rede.json`
- Create: `app/lib/integracoes/noticias/html.dart`
- Test: `app/test/integracoes/noticias/html_test.dart`

**Interfaces:**
- Consumes: núcleo; `_rede_falsa` (Tarefa 4).
- Produces:
  - `RegExp erPython(String padrao, {bool ignorarCaixa = false})` (núcleo, `compat/`).
  - `const Map<String, String> entidadesHtml5` (gerado de `html.entities.html5`, chaves com e sem `;`).
  - `String unescapeHtml(String s)` — algoritmo de `html/__init__.py` do 3.12 (`_charref`, `_replace_charref`, `_invalid_charrefs`, `_invalid_codepoints`; número enorme → `\ufffd` sem estourar `int`).
  - `String metaDe(String html, List<String> nomes)` — `<meta\b[^>]*>` sem caixa; atributos `([\w:-]+)\s*=\s*(["'])(?:([^"]*)"|([^']*)')` (no Dart, `'` sem barra: o modo unicode recusa `\'`); valor da aspa dupla se a aspa for `"`, senão o da simples; primeira ocorrência de cada chave com `content` não vazio; `unescapeHtml(...).trim()` como o `strip()`.
  - `({String img, String resumo}) lerPrevia(String html, String url)` — cabeça até o primeiro `</head>`; imagem de `og:image:secure_url`, `og:image`, `twitter:image`, `twitter:image:src`; resumo de `og:description`, `twitter:description`, `description`, espaços do Python colapsados, até 600 pontos de código; `img` resolvida com `juntarUrl`.
  - `String juntarUrl(String base, String ref)` — `Uri.parse(base).resolve(ref)`; se lançar `FormatException`, `ref` quando começa com `http`, senão `''`.
  - `noticias_rede.py` (áreas desta tarefa): `unescape` (texto → `html.unescape`), `tabela_html5` (um caso com o dict inteiro), `ler_previa` (html, url → dict) e `meta` (html, nomes → texto).

- [ ] **Step 1: Gerar a tabela e as referências**

`gerar_entidades_html5.py` grava `entidades_html5.dart` (`// Gerado por ferramentas/gerar_entidades_html5.py a partir de html.entities.html5 (Python 3.12). Não editar.`), com as chaves em ordem e escapes `\u{...}`. Casos de `unescape`: `&amp; &lt; &gt; &quot; &#39; &nbsp; &aacute; &ccedil;&atilde;o &amp &ampx &notit; &#x41; &#65 &#0; &#128; &#xD800; &#1114112; &#99999999999999999999; &#xFFFE; &unknown; &` e texto sem entidade. `ler_previa`: aspas simples e duplas, `property` e `name`, primeira ocorrência vence, `content` vazio ignorado, fallback para `twitter:*`, URL relativa, `//cdn`, `/img.jpg`, descrição com quebras e `\xa0`, descrição com 700 caracteres, sem `</head>`, entidades no `content`.

Run: `py -3.12 ferramentas/gerar_entidades_html5.py` e `py -3.12 ferramentas/gerar_referencias.py noticias_rede`
Expected: arquivo Dart com 2231 entradas; `noticias_rede: N casos`.

- [ ] **Step 2: Escrever os testes que falham**

```dart
test('tabela HTML5 igual à do Python', () => expect(entidadesHtml5, casoTabela.saida));
for (final caso in casos('unescape')) test('unescape: ${caso.nome}', () => expect(unescapeHtml(caso.entrada as String), caso.saida));
for (final caso in casos('ler_previa')) test('ler_previa: ${caso.nome}', ...);
for (final caso in casos('meta')) test('meta: ${caso.nome}', ...);
```

- [ ] **Step 3: Rodar e ver falhar**

Run: `flutter test test/integracoes/noticias/html_test.dart`
Expected: FAIL.

- [ ] **Step 4: Mover `_er` para `compat/regex_python.dart` e implementar `html.dart`**

- [ ] **Step 5: Rodar núcleo e integrações**

Run: `flutter test test/nucleo test/integracoes` e `flutter analyze`
Expected: `All tests passed!` (o `noticias.json` do plano 1 prova que a mudança no núcleo não alterou a relevância).

- [ ] **Step 6: Commit**

```bash
git add app/lib/nucleo ferramentas app/test/referencias/noticias_rede.json app/lib/integracoes app/test/integracoes
git commit -m "Plano 2, tarefa 12: html.unescape do Python, prévia Open Graph e regex do Python no núcleo"
```

---

### Task 13: Notícias, leitura do RSS do Google Notícias

Porta `_itens_xml` e `ler_rss` (noticias.py:133-175), a URL de `buscar_ticker` (198-200, `quote`) e `email.utils.parsedate_to_datetime`.

**Files:**
- Modify: `ferramentas/referencias/noticias_rede.py` (funções `ler_rss`, `ler_rss_regex`, `data_rfc2822`, `url_busca`)
- Create (regerado): `app/test/referencias/noticias_rede.json`
- Create: `app/lib/integracoes/noticias/rss.dart`
- Test: `app/test/integracoes/noticias/rss_test.dart`

**Interfaces:**
- Consumes: `Noticia`, `consulta`, `pertinente`, `temas`, `urlRss` (núcleo); `unescapeHtml`, `erPython` (Tarefa 12).
- Produces:
  - `String quotePython(String s, {String seguro = '/'})` — UTF-8 percentual, sem codificar letras, dígitos, `_.-~` e `seguro` (o `Uri.encodeComponent` deixa `!*'()`, o Python não).
  - `Uri urlBusca(String ticker, {String nome = ''})` — `urlRss` com `{q}` = `quotePython(consulta(ticker, nome: nome))`, montada por `Uri.parse` para não recodificar.
  - `double? lerDataRfc2822(String texto)` — porta de `email._parseaddr._parsedate_tz` + `parsedate_to_datetime`: dia da semana opcional, ano de 2 dígitos (> 68 → 19xx, senão 20xx), fusos numéricos e por nome (UT, UTC, GMT, Z, EST, EDT, CST, CDT, MST, MDT, PST, PDT); `null` quando o Python lança; sem fuso ou `-0000` → hora local do aparelho (como o Python).
  - `List<Noticia> lerRss(List<int> xml, String ticker, {String nome = '', required double agora})` — UTF-8 tolerante; `package:xml`: cada `item` em ordem de documento, texto de `title`, `link`, `guid`, `pubDate`, `source` e atributo `url` do `source`; se o parser lançar `XmlException`, a leitura por expressões regulares do Python (noticias.py:146-155). Depois, as regras de `ler_rss`: `strip`; sem título ou link pula; tira o sufixo `" - <fonte>"`; `pertinente`; data inválida → `agora`; `id = (guid or link).strip()`; `tickers = [ticker]`; `temas(titulo)`.

- [ ] **Step 1: Ampliar o gerador e regenerar**

`ler_rss`: XMLs de exemplo (itens com `source`, título com `" - Fonte"`, item sem link, ruído, BDR com e sem o nome no título, `&amp;` e CDATA no título, `pubDate` ausente e inválido; `time.time` congelado em `AGORA`). `ler_rss_regex`: os mesmos XMLs e um malformado, dentro de `sem_modulo("xml.etree.ElementTree")`. `data_rfc2822`: datas com GMT, `+0000`, `-0300`, `EST`, sem dia da semana, ano `26` e `99`, segundos ausentes, lixo (os casos sem fuso ficam fora da referência e vão para teste só Dart). `url_busca`: tickers de ação e BDR com nomes contendo `&`, `'`, acento e parênteses.

Run: `py -3.12 ferramentas/gerar_referencias.py noticias_rede`
Expected: mais casos; os casos da Tarefa 12 iguais (o teste dela continua passando).

- [ ] **Step 2: Escrever os testes que falham**

```dart
for (final c in casos('ler_rss')) test('ler_rss: ${c.nome}', ...);              // toJson de cada Noticia == saída
for (final c in casos('ler_rss_regex')) test('ler_rss pelas regex: ${c.nome}', ...);   // XML válido: lerRss == saída; malformado: lerRss (fallback) == saída
for (final c in casos('data_rfc2822')) test('data: ${c.nome}', ...);
for (final c in casos('url_busca')) test('url: ${c.nome}', () => expect(urlBusca(...).toString(), c.saida));
test('data sem fuso usa a hora local do aparelho', ...);       // == DateTime(2026, 10, 31, 14).millisecondsSinceEpoch / 1000
```

- [ ] **Step 3: Rodar e ver falhar**

Run: `flutter test test/integracoes/noticias/rss_test.dart`
Expected: FAIL.

- [ ] **Step 4: Implementar `rss.dart`**

- [ ] **Step 5: Rodar e ver passar**

Run: `flutter test test/integracoes/noticias` e `flutter analyze`
Expected: `All tests passed!`.

- [ ] **Step 6: Commit**

```bash
git add ferramentas/referencias/noticias_rede.py app/test/referencias/noticias_rede.json app/lib/integracoes app/test/integracoes
git commit -m "Plano 2, tarefa 13: leitura do RSS do Google Notícias, datas RFC 2822 e URL de busca"
```

---

### Task 14: Notícias em rede (busca, decodificação do link, prévias e serviço)

Porta `buscar_ticker` (noticias.py:198-204), `atualizar` (237-277, a parte sem rede já está em `aplicarBusca`), `ler_detalhes`/`gravar_detalhes` (319-337), `decodificar_link` (340-360), `baixar_pagina` (384-397), `detalhar` (400-414) e `enriquecer` (417-430).

**Files:**
- Modify: `ferramentas/referencias/noticias_rede.py` (função `decodificar_link`)
- Create (regerado): `app/test/referencias/noticias_rede.json`
- Create: `app/lib/integracoes/noticias/google_news.dart`, `app/lib/integracoes/noticias/previas.dart`, `app/lib/integracoes/noticias/servico.dart`
- Test: `app/test/integracoes/noticias/google_news_test.dart`, `app/test/integracoes/noticias/servico_test.dart`

**Interfaces:**
- Consumes: Tarefas 2, 12 e 13; `Noticia`, `lerEstado`, `gravarEstado`, `aplicarBusca`, `maxDetalhes`, `tentarDetalheDeNovo`, `Armazenamento`, `jsonPython`, `jsonPythonDecode`, `ambiente` (núcleo).
- Produces:
  - `const urlDecodificar = 'https://news.google.com/_/DotsSplashUi/data/batchexecute';`, `const uaNavegador = {...}` (noticias.py:22-23), `const uaNoticias = 'Mozilla/5.0 (CalculadoraDARF)';`
  - `String? idArtigo(String link)` (`null` se o link não é do Google Notícias); `({String sg, String ts})? assinaturaArtigo(String pagina)`; `String corpoDecodificacao(String gid, String ts, String sg)` — o texto exato de `json.dumps([[["Fbv4je", interno]]])` do Python (separador `", "`): `'[[["Fbv4je", ${jsonEncode(interno)}]]]'` com `interno` de noticias.py:352-353; `String? urlDaRespostaBatch(String texto)` (lança `FormatException` em resposta fora do formato, que o `detalhar` guarda como erro).
  - `const arquivoDetalhes = 'noticias_detalhes.json';`, `class DetalheNoticia { String url, img, resumo; double hora; String? erro; fromJson; toJson; }` (chaves do Python), `Map<String, DetalheNoticia> lerDetalhes(Armazenamento a)` (falha → `{}`), `void gravarDetalhes(Armazenamento a, Map<String, DetalheNoticia> det, {Set<String>? manter})`.
  - `class ServicoNoticias { ServicoNoticias({required http.Client cliente, required Armazenamento armazenamento, Executar executar = executarEmIsolate}); Future<List<Noticia>> buscarTicker(String ticker, {String nome = ''}); Future<(List<Noticia>, List<Noticia>)> atualizar(List<(String, String)> radar, {double? agora, bool detalhes = false}); Future<String?> decodificarLink(String link); Future<(String, String)> baixarPagina(String url, {int limite = 600000}); Future<DetalheNoticia> detalhar(Noticia item); Future<bool> enriquecer(List<Noticia> itens, {int limite = maxDetalhes}); }`
    - Clientes internos: RSS com `uaNoticias`, 20 s, até 4 simultâneos, sem repetição de 429; páginas com `uaNavegador`, 20 s, até 4 simultâneos.
    - `buscarTicker`: 429 → `LimiteConsultas`; outro ≥ 400 → `ErroHttp`; parsing por `executar` (`lerRss` com `agora = ambiente.agora()`).
    - `atualizar`: busca os tickers (até 4 ao mesmo tempo) e monta `listas` na ordem do radar só com os sem erro; erro de um ativo vira `erros[t] = <texto, até 200 pontos de código>`; depois, sem `await` no meio, `lerEstado` → `aplicarBusca` → `gravarEstado`; com `detalhes`, `enriquecer` engolindo exceções; devolve `(itens, novas)`.
    - `decodificarLink`: link de fora → o próprio link sem pedido; `GET https://news.google.com/rss/articles/<gid>` com `uaNavegador` (sem conferir status, como o Python); sem assinatura → `null`; `POST urlDecodificar` com formulário `f.req` e `Content-Type: application/x-www-form-urlencoded;charset=UTF-8`; `conferirStatus`; `urlDaRespostaBatch`.
    - `baixarPagina`: `abrir`; `conferirStatus`; `Content-Type` sem `html` (ausente conta como html) → `('', urlFinal)`; lê blocos até `≥ limite` ou até aparecer `</head>` (também na emenda de dois blocos); charset do cabeçalho, senão UTF-8 tolerante; devolve `(html, urlFinal)`.
    - `detalhar`: link não decodificado → `erro: 'link'`; exceção → `erro` com até 120 pontos de código; sucesso → `url` final, `img`, `resumo` de `lerPrevia` (parsing por `executar`); `hora = ambiente.agora()`.
    - `enriquecer`: os `limite` primeiros sem detalhe ou com erro há mais de `tentarDetalheDeNovo`; nada a fazer → `false`; até 4 `detalhar` ao mesmo tempo; grava mantendo só os ids de `itens`; `true`.

- [ ] **Step 1: Ampliar o gerador e regenerar**

`decodificar_link` com `rede(...)`: link de fora do Google; página sem `data-n-a-sg`; página e resposta válidas (resposta no formato `)]}'\n\n[["wrb.fr","Fbv4je","[\"garturlres\",\"https://site.com/m\",1]",...]]` seguido de linhas de controle); URL que não começa com `http`; POST 500. Saída: pedidos (método, URL, cabeçalhos, formulário) e resultado ou erro.

Run: `py -3.12 ferramentas/gerar_referencias.py noticias_rede`
Expected: mais casos; testes das Tarefas 12 e 13 continuam passando.

- [ ] **Step 2: Escrever os testes que falham**

```dart
for (final c in casos('decodificar_link')) test('decodificar_link: ${c.nome}', ...);   // pedidos iguais; f.req idêntico ao do Python, caractere por caractere
test('buscarTicker: URL do Python, UA de notícias; 429 → LimiteConsultas; 500 → ErroHttp', ...);
test('atualizar: um ativo com erro não impede os outros; erro com até 200 caracteres', ...);
test('atualizar: listas na ordem do radar mesmo com respostas fora de ordem', ...);   // atrasos diferentes
test('atualizar grava o estado como aplicarBusca e devolve as novas relevantes', ...);
test('baixarPagina para no </head>, respeita o limite, devolve a URL final e ignora não-HTML', ...);
test('baixarPagina: charset do cabeçalho e UTF-8 quando não há', ...);
test('detalhar: link não decodificado → erro "link"; exceção → erro com até 120 caracteres; sucesso com img e resumo', ...);
test('enriquecer: só os 40 mais recentes sem detalhe ou com erro há mais de 6 h; grava só os ids atuais', ...);
test('enriquecer sem nada a fazer devolve false e não grava', ...);
test('enriquecer: no máximo 4 detalhes ao mesmo tempo', ...);
test('noticias_detalhes.json com as chaves do Python', ...);
```

- [ ] **Step 3: Rodar e ver falhar**

Run: `flutter test test/integracoes/noticias`
Expected: FAIL.

- [ ] **Step 4: Implementar os três arquivos**

- [ ] **Step 5: Rodar e ver passar**

Run: `flutter test test/integracoes` e `flutter analyze`
Expected: `All tests passed!`.

- [ ] **Step 6: Commit**

```bash
git add ferramentas/referencias/noticias_rede.py app/test/referencias/noticias_rede.json app/lib/integracoes app/test/integracoes
git commit -m "Plano 2, tarefa 14: busca de notícias, decodificação do link, prévias e serviço"
```

---

### Task 15: Imagens das notícias e logos

Porta `baixar_imagem_noticia` (noticias.py:433-455), o nome do cache (calculadora_darf.py:2264), `baixar_imagem` (473-492), `logo_png` (495-503) e `favicon_png` (506-511); o SVG da brapi (Android, android/main.py:140-149) ganha o mesmo cache.

**Files:**
- Modify: `ferramentas/referencias/noticias_rede.py` (função `arquivo_favicon`)
- Create (regerado): `app/test/referencias/noticias_rede.json`
- Create: `app/lib/integracoes/cache_binario.dart`, `app/lib/integracoes/noticias/imagens.dart`, `app/lib/integracoes/noticias/logos.dart`
- Test: `app/test/integracoes/cache_binario_test.dart`, `app/test/integracoes/noticias/imagens_test.dart`, `app/test/integracoes/noticias/logos_test.dart`

**Interfaces:**
- Consumes: Tarefas 1, 2, 12 e 14 (`uaNavegador`, `uaNoticias`, `erPython`); `urlsLogo`, `iniciais`, `dominio`, `urlFavicon`, `validadeLogoAusente`, `Noticia`, `arredondar`, `ambiente` (núcleo); `image`, `crypto`.
- Produces:
  - `abstract interface class CacheBinario { Future<Uint8List?> ler(String nome); Future<void> gravar(String nome, List<int> bytes); Future<DateTime?> modificadoEm(String nome); Future<void> apagar(String nome); }`; `class CacheBinarioMemoria implements CacheBinario { CacheBinarioMemoria({DateTime Function()? relogio}); }`; `class CacheBinarioArquivos implements CacheBinario { CacheBinarioArquivos(String pasta); }` (nome com `/` vira subpasta; grava em `.tmp` e renomeia).
  - `String nomeImagemNoticia(String url)` → `'noticias_img/${sha1(utf8(url)).hex.substring(0, 20)}.jpg'`.
  - `Uint8List? reduzirParaJpeg(Uint8List dados, {int largura = 900})` — pura (roda por `executar`): decodifica (JPEG, PNG, WebP, GIF); não decodificou → `null`; menor que 120×80 → `null`; descarta o alfa (RGB); mais larga que `largura` → redimensiona para (`largura`, `arredondar(altura * largura / larguraOriginal, 0)`) com interpolação cúbica; JPEG qualidade 85.
  - `Future<String?> baixarImagemNoticia(ClienteHttp navegador, CacheBinario cache, String url, {Executar executar = executarEmIsolate, int largura = 900, int limite = 6000000})` — já em cache → o nome sem baixar; corpo acima do limite → `null` (para de ler); senão reduz, grava e devolve o nome.
  - `String nomeArquivoFavicon(String dominio)` → `re.sub(r"[^\w.-]", "_", d) + ".png"` (por `erPython`).
  - `class Logos { Logos({required ClienteHttp http, required CacheBinario cache}); Future<Uint8List?> logoPng(String ticker); Future<Uint8List?> logoSvg(String ticker); Future<Uint8List?> favicon(Noticia item); }` — `http` com `uaNoticias` e 15 s. Regra comum (`baixar_imagem`): arquivo em cache → bytes; `.falta` com menos de 7 dias (`ambiente.agora()`) → `null`; falha de transporte → `null` sem gravar `.falta`; 200 e válido → grava, apaga `.falta`, devolve; 403, 404 ou 200 inválido → grava `.falta` vazio e `null`; outro status → `null`. PNG: `logos/<nome da URL>` (ticker e depois a raiz de `urlsLogo`), válido = começa com `\x89PNG\r\n\x1a\n`, `.falta` = mesmo nome com `.falta` no lugar de `.png`. SVG: `logos/svg/<ticker>.svg`, válido = contém `<svg`, `.falta` em `logos/svg/<ticker>.falta`. Favicon: `logos/fontes/<nomeArquivoFavicon(dominio)>`, URL de `urlFavicon`; sem domínio → `null`.

- [ ] **Step 1: Ampliar o gerador e regenerar**

`arquivo_favicon`: domínios `g1.globo.com`, `valor.globo.com:8080`, `exame.com`, `xn--e1afmkfd.xn--p1ai`, `notícias.uol.com.br`, `a b`.

Run: `py -3.12 ferramentas/gerar_referencias.py noticias_rede`
Expected: mais casos; testes anteriores passando.

- [ ] **Step 2: Escrever os testes que falham**

Imagens geradas no próprio teste com `package:image`.
```dart
test('1800×1000 vira JPEG 900×500', ...);
test('altura no meio arredonda como o Python: 1800×1001 → 900×500', ...);   // 1001·900/1800 = 500,5 → 500
test('PNG com transparência vira JPEG', ...);
test('menor que 120×80 → null; bytes que não são imagem → null; até 900 de largura mantém o tamanho', ...);
test('nomeImagemNoticia', () => expect(nomeImagemNoticia('https://exemplo.com/a.jpg'), 'noticias_img/f270ac75223f9eca1c70.jpg'));
test('baixarImagemNoticia: em cache não baixa; acima de 6 MB → null; grava e devolve o nome', ...);
for (final c in casos('arquivo_favicon')) test('favicon: ${c.nome}', ...);
test('logoPng: PNG válido grava e apaga .falta', ...);
test('logoPng: 404, 403 e 200 não-PNG gravam .falta e não tentam de novo por 7 dias', ...);
test('logoPng: depois de 7 dias tenta de novo', ...);
test('logoPng: sem rede e 500 não gravam .falta', ...);
test('logoPng tenta PETR4 e depois PETR', ...);
test('logoSvg e favicon nos caminhos do cache', ...);
```
`cache_binario_test.dart` (pasta temporária): `test('subpastas, modificadoEm e apagar', ...)`, `test('gravação substitui o arquivo inteiro', ...)`.

- [ ] **Step 3: Rodar e ver falhar**

Run: `flutter test test/integracoes/cache_binario_test.dart test/integracoes/noticias`
Expected: FAIL.

- [ ] **Step 4: Implementar os três arquivos**

- [ ] **Step 5: Rodar e ver passar**

Run: `flutter test test/integracoes` e `flutter analyze`
Expected: `All tests passed!`.

- [ ] **Step 6: Commit**

```bash
git add ferramentas/referencias/noticias_rede.py app/test/referencias/noticias_rede.json app/lib/integracoes app/test/integracoes
git commit -m "Plano 2, tarefa 15: imagens das notícias em JPEG e logos com cache e ausência de 7 dias"
```

---

### Task 16: Atualizador

Porta `versao_tupla` (atualizador.py:21-23), `verificar` (40-60) e `baixar`/`_baixar` (63-98). A troca do executável (101-139) e a abertura do APK (android/main.py:80-91) ficam para os planos 3 e 4, pela interface `InstalarAtualizacao`.

**Files:**
- Create: `ferramentas/referencias/atualizador.py`
- Create (gerado): `app/test/referencias/atualizador.json`
- Create: `app/lib/integracoes/atualizador/atualizador.dart`
- Test: `app/test/integracoes/atualizador/atualizador_test.dart`

**Interfaces:**
- Consumes: Tarefas 1 e 2 (`versaoApp`, `ClienteHttp`, `conferirStatus`, `decodificarJson`); `ErroNucleo`; `crypto`.
- Produces:
  - `const repositorioGithub = 'JoaoGabrielOT/CalculadoraDARF';`, `const urlUltimaVersao = 'https://api.github.com/repos/JoaoGabrielOT/CalculadoraDARF/releases/latest';`, `const nomeAssetWindows = 'CalculadoraDARF.exe';`, `const nomeAssetAndroid = 'CalculadoraDARF.apk';`, `String nomeAssetDaPlataforma({bool? windows})` (padrão `Platform.isWindows`).
  - `class ErroAtualizacao extends ErroNucleo`; `class InfoAtualizacao { final String versao, notas, url, sha256; final int tamanho; }`
  - `(int, int, int) versaoTupla(String v)`; `bool versaoMaisNova(String tag, String atual)`.
  - `Future<InfoAtualizacao?> verificarAtualizacao(ClienteHttp http, {required String nomeAsset, String versaoAtual = versaoApp})` — `Accept: application/vnd.github+json`, `User-Agent: CalculadoraDARF`, 15 s; 404 → `null`; outro erro → `conferirStatus`; draft ou prerelease → `null`; tag não mais nova → `null`; sem o asset → `null`; `versao` = tag sem `v`/`V` à esquerda; `notas` = `body.strip()`; `sha256` = parte depois de `sha256:` do `digest`, senão `''`.
  - `Future<File> baixarAtualizacao(ClienteHttp http, InfoAtualizacao info, File destino, {void Function(int baixado, int total)? progresso, bool Function()? cancelado})` — `abrir` (30 s por bloco, `User-Agent: CalculadoraDARF`); `total` = `Content-Length` ou `info.tamanho` ou 0; grava e calcula o sha256 em fluxo; `cancelado()` verdadeiro → `ErroAtualizacao('Atualização cancelada.')`; tamanho conhecido e diferente → `ErroAtualizacao('O download ficou incompleto.')`; sha256 diferente (sem diferenciar maiúsculas) → `ErroAtualizacao('O arquivo baixado não confere com o publicado.')`; qualquer exceção apaga `destino` e é relançada.
  - `typedef InstalarAtualizacao = Future<void> Function(File arquivo);`

- [ ] **Step 1: Escrever `atualizador.py` e gerar**

`versao_tupla`: `"2.0.0"`, `"v1.12.1"`, `"V2"`, `"2.0.0-beta1"`, `"1.2.3.4"`, `"abc"`, `""`. `verificar` (com `atu.VERSAO` trocado por `"1.12.1"` e `"2.0.0"`): nova com digest, nova sem digest, draft, prerelease, mesma versão, mais antiga, sem o asset, 404, 500, `body` nulo. Saída: pedido (URL, cabeçalhos) e dict ou `null`/erro.

Run: `py -3.12 ferramentas/gerar_referencias.py atualizador`
Expected: `atualizador: N casos`.

- [ ] **Step 2: Escrever os testes que falham**

```dart
for (final c in casos('versao_tupla')) test('versaoTupla: ${c.nome}', ...);
for (final c in casos('verificar')) test('verificar: ${c.nome}', ...);   // mesmo pedido e mesmo resultado
test('a 2.0.0 é mais nova que a 1.12.1 e o app já sai na 2.0.0', ...);
test('baixar: progresso por bloco com o total do Content-Length ou do tamanho', ...);
test('baixar: tamanho diferente → "O download ficou incompleto." e arquivo apagado', ...);
test('baixar: sha256 diferente → "O arquivo baixado não confere com o publicado." e arquivo apagado', ...);
test('baixar: sha256 em maiúsculas confere', ...);
test('cancelar no meio → "Atualização cancelada." e arquivo apagado', ...);
test('queda de rede no meio → ErroConexao e arquivo apagado', ...);
test('nomeAssetDaPlataforma', () { expect(nomeAssetDaPlataforma(windows: true), 'CalculadoraDARF.exe');
                                    expect(nomeAssetDaPlataforma(windows: false), 'CalculadoraDARF.apk'); });
```

- [ ] **Step 3: Rodar e ver falhar**

Run: `flutter test test/integracoes/atualizador`
Expected: FAIL.

- [ ] **Step 4: Implementar `atualizador.dart`**

sha256 em fluxo com `sha256.startChunkedConversion` e um `Sink<Digest>` próprio que guarda o resultado (o `AccumulatorSink` é do `package:convert`, que não entra).

- [ ] **Step 5: Rodar e ver passar**

Run: `flutter test test/integracoes` e `flutter analyze`
Expected: `All tests passed!`.

- [ ] **Step 6: Commit**

```bash
git add ferramentas/referencias/atualizador.py app/test/referencias/atualizador.json app/lib/integracoes app/test/integracoes
git commit -m "Plano 2, tarefa 16: atualizador com releases do GitHub, tamanho e sha256"
```

---

### Task 17: Verificação final e resultado do plano 2

**Files:**
- Test: `app/test/integracoes/barril_test.dart`
- Create: `docs/superpowers/plans/2026-11-01-plano-2-resultado.md`

**Interfaces:**
- Consumes: todas as tarefas.
- Produces: o barril completo e o registro das notas para os planos 3 e 4.

- [ ] **Step 1: Escrever o teste do barril**

`barril_test.dart` importa só `package:calculadoradarf/integracoes/integracoes.dart` e referencia um símbolo de cada arquivo público (`ClienteHttp`, `ServicoYahoo`, `CacheCotacoes`, `Grafico`, `SessaoGoogle`, `loginNavegador`, `PlanilhaGoogle`, `Google`, `Sincronizador`, `DadosSincronizacaoLocal`, `ServicoNoticias`, `lerRss`, `unescapeHtml`, `Logos`, `baixarImagemNoticia`, `CacheBinarioArquivos`, `verificarAtualizacao`, `executarEmIsolate`, `carregarClienteOAuth`).

- [ ] **Step 2: Rodar tudo**

Run (em `app/`): `flutter analyze` e `flutter test`
Expected: `No issues found!` e `All tests passed!`.

- [ ] **Step 3: Conferir que as referências são reprodutíveis e que o Python segue intacto**

Run (raiz): `py -3.12 ferramentas/gerar_referencias.py` e `git diff --exit-code app/test/referencias`; `py -3.12 ferramentas/conferir_portados.py`; `python -m unittest discover -s tests`
Expected: diff vazio; `147 de 147`; `OK` (147 testes).

- [ ] **Step 4: Conferir que nenhum teste usa a internet**

Run (raiz): `git grep -n "http.Client()\|IOClient(" -- app/test`
Expected: nenhuma ocorrência (os testes só usam `ClienteFalso` e o loopback da Tarefa 8).

- [ ] **Step 5: Escrever o resultado**

`2026-11-01-plano-2-resultado.md`, no formato do resultado do plano 1: estado verificado (comandos e números), decisões tomadas durante a execução e notas:
- Plano 3: `http.Client` único por app, fechado ao sair; `carregarClienteOAuth()` com `rootBundle`; `AbrirUrl` com `url_launcher` (modo aplicativo externo); pastas com `path_provider` para `ArmazenamentoArquivos` e `CacheBinarioArquivos`; `DadosSincronizacao` sobre o isolate do núcleo (dono único dos arquivos, inclusive `noticias.json`); timers do `Sincronizador.tick` (Python: 60 s no Windows, 30 s no Android); textos de status a partir de `StatusSync`; notificações do sistema; SVG da brapi com `flutter_svg`; notas da atualização cortadas em 600 (Windows) e 500 (Android) caracteres na tela; `InstalarAtualizacao` (APK pelo instalador do sistema).
- Plano 4: CI grava `app/assets/google/credentials.json` a partir de `GOOGLE_CREDENTIALS` e sobrescreve `app/lib/versao.dart` pela tag; migrar `token.json` sem conversão; `InstalarAtualizacao` do Windows (instalador em modo silencioso); teste manual na pré-release de uma gravação que encolhe a planilha (sobras limpas, colunas extras intactas).

- [ ] **Step 6: Commit**

```bash
git add app/test/integracoes/barril_test.dart docs/superpowers/plans/2026-11-01-plano-2-resultado.md
git commit -m "Plano 2, tarefa 17: verificação final e notas para os planos 3 e 4"
```
