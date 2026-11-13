# Versão Web da Calculadora DARF (Implementation Plan)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Publicar o mesmo app Flutter (`app/`) como site e PWA, com login Google pelo servidor, cotações e notícias por um servidor intermediário próprio no Vercel, cópia reserva no Render e publicação automática a cada release estável (2.6.0).

**Architecture:** O código Dart continua único. A Web entra por uma *entrada condicional* (`app/web/entrada.dart`, `dart.library.js_interop`) que fornece a `iniciarApp` uma `PlataformaWeb` e uma fábrica de serviços que roda na thread da interface (`criarServicosWeb`, sem isolate), com `localStorage` como `Armazenamento`, um `ClienteProxy` que reescreve as chamadas ao Yahoo e ao Google News para `/api/...`, e login/renovação de token feitos pelo servidor (pacote cifrado). O servidor intermediário é um conjunto de funções Node sem dependências (`web_servidor/api/`, Web-standard `Request`/`Response`), testadas com `node --test`. O CI monta `build/web` + `web_servidor` e publica na branch `web-dist`, à qual Vercel e Render ficam ligados.

**Tech Stack:** Flutter 3.47.9 / Dart 3.13.7 (`flutter build web`, dart2js), pacotes já usados (`http` 1.6.0, `url_launcher`, `provider`) e `web` 1.1.2 (já transitivo no `pubspec.lock`, passa a direto); testes `flutter_test` na VM e `flutter test --platform chrome` (arquivos com `@TestOn('browser')`); Node 22 (`node:test`, `node:crypto`, `node:dns`, `fetch` global), Vercel Functions (Node), Render Static Site, GitHub Actions (`release.yml`).

**Spec:** `docs/superpowers/specs/2026-11-13-versao-web-design.md` (autoridade). Executores leem a spec e este plano.

## Global Constraints

Da spec, literalmente:
- "Mesmo código Flutter (`app/`), compilado com `flutter build web`; mesmas telas, temas, cálculos e textos."
- "Mudar qualquer cálculo, texto ou formato da planilha que o app do PC/Android lê" é anti-objetivo.
- "Quebrar o app Windows/Android (as mudanças para a Web entram por import condicional/injeção; as suítes atuais continuam verdes)" é anti-objetivo.
- "Proxy aberto: o servidor intermediário só repassa os endereços listados abaixo e só para chamadas do próprio site" é anti-objetivo.
- "Guardar segredo no site público (nenhum `client_secret` no bundle Web) ou usar tokens/credenciais do git ou do ambiente local" é anti-objetivo.
- "Planos grátis do Vercel e do Render. Sem `gh`. Credenciais nunca em repositório; segredo, se precisar, só como variável de ambiente no painel do Vercel."
- "Deploy sem tokens: o CI (GITHUB_TOKEN, `contents: write`) publica o build Web numa branch `web-dist`" — commit novo por release, "sem force push".
- "O Safari do iPhone apaga o armazenamento de sites não usados por 7 dias (exceto PWA instalado): a planilha é a fonte segura dos dados; o armazenamento do navegador é cache."
- Armazenamento Web: chaves prefixadas `darf:` + nome do arquivo; cache de logos só em memória.
- Login: cliente OAuth "Aplicativo da Web", fluxo de código com PKCE "por redirecionamento de página inteira (sem popup)"; "Mesmos escopos do app (inclui `drive.metadata.readonly`)" — `escoposGoogle` em `app/lib/integracoes/google/constantes.dart` não muda.
- "Login obrigatório na Web": "a primeira tela pede o login Google; sem login não há uso local."
- Rede: "Google Sheets/Drive e GitHub direto"; Yahoo e Google News pelo `/api`. "No Vercel o caminho é relativo (`/api`); fora dele (Render, localhost) usa o endereço absoluto do Vercel — decidido em tempo de execução pelo host, um único build."
- Prévias: "só `http(s)`, só IPs públicos (bloqueia localhost, redes privadas e metadados de nuvem, conferido após o DNS e a cada redirecionamento, máx. 3), só `text/html` (≤ 1 MB) ou `image/*` (≤ 2 MB), tempo-limite de 8 s, cache 1 h."
- Caches de borda: Yahoo 30 s; `rss`/`artigo` 5 min; prévias 1 h.
- Fora do escopo: atualizador, instalador, backup e migração da 1.12 na Web (escondidos); Web Push; domínio próprio; verificação OAuth.
- Nomes preferidos dos projetos: `calculadora-darf` (Vercel `https://calculadora-darf.vercel.app`, Render `https://calculadora-darf.onrender.com`).

Do ambiente:
- Trabalhar só no worktree `D:\.Minhas_Coisas\calculadora DARF\CalculadoraDARF\.claude\worktrees\migracao-flutter`, branch `migracao-flutter`. Não tocar o código Python nem a `main`.
- Dependências do `pubspec.yaml` ficam com versão exata (padrão do projeto). Nenhuma dependência npm no servidor.
- Builds Windows/Android e o teste de integração só no CI; o push é do controlador.
- O CI da Web **nunca** grava `app/assets/google/credentials.json`; a montagem falha se achar `credentials*.json` ou `client_secret` no site.

Fatos verificados no código em 13/11/2026 (base `5d70df1`):
- `flutter build web --release` numa cópia de `app/` com a plataforma web criada **compila** (70 s, "Wasm dry run succeeded"). `dart:io`/`dart:isolate` não impedem a compilação; o que falha é a execução: `Platform.isWindows` (`PlataformaReal`), `pastasDoApp` (`path_provider`), `ServicosIsolate.criar` e `Isolate.run` (`executarEmIsolate`, padrão em `SessaoGoogle`, `ServicoYahoo`, `ServicoNoticias`, `baixarImagemNoticia`; `NoticiasLocal` chama `baixarImagemNoticia` sem passar `executar`).
- `flutter create --platforms=web .` cria `web/` (index, manifesto, ícones), **e também** `test/widget_test.dart` e mexe em `analysis_options.yaml` e `.metadata`.
- `build/web/version.json` traz `version` = `--build-name` (usado pela conferência das URLs).
- `Sincronizador.tick` conecta sozinho quando `conta.temToken()` e não há e-mail; `LoginNecessario` na renovação apaga o token e avisa "Sessão expirada. Conecte sua conta Google novamente." — a Web reaproveita esse caminho.
- `ServicosLocais` emite eventos num `StreamController.broadcast` sem buffer: avisos de partida na Web vão por `EntradaWeb.avisoInicial`, não por evento.

Suposições (confirmadas na Task 13): o Vercel aceita funções em `api/` com a assinatura Web-standard (`export async function GET(request)`); o CDN do Vercel respeita `Vary: Origin`; pushes feitos com `GITHUB_TOKEN` disparam as integrações GitHub do Vercel e do Render (webhooks, não workflows); o Flutter Web não preenche `viewPadding` com `env(safe-area-inset-*)` (por isso a Task 9 lê os insets do CSS).

## Review Focus

1. **Sessão perdida no iPhone** (Safari apagou o `localStorage` ou o Google expirou o refresh token do app em teste após 7 dias): a pessoa volta à tela de login com "Sessão expirada. Conecte sua conta Google novamente.", sem travar nem perder dado da planilha. Testes: Task 7 (renovador 401 → `LoginNecessario`), Task 8 (token apagado e aviso), Task 10 (portão mostra o aviso).
2. **Duas abas do app abertas**: duas cópias dos serviços gravariam o mesmo `localStorage` e a mesma planilha sem coordenação. A segunda aba mostra "A Calculadora DARF já está aberta em outra aba ou janela deste navegador..." com "Tentar de novo". Testes: Task 9.
3. **iPhone sem a API de notificações** (Safari fora do PWA não tem `Notification`): a partida não falha; `pedirPermissaoNotificacoes` devolve false e `notificar` não faz nada. Teste: Task 9 (Chrome, `Notification` removido).
4. **Volta do login com erro, cancelamento ou pacote adulterado** (`#auth_erro=acesso_negado`, `#auth=lixo`, cookie de estado vencido): aviso "O login foi cancelado." ou "O login não foi concluído.", endereço limpo, tela de login de novo. Testes: Task 6 (servidor) e Task 7 (app).
5. **Armazenamento do navegador cheio ou bloqueado** (cota de ~5 MB, bloqueio de dados do site): ao estourar, descarta o cache de notícias e tenta de novo; sem espaço, erro claro; bloqueado, o app abre em memória com aviso. Testes: Task 2 e Task 9.

---

### Task 1: Plataforma Web do Flutter, PWA e ícones

**Files:**
- Create (via `flutter create`, depois editados): `app/web/index.html`, `app/web/manifest.json`, `app/web/favicon.png`, `app/web/icons/Icon-192.png`, `app/web/icons/Icon-512.png`, `app/web/icons/Icon-maskable-192.png`, `app/web/icons/Icon-maskable-512.png`
- Create: `app/web/icons/apple-touch-icon.png`
- Modify: `app/tool/gerar_icones.dart`, `app/pubspec.yaml` (dependência `web: 1.1.2`), `app/.metadata`
- Test: `app/test/app/plataforma/icones_test.dart` (estender), `app/test/app/plataforma/web_pwa_test.dart` (novo)

**Interfaces:**
- Consumes: nada.
- Produces: pasta `app/web/` válida para `flutter build web`; dependência direta `package:web` para as Tasks 2 e 9.

- [ ] **Step 1: Criar a plataforma e desfazer o que o `flutter create` mexe a mais**

Run (em `app/`): `flutter create --platforms=web --project-name calculadoradarf .` e depois `rm test/widget_test.dart && git checkout -- analysis_options.yaml`
Expected: `git status --short` mostra só `?? web/` e ` M .metadata`.

- [ ] **Step 2: Escrever os testes que falham**

