# Versão Web (2.6.0): resultado, verificação e pendências do dono

Concluído em 14/11/2026 na branch `migracao-flutter` (cabeça `898ad87`, antes deste documento; tag `2.6.0` publicada). Spec: `docs/superpowers/specs/2026-11-13-versao-web-design.md`. Plano: `docs/superpowers/plans/2026-11-13-versao-web.md`. O registro tarefa a tarefa está em `.superpowers/sdd/2026-11-13-versao-web/progress.md` (local, fora do git).

A Web leva o mesmo app Flutter (`app/`) a iPhone, iPad, Android, PC e Mac pelo navegador, instalável na Tela de Início (PWA). Cada pessoa entra com a própria conta Google e usa a própria planilha. Nenhum cálculo, texto ou formato de planilha mudou; o Windows e o Android continuam com as mesmas suítes verdes.

## Implementado

- **App (T1, T2, T8, T9, T10):** plataforma web (`app/web/`: `index.html` com `viewport-fit=cover`, manifesto PWA, ícones, `apple-touch-icon`); todo `dart:io`/`dart:isolate` atrás de import condicional ou injeção; serviços diretos no mesmo thread (`criarServicosWeb`, `executarDireto`); `ArmazenamentoNavegador` sobre `localStorage` (chaves `darf:`), com erro próprio para armazenamento cheio ou bloqueado; `PlataformaWeb` (abrir URL em nova aba, copiar, Notification API quando permitida, áreas seguras do iPhone); atualizador, instalador e backup em pasta escondidos; aba única (a segunda aba mostra o aviso de outra aba); tela de login obrigatória (`TelaLoginWeb`) com aviso de que só contas autorizadas entram, aviso de "Sessão expirada" e tratamento do bfcache (`pageshow` com `persisted`).
- **Login Google pelo servidor (T6, T7):** fluxo de código com PKCE por redirecionamento de página inteira, com `state` e nonce ligados ao navegador (`GuardaNonce`, `sessionStorage`). O servidor troca o código e devolve ao site um pacote `v1.…` com o refresh token cifrado; o site o guarda no `localStorage` e o envia no corpo do POST (sem cookies de terceiros, igual no Vercel e no Render). Só 401 vira "login necessário"; erro de servidor ou resposta malformada vira "offline" sem apagar o token.
- **Servidor intermediário (T3, T4, T5):** funções Node em `web_servidor/api/`: `/api/yahoo/chart/{ticker}`, `/api/noticias/{rss,resolver,artigo/{gid},pagina,imagem}`, `/api/auth/{inicio,retorno,token,sair}`. Lista fechada de destinos, só origem do Vercel, do Render e localhost, CORS só para elas, `Vary: Origin` em toda resposta, CSP `sandbox` e `frame-ancestors 'none'` nas respostas repassadas, limite por IP, bloqueio de IPs privados, de metadados de nuvem e de redirecionamentos nas prévias (`/api/noticias/pagina`, `/api/noticias/imagem`).
- **Publicação (T11, T12):** job `web` (compila a Web e roda os testes no Chrome) e `publicar-web` (commit novo na branch `web-dist`, sem force push) no `release.yml`; job `conferir-web` confere as duas URLs e a versão. `montar_web.sh` e `testar_ci_web.sh` montam e conferem a saída (inclusive a ausência do segredo do Google no bundle). Versão 2.6.0 e `docs/release/2.6.0.md`.

## Infraestrutura (T13)

