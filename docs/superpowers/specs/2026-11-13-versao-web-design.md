# Versão Web da Calculadora DARF — design

Data: 13/11/2026. Base: app Flutter 2.5.0 (branch `migracao-flutter`, pasta `app/`).

## Intenção
Quem usa iPhone não consegue instalar o APK. A versão Web leva o mesmo app a qualquer aparelho (iPhone, iPad, Android, PC, Mac) pelo navegador, com layout adaptado a celular e PC, instalável na Tela de Início (PWA). Cada pessoa usa a própria conta Google e a própria planilha, como no app do PC/Android, e os dados aparecem nos outros aparelhos dela.

## Objetivos
- Mesmo código Flutter (`app/`), compilado com `flutter build web`; mesmas telas, temas, cálculos e textos.
- Login Google por pessoa e sincronização com a planilha dela (mesmo formato da planilha do app; a função Amigos continua funcionando).
- Cotações (Yahoo) e notícias (Google News) funcionando no navegador por um servidor intermediário próprio.
- Hospedagem (decisão do dono, opção 1): **Vercel** com o site e o servidor intermediário (funções em `/api/...`); **Render** com uma segunda cópia do site (endereço reserva) que usa o servidor do Vercel.
- PWA: manifesto, ícones, `apple-touch-icon`, tela cheia, áreas seguras do iPhone (notch/barra inferior).
- Cada release estável (tag) também publica a Web, automaticamente.

## Fora do escopo / não-objetivos
- Atualizador, instalador, backup em pasta e migração da 1.12 (não existem na Web; escondidos).
- Notificações com o site fechado (Web Push). Com a aba aberta: aviso dentro do app e, se a pessoa permitir, notificação do navegador.
- Domínio próprio (usar os endereços grátis `*.vercel.app` e `*.onrender.com`).
- Verificação do app OAuth pelo Google (processo do dono, semanas). Ver Riscos.

## Anti-objetivos (seria falha mesmo funcionando)
- Mudar qualquer cálculo, texto ou formato da planilha que o app do PC/Android lê.
- Quebrar o app Windows/Android (as mudanças para a Web entram por import condicional/injeção; as suítes atuais continuam verdes).
- Proxy aberto: o servidor intermediário só repassa os endereços listados abaixo e só para chamadas do próprio site.
- Guardar segredo no site público (nenhum `client_secret` no bundle Web) ou usar tokens/credenciais do git ou do ambiente local.

## Restrições
- Planos grátis do Vercel e do Render. Sem `gh`. Credenciais nunca em repositório; segredo, se precisar, só como variável de ambiente no painel do Vercel.
- Deploy sem tokens: o CI (GITHUB_TOKEN, `contents: write`) publica o build Web numa branch `web-dist`; Vercel e Render ficam ligados a essa branch pela integração com o GitHub (configurada pelo navegador do dono, já logado).
- O Safari do iPhone apaga o armazenamento de sites não usados por 7 dias (exceto PWA instalado): a planilha é a fonte segura dos dados; o armazenamento do navegador é cache.

## Abordagens consideradas
1. **Vercel = site + funções `/api`; Render = cópia do site usando o `/api` do Vercel** — escolhida pelo dono. Cotações rápidas (mesma origem, sem "acordar" servidor), tudo grátis, Render como reserva.
2. Vercel = site; Render = servidor intermediário — Render grátis dorme após 15 min (primeira cotação 30–60 s) ou US$ 7/mês.
3. Duas cópias completas, cada uma com servidor — redundância máxima, manutenção dobrada e o mesmo atraso do Render grátis.

## Desenho

### App (Flutter Web)
- Criar a plataforma web (`flutter create --platforms=web .`), `web/index.html` com `viewport-fit=cover`, manifesto PWA (nome "Calculadora DARF", ícones do app, `display: standalone`, cores do tema), `apple-touch-icon` e meta tags do iOS.
- **Compilação**: todo `dart:io`/`dart:isolate` (≈13 arquivos levantados: armazenamento_arquivos, cache_binario, http/cliente, google/login, atualizador, atualizador_local, plataforma, instalador, backup, pastas, migracao, executor, servicos_isolate) atrás de import condicional ou injeção, para o mesmo código compilar nas três plataformas.
- **Serviços**: na Web, `ServicosApp` roda direto no mesmo thread (`criarServicosLocais` sem isolate; `executarDireto`). Separar o proxy do isolate de `criarServicosLocais`.
- **Armazenamento**: `ArmazenamentoNavegador` (implementa `Armazenamento`, síncrono) sobre `localStorage`, chaves prefixadas (`darf:` + nome do arquivo). Cache de logos só em memória (as imagens vêm por URL).
- **Plataforma**: `PlataformaWeb` — abrir URL em nova aba; copiar texto pela API do navegador; notificação pela Notification API quando permitida (senão só o aviso no app); `instalarAtualizacao` sem efeito; telas de atualização e backup escondidas.
- **Login Google na Web — pelo servidor (decisão do dono)**, para a pessoa continuar logada por semanas, inclusive no iPhone e no PWA:
  - Cliente OAuth do tipo "Aplicativo da Web" no mesmo projeto do Google Cloud; redirect = `https://<vercel>/api/auth/retorno` (e localhost para desenvolvimento). Fluxo de código com PKCE por redirecionamento de página inteira (sem popup, que falha no PWA do iOS).
  - O `client_secret` e uma chave de cifra ficam só em variáveis de ambiente do Vercel (configuradas pelo painel), nunca no git nem no site.
  - Funções: `/api/auth/inicio` (monta a URL do Google com `state` e PKCE, guardando a origem de volta — Vercel ou Render — numa lista permitida), `/api/auth/retorno` (troca o código; devolve ao site um *pacote* com o refresh token **cifrado pela chave do servidor**), `/api/auth/token` (POST com o pacote → access token novo de ~1 h), `/api/auth/sair` (revoga).
  - O site guarda o pacote cifrado no `localStorage` (inútil sem o servidor) e o envia no corpo do POST — sem cookies de terceiros, então funciona igual no endereço do Render. Se o Safari apagar o armazenamento, a pessoa só entra de novo (os dados estão na planilha).
  - Mesmos escopos do app (inclui `drive.metadata.readonly`, exigido pela busca da planilha de amigos).