Em `web_pwa_test.dart` (lê arquivos, VM):
```dart
test('manifesto da PWA', () {
  final m = jsonDecode(File('web/manifest.json').readAsStringSync()) as Map;
  expect(m['name'], 'Calculadora DARF');
  expect(m['short_name'], 'Calculadora DARF');
  expect(m['display'], 'standalone');
  expect(m['start_url'], './');
  expect(m['background_color'], '#0D1117');
  expect(m['theme_color'], '#0D1117');
  for (final i in (m['icons'] as List).cast<Map>()) {
    expect(File('web/${i['src']}').existsSync(), isTrue, reason: '${i['src']}');
  }
});
test('index.html com viewport-fit, iOS e sem textos do modelo', () {
  final h = File('web/index.html').readAsStringSync();
  for (final s in ['lang="pt-BR"', 'viewport-fit=cover', 'rel="apple-touch-icon" href="icons/apple-touch-icon.png"',
      'apple-mobile-web-app-capable', 'apple-mobile-web-app-title" content="Calculadora DARF"',
      '<title>Calculadora DARF</title>', 'name="theme-color" content="#0D1117"']) {
    expect(h, contains(s));
  }
  expect(h, isNot(contains('A new Flutter project')));
});
```
Em `icones_test.dart`, para `Icon-192` 192², `Icon-512` 512², `Icon-maskable-192` 192², `Icon-maskable-512` 512², `apple-touch-icon` 180², `favicon.png` 32²: decodificar e conferir o tamanho; `apple-touch-icon` e `Icon-maskable-512` com pixel (0,0) opaco e igual a `#0D1117`; `Icon-512` diferente (sha256) do `Icon-512.png` que o `flutter create` gerou (anotar o hash antes do Step 4, como `hashPadraoAnotado`).

- [ ] **Step 3: Rodar e ver falhar**

Run: `flutter test test/app/plataforma/web_pwa_test.dart test/app/plataforma/icones_test.dart`
Expected: FAIL (nome `calculadoradarf`, sem `viewport-fit`, sem `apple-touch-icon.png`).

- [ ] **Step 4: Gerar os ícones em `tool/gerar_icones.dart` e escrever `index.html`/`manifest.json`**

Fonte: `../assets/logo.png` (1024², mesma arte do `icone_janela.png`). `Icon-192/512` e `favicon` redimensionados (transparência mantida); `Icon-maskable-*`: logo a 80 % centrado sobre quadrado `#0D1117`; `apple-touch-icon` (180): logo inteiro sobre `#0D1117`, sem transparência. As saídas atuais (Windows/Android) não mudam. `index.html`: `lang="pt-BR"`, `<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">`, `theme-color`, `mobile-web-app-capable`, `apple-mobile-web-app-capable` = yes, `apple-mobile-web-app-status-bar-style` = `black-translucent`, título e `apple-mobile-web-app-title` "Calculadora DARF", descrição "Apuração de IR em ações, metas, radar e notícias.", `html, body { background: #0D1117; }`, `<noscript>` "Ative o JavaScript para usar a Calculadora DARF.". `manifest.json` com os valores do teste, `"scope": "./"`, `"orientation": "any"` e os 4 ícones do modelo. Em `pubspec.yaml`, `web: 1.1.2` em `dependencies`.

Run: `dart run tool/gerar_icones.dart` (em `app/`).

- [ ] **Step 5: Rodar e ver passar; conferir build**

Run: `flutter test test/app/plataforma/` e `flutter build web --release --no-wasm-dry-run`
Expected: `All tests passed!` e `√ Built build\web`.

- [ ] **Step 6: Commit**

```bash
git add app/web app/tool/gerar_icones.dart app/pubspec.yaml app/pubspec.lock app/.metadata app/test/app/plataforma/icones_test.dart app/test/app/plataforma/web_pwa_test.dart
git commit -m "Web: plataforma do Flutter, manifesto da PWA e ícones"
```

---

### Task 2: Execução e armazenamento no navegador

**Files:**
- Modify: `app/lib/integracoes/executor.dart`
- Create: `app/lib/integracoes/executor_isolate.dart`, `app/lib/integracoes/executor_sem_isolate.dart`
- Create: `app/lib/nucleo/armazenamento_chave_valor.dart`
- Create: `app/lib/app/web/chave_valor_navegador.dart` (só Web, `package:web`)
- Test: `app/test/nucleo/armazenamento_chave_valor_test.dart`, `app/test/web/executor_web_test.dart`, `app/test/web/chave_valor_navegador_test.dart`

**Interfaces:**
- Consumes: `Armazenamento` (`app/lib/nucleo/armazenamento.dart`).
- Produces:
  - `executarEmIsolate<R>(FutureOr<R> Function() tarefa)` com a mesma assinatura; na Web roda direto (import condicional `if (dart.library.js_interop)`).
  - `abstract interface class ChaveValor { String? obter(String chave); void definir(String chave, String valor); void remover(String chave); Iterable<String> chaves(); }`
  - `class ChaveValorMemoria implements ChaveValor`
  - `class ArmazenamentoChaveValor implements Armazenamento { ArmazenamentoChaveValor(ChaveValor kv, {String prefixo = 'darf:'}); }`
  - `const arquivosDescartaveis = ['noticias_detalhes.json', 'noticias.json'];`
  - `class ErroArmazenamentoCheio implements Exception` com `toString()` = `textoArmazenamentoCheio` = `'O navegador ficou sem espaço para os dados do app. Os dados já sincronizados continuam na planilha do Google.'`
  - `ChaveValor? chaveValorDoNavegador()` — `null` quando o `localStorage` não existe, lança ao acessar ou recusa uma gravação de teste (`darf:__teste`).

- [ ] **Step 1: Escrever os testes que falham**

`armazenamento_chave_valor_test.dart` (VM), com um `ChaveValorLimitado` de teste que lança `StateError('QuotaExceededError')` quando a soma dos tamanhos dos valores passa de um limite:
```dart
test('grava com o prefixo e lista só as chaves do app', () {
  final kv = ChaveValorMemoria()..definir('outro', 'x');
  final a = ArmazenamentoChaveValor(kv);
  a.gravar('2026-11.json', '{}');
  expect(kv.obter('darf:2026-11.json'), '{}');
  expect(a.listar(), ['2026-11.json']);
  expect(a.existe('2026-11.json'), isTrue);
  a.apagar('nao-existe.json'); // sem efeito
  expect(a.ler('nao-existe.json'), isNull);
});
test('sem espaço, descarta o cache de notícias e grava', () { /* limite 30; noticias.json com 25 chars; gravar config.json com 10 → ok, noticias.json apagado */ });
test('sem espaço e sem o que descartar, lança ErroArmazenamentoCheio', () {
  expect(() => a.gravar('2026-11.json', 'x' * 100),
      throwsA(isA<ErroArmazenamentoCheio>().having((e) => '$e', 'texto', textoArmazenamentoCheio)));
});
test('gravar o próprio noticias.json só descarta o outro descartável', ...);
```
`test/web/executor_web_test.dart` e `test/web/chave_valor_navegador_test.dart` com `@TestOn('browser')`: `executarEmIsolate(() => 2 + 3)` dá 5 e propaga `FormatException`; `chaveValorDoNavegador()` não é nulo no Chrome, `definir/obter/remover/chaves` vão ao `window.localStorage` (limpar `darf:*` no `tearDown`).

- [ ] **Step 2: Rodar e ver falhar**

Run: `flutter test test/nucleo/armazenamento_chave_valor_test.dart` e `flutter test --platform chrome test/web`
Expected: FAIL (arquivos/símbolos inexistentes).

- [ ] **Step 3: Implementar**

`executor.dart` mantém `Executar` e `executarDireto` e passa a importar `executor_isolate.dart` (com `Isolate.run`) `if (dart.library.js_interop) 'executor_sem_isolate.dart'` (chama a tarefa direto). `ArmazenamentoChaveValor.gravar`: tenta `definir`; em qualquer exceção apaga os `arquivosDescartaveis` diferentes de `nome` e tenta uma vez; nova falha vira `ErroArmazenamentoCheio`. `chave_valor_navegador.dart` usa `package:web` (`window.localStorage`), dentro de `try`.

- [ ] **Step 4: Rodar e ver passar**

Run: `flutter test test/nucleo/armazenamento_chave_valor_test.dart test/integracoes/executor_test.dart` e `flutter test --platform chrome test/web`
Expected: `All tests passed!` nas duas.

- [ ] **Step 5: Commit**

```bash
git add app/lib/integracoes/executor*.dart app/lib/nucleo/armazenamento_chave_valor.dart app/lib/app/web/chave_valor_navegador.dart app/test/nucleo/armazenamento_chave_valor_test.dart app/test/web
git commit -m "Web: execução sem isolate e armazenamento no localStorage"
```

---

### Task 3: Cliente de proxy e endereço da API

**Files:**
- Create: `app/lib/integracoes/http/cliente_proxy.dart` (exportar em `app/lib/integracoes/integracoes.dart`)
- Create: `app/lib/app/web/endereco_api.dart`
- Test: `app/test/integracoes/http/cliente_proxy_test.dart`, `app/test/app/web/endereco_api_test.dart`

**Interfaces:**
- Consumes: `package:http` (`BaseClient`, `StreamedResponseV2`, `AbortableRequest`).
- Produces:
  - `enum DestinoLivre { pagina, imagem }`
  - `const cabecalhoUrlFinal = 'x-url-final';`
  - `const hostsDiretos = {'sheets.googleapis.com', 'www.googleapis.com', 'oauth2.googleapis.com', 'api.github.com'};`
  - `class ClienteProxy extends http.BaseClient { ClienteProxy(http.Client interno, {required Uri api, DestinoLivre livre = DestinoLivre.pagina}); Uri reescrever(Uri url); }`
  - `const urlVercel = String.fromEnvironment('URL_VERCEL', defaultValue: 'https://calculadora-darf.vercel.app');`
  - `Uri enderecoApi(Uri pagina)` — `<origem da página>/api` quando o host da página é o de `urlVercel`; senão `$urlVercel/api`.