- **Endereços:** https://calculadora-darf-web.vercel.app (principal) e https://calculadora-darf.onrender.com (reserva), ambos servidos da branch `web-dist`. O nome `calculadora-darf.vercel.app` já pertencia a outra pessoa; o antigo `calculadora-darf-beta.vercel.app` redireciona.
- **Google Cloud:** cliente OAuth "Calculadora DARF Web" (Aplicativo da Web) no projeto `calculadora-darf-512412`. Redirecionamentos: o do Vercel acima mais `/api/auth/retorno`, e `http://localhost:3000/api/auth/retorno`. App em modo "Testando", com 4 usuários de teste.
- **Vercel:** projeto `calculadora-darf`, branch de produção `web-dist`, Ignored Build Step "Only build production". O segredo do cliente e a `CHAVE_PACOTE` ficam só nas variáveis do Vercel (Sensitive). `ORIGENS_PERMITIDAS` = as duas origens; `URL_RETORNO` = o do Vercel.
- **Render:** Static Site `calculadora-darf` (branch `web-dist`), rewrite `/*` para `/index.html`; cabeçalhos `frame-ancestors 'none'`, `X-Frame-Options: DENY` e no-cache em `/`, `/index.html`, `/main.dart.js`, `/flutter_bootstrap.js`, `/version.json` e `/manifest.json`.

## Testado

- **CI:** run 43614190897 (primeiro com os testes no Chrome verdes), 43617578870 (`325a298`); publicações da `web-dist` 43632870870 e 43634577071; tag `2.6.0`, run 43635919597, success em todos os jobs (`versao`, `testes`, `android`, `windows`, `web`, `publicar`, `publicar-web`, `conferir-atualizador`, `conferir-web`).
- **curl, nas duas URLs:** `version.json` = 2.6.0; ocorrências do padrão `GOCSPX` no `main.dart.js` = 0; `package.json`, `api/_lib/*` e `vercel.json` respondem 404; Yahoo com origem própria = 200, sem origem = 403, origem estranha = 403, origem do Render = 200 com `Access-Control-Allow-Origin` do Render, CSP `sandbox; default-src 'none'; frame-ancestors 'none'` e `Vary: Origin`; `/api/noticias/pagina?url=http://169.254.169.254/` = 400 `{"erro":"destino"}`; RSS = 200; `/api/auth/inicio` sem `n` = 400 e com `n` = 302 para o Google; o index traz `frame-ancestors` e `X-Frame-Options` nos dois.
- **Chrome (PC), feito pelo dono e pelo controlador:** Vercel: tela de login, login Google, volta conectado; Apuração com os dados da planilha e cotações; Notícias com itens e logos; Radar com cotações e gráficos. Recarregar a página mantém o login; a segunda aba mostra o aviso de outra aba. Render: login, conectado, Radar com cotações vindas do Vercel. Compra de teste PETR4 1 x R$ 1 registrada, sincronizada, excluída pelo menu do botão direito e sincronizada de novo. Sair volta à tela de login.

## Publicado

- Tag `2.6.0`, **Latest**, release estável. `CalculadoraDARF.exe` 12906990 bytes, sha256 `8f25ee17…c049`; `CalculadoraDARF.apk` 44498700 bytes, sha256 `3fb45380…89a1`; commit da `web-dist` `14263e6`.

## Não verificado

- PWA instalado e iPhone real (pendente do dono, D3).
- Desempenho de `reduzirParaJpeg`, que roda na thread da interface (medir em uso real).
- Instalação do PWA pelo DevTools.

## Pendências do dono

1. Testar no iPhone: Safari, Adicionar à Tela de Início, login, áreas seguras e teclado sobre os formulários.
2. Cadastrar novos usuários de teste no Google Cloud quando precisar (limite de 100).
3. Ativar 2FA no Vercel (recomendado).
4. No modo de teste, o Google pode pedir login de novo a cada 7 dias (refresh token expira); a pessoa só entra de novo, os dados estão na planilha. A verificação do app OAuth pelo Google continua fora do escopo.

## Decisões principais (Ruling)