- **Login obrigatório na Web (decisão do dono)**: a primeira tela pede o login Google; sem login não há uso local.
- **Público (decisão do dono)**: até 100 conhecidos, app OAuth em modo de teste; o dono cadastra os e-mails no Google Cloud. A tela de login da Web avisa que só contas autorizadas entram e o que fazer se aparecer "acesso bloqueado".
- **Rede**: Yahoo e Google News passam pelo servidor intermediário (`/api/...`); Google Sheets/Drive e GitHub direto (aceitam chamadas do navegador). No Vercel o caminho é relativo (`/api`); fora dele (Render, localhost) usa o endereço absoluto do Vercel — decidido em tempo de execução pelo host, um único build.
- **Layout**: as telas já se adaptam pela largura (≥ 840 px = PC). Conferir alturas baixas, teclado do iPhone sobre formulários, áreas seguras e o menu do botão direito (só PC) no navegador.

### Servidor intermediário (funções do Vercel, Node, pasta `web/api/` na branch publicada)
- `GET /api/yahoo/chart/{ticker}?…` → `query1.finance.yahoo.com/v8/finance/chart/{ticker}` (repassa só os parâmetros usados pelo app; `User-Agent` de navegador; cache de borda 30 s).
- `GET /api/noticias/rss?…` → `news.google.com/rss/search`; `POST /api/noticias/resolver` → `news.google.com/_/DotsSplashUi/data/batchexecute`; `GET /api/noticias/artigo/{gid}` → `news.google.com/rss/articles/{gid}` (cache 5 min).
- Prévias das notícias (minha decisão: manter, como no app): `GET /api/noticias/pagina?url=` e `GET /api/noticias/imagem?url=` para o resumo/`og:image` da matéria — só `http(s)`, só IPs públicos (bloqueia localhost, redes privadas e metadados de nuvem, conferido após o DNS e a cada redirecionamento, máx. 3), só `text/html` (≤ 1 MB) ou `image/*` (≤ 2 MB), tempo-limite de 8 s, cache 1 h.
- Aceita só origem/referer do Vercel, do Render e localhost; responde CORS só para essas origens; recusa qualquer outro destino; limite simples por IP.
- Testes automatizados das funções (allowlist, origem recusada, repasse).

### Publicação
- Job novo no `release.yml` em tags: `flutter build web --release`, copia `web/api` e `vercel.json`/`render` config para o build e publica na branch `web-dist` (commit novo por release, sem force push). Também confere que o build Web compila nos pushes de branch (sem publicar).
- Vercel: projeto ligado à branch `web-dist`, saída estática + funções; Render: Static Site ligado à mesma branch, com rewrite de tudo para `index.html`.
- `conferir-atualizador` ganha uma checagem: as duas URLs respondem e mostram a versão da tag.

## Riscos
- **App OAuth não verificado**: tela de aviso no login; em modo de teste só entram contas cadastradas (até 100) e o Google pode expirar o refresh token de apps em teste após 7 dias — nesse caso a pessoa entra de novo (aviso claro, sem perda de dados). Abrir a qualquer pessoa exigiria a verificação e a avaliação de segurança do escopo restrito `drive.metadata.readonly` (fora do escopo).
- Pacote cifrado roubado do navegador permite pedir tokens ao servidor: mitigação pela lista de origens, limite por IP e `/api/auth/sair`; mesmo nível de risco do `token.json` do app no PC.
- Yahoo/Google News podem bloquear o IP do Vercel; mitigação: cache e mensagem clara de "cotação indisponível".
- Desempenho no iPhone sem isolate (parsing de XML/imagens na thread da interface).

## Deixado ao builder
- Estrutura exata dos imports condicionais, nomes de arquivos, testes Web (`flutter test --platform chrome` onde fizer sentido), detalhes do manifesto, limite por IP, nomes dos projetos no Vercel/Render (preferência: `calculadora-darf`).