- [ ] **Step 1: Escrever os testes que falham**

Com `api = Uri.parse('https://calculadora-darf.vercel.app/api')`, `reescrever`:
- `https://query1.finance.yahoo.com/v8/finance/chart/PETR4.SA?range=5d&interval=1d` → path `/api/yahoo/chart/PETR4.SA`, `queryParameters` `{range: 5d, interval: 1d}`.
- `https://news.google.com/rss/search?q=PETR4&hl=pt-BR&gl=BR&ceid=BR:pt-419` → path `/api/noticias/rss`, mesmos `queryParameters`.
- `https://news.google.com/_/DotsSplashUi/data/batchexecute` → `https://calculadora-darf.vercel.app/api/noticias/resolver`.
- `https://news.google.com/rss/articles/CBMiabc` → `.../api/noticias/artigo/CBMiabc`.
- `https://sheets.googleapis.com/v4/spreadsheets/x` e `https://www.googleapis.com/drive/v3/about` → iguais (diretos); URL que já começa com `api` → igual.
- `https://www.infomoney.com.br/a?b=1` → path `/api/noticias/pagina`, `queryParameters['url']` = a URL original; com `livre: DestinoLivre.imagem` → `/api/noticias/imagem`.
- `ftp://x/y` → `throwsArgumentError`.

`send` com `MockClient.streaming`: o pedido que chega não tem `User-Agent` (mesmo com `ClienteHttp(..., userAgent: 'Mozilla/5.0')`), mantém `Accept-Language`, `Content-Type` e o corpo do POST; resposta com `x-url-final: https://site/final` → `ClienteHttp(proxy).abrir(...)` devolve `urlFinal == Uri.parse('https://site/final')`; sem o cabeçalho, `urlFinal` é a URL original (não a do `/api`). Status 502 do proxy chega como 502 (sem exceção).

`enderecoApi`: `https://calculadora-darf.vercel.app/#/` → `https://calculadora-darf.vercel.app/api`; `https://calculadora-darf.onrender.com/` e `http://localhost:5000/` → `https://calculadora-darf.vercel.app/api`.

- [ ] **Step 2: Rodar e ver falhar**

Run: `flutter test test/integracoes/http/cliente_proxy_test.dart test/app/web/endereco_api_test.dart`
Expected: FAIL (símbolos inexistentes).

- [ ] **Step 3: Implementar**

`send` monta um `AbortableRequest` (repassando o `abortTrigger` quando o original é `Abortable`) para `reescrever(request.url)`, copia método, cabeçalhos menos `user-agent` e o corpo (`finalize()`), e devolve `StreamedResponseV2` com `url` = `x-url-final` quando houver, senão a URL original.

- [ ] **Step 4: Rodar e ver passar**

Run: o mesmo do Step 2. Expected: `All tests passed!`

- [ ] **Step 5: Commit**

```bash
git add app/lib/integracoes/http/cliente_proxy.dart app/lib/integracoes/integracoes.dart app/lib/app/web/endereco_api.dart app/test/integracoes/http/cliente_proxy_test.dart app/test/app/web/endereco_api_test.dart
git commit -m "Web: cliente que leva Yahoo e Google News ao servidor intermediário"
```

---

### Task 4: Servidor intermediário — base, Yahoo e Google News

**Files:**
- Create: `web_servidor/package.json` (`{"private": true, "type": "module", "engines": {"node": "22.x"}}`), `web_servidor/vercel.json`
- Create: `web_servidor/api/_lib/http.js`, `web_servidor/api/_lib/repasse.js`
- Create: `web_servidor/api/yahoo/chart/[ticker].js`, `web_servidor/api/noticias/rss.js`, `web_servidor/api/noticias/resolver.js`, `web_servidor/api/noticias/artigo/[gid].js`
- Test: `web_servidor/test/http.test.js`, `web_servidor/test/yahoo.test.js`, `web_servidor/test/noticias.test.js`

**Interfaces:**
- Consumes: nada (Node 22).
- Produces (usados pelas Tasks 5 e 6):
  - `origensPermitidas(env) -> string[]` (de `env.ORIGENS_PERMITIDAS`, separadas por vírgula; mais `http://localhost:*` e `http://127.0.0.1:*` por regra).
  - `origemDoPedido(request) -> string | null` (cabeçalho `Origin`; senão a origem do `Referer`).
  - `criarRota({ metodos: { GET?, POST? }, limite: number, cache?: string, exigirOrigem = true }, dep) -> { GET?, POST?, OPTIONS }` — confere origem (403 `{"erro":"origem"}`), limite por IP em janela de 60 s (429 `{"erro":"limite"}` com `Retry-After: 30`), responde `OPTIONS` (204 com `Access-Control-Allow-Origin` = origem, `Allow-Methods: GET, POST, OPTIONS`, `Allow-Headers: content-type, accept-language`, `Max-Age: 600`), põe `Access-Control-Allow-Origin` + `Access-Control-Expose-Headers: x-url-final, content-type` + `Vary: Origin` nas respostas a pedidos com `Origin`, e transforma exceções em 502 `{"erro":"indisponivel"}` sem detalhes.
  - `repassar(url, { fetch, metodo = 'GET', corpo, tipo, tempoMs = 8000, cache }) -> Response` — repassa status, corpo e `content-type`; `Cache-Control` só em 200; falha de rede/tempo → 502.
  - Cada rota exporta `criar(dep)` (`dep = { fetch, env, agora }`) e os métodos ligados ao `dep` padrão (`export const { GET, OPTIONS } = criar(depPadrao)`), na assinatura Web-standard do Vercel.
  - Limites por IP/min: Yahoo 240, notícias 120. Cabeçalhos ao destino: `User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36`, `Accept-Language: pt-BR,pt;q=0.9`.

- [ ] **Step 1: Escrever os testes que falham** (`node:test` + `node:assert/strict`, `fetch` falso que grava as chamadas)

`http.test.js`: sem `Origin` e sem `Referer` → 403; `Origin: https://evil.example` → 403; `Referer: https://calculadora-darf.vercel.app/` → aceito; `Origin: http://localhost:5173` → aceito com `access-control-allow-origin` igual; `OPTIONS` de origem permitida → 204 com os cabeçalhos acima; 241º pedido do mesmo IP (`x-forwarded-for`) em 60 s na rota Yahoo → 429 com `retry-after: 30`; a contagem zera com `agora` 61 s depois.

`yahoo.test.js`:
```js
test('repassa o chart com só os parâmetros permitidos', async () => {
  const { GET } = criar({ fetch: fetchFalso(200, '{"chart":{}}'), env, agora: () => 0 });
  const r = await GET(pedido('/api/yahoo/chart/PETR4.SA?range=5d&interval=1d&x=1'));
  assert.equal(r.status, 200);
  assert.equal(chamadas[0].url, 'https://query1.finance.yahoo.com/v8/finance/chart/PETR4.SA?range=5d&interval=1d');
  assert.match(r.headers.get('cache-control'), /s-maxage=30/);
  assert.equal(r.headers.get('vary'), 'Origin');
});
```
mais: parâmetros aceitos são só `range, interval, period1, period2, includePrePost`; ticker fora de `^[A-Z0-9]{1,12}\.SA$` (ex.: `..%2Fetc`, `PETR4`) → 400 sem chamar o `fetch`; Yahoo 404 → 404 repassado; `fetch` que rejeita ou passa de 8 s → 502 `{"erro":"indisponivel"}`.

`noticias.test.js`: `rss` repassa só `q, hl, gl, ceid` para `https://news.google.com/rss/search` (q > 300 caracteres → 400), `s-maxage=300`; `resolver` aceita só POST `application/x-www-form-urlencoded` com corpo começando por `f.req=` e ≤ 4096 bytes, repassa o corpo idêntico para `https://news.google.com/_/DotsSplashUi/data/batchexecute`, sem cache; GET no `resolver` → 405; `artigo` com gid fora de `^[A-Za-z0-9_-]{10,600}$` → 400, válido vai para `https://news.google.com/rss/articles/{gid}` com `s-maxage=300`.

- [ ] **Step 2: Rodar e ver falhar**

Run (na raiz): `node --test web_servidor/test/`
Expected: FAIL (`Cannot find module`).

- [ ] **Step 3: Implementar `_lib/http.js`, `_lib/repasse.js` e as quatro rotas; `vercel.json`**

`vercel.json`: `{"framework": null, "buildCommand": "", "installCommand": "", "outputDirectory": ".", "functions": {"api/**/*.js": {"maxDuration": 10}}, "headers": [...]}` com `Cache-Control: no-cache` para `/`, `/index.html`, `/flutter_bootstrap.js`, `/main.dart.js`, `/version.json`, `/manifest.json`, e `X-Content-Type-Options: nosniff` e `Referrer-Policy: strict-origin-when-cross-origin` em `/(.*)`.

- [ ] **Step 4: Rodar e ver passar**

Run: `node --test web_servidor/test/`
Expected: `# fail 0`.

- [ ] **Step 5: Commit**

```bash
git add web_servidor
git commit -m "Servidor da Web: origem, limite, Yahoo e Google News"
```

---

### Task 5: Servidor intermediário — prévias seguras das notícias

**Files:**
- Create: `web_servidor/api/_lib/rede_publica.js`, `web_servidor/api/noticias/pagina.js`, `web_servidor/api/noticias/imagem.js`
- Test: `web_servidor/test/previas.test.js`