- **Tag sem "v":** `2.6.0`, convenção do repositório.
- **Segredo no bundle:** a checagem procura o valor (padrão `GOCSPX-` e arquivos `credentials*.json`) fora de `api/`, não a palavra `client_secret`, que existe legitimamente no código Dart do login/token.
- **`dart:io` transitivo (desvio da spec):** a Web não importa `dart:io` diretamente nem `servicos_isolate.dart`; `atualizador_local` e `cliente.dart` ainda o importam, mas compilam na Web e não executam lá. Custo futuro: refatoração se o Flutter endurecer.
- **`/api/auth/retorno` sem exigir `Origin`** (navegação vinda do Google), mas com `state` e cookie obrigatórios, com teste.
- **`Vary: Origin` em toda resposta** (T4), para o CORS do Render não quebrar com cache; o servidor não segue redirecionamentos ao repassar (proxy aberto).
- **Login forçado (T6):** nonce por navegador e `lerRetornoLogin(nonceEsperado)`; localhost só com origens de desenvolvimento; rótulo de propósito no cifrado. Acrescentados ao escopo por segurança.
- **Renovação (T7):** pacote rotacionado é gravado; só 401 desconecta.
- **Aviso "Sessão expirada" só na Web** (T8), sem mudar o `Sincronizador` compartilhado.
- **Testes no Chrome** (`test/web`) rodam no CI, não localmente (T2, T7, T9); aceitos como evidência.
- **Aba única:** `_trava` volta a false para permitir "Tentar de novo" depois que a outra aba fecha.
- **Prévia de notícias (T5):** só portas 80/443, sem credenciais na URL, SVG recusado (415), destino não-2xx = 502 (o app trata como sem prévia); HTML cortado em 1 MB (o app lê só até `</head>`).
- **`conferir-web` separado** de `conferir-atualizador`, que continua dependendo só de `versao` e `publicar`.
- **Revisão final:** uma onda de correção (`9fe0fb3..a74b7af`): token.js 400/401 que não sejam `invalid_grant` viram 503; `_renovar` com try/catch; defesas (CSP sandbox, nosniff etc.) em todo repasse; `pageshow` persistido; `frame-ancestors`. Depois, ajuste `325a298` (CSP de frames só fora de `/api`, funções levam `frame-ancestors` e `X-Frame-Options`), confirmado em produção por curl.

## Minors adiados que ficaram

- Servidor: 502 do catch sem cabeçalhos CORS (`http.js`); `x-url-final` sem teste; teste de timeout espera 8 s reais; `fetchFixado` sem teste automatizado; `content-encoding` deflate/encadeado repassado comprimido; faixas IPv6/IPv4 especiais fora do bloqueio (SIIT `::ffff:0:0/96`, `64:ff9b:1::/48`, Teredo, documentação); `lerPacote` lê tudo antes de checar 8 KB; pacote sem idade máxima; Google 400 `invalid_client` vira "sessão"; exceção genérica no retorno sem apagar cookie/no-store; `outputDirectory '.'` pode servir `test/` e fonte (conferido em produção: `package.json`, `api/_lib/*` e `vercel.json` dão 404).
- App: `Uri.tryParse` e `queryParametersAll` no parser de retorno; catch genérico e `remover` sem try no armazenamento; texto de Offline novo "O servidor não respondeu (HTTP n)…"; testes faltando (guardar lança, 429, `expires_in` ausente); `_msgSessao` duplicado e `FazerLogin` puxando `login.dart` ao grafo Web; `RetornoErro.codigo` sem filtro; `gravarToken` em `_renovar` sem try/catch (falha de disco derruba o pedido; parcialmente tratado na onda final); adaptador `abrirUrl`/`_msgNavegador` duplicado; `textos.dart` importa `servicos_isolate`; `Casca` declarada duas vezes (`routes` e `onGenerateInitialRoutes`); testes do `app_test` dependentes de ordem; rota ou diálogo empilhado sobrevive à queda da sessão (`popUntil` no `initState` da `TelaLoginWeb`); leitura antiga da conta pode sobrescrever `EventoConta`; `saidaPedida` público; fundo da tela de carregamento; nome de teste.
- CI: `conferir_web` depende do Yahoo responder 200; `grep || true` engole erro; `${{ }}` em `run:`; caminho da API do `conferir_web` sem teste automatizado; `\r` não escapado no `::error`.
- Documentação: o aviso "uma aba por vez" e a frase "Cotações e notícias funcionam na Web" foram confirmados após o deploy (cotações e notícias verificadas no Chrome).