**Interfaces:**
- Consumes: `criarRota` (Task 4).
- Produces:
  - `ipPublico(ip: string) -> boolean` — false para `0.0.0.0/8`, `10/8`, `100.64/10`, `127/8`, `169.254/16`, `172.16/12`, `192.168/16`, `198.18/15`, `224/4` e acima, `::`, `::1`, `fc00::/7`, `fe80::/10` e IPv4 mapeado (`::ffff:a.b.c.d`) privado.
  - `buscarPublico(url, { fetch, lookup, tipos: RegExp, maxBytes, tempoMs = 8000, maxRedirecionamentos = 3 }) -> { status, tipo, corpo: Uint8Array, urlFinal }` — lança `ErroPrevia(status)`.
  - `GET /api/noticias/pagina?url=` (só `text/html`, até 1 MB: o que passar é cortado em 1 MB, porque o app só lê até `</head>`) e `GET /api/noticias/imagem?url=` (só `image/*`, acima de 2 MB → 413); ambos com `x-url-final`, `content-type` repassado e `s-maxage=3600`; limite 120/min por IP.
  - Erros: URL não `http(s)` ou IP não público → 400 `{"erro":"destino"}`; tipo errado → 415; mais de 3 redirecionamentos → 508; tempo → 504; falha de rede → 502.

- [ ] **Step 1: Escrever os testes que falham**

`ipPublico` para cada faixa acima (inclui `169.254.169.254` e `::ffff:10.0.0.1` → false; `8.8.8.8` e `2606:4700::1111` → true). `pagina` com `lookup` falso: host que resolve para `10.0.0.5` → 400 sem chamar o `fetch`; `http://localhost/` → 400; redirecionamento 302 para `http://169.254.169.254/` → 400 (conferido no 2º salto); 4 redirecionamentos públicos → 508; `content-type: application/pdf` → 415; HTML de 1,5 MB → 200 com 1 048 576 bytes; resposta com redirecionamento público → `x-url-final` = URL do último salto; `fetch` chamado com `redirect: 'manual'`. `imagem`: `image/png` de 3 MB → 413; `text/html` → 415; `image/jpeg` pequeno → 200 com `s-maxage=3600`. Sem origem → 403.

- [ ] **Step 2: Rodar e ver falhar** — Run: `node --test web_servidor/test/previas.test.js` → FAIL.

- [ ] **Step 3: Implementar** — `lookup` padrão `dns.promises.lookup(host, { all: true })`, todos os endereços têm de ser públicos; o corpo é lido em fluxo e interrompido ao passar do limite (`AbortController` para o tempo).

- [ ] **Step 4: Rodar e ver passar** — Run: `node --test web_servidor/test/` → `# fail 0`.

- [ ] **Step 5: Commit**

```bash
git add web_servidor
git commit -m "Servidor da Web: prévias das notícias só de endereços públicos"
```

---

### Task 6: Servidor intermediário — login Google pelo servidor

**Files:**
- Create: `web_servidor/api/_lib/cifra.js`, `web_servidor/api/auth/inicio.js`, `web_servidor/api/auth/retorno.js`, `web_servidor/api/auth/token.js`, `web_servidor/api/auth/sair.js`
- Test: `web_servidor/test/cifra.test.js`, `web_servidor/test/auth.test.js`

**Interfaces:**
- Consumes: `criarRota`, `origensPermitidas` (Task 4).
- Produces:
  - Variáveis de ambiente (só no painel do Vercel): `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET`, `CHAVE_PACOTE` (32 bytes em base64), `ORIGENS_PERMITIDAS`, `URL_RETORNO`. Faltando alguma → 500 `{"erro":"configuracao"}`.
  - `cifrar(dados: object, chaveB64) -> 'v1.' + base64url(iv[12] ‖ tag[16] ‖ texto)` (AES-256-GCM); `decifrar(pacote, chaveB64) -> object` (lança `ErroPacote`).
  - `GET /api/auth/inicio?volta=<origem>`: `volta` tem de estar em `origensPermitidas` (senão 400); 302 para `https://accounts.google.com/o/oauth2/v2/auth` com `client_id`, `redirect_uri = URL_RETORNO`, `response_type=code`, `scope` = os 3 escopos de `escoposGoogle` separados por espaço, `access_type=offline`, `prompt=consent`, `code_challenge` (S256), `code_challenge_method=S256`, `state` (16 bytes aleatórios base64url); `Set-Cookie: __Host-darf_oauth=<cifrar({s, v, o: volta, e: agora + 600000})>; HttpOnly; Secure; SameSite=Lax; Path=/; Max-Age=600`. Limite 30/min por IP; sem exigência de `Origin` (é navegação).
  - `GET /api/auth/retorno`: cookie ausente/ilegível → 400 HTML "Login não concluído. Volte para a Calculadora DARF e tente de novo."; `state` diferente ou vencido → 302 `<volta>/#auth_erro=estado`; `error=access_denied` → `#auth_erro=acesso_negado`; outro `error` ou troca sem `refresh_token` → `#auth_erro=falhou`; sucesso: POST `https://oauth2.googleapis.com/token` (form: `code`, `client_id`, `client_secret`, `redirect_uri`, `grant_type=authorization_code`, `code_verifier`) e 302 `<volta>/#auth=<cifrar({r: refresh_token, t: agora})>`. Sempre apaga o cookie (`Max-Age=0`), `Cache-Control: no-store`, `Referrer-Policy: no-referrer`.
  - `POST /api/auth/token` corpo JSON `{"pacote": "..."}` (exige origem; limite 30/min): pacote inválido → 401 `{"erro":"sessao"}`; Google 400/401 → 401 `{"erro":"sessao"}`; Google 429/5xx/rede → 503 `{"erro":"indisponivel"}`; 200 → `{"access_token", "expires_in", "pacote"?}` (`pacote` só se o Google devolver `refresh_token` novo); `Cache-Control: no-store`.
  - `POST /api/auth/sair` `{"pacote"}` (exige origem): se decifrar, POST `https://oauth2.googleapis.com/revoke` com `token=<refresh>`; responde 204 sempre.

- [ ] **Step 1: Escrever os testes que falham**

`cifra.test.js`: ida e volta; um caractere trocado → `ErroPacote`; outra chave → `ErroPacote`; sem `v1.` → `ErroPacote`.
`auth.test.js` (env completo, `fetch` falso, `agora` fixo): `inicio` com `volta=https://evil.example` → 400; `inicio` válido → 302 cujo `Location` tem os parâmetros listados (conferir `scope` exato e `redirect_uri`), cookie com `HttpOnly`, `Secure`, `SameSite=Lax`, `Max-Age=600`; `retorno` com `state` ≠ cookie → `Location` = `https://calculadora-darf.onrender.com/#auth_erro=estado` (cookie com `o` do Render); `error=access_denied` → `#auth_erro=acesso_negado`; sucesso → `fetch` do token recebeu `code_verifier` = `v` do cookie, `Location` começa com `https://calculadora-darf.vercel.app/#auth=v1.` e `decifrar(pacote).r === 'rt-1'`; sem `refresh_token` → `#auth_erro=falhou`; cookie vencido (`agora` + 11 min) → `#auth_erro=estado`; `token` com pacote válido → 200 `{access_token: 'at', expires_in: 3599}`; Google `400 invalid_grant` → 401 `{"erro":"sessao"}`; Google 503 → 503; pacote adulterado → 401; origem `https://evil.example` → 403; Google devolve `refresh_token: 'rt-2'` → resposta com `pacote` que decifra para `r: 'rt-2'`; `sair` → `fetch` do revoke com corpo `token=rt-1`, 204; env sem `CHAVE_PACOTE` → 500 `{"erro":"configuracao"}`.

- [ ] **Step 2: Rodar e ver falhar** — Run: `node --test web_servidor/test/` → FAIL nos testes novos.

- [ ] **Step 3: Implementar** com `node:crypto` (`createCipheriv('aes-256-gcm')`, `randomBytes`, `createHash('sha256')`).

- [ ] **Step 4: Rodar e ver passar** — Run: `node --test web_servidor/test/` → `# fail 0`; e `git grep -n "client_secret" -- app/lib` continua mostrando só o fluxo do app instalado (`login.dart`, `token.dart`, `credenciais.dart`).

- [ ] **Step 5: Commit**

```bash
git add web_servidor
git commit -m "Servidor da Web: login Google com PKCE e pacote cifrado"
```

---

### Task 7: Login Google na Web (lado do app)

**Files:**
- Modify: `app/lib/integracoes/google/sessao.dart` (renovação injetável), `app/lib/integracoes/google/google.dart` (login e saída injetáveis)
- Create: `app/lib/integracoes/google/login_web.dart` (exportar em `integracoes.dart`)
- Test: `app/test/integracoes/google/login_web_test.dart`; casos novos em `sessao_test.dart` e `google_test.dart`

**Interfaces:**
- Consumes: `ClienteHttp`, `TokenGoogle`, `lerToken`/`gravarToken`, `LoginNecessario`, `Offline`, `ErroGoogle`, `AbrirUrl`.
- Produces:
  - `typedef RenovarToken = Future<TokenGoogle> Function(TokenGoogle atual);` e `SessaoGoogle({..., RenovarToken? renovar})` — sem ele, `renovarToken(http, t)` como hoje.
  - `typedef FazerLogin = Future<String> Function(AbrirUrl abrirUrl, {Future<void>? cancelar});` e `Google({..., FazerLogin? fazerLogin, void Function(TokenGoogle? token)? aoSair})`; `temCredencial` = `cliente != null || fazerLogin != null`; `login` usa `fazerLogin` quando houver; `sair` lê o token (falha → `null`), chama `sessao.sair()` e depois `aoSair`.
  - Em `login_web.dart`: `const marcadorServidor = 'servidor';` `void gravarPacoteWeb(Armazenamento a, String pacote)` (grava `TokenGoogle(refreshToken: pacote, clientId: marcadorServidor, clientSecret: marcadorServidor)` sem `token` nem `expiry`, no `token.json`); `Uri urlInicioLogin(Uri api, Uri origem)` = `$api/auth/inicio?volta=<origem.origin>`; `FazerLogin criarLoginWeb({required Uri api, required Uri origem, required Future<void> Function(Uri url) irPara})`; `RenovarToken criarRenovadorWeb(ClienteHttp http, Uri api)`; `Future<void> revogarWeb(ClienteHttp http, Uri api, String pacote)` (engole erros); `sealed class RetornoLogin`, `final class RetornoPacote(String pacote)`, `final class RetornoErro(String codigo)`; `RetornoLogin? lerRetornoLogin(Uri endereco)`; `(String, String) avisoRetorno(RetornoErro e)`.

- [ ] **Step 1: Escrever os testes que falham**

- `sessao_test.dart`: com `token.json` vencido e `renovar: (t) async => TokenGoogle(token: 'novo', refreshToken: t.refreshToken, clientId: t.clientId, clientSecret: t.clientSecret, expiry: <agora + 1 h>)`, `carregarToken()` faz um único pedido HTTP (`GET .../drive/v3/about` com `Authorization: Bearer novo`) e nenhum a `oauth2.googleapis.com`.
- `google_test.dart`: `Google(cliente: null, fazerLogin: ...)` → `temCredencial` true e `login` delega; `sair()` com `token.json` de pacote `v1.p` → `aoSair` recebe token com `refreshToken == 'v1.p'` e o `token.json` some; `token.json` ilegível → `aoSair(null)` e sem exceção.
- `login_web_test.dart`, com `api = Uri.parse('https://calculadora-darf.vercel.app/api')`:
```dart
test('pacote gravado vira token vencido para renovar', () {
  final a = ArmazenamentoMemoria();
  gravarPacoteWeb(a, 'v1.p');
  final t = lerToken(a)!;
  expect((t.refreshToken, t.clientId, t.clientSecret), ('v1.p', marcadorServidor, marcadorServidor));
  expect(t.valido(ambiente.agora()), isFalse);
});
test('URL de início leva a origem de volta', () {
  expect(urlInicioLogin(api, Uri.parse('https://calculadora-darf.onrender.com/#/')).toString(),
      'https://calculadora-darf.vercel.app/api/auth/inicio?volta=https%3A%2F%2Fcalculadora-darf.onrender.com');
});
```
  `criarLoginWeb`: `irPara` chamado uma vez com essa URL e o futuro não termina; completar `cancelar` → `ErroGoogle('O login foi cancelado.')`; `irPara` que lança → `ErroGoogle('O login não foi concluído.')`. `criarRenovadorWeb` com `MockClient`: POST `$api/auth/token`, `Content-Type: application/json`, corpo `{"pacote":"v1.p"}`; 200 `{"access_token":"a","expires_in":3599}` → `token == 'a'`, `refreshToken == 'v1.p'`, `valido` true; 200 com `"pacote":"v1.q"` → `refreshToken == 'v1.q'`; 401 → `LoginNecessario('Sessão expirada. Faça login novamente.')`; 503 → `Offline`; `ClientException` → `Offline`. `revogarWeb` com 500 ou erro de rede → completa sem lançar, POST `$api/auth/sair` com `{"pacote":"v1.p"}`. `lerRetornoLogin`: `https://x/#auth=v1.` + 40 caracteres base64url → `RetornoPacote`; `#auth_erro=acesso_negado` → `RetornoErro('acesso_negado')` e `avisoRetorno` → `('Login não concluído', 'O login foi cancelado.')`; `#auth=lixo` → `RetornoErro('falhou')` → `('Login não concluído', 'O login não foi concluído.')`; `#auth_erro=estado` → mesmo aviso de "falhou"; `#/` e sem fragmento → `null`.

- [ ] **Step 2: Rodar e ver falhar**

Run: `flutter test test/integracoes/google/`
Expected: FAIL nos casos novos.

- [ ] **Step 3: Implementar** — pacote aceito só se casar `^v1\.[A-Za-z0-9_-]{20,4096}$`; `carregarToken` e `_renovar` de `SessaoGoogle` usam `renovar`.

- [ ] **Step 4: Rodar e ver passar**

Run: `flutter test test/integracoes/` → `All tests passed!` (os testes atuais do login loopback seguem verdes).

- [ ] **Step 5: Commit**

```bash
git add app/lib/integracoes/google app/lib/integracoes/integracoes.dart app/test/integracoes/google
git commit -m "Web: login e renovação do token pelo servidor"
```

---

### Task 8: Serviços na thread da interface

**Files:**
- Create: `app/lib/app/servicos/servicos_reais.dart` (recebe `TimersServicos`, as constantes de intervalo e `_ServicosReais`, que vira `ServicosReais`)
- Modify: `app/lib/app/servicos/servicos_isolate.dart` (usa `servicos_reais.dart` e o reexporta: `export 'servicos_reais.dart';`)
- Create: `app/lib/app/servicos/servicos_web.dart`
- Test: `app/test/app/servicos/servicos_web_test.dart`

**Interfaces:**
- Consumes: `ClienteProxy`, `DestinoLivre` (Task 3); `ArmazenamentoChaveValor`, `executarDireto` (Task 2); `criarLoginWeb`, `criarRenovadorWeb`, `revogarWeb` (Task 7; o `aoSair` revoga `token?.refreshToken` quando não é nulo); `CacheBinarioMemoria` (existente).
- Produces:
  - `class ServicosReais extends ServicosLocais` (mesmo construtor e comportamento de hoje: `cliente`, `timers`, timers ligados no fim de `iniciar`, `encerrar` fecha o cliente).
  - `ServicosApp criarServicosWeb({required Uri api, required Uri origem, required Armazenamento armazenamento, required Future<void> Function(Uri url) irPara, required Future<bool> Function(Uri url) abrirUrl, http.Client? cliente, bool timers = true})` — `ServicosReais` sem `atualizador` nem `fazerBackup`; `ServicoYahoo` e `ServicoNoticias` sobre `ClienteProxy(livre: pagina)`, `Logos` e o cliente das imagens sobre `ClienteProxy(livre: imagem)`; Google sobre o cliente direto, `SessaoGoogle(renovar: criarRenovadorWeb(...), executar: executarDireto)`, `Google(fazerLogin: criarLoginWeb(...), aoSair: (t) { if (t?.refreshToken != null) unawaited(revogarWeb(http, api, t!.refreshToken!)); })`; `executarDireto` em `ServicoYahoo` e `ServicoNoticias`; `CacheBinarioMemoria`; timers com `intervaloSyncPadrao(windows: false)`. Não importa `dart:io`, `dart:isolate` nem `servicos_isolate.dart`.

- [ ] **Step 1: Escrever os testes que falham** (VM, `MockClient` que grava pedidos, `ArmazenamentoMemoria`, `timers: false`)

- `cotacao('PETR4')` → um pedido a `https://calculadora-darf.vercel.app/api/yahoo/chart/PETR4.SA?range=5d&interval=1d`, sem `User-Agent`.
- com `gravarPacoteWeb(a, 'v1.' + 'p' * 30)`, `iniciar()` e depois `(s as ServicosReais).tickSync()` → primeiro pedido POST `.../api/auth/token` com o pacote; depois `GET https://www.googleapis.com/drive/v3/about` com `Bearer at`; `conta()` tem `email` da resposta.
- **Review Focus 1:** `/api/auth/token` responde 401 → depois do `tickSync`, `a.existe('token.json')` false, `conta()` com `temToken` false e `status == StatusSync.off`, e um `EventoAviso` com texto contendo `Sessão expirada`.
- `conectar()` → `irPara` recebeu `https://calculadora-darf.vercel.app/api/auth/inicio?volta=https%3A%2F%2Fcalculadora-darf.vercel.app` e `conta().status == StatusSync.login`.
- `sair()` com pacote gravado → POST `.../api/auth/sair`.
- `verificarAtualizacao()` → `throwsStateError` ("Atualizador não configurado.").
- Os testes atuais de `servicos_isolate` e `TimersServicos` continuam passando sem mudar os imports.

- [ ] **Step 2: Rodar e ver falhar** — Run: `flutter test test/app/servicos/servicos_web_test.dart` → FAIL.

- [ ] **Step 3: Mover `TimersServicos`/`_ServicosReais` para `servicos_reais.dart` (sem mudar comportamento) e escrever `criarServicosWeb`.**

- [ ] **Step 4: Rodar e ver passar**

Run: `flutter test test/app/servicos/ test/integracoes/isolate_real_test.dart` e `flutter analyze`
Expected: `All tests passed!` e `No issues found!`

- [ ] **Step 5: Commit**

```bash
git add app/lib/app/servicos app/test/app/servicos/servicos_web_test.dart
git commit -m "Web: serviços na mesma thread, com proxy, localStorage e login pelo servidor"
```

---

### Task 9: PlataformaWeb, entrada condicional e partida

**Files:**
- Modify: `app/lib/app/plataforma/plataforma.dart` (`web`, `areasSeguras`), `app/test/app/apoio/plataforma_falsa.dart`
- Create: `app/lib/app/plataforma/plataforma_web.dart` (só Web)
- Create: `app/lib/app/web/entrada_web.dart` (puro), `app/lib/app/web/entrada.dart` (export condicional), `app/lib/app/web/entrada_stub.dart`, `app/lib/app/web/entrada_navegador.dart` (só Web), `app/lib/app/web/areas_seguras.dart` (puro)
- Modify: `app/lib/app/app.dart` (`iniciarApp`, `_AppMaterial`)
- Test: `app/test/app/web/entrada_web_test.dart`, `app/test/app/web/areas_seguras_test.dart`, casos novos em `app/test/app/app_test.dart`, `app/test/web/plataforma_web_test.dart`

**Interfaces:**
- Consumes: `criarServicosWeb` (Task 8); `chaveValorDoNavegador`, `ArmazenamentoChaveValor` (Task 2); `enderecoApi` (Task 3); `lerRetornoLogin`, `gravarPacoteWeb`, `avisoRetorno` (Task 7).
- Produces:
  - Em `Plataforma`: `bool get web;` e `ValueListenable<EdgeInsets>? get areasSeguras;` (`PlataformaReal`: `false` e `null`; `PlataformaFalsa({this.windows = true, this.web = false})`, `areasSeguras` campo anulável).
  - `class PlataformaWeb implements Plataforma` (`windows` false, `web` true): `abrirUrl` com `launchUrl(..., webOnlyWindowName: '_blank')`; `navegar(Uri)` com `'_self'`; `copiarTexto` com `Clipboard`; notificações pela Notification API quando existe e foi permitida (toque → `window.focus()` e `aoTocar(link)`), senão nada; `pedirPermissaoNotificacoes` → true só com permissão `granted`; `instalarAtualizacao` sem efeito; `Future<bool> travarAbaUnica()` (Web Locks `navigator.locks.request('calculadora-darf', {ifAvailable: true})`, segurando a trava; sem a API → true); `void limparEndereco()` (`history.replaceState` para o caminho sem fragmento); `areasSeguras` lidas de um elemento com `padding: env(safe-area-inset-*)` e relidas no `resize`.
  - `class ErroOutraAba implements Exception` com `toString()` = `'A Calculadora DARF já está aberta em outra aba ou janela deste navegador. Feche a outra e toque em "Tentar de novo".'`
  - `class EntradaWeb { EntradaWeb({required Plataforma plataforma, required Future<ServicosApp> Function(Plataforma) criarServicos}); (String, String)? avisoInicial; }`
  - `Future<ServicosApp> prepararServicosWeb({required Uri endereco, required Armazenamento? armazenamentoNavegador, required Future<bool> Function() travarAba, required void Function() limparEndereco, required Future<void> Function(Uri) irPara, required Future<bool> Function(Uri) abrirUrl, required void Function(String titulo, String texto) avisar, http.Client? cliente, bool timers = true})` — ordem: trava (false → `ErroOutraAba`, sem tocar no armazenamento); armazenamento nulo → `ArmazenamentoMemoria` e aviso `('Dados do navegador bloqueados', 'O navegador não permite que o app guarde dados neste site. O app funciona, mas será preciso entrar de novo a cada visita.')`; retorno do login → `limparEndereco()` e grava o pacote ou avisa `avisoRetorno`; depois `criarServicosWeb(api: enderecoApi(endereco), origem: endereco, ...)`.
  - `EntradaWeb? entradaWeb()` — `null` fora da Web; na Web chama `BrowserContextMenu.disableContextMenu()` (o menu do botão direito do app aparece no navegador) e monta `EntradaWeb` com `PlataformaWeb` e `prepararServicosWeb`.
  - `MediaQueryData comAreasSeguras(MediaQueryData m, EdgeInsets extra)` — `padding` e `viewPadding` = máximo por lado entre o atual e `extra`.
  - `iniciarApp`: `final web = (plataforma == null && criarServicos == null && servicos == null) ? entradaWeb() : null;` usa `web.plataforma`/`web.criarServicos` quando houver; o aviso de partida é o da migração ou `web?.avisoInicial`; `EstadoApp(serv, plat, verificarAtualizacaoAutomatica: kReleaseMode && !plat.web)`. `_AppMaterial` aplica `comAreasSeguras` quando `plataforma.areasSeguras != null` (entre `MediaQuery.fromView` e o `MaterialApp`) e usa `onGenerateInitialRoutes: (_) => [MaterialPageRoute<void>(builder: (_) => <home>)]` para ignorar qualquer fragmento restante.

- [ ] **Step 1: Escrever os testes que falham**

`entrada_web_test.dart` (VM, `MockClient`, `timers: false`):
- **Review Focus 2:** `travarAba: () async => false` → `throwsA(isA<ErroOutraAba>())` e o armazenamento continua vazio; com `iniciarApp(criarServicos: (_) async => throw const ErroOutraAba(), plataforma: PlataformaFalsa(web: true))` → `find.text(<texto de ErroOutraAba>)` e o botão "Tentar de novo".
- endereço `https://calculadora-darf.vercel.app/#auth=v1.<40 chars>` → `token.json` com esse pacote e `limparEndereco` chamado uma vez.
- `#auth_erro=acesso_negado` → `avisar('Login não concluído', 'O login foi cancelado.')`, `limparEndereco` chamado, sem `token.json`.
- **Review Focus 5:** `armazenamentoNavegador: null` → serviços sobem e `avisar('Dados do navegador bloqueados', ...)`.
- sem fragmento → `limparEndereco` não é chamado.

`areas_seguras_test.dart`: `comAreasSeguras(MediaQueryData(padding: EdgeInsets.only(top: 10)), EdgeInsets.only(top: 47, bottom: 34))` → `padding` e `viewPadding` `top: 47, bottom: 34`.

`app_test.dart`: `iniciarApp(servicos: s, plataforma: PlataformaFalsa(web: true))` → o `EstadoApp` da árvore tem `verificarAtualizacaoAutomatica == false`; com `PlataformaFalsa(web: true)..areasSeguras = ValueNotifier(EdgeInsets.only(bottom: 34))`, `MediaQuery.of` dentro do `MaterialApp` tem `padding.bottom == 34`.

`test/web/plataforma_web_test.dart` (`@TestOn('browser')`): duas chamadas a `travarAbaUnica()` na mesma página → `true` e depois `false`; **Review Focus 3:** removendo `Notification` do `globalThis` (`dart:js_interop_unsafe`) antes de criar a `PlataformaWeb`, `iniciarNotificacoes` e `notificar` completam sem erro e `pedirPermissaoNotificacoes()` é `false`.

- [ ] **Step 2: Rodar e ver falhar**

Run: `flutter test test/app/web test/app/app_test.dart` e `flutter test --platform chrome test/web`
Expected: FAIL (símbolos inexistentes).

- [ ] **Step 3: Implementar** (`entrada.dart`: `export 'entrada_stub.dart' if (dart.library.js_interop) 'entrada_navegador.dart';`).

- [ ] **Step 4: Rodar e ver passar**

Run: `flutter analyze`, `flutter test --exclude-tags golden,vivo`, `flutter test --platform chrome test/web`, `flutter build web --release --no-wasm-dry-run`
Expected: `No issues found!`, `All tests passed!` (duas vezes) e `√ Built build\web`.

- [ ] **Step 5: Commit**

```bash
git add app/lib/app app/test/app app/test/web
git commit -m "Web: plataforma do navegador, aba única, áreas seguras e partida sem isolate"
```

---

### Task 10: Portão de login e telas da Web

**Files:**
- Create: `app/lib/app/telas/login_web/tela_login_web.dart`
- Modify: `app/lib/app/regras/textos.dart` (textos da tela), `app/lib/app/app.dart` (`home`), `app/lib/app/telas/conta/tela_conta.dart` (`_BlocoSobre`)
- Test: `app/test/app/telas/login_web_test.dart`, `app/test/app/telas/layout_web_test.dart`

**Interfaces:**
- Consumes: `Plataforma.web` (Task 9); `EstadoApp.conta` (`EstadoConta`), `EstadoApp.proximoAviso()`, `ServicosApp.conectar()`.
- Produces:
  - `class PortaoLoginWeb extends StatelessWidget { const PortaoLoginWeb({required Widget child}); }` — mostra `TelaLoginWeb` quando `!conta.temToken && conta.email == null`; senão `child`. `_AppMaterial`: `home: plataforma.web ? const PortaoLoginWeb(child: Casca()) : const Casca()`.
  - `class TelaLoginWeb` — centrada, largura máxima 420, `SafeArea`, com rolagem; consome os avisos com `proximoAviso()` e mostra o último num quadro acima do botão (título em negrito + texto).
  - Textos (em `textos.dart`): `textoLoginWebTitulo = 'Entre com a sua conta Google'`; `textoLoginWebCorpo = 'A Calculadora DARF guarda os seus dados na sua planilha do Google, a mesma usada pelo app do PC e do Android.'`; botão `'Entrar com o Google'` (com `status == StatusSync.login`: desabilitado, `'Abrindo o Google...'`); `textoLoginWebContasAutorizadas = 'Por enquanto, só entram contas autorizadas. Se o Google mostrar "Acesso bloqueado", peça para cadastrarem o seu e-mail e tente de novo. Se aparecer "O Google não verificou este app", toque em "Avançado" e continue.'`
  - Na Conta, `_BlocoSobre` esconde "Verificar atualização" e a mensagem dela quando `plataforma.web`.

- [ ] **Step 1: Escrever os testes que falham** (`montarApp` com `ServicosFalsos` e `PlataformaFalsa`)

`login_web_test.dart`:
- `web: true`, `estadoConta = EstadoConta(temCredencial: true)` → acha `textoLoginWebTitulo`, `'Entrar com o Google'` e `textoLoginWebContasAutorizadas`; `find.byType(Casca)` vazio.
- tocar no botão → `ServicosFalsos` registra a chamada `conectar`.
- `EstadoConta(temCredencial: true, temToken: true)` → `Casca` aparece; idem com `email: 'a@b.c'`.
- `web: false` sem token → `Casca` (Windows/Android sem mudança).
- **Review Focus 1:** `estado.avisar('Sessão expirada', 'Conecte sua conta Google novamente.')` com `web: true` sem token → os dois textos aparecem na tela de login.
- `EstadoConta(status: StatusSync.login, temCredencial: true)` → `'Abrindo o Google...'` com o botão desabilitado.
- Conta com `web: true` → sem `'Verificar atualização'`; com `web: false` → presente.

`layout_web_test.dart` (alturas baixas e teclado): para `Size(320, 568)`, `Size(390, 844)` e `Size(667, 375)`, `web: true`, `windows: false`, com token: `montarApp` + `pumpAndSettle` → `t.takeException()` nulo; tela de login (sem token) nos três tamanhos → sem exceção; formulário de compra aberto (`apoio/abrir_formulario.dart`) em `Size(390, 844)` com `t.view.viewInsets = FakeViewPadding(bottom: 336)` → sem exceção e o botão de confirmar visível após `ensureVisible`.

- [ ] **Step 2: Rodar e ver falhar** — Run: `flutter test test/app/telas/login_web_test.dart test/app/telas/layout_web_test.dart` → FAIL.

- [ ] **Step 3: Implementar a tela, o portão e o ajuste da Conta.** Overflow achado no `layout_web_test` é corrigido no widget responsável, sem mudar texto nem cálculo.

- [ ] **Step 4: Rodar e ver passar**

Run: `flutter test --exclude-tags golden,vivo` e `flutter test --tags golden test/app/goldens`
Expected: `All tests passed!` nas duas (goldens sem mudança).

- [ ] **Step 5: Commit**

```bash
git add app/lib/app app/test/app/telas
git commit -m "Web: login obrigatório e ajustes de tela para celular"
```

---

### Task 11: CI — build, testes e publicação da Web

**Files:**
- Create: `app/ci/montar_web.sh`, `app/ci/publicar_web.sh`, `app/ci/conferir_web.sh`, `app/ci/testar_ci_web.sh`
- Modify: `.github/workflows/release.yml`

**Interfaces:**
- Consumes: `app/build/web` (Task 1+), `web_servidor/` (Tasks 4-6), `urlVercel` (Task 3, via `--dart-define=URL_VERCEL`).
- Produces:
  - `montar_web.sh <build_web> <servidor> <saida>`: falha sem `<build_web>/index.html`; copia `build_web/.`, `servidor/api`, `servidor/vercel.json`, `servidor/package.json` para `<saida>` (recriada); falha com `::error::` se houver `credentials*.json` em qualquer lugar de `<saida>` ou a palavra `client_secret` fora de `<saida>/api`.
  - `publicar_web.sh <saida> <remoto> <versao>`: clona `web-dist` do `<remoto>` (ou cria órfã se não existir), troca todo o conteúdo pelo de `<saida>`, commit `Web <versao> (<GITHUB_SHA ou local>)` com o usuário `github-actions[bot]` e `git push origin web-dist` **sem** `--force`; sem mudança → `::notice::` e sai 0.
  - `conferir_web.sh <versao> <url_vercel> <url_render> [--sem-api]` (`TENTATIVAS`=20, `ESPERA`=30 s): `version.json` das duas URLs com `.version == <versao>`; sem `--sem-api`: `GET <url_vercel>/api/yahoo/chart/PETR4.SA?range=5d&interval=1d` com `Origin: <url_render>` → 200 e `access-control-allow-origin` = `<url_render>`; sem `Origin`/`Referer` → 403.
  - `release.yml`: `env` no topo `URL_VERCEL: https://calculadora-darf.vercel.app` e `URL_RENDER: https://calculadora-darf.onrender.com`; `workflow_dispatch.inputs.publicar_web` (boolean, padrão false, "Publicar o build Web na branch web-dist"); job `web` (ubuntu, `needs: versao`, todos os eventos); job `publicar-web`; `conferir-atualizador` com `needs: [versao, publicar, publicar-web]` e o passo novo.

- [ ] **Step 1: Escrever `testar_ci_web.sh` (o teste que falha)**

Casos, em pastas temporárias: (1) `montar_web.sh` com build falso (`index.html`, `version.json`) → sai 0 e `<saida>` tem `index.html`, `api/auth/token.js`, `vercel.json`, `package.json`; (2) build falso com `assets/assets/google/credentials.json` → sai 1 e imprime `::error::`; (3) `main.dart.js` com `client_secret` → sai 1; (4) `publicar_web.sh` contra `git init --bare` duas vezes com conteúdos diferentes → `git log web-dist --oneline` com 2 commits, o 2º filho do 1º; terceira vez igual → continua 2 commits; (5) `conferir_web.sh 9.9.9 <http://127.0.0.1:PORTA> <idem> --sem-api` com `python -m http.server` servindo `{"version":"9.9.9"}` e `TENTATIVAS=1 ESPERA=0` → 0; com `version` 9.9.8 → 1.

- [ ] **Step 2: Rodar e ver falhar** — Run: `bash app/ci/testar_ci_web.sh` → FAIL (scripts ausentes).

- [ ] **Step 3: Escrever os três scripts.**

- [ ] **Step 4: Rodar e ver passar** — Run: `bash app/ci/testar_ci_web.sh` → `ok: 5 casos`.

- [ ] **Step 5: Alterar `release.yml`**

Job `web`: checkout; `actions/setup-node@v4` (Node 22); `node --test web_servidor/test/`; `bash app/ci/testar_ci_web.sh`; `subosito/flutter-action@v2` (3.47.9, stable, cache); em tag, grava `app/lib/versao.dart` como os outros jobs (bash); `flutter pub get`; `flutter test --platform chrome test/web`; `flutter build web --release --no-wasm-dry-run --build-name "$VERSAO" --build-number "$NUMERO" --dart-define=URL_VERCEL="$URL_VERCEL"`; `bash app/ci/montar_web.sh app/build/web web_servidor saida-web`; `actions/upload-artifact@v4` (`name: web`, `path: saida-web`). **Sem** o passo de `GOOGLE_CREDENTIALS`.
Job `publicar-web`: `needs: [versao, testes, android, windows, web, publicar]`, `permissions: contents: write`, `if: ${{ !cancelled() && needs.web.result == 'success' && needs.testes.result == 'success' && ((github.event_name == 'push' && github.ref_type == 'tag' && needs.publicar.result == 'success') || (github.event_name == 'workflow_dispatch' && inputs.publicar_web)) }}`; checkout; download do artefato `web` em `saida-web`; `bash app/ci/publicar_web.sh saida-web "https://x-access-token:${GH_TOKEN}@github.com/${GITHUB_REPOSITORY}.git" "$VERSAO"` com `GH_TOKEN: ${{ github.token }}`; `::notice title=Web::` com o hash publicado.
`conferir-atualizador`: passo "Web publicada nas duas URLs" → `bash app/ci/conferir_web.sh "$VERSAO" "$URL_VERCEL" "$URL_RENDER"`, com `::error title=Web::` na falha.

Run: `python -c "import yaml,sys; d=yaml.safe_load(open('.github/workflows/release.yml', encoding='utf-8')); print(sorted(d['jobs']))"`
Expected: `['android', 'conferir-atualizador', 'publicar', 'publicar-web', 'testes', 'versao', 'web', 'windows']`.

- [ ] **Step 6: Commit**

```bash
git add app/ci .github/workflows/release.yml
git commit -m "CI: build, testes e publicação da Web na branch web-dist"
```

---

### Task 12: Release 2.6.0 — versão e notas

**Files:**
- Modify: `app/lib/versao.dart` (`'2.6.0'`), `app/test/versao_test.dart`
- Create: `docs/release/2.6.0.md`

**Interfaces:**
- Consumes: tudo acima.
- Produces: árvore pronta para a tag `v2.6.0` (feita na Task 13).

- [ ] **Step 1: Teste que falha** — em `versao_test.dart`, título "versaoApp tem formato x.y.z e vale 2.6.0" e `expect(versaoApp, '2.6.0')`. Run: `flutter test test/versao_test.dart` → FAIL.

- [ ] **Step 2: Versão e notas**

`versao.dart` com `'2.6.0'`. `docs/release/2.6.0.md`, no formato da 2.5.0:
```markdown
## Calculadora DARF 2.6.0

Versão Web: o mesmo app no navegador do iPhone, iPad, Android, PC e Mac. Sem mudanças de cálculo nem da planilha.

### O que muda

- Endereço principal: https://calculadora-darf.vercel.app (reserva: https://calculadora-darf.onrender.com).
- Entre com a sua conta Google: os dados vêm da mesma planilha do app do PC e do Android, e o que você registrar na Web aparece nos outros aparelhos.
- No iPhone, abra no Safari e use Compartilhar > Adicionar à Tela de Início para usar como app, em tela cheia.
- Cotações e notícias funcionam na Web. Notificações só com a página aberta e se o navegador permitir.
- Por enquanto só entram contas autorizadas. Se o Google mostrar "Acesso bloqueado", peça o cadastro do seu e-mail.
- Na Web não há atualizador: a página sempre abre na versão mais nova.

### Voltar para a versão anterior

Sem migração de dados: é possível voltar para a 2.5.0 sem perda.
```
(Se a Task 13 mudar os endereços, esta nota acompanha.)

- [ ] **Step 3: Verificação completa**

Run (em `app/`): `flutter analyze`; `flutter test --exclude-tags golden,vivo`; `flutter test --tags golden test/app/goldens`; `flutter test --platform chrome test/web`; `flutter build web --release --no-wasm-dry-run --build-name 2.6.0 --build-number 20600`; na raiz: `node --test web_servidor/test/`; `bash app/ci/testar_ci_web.sh`; `git diff 5d70df1 --stat -- calculadora_darf.py android/ atualizador.py nucleo.py metas.py sugestoes.py mercado.py noticias.py tests/ app/lib/nucleo/`
Expected: `No issues found!`; `All tests passed!` (três vezes); `√ Built build\web` e `build/web/version.json` com `"version":"2.6.0"`; `# fail 0`; `ok: 5 casos`; o último diff mostra só `app/lib/nucleo/armazenamento_chave_valor.dart` (novo).

- [ ] **Step 4: Commit**

```bash
git add app/lib/versao.dart app/test/versao_test.dart docs/release/2.6.0.md
git commit -m "Versão 2.6.0: notas da release"
```

---

### Task 13: Infraestrutura, verificação ponta a ponta e publicação (controlador, com Claude in Chrome)

Executada pelo controlador (não por subagente), com o navegador do dono já logado (skill `anthropic-skills:chrome-browser`) e o agente `monitor-ci` para o GitHub Actions. Nenhum segredo vai para arquivo, git, commit ou relatório: o `client_secret` e a `CHAVE_PACOTE` passam do painel de origem direto para o campo do Vercel.

**Exige o dono (o controlador para e pede):**
- (D1) Autorizar o acesso das integrações GitHub do Vercel e do Render ao repositório `JoaoGabrielOT/CalculadoraDARF`, se o GitHub pedir.
- (D2) Cadastrar os e-mails de teste em Google Cloud > APIs e serviços > Tela de consentimento OAuth > Usuários de teste (até 100), incluindo a conta usada no teste abaixo.
- (D3) Testar no iPhone real: Safari, "Adicionar à Tela de Início", login, áreas seguras (notch e barra inferior), teclado sobre o formulário de compra.
- (D4) Autorizar a tag `v2.6.0` e a escrita reversível na planilha durante o teste.

- [ ] **Step 1: Push da branch e CI verde** — o controlador faz `git push origin migracao-flutter`; `monitor-ci` acompanha. Aceite: execução Success com os jobs `versao`, `testes`, `android`, `windows`, `web` verdes e `publicar`/`publicar-web` pulados.

- [ ] **Step 2: Criar a `web-dist`** — GitHub > Actions > Release > Run workflow, branch `migracao-flutter`, `publicar_web` marcado. Aceite: job `publicar-web` Success; a branch `web-dist` existe com `index.html`, `version.json` (`2.6.0`), `api/auth/token.js`, `vercel.json`, `package.json` e sem `credentials.json`.

- [ ] **Step 3: Cliente OAuth Web no Google Cloud** — no mesmo projeto do cliente "Desktop" atual: Credenciais > Criar ID do cliente OAuth > "Aplicativo da Web", nome "Calculadora DARF Web"; URIs de redirecionamento: `https://calculadora-darf.vercel.app/api/auth/retorno` e `http://localhost:3000/api/auth/retorno`; sem origens JavaScript. Conferir que a tela de consentimento está em "Teste" e lista os três escopos. Aceite: cliente criado; ID e segredo disponíveis só no painel.

- [ ] **Step 4: Projeto no Vercel** — Add New > Project > importar o repositório; nome `calculadora-darf`; Framework "Other"; Root Directory `.`; Build e Install Command vazios (override); Output Directory `.`. Settings > Git: Production Branch = `web-dist`; Ignored Build Step = `if [ "$VERCEL_GIT_COMMIT_REF" = "web-dist" ]; then exit 1; else exit 0; fi`. Settings > Environment Variables (Production): `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET` (Sensitive), `CHAVE_PACOTE` (Sensitive; gerar com `node -e "console.log(require('crypto').randomBytes(32).toString('base64'))"` e colar sem gravar), `ORIGENS_PERMITIDAS=https://calculadora-darf.vercel.app,https://calculadora-darf.onrender.com`, `URL_RETORNO=https://calculadora-darf.vercel.app/api/auth/retorno`. Redeploy da `web-dist`. Aceite: `https://calculadora-darf.vercel.app/version.json` mostra `2.6.0`; `curl -s -o /dev/null -w "%{http_code}" -H "Origin: https://calculadora-darf.vercel.app" "https://calculadora-darf.vercel.app/api/yahoo/chart/PETR4.SA?range=5d&interval=1d"` → `200`; sem `Origin` → `403`. Se as funções não responderem (assinatura Web-standard não aceita), trocar o adaptador de `criarRota` para `export default async function handler(req, res)` numa correção pequena com teste, nova execução do Step 2.

- [ ] **Step 5: Static Site no Render** — New > Static Site > repositório, branch `web-dist`, nome `calculadora-darf`, Build Command vazio, Publish Directory `.`; Redirects/Rewrites: `/*` → `/index.html` (Rewrite); Headers: `Cache-Control: no-cache` para `/index.html`, `/main.dart.js`, `/flutter_bootstrap.js`, `/version.json`, `/manifest.json`. Aceite: `https://calculadora-darf.onrender.com/version.json` mostra `2.6.0`.

- [ ] **Step 6: Endereços reais** — se o Vercel ou o Render deram outro endereço (nome ocupado), atualizar `URL_VERCEL`/`URL_RENDER` no `release.yml`, o `defaultValue` de `urlVercel` (`app/lib/app/web/endereco_api.dart`) e os testes da Task 3, as notas da 2.6.0, `ORIGENS_PERMITIDAS`/`URL_RETORNO` no Vercel e o redirecionamento no Google; commit "Endereços reais da Web" e repetir o Step 2. Aceite: `bash app/ci/conferir_web.sh 2.6.0 <url_vercel> <url_render>` sai 0.

- [ ] **Step 7: Verificação ponta a ponta** (Chrome no PC, conta de teste cadastrada em D2; registrar o resultado de cada item)
  1. Vercel abre a tela de login com `textoLoginWebContasAutorizadas`; `main.dart.js` não contém `client_secret` (`curl -s .../main.dart.js | grep -c client_secret` → `0`).
  2. Login: "Entrar com o Google" → Google → volta para a Vercel já conectado; Conta mostra o e-mail e o link da planilha (a mesma do app do PC); endereço sem `#auth=`.
  3. Cotação: Radar mostra o preço de PETR4; na aba Rede, `/api/yahoo/chart/...` 200.
  4. Notícia: Notícias lista itens; ao menos um com resumo ou imagem (pedidos `/api/noticias/*` 200).
  5. Planilha: meses e lançamentos iguais aos do app do PC. Com D4: registrar uma compra de teste na Web, ver na planilha e no app do PC após a sincronização, excluir e ver sumir dos três.
  6. Recarregar (F5) e fechar/reabrir a aba: continua conectado (`/api/auth/token` 200).
  7. Segunda aba com o mesmo endereço: mensagem de `ErroOutraAba`.
  8. Render: mesmo login termina no `onrender.com` conectado; cotação funciona (pedido ao Vercel com CORS). Abrir o Radar na Vercel e em seguida no Render em menos de 30 s: a cotação do Render continua funcionando (cache de borda + `Vary: Origin`). Se falhar, trocar o `Cache-Control` do Yahoo para `private, max-age=30` (teste da Task 4 ajustado) e republicar.
  9. Sair: volta à tela de login; `/api/auth/sair` 204.
  10. Segurança por `curl`: `Origin: https://evil.example` → 403; `/api/noticias/pagina?url=http://169.254.169.254/` com origem válida → 400.
  11. PWA: Chrome DevTools > Application > Manifest sem erros e ícones carregados; opção "Instalar" disponível.
  12. (D3) iPhone: resultado informado pelo dono.

  Aceite: itens 1-11 OK (12 quando o dono informar). Falha num item vira correção com `superpowers:systematic-debugging` antes de seguir.

- [ ] **Step 8: Tag e publicação da 2.6.0** (com D4) — o controlador cria e envia a tag `v2.6.0` no commit verificado; `monitor-ci` acompanha. Aceite: execução Success com `publicar`, `publicar-web` e `conferir-atualizador` verdes; `/releases/latest` = 2.6.0 estável com o `.exe` e o `.apk`; `web-dist` ganhou o commit `Web 2.6.0 (...)` sem force push; as duas URLs mostram `2.6.0`; anotação `::notice title=Atualizadores::` presente.

- [ ] **Step 9: Registro** — `docs/superpowers/plans/2026-11-13-versao-web-resultado.md` no padrão dos resultados anteriores (o que foi feito, saídas dos comandos, resultado de cada item do Step 7, pendências do dono); commit "Resultado da versão Web".

---

## Self-review (feito ao escrever)

1. **Cobertura da spec:** plataforma web, `index.html`/manifesto/`apple-touch-icon`/`viewport-fit` (T1); `dart:io`/`dart:isolate` atrás de condicional ou injeção (T2 executor, T8 sem `servicos_isolate`, T9 entrada); serviços sem isolate e proxy separado de `criarServicosLocais` (T8); `ArmazenamentoNavegador` com `darf:` e logos em memória (T2, T8); `PlataformaWeb` (T9); login pelo servidor com as 4 funções, PKCE, redirect de página inteira, pacote no `localStorage` por POST, mesmos escopos (T6, T7, T8); login obrigatório e aviso de contas autorizadas (T10); rede por host e `/api` relativo/absoluto (T3); layout (T9 áreas seguras e menu do botão direito, T10 alturas e teclado); servidor com allowlist, origem, CORS, limite por IP e testes (T4-T6); job no `release.yml`, `web-dist` sem force push, verificação nos pushes, `conferir-atualizador` (T11, T13); Vercel, Render, OAuth e ponta a ponta (T13); release 2.6.0 (T12, T13). Riscos: aviso de app não verificado (T10), expiração de 7 dias (Review Focus 1), Yahoo bloqueado (502 claro, T4), desempenho sem isolate (aceito pela spec; executor direto na T2).
2. **Passos:** cada passo de código traz assinatura, arquivo e valores; os de teste trazem nomes e asserções; os de verificação, comando e saída.
3. **Tipos:** `ChaveValor`/`ArmazenamentoChaveValor` (T2→T8, T9); `ClienteProxy`/`DestinoLivre`/`enderecoApi`/`urlVercel` (T3→T8, T9, T13); `RenovarToken`/`FazerLogin`/`criarLoginWeb`/`criarRenovadorWeb`/`revogarWeb`/`gravarPacoteWeb`/`lerRetornoLogin`/`avisoRetorno` (T7→T8, T9); `ServicosReais`/`criarServicosWeb` (T8→T9); `Plataforma.web`/`areasSeguras`/`ErroOutraAba`/`EntradaWeb`/`prepararServicosWeb` (T9→T10). Rotas `/api/...` iguais em T3, T4-T6 e T7.
4. **Review Focus:** os cinco casos têm teste na tarefa dona (indicada em cada linha).
5. **Proporção:** os blocos de código são só testes-chave e os textos fixados; os corpos ficam com o implementador.
