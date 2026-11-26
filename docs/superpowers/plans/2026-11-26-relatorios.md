# Aba "Relatórios" (Implementation Plan)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Mostrar no app (Windows, Android e Web), numa 6ª aba "Relatórios", o Relatório de Abertura de Mercado que uma automação grava todo dia útil numa pasta do Google Drive, com o visual do e-mail, cache local e a versão 2.7.0.

**Architecture:** Núcleo puro (`lib/nucleo/relatorios/`) com o modelo tolerante do JSON e as regras de data, ordenação e escolha. Integração Drive (`lib/integracoes/google/relatorios.dart`) sobre a `SessaoGoogle` existente. `RelatoriosLocal` (no isolate de serviços e, na Web, na thread da interface) junta Drive e `Armazenamento` (cache por `modifiedTime`) e devolve uma `VisaoRelatorios` pelo `ServicosApp`. A tela (`lib/app/telas/relatorios/`) segue o padrão de Notícias: controle `ChangeNotifier` que lê o cache primeiro e a rede em seguida.

**Tech Stack:** Flutter 3.47.9 / Dart 3.13.7, pacotes já usados (`http`, `provider`, `url_launcher`); `dart:developer` para o log; testes `flutter_test` (VM) e goldens (`--tags golden`, só no Windows); Node 22 `node:test` no `web_servidor`.

**Spec:** `docs/superpowers/specs/2026-11-26-relatorios-design.md` e o pedido do dono `prompt.md` (raiz do repositório principal, `D:\.Minhas_Coisas\calculadora DARF\CalculadoraDARF\prompt.md`), que vale por inteiro para comportamento, renderização, formato JSON, robustez e testes. Executores leem os dois e este plano.

## Global Constraints

Do pedido e do design, literalmente:
- "Use a stack, a camada de autenticação Google e os padrões já existentes. Não adicione dependências sem me perguntar."
- Pasta "Calculadora DARF - Relatórios", folderId `1pIy2wYGucMq_1Jitg96yWy8Bxu4ytn5B`; arquivos `relatorio-abertura-AAAA-MM-DD.json`.
- Listar: `files.list` com q = `'1pIy2wYGucMq_1Jitg96yWy8Bxu4ytn5B' in parents and trashed = false and name contains 'relatorio-abertura-'`, fields id, name, modifiedTime, "com paginação". Baixar: `files.get` com `alt=media`.
- Escopo: "trocar `drive.metadata.readonly` por `drive.readonly`" em `app/lib/integracoes/google/constantes.dart` e `web_servidor/api/auth/inicio.js`. "O Python 1.12 não muda."
- "Token antigo sem `drive.readonly`: a sincronização continua normal; só a aba Relatórios mostra 'Para ver os relatórios, entre de novo com o Google' com o botão de login (não desconecta ninguém)."
- "6ª aba 'Relatórios' entre Notícias e Conta (barra lateral no PC, barra inferior no celular)."
- "'hoje' em America/Sao_Paulo calculado como UTC−3 fixo [...] isolado numa função."
- Mensagem: "O relatório de hoje ainda não está disponível (fica pronto até 9h30 em dias de pregão)".
- Lista: "do mais recente para o mais antigo", "data por extenso e a contagem do termômetro em cores (ex.: 7 positivas · 7 mistas · 3 neutras · 5 negativas)".
- "Um botão 'Atualizar' que lista a pasta de novo. A pasta também é lida toda vez que a aba é aberta."
- Cache: "baixar de novo só quando o modifiedTime mudar. Sem internet, mostrar o que estiver em cache, com um aviso discreto." "Na Web o cache é descartável."
- Paleta (fixa, não muda com o tema): positiva `#1b7f3b`/`#e6f4ea`; negativa `#b3261e`/`#fce8e6`; mista `#b06000`/`#fef7e0`; neutra `#5f6368`/`#f1f3f4`; caixa azul `#e8f0fe`/`#174ea6`; faixas âmbar `#fef7e0`; `aviso` `#fff4e5`. Direção: "alta" verde com ▲, "queda" vermelho com ▼, "neutra" cinza sem seta.
- Seções a–k na ordem do pedido. "Todos os links abrem no navegador padrão."
- Robustez: campo ausente ou null → "—" ou linha escondida, "Nunca travar"; enum desconhecido → "neutra"; campos extras ignorados; `schemaVersion > 1` → renderiza com "aviso discreto de versão nova"; "JSON inválido ou arquivo fora do padrão de nome: ignorar, registrar no log e seguir com os outros."
- Esclarecimento do dono (26/11): a quantidade de ativos muda a cada relatório. "O app nunca pode supor um número fixo de ativos": lista, tabela, termômetro e cartões vêm do JSON e funcionam com 0, 1 e muitos (60) ativos sem quebrar o layout no celular. Se `termometro` divergir das leituras de `ativos`, mostrar os números de `termometro` e registrar a divergência no log.
- Reforço do dono (26/11): a aba funciona em todas as versões — Windows (layout expandido, barra lateral), Android (layout compacto, 6ª aba na barra inferior) e Web/PWA, inclusive iPhone. Na Web: Drive chamado direto do navegador com Bearer, sem passar pelo servidor do Vercel; cache no `localStorage` com o limite de espaço tratado (relatórios descartáveis, como as notícias); escopo novo também no login pelo servidor (`inicio.js`). Testes de widget e goldens nos dois layouts e nos 3 temas; teste no navegador (`@TestOn('browser')`) para a lógica de cache da Web; verificação final nas três plataformas.
- Release 2.7.0; tag `2.7.0` sem "v".
- Fora do escopo: gerar ou editar relatórios; notificação de relatório novo; outros tipos além de "abertura".

Do ambiente:
- Trabalhar só no worktree `D:\.Minhas_Coisas\calculadora DARF\CalculadoraDARF\.claude\worktrees\migracao-flutter`, branch `migracao-flutter`. Não tocar o código Python nem a `main`. Comandos Flutter rodam em `app/`.
- Builds Windows/Android só no CI; push e tag só pelo controlador. Goldens só no Windows (`flutter test --tags golden`).
- Todo commit termina com as linhas de atribuição da sessão que o fizer.

Fatos verificados no código (HEAD `1cd0a9d`):
- `escoposGoogle` (`constantes.dart`) = `drive.file`, `drive.metadata.readonly`, `spreadsheets.readonly`; o mesmo trio está em `web_servidor/api/auth/inicio.js` e nos testes `token_test.dart`, `login_test.dart`, `web_servidor/test/auth.test.js`.
- `TokenGoogle.scopes` é gravado no `token.json`, mas **não** são os escopos concedidos: `loginNavegador` grava `List.of(escoposGoogle)` (`login.dart:205`), `gravarPacoteWeb` usa o padrão e a ausência de `scopes` no arquivo vira `escoposGoogle`. Os tokens já gravados (2.6.0 e migrados da 1.12) trazem a lista antiga explícita.
- `renovarToken` envia `'scope': escoposGoogle.join(' ')` no refresh (`token.dart:169`). O renovador da Web (`/api/auth/token`) não envia `scope` e devolve só `access_token`/`expires_in`/`pacote`.
- `SessaoGoogle.req` devolve o JSON decodificado (`{}` se vazio), lança `ErroGoogle(msg, status)` para status >= 400 e `LoginNecessario` sem token em memória; não há getter de escopos.
- `ContaLocal.conectar` sai cedo se `_conta.email != null`; `Sincronizador.conectar(abrirUrl)` refaz o login sem sair (o login grava o token novo e `sessao.iniciar` troca a sessão). Na Web o retorno do login regrava o token com `gravarPacoteWeb` (`entrada_web.dart:63`).
- `ArmazenamentoArquivos.gravar` cria só a pasta raiz (subpasta falha) e `listar()` só vê arquivos da raiz; `ArmazenamentoChaveValor` descarta só `arquivosDescartaveis` quando o navegador enche.
- `ambiente.agoraBr()` já existe (`DataHora` com `fusoBrasilia = -10800`); `DataHora.noFuso` converte.
- `ServicosFalsos` implementa `ServicosApp` com `noSuchMethod`; `ServicosEco` (proxy do isolate) não. O golden de telas percorre `Aba.values` × 3 temas × PC/celular: a aba nova ganha goldens sozinha e **todos** os goldens de telas mudam (a barra ganha um destino).
- Não há log no app; `release.yml` roda `flutter test --exclude-tags golden,vivo` com `working-directory: app` e checkout completo (o teste lê `../tests/fixtures/`).
- Fixture real `tests/fixtures/relatorio-abertura-2026-11-26.json` (38,8 KB, ainda não commitada): schemaVersion 1, 22 ativos (posições 0–21), termômetro 7/7/3/5, 6 indicadores, 1 aviso de topo, 1 alerta, 3 ativos com `explicacao` (T1TW34, GOGL34, RURA11), 2 com `precoExterior` (T1TW34, GOGL34), 4 `fontesCenario`.

Suposições (confirmadas na Task 11):
- O Google recusa (`invalid_scope`) um refresh que pede escopo não concedido; por isso o refresh deixa de mandar `scope` (Task 3). Sem o `scope` o Google devolve o token com tudo o que foi concedido e informa `scope` na resposta.
- Com escopo insuficiente o Drive responde 403 com `reason: insufficientPermissions` (ou `ACCESS_TOKEN_SCOPE_INSUFFICIENT` em `details`).
- O Drive aceita CORS com `Authorization: Bearer` em `files.list` e `alt=media` a partir da Web (como já faz com Sheets).

## Decisões além do design (corrigíveis pelo dono)

1. **Fixture:** fica só em `tests/fixtures/` (onde o dono a pôs), lida pelos testes Flutter por `../tests/fixtures/relatorio-abertura-2026-11-26.json` através de um apoio único. Sem cópia em `app/test/`: uma fonte só, e o CI tem o checkout completo.
2. **Refresh sem `scope` e escopos concedidos gravados:** `renovarToken` para de enviar `scope`; login, refresh do app e refresh da Web gravam em `TokenGoogle.scopes` o `scope` devolvido pelo Google (na falta dele, mantêm o que havia). O servidor passa a repassar `scope` em `/api/auth/token`. Sem isso, trocar `escoposGoogle` faria o refresh dos tokens antigos pedir `drive.readonly` e desconectar todo mundo.
3. **"Entrar de novo" sem sair:** novo `ServicosApp.entrarDeNovoGoogle()` → `ContaLocal.reconectar()` → `Sincronizador.conectar` (sem o atalho de `email != null`). Cancelar o login não desconecta.
4. **Erro de escopo tipado:** `EscopoInsuficiente extends ErroGoogle` lançado por `SessaoGoogle.req` em 403 de escopo; `SessaoGoogle.escopos` expõe os escopos do token em memória.
5. **Cache:** `relatorios/indice.json` + `relatorios/<nome do arquivo>`. O índice guarda, por nome, `id`, `modificado`, `invalido` e o termômetro (resumo da lista). Só os `limiteConteudo` mais recentes têm o conteúdo baixado e guardado (10 no app, 5 na Web); os mais antigos aparecem na lista com a data e, se já foram baixados alguma vez, o termômetro; são baixados ao tocar. Isso evita baixar centenas de arquivos e estourar o `localStorage`.
6. **Log:** `dart:developer` `log(..., name: 'relatorios')`, injetável em `RelatoriosLocal` para os testes.
7. **Termômetro ausente** no JSON → contado pelas leituras dos ativos. Divergente → mostra o do JSON e registra no log.
8. **Textos novos** (fixados nas tarefas): legenda das leituras, aviso sem conexão, sem conta, lista vazia, versão nova, plurais ("1 positiva"/"2 positivas"), "N ativos do Radar" ("da lista reserva" quando `origemAtivos.aba == 'reserva'`).
9. **Layout:** PC = relatório à esquerda e "Relatórios anteriores" numa coluna de 320 px à direita; celular = botão "Anteriores" no topo que abre a lista numa folha inferior. Relatório num `CustomScrollView` com cartões preguiçosos (60 ativos). Tabela-resumo com rolagem horizontal no celular. Variações e selos sempre como pílula com o fundo da paleta (contraste nos temas escuros).
10. **Links:** só `http`/`https` viram link (por `EstadoApp.abrirLink`, que já avisa quando o navegador não abre); outros esquemas aparecem como texto.
11. **Duplicados:** dois arquivos com o mesmo nome na pasta → vale o de `modifiedTime` mais novo.

## Review Focus

1. **Token antigo depois de atualizar para a 2.7.0** (escopos gravados sem `drive.readonly`): a renovação segue funcionando e a sincronização não para; só a aba mostra "Para ver os relatórios, entre de novo com o Google". Testes: Task 3 (refresh sem `scope` e escopos mantidos), Task 6 (`novoLogin` sem pedido ao Drive), Task 9 (botão chama `entrarDeNovoGoogle`).
2. **Consentimento parcial** (a pessoa desmarca o Drive na tela granular do Google): o token grava os escopos devolvidos, e a aba volta a pedir o login em vez de mostrar erro genérico. Testes: Task 3 (login com `scope` sem `drive.readonly`) e Task 6 (`EscopoInsuficiente` no download → `novoLogin`).
3. **Pasta não compartilhada ou vazia** (`files.list` devolve zero arquivos, sem erro): mensagem clara de lista vazia, nunca "carregando" sem fim. Testes: Task 6 e Task 9.
4. **Arquivos estranhos na pasta** (nome fora do padrão, data impossível como `relatorio-abertura-2026-02-30.json`, JSON inválido, duas cópias com o mesmo nome): ignorados com log ou resolvidos pelo `modifiedTime` mais novo; a lista continua. Testes: Task 2 e Task 6.
5. **Link com esquema estranho no JSON** (`javascript:`, `file:`, vazio): aparece como texto e nunca é aberto. Teste: Task 7.

---

### Task 1: Modelo tolerante do relatório (com a fixture real)

**Files:**
- Add: `tests/fixtures/relatorio-abertura-2026-11-26.json` (já copiada pelo controlador; entra neste commit)
- Create: `app/lib/nucleo/relatorios/relatorio.dart`; exportar em `app/lib/nucleo/nucleo.dart`
- Create: `app/test/nucleo/apoio/fixture_relatorio.dart`
- Test: `app/test/nucleo/relatorio_test.dart`

**Interfaces:**
- Consumes: nada.
- Produces (todos imutáveis, campos `final`, enviáveis entre isolates):
  - `enum Leitura { positiva, mista, neutra, negativa }` (ordem do termômetro) e `Leitura leituraDe(Object? v)`; `enum Direcao { alta, queda, neutra }` e `Direcao direcaoDe(Object? v)` — desconhecido ou ausente → `neutra`.
  - `class Fonte { String nome; String url; }` (`nome` ausente → `url`; os dois ausentes → item descartado).
  - `class Indicador { String nome; String valor; String? variacao; Direcao direcao; String? contexto; }`
  - `class Termometro { int positiva, mista, neutra, negativa; int get total; int de(Leitura l); }`
  - `class Preco { String? texto; double? valor; String? data; String? variacao; Direcao direcao; String? observacao; }`
  - `class PrecoExterior { String? ticker; String? bolsa; String? texto; double? valor; String? data; String? variacao; Direcao direcao; }`
  - `class ItemEspecialista { String? casa; String? recomendacao; String? precoAlvo; String? data; String? url; }`
  - `class Especialistas { String? resumo; List<ItemEspecialista> itens; }`
  - `class AtivoRelatorio { int? posicao; String ticker; String? empresa; String? descricao; String? tipoAtivo; Leitura leitura; String? explicacao; String? dono; Preco? preco; PrecoExterior? precoExterior; String? noticias; Especialistas especialistas; String? riscos; List<Fonte> fontes; }` (`ticker` ausente → `'—'`)
  - `class EducacaoRisco { String? titulo; String? formula; String? exemplo; String? alerta; }`
  - `class OrigemAtivos { String? planilha; String? aba; int? quantidade; }`
  - `class Relatorio { int schemaVersion; String? tipo; String data; String? dataExtenso; String? geradoEm; String? titulo; OrigemAtivos? origemAtivos; List<String> avisosTopo; List<String> alertas; List<Indicador> indicadores; String? resumo; Termometro termometro; bool termometroDoJson; List<AtivoRelatorio> ativos; EducacaoRisco? educacaoRisco; String? aviso; List<Fonte> fontesCenario; bool get versaoNova; Termometro get contagemAtivos; bool get termometroDiverge; static Relatorio deJson(Object? json, {String? dataDoArquivo}); }`
  - Em `test/nucleo/apoio/fixture_relatorio.dart`: `const caminhoFixtureRelatorio = '../tests/fixtures/relatorio-abertura-2026-11-26.json';` `Map<String, Object?> fixtureRelatorio()` (lê e decodifica a cada chamada, cópia nova) e `Map<String, Object?> fixtureComAtivos(int n)` (a fixture com `ativos` trocado por `n` cópias do primeiro ativo, posições `0..n-1`, tickers `ATV0`, `ATV1`…, e `termometro` recontado pelas cópias).

- [ ] **Step 1: Escrever os testes que falham**

```dart
test('fixture real: todos os campos, 22 ativos, termômetro somando 22', () {
  final r = Relatorio.deJson(fixtureRelatorio());
  expect((r.schemaVersion, r.tipo, r.data), (1, 'abertura', '2026-11-26'));
  expect(r.dataExtenso, 'Quinta-feira, 26 de novembro de 2026');
  expect(r.titulo, 'Relatório de Abertura de Mercado — 26/11/2026');
  expect(r.geradoEm, '2026-11-26T15:40:00-03:00');
  expect((r.origemAtivos!.planilha, r.origemAtivos!.aba, r.origemAtivos!.quantidade),
      ('Calculadora DARF', 'Radar', 22));
  expect((r.avisosTopo.length, r.alertas.length, r.indicadores.length), (1, 1, 6));
  final i = r.indicadores.first;
  expect((i.nome, i.valor, i.variacao, i.direcao), ('Ibovespa', '174.204 pts', '+4,51%', Direcao.alta));
  expect(r.resumo, startsWith('O Ibovespa fechou ontem'));
  expect(r.ativos, hasLength(22));
  expect(r.ativos.map((a) => a.posicao), List.generate(22, (i) => i));
  expect(r.termometro.total, 22);
  expect((r.termometro.positiva, r.termometro.mista, r.termometro.neutra, r.termometro.negativa), (7, 7, 3, 5));
  expect(r.termometroDiverge, isFalse);
  final csn = r.ativos.first;
  expect((csn.ticker, csn.leitura, csn.tipoAtivo, csn.explicacao), ('CSNA3', Leitura.negativa, 'acao', null));
  expect((csn.preco!.texto, csn.preco!.valor, csn.preco!.data, csn.preco!.variacao, csn.preco!.direcao, csn.preco!.observacao),
      ('R\$ 3,45', 3.45, '2026-11-25', '+6,48%', Direcao.alta, 'no dia'));
  final ttwo = r.ativos[1];
  expect(ttwo.explicacao, isNotNull);
  expect((ttwo.precoExterior!.ticker, ttwo.precoExterior!.bolsa, ttwo.precoExterior!.texto, ttwo.precoExterior!.data),
      ('TTWO', 'Nasdaq', 'US\$ 216,54', '2026-11-18'));
  expect((ttwo.preco!.texto, ttwo.preco!.valor, ttwo.preco!.data), ('Não confirmado', null, null));
  final taee = r.ativos.firstWhere((a) => a.ticker == 'TAEE11');
  final e = taee.especialistas.itens.single;
  expect((e.casa, e.recomendacao, e.precoAlvo, e.data), ('BTG Pactual', 'venda', 'R\$ 40,00', '2026-11-11'));
  expect(e.url, startsWith('https://'));
  expect(r.ativos.where((a) => a.explicacao != null).map((a) => a.ticker), ['T1TW34', 'GOGL34', 'RURA11']);
  expect(r.educacaoRisco!.titulo, 'Como limitar o risco a 1% do capital');
  expect(r.aviso, startsWith('Este relatório é educacional'));
  expect(r.fontesCenario, hasLength(4));
  expect(r.versaoNova, isFalse);
});
```
Outros testes do arquivo (sintéticos só para campo faltando):
- `'relatório mínimo não trava'`: `Relatorio.deJson({}, dataDoArquivo: '2026-11-26')` → `data == '2026-11-26'`, listas vazias, `titulo`/`resumo`/`educacaoRisco`/`aviso` null, `termometro.total == 0`.
- `'campos com tipo errado viram null'`: `{'titulo': 3, 'ativos': [{'ticker': 7, 'preco': 'x', 'especialistas': null, 'fontes': 'y'}]}` → um ativo com `ticker == '—'`, `preco == null`, `especialistas.itens` vazio, `fontes` vazio.
- `'enum desconhecido vira neutra'`: `leitura: 'otima'` → `Leitura.neutra`; `direcao: 'subindo'` → `Direcao.neutra`.
- `'campos extras são ignorados'`: fixture com `'novo': {'a': 1}` no topo e num ativo → mesmo resultado da fixture.
- `'schemaVersion 2 renderiza com aviso'`: fixture com `schemaVersion: 2` → `versaoNova` true e `ativos.length == 22`.
- `'ativos em ordem de posição'`: posições `[2, 0, null, 1]` → ordem `0, 1, 2, null` (sem posição vai para o fim, na ordem original).
- `'0, 1 e 60 ativos'`: `fixtureComAtivos(0)`, `(1)`, `(60)` → `ativos.length` 0, 1, 60 e `termometro.total` igual.
- `'termômetro divergente: vale o do JSON'`: fixture com `termometro: {'positiva': 1, 'mista': 0, 'neutra': 0, 'negativa': 0}` → `termometro.total == 1`, `contagemAtivos.total == 22`, `termometroDiverge` true.
- `'termômetro ausente: contado pelos ativos'`: fixture sem `termometro` → `(7, 7, 3, 5)`, `termometroDoJson` false, `termometroDiverge` false.
- `'data do JSON inválida usa a do arquivo'`: `{'data': '26/11/2026'}` com `dataDoArquivo: '2026-11-26'` → `'2026-11-26'`.
- `'JSON que não é objeto lança FormatException'`: `deJson([1, 2])` e `deJson(null)`.

- [ ] **Step 2: Rodar e ver falhar**

Run: `flutter test test/nucleo/relatorio_test.dart`
Expected: FAIL (`relatorio.dart` não existe).

- [ ] **Step 3: Implementar `Relatorio.deJson` em `app/lib/nucleo/relatorios/relatorio.dart`**

Leitores pequenos privados (`_texto`, `_inteiro`, `_numero`, `_lista`, `_mapa`) que devolvem null para tipo errado; `data` só aceita `AAAA-MM-DD` válida; números `int` aceitam `num` inteiro.

- [ ] **Step 4: Rodar e ver passar**

Run: `flutter test test/nucleo/relatorio_test.dart`
Expected: `All tests passed!`

- [ ] **Step 5: Commit**

```bash
git add tests/fixtures/relatorio-abertura-2026-11-26.json app/lib/nucleo/relatorios/relatorio.dart app/lib/nucleo/nucleo.dart app/test/nucleo/apoio/fixture_relatorio.dart app/test/nucleo/relatorio_test.dart
git commit -m "Relatórios: modelo tolerante do relatório e fixture real"
```

---

### Task 2: Nome do arquivo, hoje em Brasília, ordenação e escolha

**Files:**
- Create: `app/lib/nucleo/relatorios/selecao.dart`; exportar em `nucleo.dart`
- Test: `app/test/nucleo/relatorios_selecao_test.dart`

**Interfaces:**
- Consumes: `Termometro` (Task 1), `DataHora`, `fusoBrasilia`.
- Produces:
  - `String? dataDoNome(String nome)` — casa `^relatorio-abertura-(\d{4}-\d{2}-\d{2})\.json$` e data real; senão `null`.
  - `String hojeBrasilia(DataHora agora)` = `agora.noFuso(fusoBrasilia).data` (a única função que sabe do UTC−3).
  - `class ResumoRelatorio { const ResumoRelatorio({required this.nome, required this.data, this.termometro}); final String nome; final String data; final Termometro? termometro; }`
  - `List<ResumoRelatorio> ordenarRelatorios(Iterable<ResumoRelatorio> itens)` — data decrescente; empate por nome decrescente.
  - `({ResumoRelatorio? escolhido, bool ehHoje}) escolherRelatorio(List<ResumoRelatorio> ordenados, String hoje)` — o de `hoje` se existir; senão o primeiro da lista (o mais recente); lista vazia → `(escolhido: null, ehHoje: false)`.
  - `String dataPorExtenso(String iso)` — `'2026-11-26'` → `'Quinta-feira, 26 de novembro de 2026'` (mesmo formato do `dataExtenso` da fixture).

- [ ] **Step 1: Escrever os testes que falham**

```dart
test('data pelo nome do arquivo', () {
  expect(dataDoNome('relatorio-abertura-2026-11-26.json'), '2026-11-26');
  for (final n in ['relatorio-abertura-2026-02-30.json', 'relatorio-abertura-2026-11-26.json.bak',
      'copia relatorio-abertura-2026-11-26.json', 'relatorio-abertura-26-11-2026.json', '']) {
    expect(dataDoNome(n), isNull, reason: n);
  }
});
test('hoje no fuso de Brasília (UTC−3 fixo)', () {
  expect(hojeBrasilia(DataHora.parse('2026-11-27T02:00:00Z')), '2026-11-26');
  expect(hojeBrasilia(DataHora.parse('2026-11-27T03:00:00Z')), '2026-11-27');
  expect(hojeBrasilia(DataHora.parse('2026-11-26T23:59:00-03:00')), '2026-11-26');
});
test('escolha: existe o de hoje', () {
  final l = ordenarRelatorios([_r('2026-11-25'), _r('2026-11-26'), _r('2026-11-24')]);
  expect(l.map((r) => r.data), ['2026-11-26', '2026-11-25', '2026-11-24']);
  final e = escolherRelatorio(l, '2026-11-26');
  expect((e.escolhido!.data, e.ehHoje), ('2026-11-26', true));
});
test('escolha: hoje não existe, cai no mais recente', () {
  final e = escolherRelatorio(ordenarRelatorios([_r('2026-11-24'), _r('2026-11-25')]), '2026-11-26');
  expect((e.escolhido!.data, e.ehHoje), ('2026-11-25', false));
  expect(escolherRelatorio(const [], '2026-11-26').escolhido, isNull);
});
test('data por extenso', () {
  expect(dataPorExtenso('2026-11-26'), 'Quinta-feira, 26 de novembro de 2026');
  expect(dataPorExtenso('2026-03-01'), 'Domingo, 1 de março de 2026');
});
```
(`_r(data)` = `ResumoRelatorio(nome: 'relatorio-abertura-$data.json', data: data)`.)

- [ ] **Step 2: Rodar e ver falhar** — Run: `flutter test test/nucleo/relatorios_selecao_test.dart` → FAIL (`selecao.dart` não existe).

- [ ] **Step 3: Implementar `selecao.dart`** — dia da semana por `DateTime.utc(a, m, d).weekday`; nomes de meses e dias em minúsculas, só a primeira letra do resultado em maiúscula.

- [ ] **Step 4: Rodar e ver passar** — Run: `flutter test test/nucleo/` → `All tests passed!`

- [ ] **Step 5: Commit**

```bash
git add app/lib/nucleo/relatorios/selecao.dart app/lib/nucleo/nucleo.dart app/test/nucleo/relatorios_selecao_test.dart
git commit -m "Relatórios: data pelo nome, hoje em Brasília, ordenação e escolha"
```

---

### Task 3: Escopo `drive.readonly` e escopos concedidos no token

**Files:**
- Modify: `app/lib/integracoes/google/constantes.dart` (trio novo, `escopoRelatorios`, comentário de cabeçalho explicando a troca), `app/lib/integracoes/google/token.dart` (`renovarToken`), `app/lib/integracoes/google/login.dart` (`loginNavegador`), `app/lib/integracoes/google/login_web.dart` (`criarRenovadorWeb`)
- Modify: `web_servidor/api/auth/inicio.js` (`ESCOPOS`), `web_servidor/api/auth/token.js` (repassa `scope`)
- Test: `app/test/integracoes/google/token_test.dart`, `login_test.dart`, `login_web_test.dart`; `web_servidor/test/auth.test.js`

**Interfaces:**
- Consumes: nada novo.
- Produces:
  - `const escoposGoogle = ['https://www.googleapis.com/auth/drive.file', 'https://www.googleapis.com/auth/drive.readonly', 'https://www.googleapis.com/auth/spreadsheets.readonly'];`
  - `const escopoRelatorios = 'https://www.googleapis.com/auth/drive.readonly';`
  - `List<String>? escoposDaResposta(Object? scope)` em `token.dart`: texto separado por espaço → lista sem vazios; outro tipo ou vazio → `null`.
  - `renovarToken` sem `scope` no formulário; o token novo tem `scopes: escoposDaResposta(dados['scope']) ?? t.scopes`. Mesma regra em `criarRenovadorWeb` e, no login, `escoposDaResposta(tok['scope']) ?? List.of(escoposGoogle)`.
  - `/api/auth/token` devolve `{access_token, expires_in, scope?, pacote?}` (`scope` só quando o Google mandar texto).

- [ ] **Step 1: Escrever os testes que falham**

- `token_test.dart`: `'renovarToken: corpo do formulário e novo expiry'` passa a exigir `expect(pedido.formulario.containsKey('scope'), isFalse)`; novo `'renovarToken: grava os escopos devolvidos pelo Google'` (resposta com `'scope': 'https://www.googleapis.com/auth/drive.file https://www.googleapis.com/auth/spreadsheets.readonly'` → `t.scopes` = essas duas); novo `'renovarToken sem scope na resposta mantém os do token'` (token com a lista antiga `_escopos` → mesma lista); `'scopes ausente assume os escopos do app'` passa a comparar com `escoposGoogle`; novo `'escopos do app trocam metadata por drive.readonly'`: `expect(escoposGoogle, ['https://www.googleapis.com/auth/drive.file', 'https://www.googleapis.com/auth/drive.readonly', 'https://www.googleapis.com/auth/spreadsheets.readonly'])`.
- `login_test.dart`: novo `'login grava os escopos concedidos'` — troca de código com `'scope': 'https://www.googleapis.com/auth/drive.file https://www.googleapis.com/auth/spreadsheets.readonly'` → `salvo['scopes']` igual a essas duas (sem `drive.readonly`); o teste atual sem `scope` continua esperando `escoposGoogle`.
- `login_web_test.dart`: renovador com 200 `{"access_token":"a","expires_in":3599,"scope":"x y"}` → `scopes == ['x', 'y']`; sem `scope` → `scopes` do token atual.
- `auth.test.js`: `'inicio válido'` espera `'https://www.googleapis.com/auth/drive.file https://www.googleapis.com/auth/drive.readonly https://www.googleapis.com/auth/spreadsheets.readonly'`; `'token com pacote válido'` espera `{ access_token: 'at', expires_in: 3599, scope: 'x' }`; novo caso sem `scope` na resposta do Google → corpo sem a chave `scope`.

- [ ] **Step 2: Rodar e ver falhar**

Run: `flutter test test/integracoes/google/` e, na raiz, `node --test web_servidor/test/`
Expected: FAIL nos casos novos e alterados.

- [ ] **Step 3: Implementar** conforme as Interfaces (sem mexer em mais nada do fluxo de login).

- [ ] **Step 4: Rodar e ver passar**

Run: `flutter test test/integracoes/` e `node --test web_servidor/test/`
Expected: `All tests passed!` e `# fail 0`.

- [ ] **Step 5: Commit**

```bash
git add app/lib/integracoes/google app/test/integracoes/google web_servidor/api/auth web_servidor/test/auth.test.js
git commit -m "Google: drive.readonly no lugar de drive.metadata.readonly; refresh sem scope e escopos concedidos no token"
```

---

### Task 4: Drive — escopo insuficiente, listagem paginada e download

**Files:**
- Modify: `app/lib/integracoes/google/erros.dart` (`EscopoInsuficiente`), `app/lib/integracoes/google/sessao.dart` (getter e 403)
- Create: `app/lib/integracoes/google/relatorios.dart`; exportar em `app/lib/integracoes/integracoes.dart`
- Test: `app/test/integracoes/google/sessao_test.dart` (casos novos), `app/test/integracoes/google/relatorios_test.dart`

**Interfaces:**
- Consumes: `escopoRelatorios` (Task 3), `SessaoGoogle.req`.
- Produces:
  - `class EscopoInsuficiente extends ErroGoogle { EscopoInsuficiente([super.mensagem, super.status]); }`
  - `List<String>? get escopos` em `SessaoGoogle` (escopos do token em memória; `null` sem sessão).
  - `SessaoGoogle.req`: status 403 cujo corpo tem `error.errors[].reason == 'insufficientPermissions'` ou `error.details[].reason == 'ACCESS_TOKEN_SCOPE_INSUFFICIENT'` → `EscopoInsuficiente(mensagem, 403)`; outros 403 continuam `ErroGoogle`.
  - Em `relatorios.dart`: `const pastaRelatorios = '1pIy2wYGucMq_1Jitg96yWy8Bxu4ytn5B';` `const consultaRelatorios = "'1pIy2wYGucMq_1Jitg96yWy8Bxu4ytn5B' in parents and trashed = false and name contains 'relatorio-abertura-'";` `class ArquivoRelatorio { const ArquivoRelatorio({required this.id, required this.nome, required this.modificado}); final String id, nome, modificado; }` `bool podeLerRelatorios(List<String>? escopos)` (`escopos?.contains(escopoRelatorios) ?? false`);
    `abstract interface class FonteRelatorios { List<String>? get escopos; Future<List<ArquivoRelatorio>> listar(); Future<Map<String, Object?>> baixar(String id); }` e `class DriveRelatorios implements FonteRelatorios { DriveRelatorios(this.sessao); final SessaoGoogle sessao; }`.
  - `listar()`: `GET $urlDrive/files` com `q: consultaRelatorios`, `fields: 'nextPageToken,files(id,name,modifiedTime)'`, `pageSize: 100`, `pageToken` a partir da 2ª página; para quando não há `nextPageToken`, quando ele se repete ou após 50 páginas; descarta itens sem `id`, `name` ou `modifiedTime` texto. `baixar(id)`: `GET $urlDrive/files/$id` com `alt: media`.

- [ ] **Step 1: Escrever os testes que falham**

- `sessao_test.dart`: 403 com `{'error': {'code': 403, 'message': 'Request had insufficient authentication scopes.', 'errors': [{'reason': 'insufficientPermissions'}], 'status': 'PERMISSION_DENIED'}}` → `throwsA(isA<EscopoInsuficiente>().having((e) => e.status, 'status', 403))`; 403 com `details: [{'reason': 'ACCESS_TOKEN_SCOPE_INSUFFICIENT'}]` → `EscopoInsuficiente`; 403 com `reason: 'insufficientFilePermissions'` → `isA<ErroGoogle>()` e `isNot(isA<EscopoInsuficiente>())`; `escopos` antes da sessão `null` e depois de `carregarToken` igual ao `scopes` do `token.json`.
- `relatorios_test.dart` (padrão `_montar` de `planilha_test.dart`):
```dart
test('listar pagina com a consulta e os campos do pedido', () async {
  final (drive, falso) = await _montar([
    RespostaFalsa(200, json: {'nextPageToken': 'p2', 'files': [_f('a', '2026-11-26'), _f('b', '2026-11-25')]}),
    RespostaFalsa(200, json: {'files': [_f('c', '2026-11-24'), {'id': 'sem-nome'}]}),
  ]);
  final l = await drive.listar();
  expect(l.map((a) => (a.id, a.nome)), [('a', 'relatorio-abertura-2026-11-26.json'),
      ('b', 'relatorio-abertura-2026-11-25.json'), ('c', 'relatorio-abertura-2026-11-24.json')]);
  final q1 = falso.pedidos[0].url.queryParameters, q2 = falso.pedidos[1].url.queryParameters;
  expect(q1['q'], consultaRelatorios);
  expect(q1['fields'], 'nextPageToken,files(id,name,modifiedTime)');
  expect((q1['pageSize'], q1.containsKey('pageToken'), q2['pageToken']), ('100', false, 'p2'));
});
```
  (`_f(id, data)` = `{'id': id, 'name': 'relatorio-abertura-$data.json', 'modifiedTime': '${data}T12:00:00.000Z'}`.) Mais: `nextPageToken` repetido → para na 2ª página; `baixar('abc')` faz `GET https://www.googleapis.com/drive/v3/files/abc?alt=media` com `Authorization: Bearer ya29.a` e devolve o mapa; corpo `texto: 'não é json'` → `throwsA(isA<ErroGoogle>())`; `podeLerRelatorios(null)`, `([])`, `(escoposAntigos)` false e `(escoposGoogle)` true (`escoposAntigos` = o trio da 2.6.0, com `drive.metadata.readonly`, constante local do teste).

- [ ] **Step 2: Rodar e ver falhar** — Run: `flutter test test/integracoes/google/` → FAIL nos casos novos.

- [ ] **Step 3: Implementar** conforme as Interfaces; o motivo do 403 sai do mesmo JSON que `_mensagem` já lê.

- [ ] **Step 4: Rodar e ver passar** — Run: `flutter test test/integracoes/` → `All tests passed!`

- [ ] **Step 5: Commit**

```bash
git add app/lib/integracoes app/test/integracoes/google
git commit -m "Drive: listagem paginada e download dos relatórios; erro de escopo insuficiente"
```

---

### Task 5: Armazenamento com subpasta e cache descartável na Web

**Files:**
- Modify: `app/lib/nucleo/armazenamento_arquivos.dart` (`gravar`), `app/lib/nucleo/armazenamento_chave_valor.dart` (`gravar`, `prefixosDescartaveis`)
- Test: `app/test/nucleo/armazenamento_chave_valor_test.dart`; `app/test/nucleo/repositorio_test.dart` (ou o teste que já cobre `ArmazenamentoArquivos`; achar com `grep -rln ArmazenamentoArquivos app/test`)
- Test (navegador): `app/test/web/armazenamento_relatorios_navegador_test.dart` (`@TestOn('browser')`, mesmo `limpar()` de `chave_valor_navegador_test.dart`)

**Interfaces:**
- Consumes: nada.
- Produces:
  - `ArmazenamentoArquivos.gravar('relatorios/x.json', ...)` cria a pasta-mãe do arquivo (`_arquivo(nome).parent.createSync(recursive: true)`); `listar()` continua só com os arquivos da raiz (o `Repositorio` não vê o cache).
  - `const prefixosDescartaveis = ['relatorios/'];` em `armazenamento_chave_valor.dart`: quando o navegador enche, `gravar` apaga também as chaves com esses prefixos (menos a que está sendo gravada) antes da 2ª tentativa.

- [ ] **Step 1: Escrever os testes que falham**
  - `'gravar em subpasta cria a pasta e listar não a mostra'` (pasta temporária com `Directory.systemTemp.createTempSync`): grava `relatorios/indice.json`, `ler` devolve o texto, `listar()` não contém nada com `relatorios`.
  - `'armazenamento cheio descarta o cache dos relatórios'`: `ChaveValor` falso que lança na 1ª `definir` de `darf:2026-11.json`; antes há `darf:relatorios/indice.json` e `darf:relatorios/relatorio-abertura-2026-11-26.json` → ambos removidos e a gravação do mês acontece.
  - Navegador, `'localStorage cheio: os relatórios saem e o mês é gravado'`: com `ArmazenamentoChaveValor(chaveValorDoNavegador()!)`, grava blocos de 1.000.000 de caracteres em `relatorios/enchimento-<i>` até o `localStorage` recusar (o `gravar` lança `ErroArmazenamentoCheio`); depois `gravar('2026-11.json', 'x' * 200000)` não lança, `ler('2026-11.json')` devolve o texto e nenhuma chave `darf:relatorios/` sobra.

- [ ] **Step 2: Rodar e ver falhar** — Run: `flutter test test/nucleo/armazenamento_chave_valor_test.dart test/nucleo/repositorio_test.dart` e `flutter test --platform chrome test/web/armazenamento_relatorios_navegador_test.dart` → FAIL nos casos novos.

- [ ] **Step 3: Implementar** conforme as Interfaces.

- [ ] **Step 4: Rodar e ver passar** — Run: `flutter test test/nucleo/` e `flutter test --platform chrome test/web` → `All tests passed!` nos dois.

- [ ] **Step 5: Commit**

```bash
git add app/lib/nucleo/armazenamento_arquivos.dart app/lib/nucleo/armazenamento_chave_valor.dart app/test/nucleo
git commit -m "Armazenamento: subpasta no disco e cache dos relatórios descartável na Web"
```

---

### Task 6: `RelatoriosLocal` — cache por modifiedTime, sem conexão e novo login

**Files:**
- Modify: `app/lib/app/servicos/api.dart` (só os tipos `SituacaoRelatorios` e `VisaoRelatorios`; os métodos entram na Task 7)
- Create: `app/lib/app/servicos/locais/relatorios_local.dart`
- Test: `app/test/app/servicos/relatorios_local_test.dart`

**Interfaces:**
- Consumes: `Relatorio.deJson`, `termometroDiverge` (Task 1); `dataDoNome`, `hojeBrasilia`, `ResumoRelatorio`, `ordenarRelatorios`, `escolherRelatorio` (Task 2); `FonteRelatorios`, `ArquivoRelatorio`, `podeLerRelatorios`, `EscopoInsuficiente` (Task 4); `ContaGoogle` (`email`, `temToken()`); `Armazenamento`; `ambiente.agoraBr()`.
- Produces:
  - Em `api.dart`: `enum SituacaoRelatorios { ok, semConexao, semConta, novoLogin }` e
    `class VisaoRelatorios { const VisaoRelatorios({required this.itens, required this.hoje, this.atual, this.ehHoje = false, this.situacao = SituacaoRelatorios.ok}); final List<ResumoRelatorio> itens; final String hoje; final Relatorio? atual; final bool ehHoje; final SituacaoRelatorios situacao; }` (`itens` já ordenados; `atual` = conteúdo do escolhido, se houver).
  - `class RelatoriosLocal { RelatoriosLocal({required Armazenamento disco, required FonteRelatorios fonte, required ContaGoogle conta, int limiteConteudo = 10, void Function(String) registrar = registrarRelatorios}); Future<VisaoRelatorios> emCache(); Future<VisaoRelatorios> atualizar(); Future<Relatorio> abrir(String nome); }`
  - `void registrarRelatorios(String texto)` = `developer.log(texto, name: 'relatorios')`.
  - Cache: `const arquivoIndiceRelatorios = 'relatorios/indice.json';` formato `{"versao": 1, "arquivos": {"<nome>": {"id": str, "modificado": str, "invalido": bool, "termometro": {"positiva": int, "mista": int, "neutra": int, "negativa": int} | null}}}`; conteúdo em `'relatorios/<nome>'` com `jsonEncode` do mapa baixado.
  - Regras de `atualizar()`:
    1. Sem `conta.email`: sem token → `semConta`; com token → visão do cache com `semConexao`. Nenhum pedido.
    2. `!podeLerRelatorios(fonte.escopos)` → `VisaoRelatorios(itens: const [], hoje: …, situacao: novoLogin)`, sem pedido ao Drive.
    3. `fonte.listar()`; nomes com `dataDoNome == null` vão para o log e saem; nome repetido → fica o de `modificado` maior.
    4. Entre os `limiteConteudo` mais recentes (e sempre o escolhido), baixa os que não têm conteúdo em cache ou cujo `modificado` mudou; falha de `deJson`/`ErroGoogle` comum → log, `invalido: true` no índice (não baixa de novo com o mesmo `modificado`) e o item sai da lista; `termometroDiverge` → só log.
    5. Apaga do índice e do disco o que sumiu da pasta e o conteúdo fora dos `limiteConteudo` mais recentes (o termômetro fica no índice).
    6. `Offline`/`LoginNecessario` em qualquer ponto → visão do cache com `semConexao`; `EscopoInsuficiente` → `novoLogin`; outro `ErroGoogle` na listagem → visão do cache com `semConexao` e log.
    7. Índice ilegível → vazio; conteúdo ilegível → apagado e baixado de novo; falha ao gravar (`ErroArmazenamentoCheio`, `FileSystemException`) → log, e a visão sai da memória.
    8. Duas chamadas simultâneas compartilham o mesmo futuro.
  - `abrir(nome)`: conteúdo do cache; sem cache baixa e guarda (`Offline` sem cache relança `Offline`; nome fora do índice → `ErroValidacao('Relatório não encontrado.')`).

- [ ] **Step 1: Escrever os testes que falham** (`FonteFalsa implements FonteRelatorios` com `escopos`, lista de `ArquivoRelatorio`, mapa id → conteúdo ou erro e contadores `listagens`/`downloads`; `ContaFalsa` de `test/app/apoio/conta_falsa.dart`; `setUp`: `ambiente = Ambiente.fixo(agoraBr: '2026-11-26T10:00:00-03:00')`, `tearDown` volta ao sistema)

```dart
test('primeira atualização baixa, grava e escolhe o de hoje', () async {
  final f = FonteFalsa(arquivos: [_arq('2026-11-25'), _arq('2026-11-26')],
      conteudos: {'id-2026-11-26': fixtureRelatorio(), 'id-2026-11-25': fixtureRelatorio()..['data'] = '2026-11-25'});
  final disco = ArmazenamentoMemoria();
  final v = await _local(f, disco).atualizar();
  expect(v.situacao, SituacaoRelatorios.ok);
  expect(v.itens.map((r) => r.data), ['2026-11-26', '2026-11-25']);
  expect((v.atual!.data, v.ehHoje, v.hoje), ('2026-11-26', true, '2026-11-26'));
  expect(v.itens.first.termometro!.total, 22);
  expect(disco.existe('relatorios/indice.json'), isTrue);
  expect(disco.existe('relatorios/relatorio-abertura-2026-11-26.json'), isTrue);
});
```
  Demais casos, um `test` cada: `'modifiedTime igual não baixa de novo; diferente baixa'` (`downloads` 2 → 2 → 3); `'sem o de hoje mostra o mais recente'` (`ehHoje` false, `atual.data == '2026-11-25'`); `'sem internet mostra o cache com aviso'` (2ª atualização com `listar` lançando `Offline('x')` → mesmos itens, `semConexao`, `atual` do cache); `'primeira abertura sem internet e sem cache'` (itens vazios, `semConexao`); `'token sem drive.readonly pede novo login sem tocar no Drive'` (`escopos` = lista antiga → `novoLogin`, `listagens == 0`); `'escopo insuficiente no download pede novo login'`; `'sem conta e sem token: semConta'`; `'token sem sessão: cache e semConexao'`; `'pasta vazia: ok e lista vazia'`; `'nome fora do padrão e data impossível vão para o log'` (`registrados` contém os dois nomes; itens sem eles); `'JSON inválido é ignorado e não é baixado de novo'` (conteúdo `[1, 2]` → item fora, log, e a próxima atualização com o mesmo `modificado` não baixa); `'nome repetido: vale o modifiedTime mais novo'`; `'termômetro divergente só vai para o log'`; `'só os N mais recentes têm conteúdo'` (`limiteConteudo: 2`, 4 arquivos → 2 downloads, conteúdo do 3º apagado se existia, termômetro dele preservado no índice); `'arquivo removido da pasta sai do índice e do disco'`; `'abrir usa o cache; sem cache baixa; Offline sem cache relança'`; `'índice ilegível vira vazio'`; `'armazenamento cheio não derruba a visão'` (disco cuja `gravar` lança `ErroArmazenamentoCheio` → visão `ok` com os itens); `'duas atualizações simultâneas listam uma vez'`; `'0, 1 e 60 ativos'` (`fixtureComAtivos(n)` como conteúdo → `atual.ativos.length == n`).

- [ ] **Step 2: Rodar e ver falhar** — Run: `flutter test test/app/servicos/relatorios_local_test.dart` → FAIL (`relatorios_local.dart` não existe).

- [ ] **Step 3: Implementar `RelatoriosLocal`** conforme as regras acima.

- [ ] **Step 4: Rodar e ver passar** — Run: `flutter test test/app/servicos/relatorios_local_test.dart` → `All tests passed!`

- [ ] **Step 5: Commit**

```bash
git add app/lib/app/servicos/api.dart app/lib/app/servicos/locais/relatorios_local.dart app/test/app/servicos/relatorios_local_test.dart
git commit -m "Relatórios: serviço local com cache por modifiedTime, sem conexão e novo login"
```

---

### Task 7: Contrato dos serviços, "entrar de novo" e montagem (isolate e Web)

**Files:**
- Modify: `app/lib/app/servicos/api.dart` (métodos), `app/lib/app/servicos/servicos_locais.dart`, `app/lib/app/servicos/locais/conta_local.dart` (`reconectar`), `app/lib/app/servicos/servicos_reais.dart` (repasse do parâmetro), `app/lib/app/servicos/servicos_isolate.dart` (`criarServicosLocais` e proxy), `app/lib/app/servicos/servicos_web.dart`
- Modify (apoio de testes): `app/test/app/apoio/servicos_falsos.dart`, `app/test/app/apoio/servicos_eco.dart`
- Test: `app/test/app/servicos/conta_local_test.dart`, `servicos_isolate_test.dart`, `servicos_web_test.dart`

**Interfaces:**
- Consumes: `RelatoriosLocal`, `VisaoRelatorios` (Task 6); `DriveRelatorios` (Task 4).
- Produces:
  - Em `ServicosApp`, bloco `// relatórios de abertura (pasta do Drive)`: `Future<VisaoRelatorios> relatorios();` (só cache) `Future<VisaoRelatorios> atualizarRelatorios();` `Future<Relatorio> abrirRelatorio(String nome);` `Future<void> entrarDeNovoGoogle();`
  - `ServicosLocais({..., RelatoriosLocal Function()? relatorios})` — sem ele os três métodos lançam `StateError('Relatórios não configurados.')`; `entrarDeNovoGoogle` → `_conta.reconectar()`.
  - `ContaLocal.reconectar()`: igual a `conectar()` sem o retorno antecipado por `email != null` (mesmo aviso de credencial ausente, `_sync.conectar(_abrirUrl)`, `_reconciliar()` no `finally`); não chama `sair`.
  - `criarServicosLocais`: `RelatoriosLocal(disco: disco, fonte: DriveRelatorios(sessao), conta: google)` (limite 10). `criarServicosWeb`: o mesmo com `limiteConteudo: 5`, `disco` = o `armazenamento` do navegador e a mesma `sessao` (cliente `http30` direto ao Google com Bearer; nunca o `ClienteProxy` nem `/api`).
  - `ServicosFalsos`: `VisaoRelatorios visaoRelatorios` (padrão vazio, `hoje: '2026-11-26'`), `Map<String, Relatorio> relatoriosAbertos`, `Future<VisaoRelatorios> Function()? atualizarRelatoriosFn`; registra `relatorios()`, `atualizarRelatorios()`, `abrirRelatorio(<nome>)`, `entrarDeNovoGoogle()` em `chamadas` e respeita `erros[...]`. `ServicosEco`: respostas fixas enviáveis.

- [ ] **Step 1: Escrever os testes que falham**
  - `conta_local_test.dart`: `'reconectar com a sessão aberta faz login de novo sem sair'` → `ContaFalsa.chamadas` termina com `login` e não contém `sair`; `'reconectar cancelado mantém a conta'` → `email` continua o mesmo.
  - `servicos_isolate_test.dart`: pelo proxy com `ServicosEco`, `relatorios()`, `atualizarRelatorios()` e `abrirRelatorio('relatorio-abertura-2026-11-26.json')` devolvem os valores do eco; `entrarDeNovoGoogle()` completa.
  - `servicos_web_test.dart`: `criarServicosWeb` com `MockClient` e um `token.json` válido com `escoposGoogle` → `atualizarRelatorios()` (depois de a conta abrir a sessão) faz `GET https://www.googleapis.com/drive/v3/files?...` com `q` = `consultaRelatorios` e `Authorization: Bearer <token>`, e nenhum pedido ao host da `api` (Vercel); o download vai a `https://www.googleapis.com/drive/v3/files/<id>?alt=media` e o conteúdo fica em `darf:relatorios/<nome>` do armazenamento recebido; com `token.json` de escopos antigos → `situacao == SituacaoRelatorios.novoLogin` e nenhum pedido ao Drive.

- [ ] **Step 2: Rodar e ver falhar** — Run: `flutter test test/app/servicos/` → FAIL nos casos novos (e erro de compilação até os métodos existirem).

- [ ] **Step 3: Implementar** conforme as Interfaces.

- [ ] **Step 4: Rodar e ver passar**

Run: `flutter analyze` e `flutter test --exclude-tags golden,vivo`
Expected: `No issues found!` e `All tests passed!`

- [ ] **Step 5: Commit**

```bash
git add app/lib/app/servicos app/test/app/apoio app/test/app/servicos
git commit -m "Serviços: relatórios no contrato, no isolate e na Web; entrar de novo com o Google sem sair"
```

---

### Task 8: Vista do relatório (seções a–k) com a paleta do e-mail

**Files:**
- Create: `app/lib/app/telas/relatorios/paleta_relatorio.dart`, `app/lib/app/telas/relatorios/vista_relatorio.dart` (seções a–g e i–k), `app/lib/app/telas/relatorios/cartao_ativo.dart` (h)
- Test: `app/test/app/telas/relatorios/vista_relatorio_test.dart`

**Interfaces:**
- Consumes: `Relatorio` e tipos da Task 1; `Cartao`, `CoresApp`, `expandido`.
- Produces:
  - `abstract final class PaletaRelatorio` com as constantes da paleta (Global Constraints) e `(Color texto, Color fundo) coresLeitura(Leitura l)`, `(Color texto, Color fundo) coresDirecao(Direcao d)` (alta = positiva, queda = negativa, neutra = neutra).
  - `String rotuloLeitura(Leitura l)` → `'Positiva'`, `'Mista'`, `'Neutra'`, `'Negativa'`; `String textoTermometro(Termometro t)` → `'7 positivas · 7 mistas · 3 neutras · 5 negativas'` (singular com 1: `'1 positiva'`, `'1 mista'`, `'1 neutra'`, `'1 negativa'`); `Uri? linkSeguro(String? url)` (só `http`/`https` com host; senão `null`).
  - `class VistaRelatorio extends StatelessWidget { const VistaRelatorio({super.key, required this.relatorio, required this.aoAbrirLink, this.topo = const []}); final Relatorio relatorio; final void Function(Uri) aoAbrirLink; final List<Widget> topo; }` — um `CustomScrollView`: `topo` (mensagens da aba), a–g e o cabeçalho de h como slivers simples, os cartões de h num `SliverList.builder` (preguiçoso), depois i–k.
  - `class CartaoAtivo extends StatelessWidget { const CartaoAtivo(this.ativo, {super.key, required this.aoAbrirLink}); }`
  - Textos fixos: (a) `'${n} ativos do Radar'` (`'1 ativo do Radar'`; com `origemAtivos.aba == 'reserva'`, `'da lista reserva'`; sem quantidade, a linha some); (c) legenda: `'Positiva: notícias e números do dia favoráveis à empresa.'`, `'Mista: sinais favoráveis e desfavoráveis ao mesmo tempo.'`, `'Neutra: nada relevante para o preço no dia.'`, `'Negativa: notícias e números do dia desfavoráveis à empresa.'` e a nota `'A leitura resume as notícias e os dados do dia. Não é previsão de preço nem recomendação de compra ou venda.'`; (f) título `'Termômetro'`; (g) cabeçalhos `'Ativo'`, `'Último preço'`, `'Leitura'`, `'Especialistas'`, preço como `'R$ 3,45 · 25/11/2026'`; 0 ativos → no lugar de g e h, `'Nenhum ativo neste relatório.'`; (h) rótulos `'Quem é dono'`, `'Preço'`, `'Notícias'`, `'Especialistas'`, `'Riscos'`, `'Fontes'`, item de especialista `'BTG Pactual · venda · alvo R$ 40,00 · 11/11/2026'` (partes ausentes somem; data `AAAA-MM` vira `MM/AAAA`), preço no exterior `'TTWO (Nasdaq): US$ 216,54 · 18/11/2026'`; (k) `'Fontes do cenário'`; versão nova: `'Este relatório usa um formato mais novo que esta versão do app; algumas partes podem não aparecer.'`. Campo de texto ausente: a linha some; valor ausente numa linha que precisa existir (tabela) mostra `'—'`.
  - Chaves para os testes: `Key('secao-<letra>')` no início de cada seção a–k, `Key('selo-termometro-<ticker>')`, `Key('cartao-<ticker>')`, `Key('explicacao-<ticker>')`, `Key('versao-nova')`.

- [ ] **Step 1: Escrever os testes que falham** (`montarComponente`, `fixtureRelatorio()`; tamanho PC `Size(1366, 900)` e celular `Size(360, 800)`)

```dart
testWidgets('seções na ordem a–k', (t) async {
  await montarComponente(t, _vista(Relatorio.deJson(fixtureRelatorio())), tamanho: const Size(1366, 20000));
  double y(String l) => t.getTopLeft(find.byKey(Key('secao-$l'))).dy;
  final letras = ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k'];
  for (var i = 1; i < letras.length; i++) {
    expect(y(letras[i]), greaterThan(y(letras[i - 1])), reason: letras[i]);
  }
});
```
  Demais casos: `'termômetro: positivas, mistas, neutras, negativas e a contagem do JSON'` — os 22 `Key('selo-termometro-<ticker>')` em ordem de leitura do `Wrap` (linha, depois coluna) trazem primeiro os 7 positivos, depois os 7 mistos, os 3 neutros e os 5 negativos (dentro de cada grupo, na ordem de `posicao`: o primeiro selo é `T1TW34`, o positivo de menor posição, e o último é `HAPV3`) e `find.text('7 positivas · 7 mistas · 3 neutras · 5 negativas')`; termômetro divergente mostra o texto do JSON; cartões na ordem de `posicao` (CSNA3 antes de T1TW34); `explicacao` só nos 3 tickers da fixture (`Key('explicacao-CSNA3')` ausente); direção: Ibovespa mostra `'▲ +4,51%'`, um indicador `queda` mostra `'▼'`, o `neutra` sem seta; cor do selo `Positiva` = texto `0xFF1B7F3B` e fundo `0xFFE6F4EA`; caixa da explicação fundo `0xFFE8F0FE`; tocar `'InfoMoney'` chama `aoAbrirLink` com a URL da fixture; fonte com `url: 'javascript:alert(1)'` e com `url: ''` aparece como texto e o toque não chama `aoAbrirLink`; relatório mínimo `Relatorio.deJson({}, dataDoArquivo: '2026-11-26')` monta sem exceção (`t.takeException()` null) e mostra `'Nenhum ativo neste relatório.'`; `schemaVersion: 2` mostra `Key('versao-nova')`; **0, 1 e 60 ativos no celular** (`fixtureComAtivos(n)`, `Size(360, 800)`): sem exceção de overflow, e com 60 rolar até o fim encontra `Key('cartao-ATV59')`; nos temas `terminal` e `moderno` os selos mantêm as cores da paleta.

- [ ] **Step 2: Rodar e ver falhar** — Run: `flutter test test/app/telas/relatorios/vista_relatorio_test.dart` → FAIL (arquivos não existem).

- [ ] **Step 3: Implementar** conforme as Interfaces; seções em widgets privados pequenos; cartões de índice e indicadores com `Cartao` do tema; faixa lateral do cartão do ativo com a cor de texto da leitura; tabela g com `SingleChildScrollView(scrollDirection: Axis.horizontal)` quando `!expandido(context)`; grade d com `Wrap` de cartões de largura fixa (240 no PC, largura total no celular).

- [ ] **Step 4: Rodar e ver passar** — Run: `flutter test test/app/telas/relatorios/` → `All tests passed!`

- [ ] **Step 5: Commit**

```bash
git add app/lib/app/telas/relatorios app/test/app/telas/relatorios
git commit -m "Relatórios: vista do relatório com as seções e a paleta do e-mail"
```

---

### Task 9: A aba "Relatórios" (navegação, controle, lista, Atualizar) e goldens

**Files:**
- Modify: `app/lib/app/estado/estado_app.dart` (`enum Aba { apuracao, caixa, radar, noticias, relatorios, conta }`), `app/lib/app/telas/casca.dart` (`rotulo` `'Relatórios'`, `icone` `Icons.summarize`, `_telaPadrao`)
- Create: `app/lib/app/telas/relatorios/controle_relatorios.dart`, `app/lib/app/telas/relatorios/tela_relatorios.dart`
- Modify: `app/test/app/goldens/telas_golden_test.dart` (`_ServicosGolden` com `visaoRelatorios` da fixture), `app/test/app/telas/casca_test.dart`; regenerar `app/test/app/goldens/arquivos/*.png`
- Test: `app/test/app/telas/relatorios/tela_relatorios_test.dart`

**Interfaces:**
- Consumes: os quatro métodos do `ServicosApp` (Task 7); `VistaRelatorio`, `textoTermometro`, `coresLeitura` (Task 8); `dataPorExtenso` (Task 2); `EstadoApp.abrirLink`, `EstadoApp.aba`, `EstadoApp.conta`.
- Produces:
  - `class ControleRelatorios extends ChangeNotifier { ControleRelatorios(ServicosApp servicos, EstadoApp estado); VisaoRelatorios? visao; Relatorio? aberto; String? nomeAberto; bool atualizando; String? erro; Future<void> atualizar(); Future<void> abrir(String nome); Future<void> entrarDeNovo(); Future<void> entrar(); }` — ao nascer lê `relatorios()` e, com a aba aberta, `atualizarRelatorios()`; a cada entrada na aba chama `atualizar()`; quando `estado.conta.email` muda chama `atualizar()`; `aberto` começa no `visao.atual` e muda com `abrir`; respostas atrasadas de pedidos antigos são descartadas (geração, como em `ControleNoticias`); `entrar()` → `servicos.conectar()`.
  - `class TelaRelatorios extends StatelessWidget` com `ChangeNotifierProvider<ControleRelatorios>` (padrão de `TelaNoticias`).
  - Textos fixos da aba: botão `'Atualizar'` (`Key('relatorios-atualizar')`); `'O relatório de hoje ainda não está disponível (fica pronto até 9h30 em dias de pregão)'` seguido de `'Mostrando o relatório de ${dataPorExtenso(data)}'` em negrito; sem conexão `'Sem conexão com o Google. Mostrando os relatórios salvos neste aparelho.'` (faixa discreta, `textoSuave`); novo login `'Para ver os relatórios, entre de novo com o Google'` + botão `'Entrar de novo com o Google'` + `'A sincronização continua funcionando normalmente.'`; sem conta `'Entre com a sua conta Google para ver os relatórios.'` + botão `'Entrar com o Google'`; lista vazia `'Nenhum relatório encontrado na pasta "Calculadora DARF - Relatórios". Se o acesso acabou de ser liberado, toque em Atualizar.'`; título da lista `'Relatórios anteriores'`; no celular o botão `'Anteriores'` abre a lista numa folha inferior.
  - Layout por `expandido(context)` (o mesmo critério da casca, >= 840): expandido (Windows, Web larga) = vista + `Key('lista-relatorios')` em coluna de 320 px à direita; compacto (Android, Web no celular/iPhone) = vista em tela cheia + botão `'Anteriores'` que abre a lista numa folha inferior.
  - Item da lista: `dataPorExtenso(data)` e, com termômetro, os quatro números em pílulas com `coresLeitura` (`'7 positivas'` · `'7 mistas'` · `'3 neutras'` · `'5 negativas'`); o item aberto fica destacado; `Key('item-relatorio-<data>')`.

- [ ] **Step 1: Escrever os testes que falham** (`montarApp` + `ServicosFalsos`; `visaoRelatorios` montada com `Relatorio.deJson(fixtureRelatorio())`)
  - `casca_test.dart`: `'seis abas, Relatórios entre Notícias e Conta'` — no celular (`Size(360, 800)`, layout compacto do Android) os rótulos da `NavigationBar` e no PC (`Size(1366, 768)`, layout expandido do Windows) os da barra lateral, na ordem `['Apuração', 'Caixa', 'Radar', 'Notícias', 'Relatórios', 'Conta']` (lateral com `'Apuração / DARF'`); no celular nenhum rótulo cortado (`t.takeException()` null e o `Text('Relatórios')` da barra com `didExceedMaxLines` false).
  - `tela_relatorios_test.dart`, `group('layouts e temas')`: para cada `TemaVisual` em `[terminal, claro, moderno]` × `{pc: Size(1366, 768), celular: Size(360, 800)}`, a aba monta com a fixture sem exceção; no PC a lista `'Relatórios anteriores'` aparece ao lado da vista (`Key('lista-relatorios')` à direita de `Key('secao-a')`) e não há botão `'Anteriores'`; no celular há o botão `'Anteriores'` e a lista não está à vista até o toque.
  - `tela_relatorios_test.dart`: `'abrir a aba lê o cache e a pasta e mostra o de hoje'` (`chamadas` contém `relatorios()` e `atualizarRelatorios()`; título da fixture à vista; sem a mensagem de hoje indisponível); `'sem o de hoje: mensagem e data do mais recente'` (`hoje: '2026-11-27'`, `ehHoje: false` → texto exato do pedido e `'Mostrando o relatório de Quinta-feira, 26 de novembro de 2026'`); `'lista do mais recente para o mais antigo com o termômetro'` (3 itens → ordem das `Key('item-relatorio-…')` e `find.text('7 positivas')`); `'tocar num item abre o relatório'` (`abrirRelatorio(relatorio-abertura-2026-11-25.json)` em `chamadas` e a vista troca); `'Atualizar lista a pasta de novo'`; `'sair e voltar à aba atualiza de novo'`; `'novo login: texto, botão e nada de relatório'` (toque → `entrarDeNovoGoogle()`); `'sem conta: botão Entrar com o Google'` (toque → `conectar()`); `'sem conexão: aviso discreto e o cache'`; `'pasta vazia: mensagem'`; `'falha ao abrir mostra o erro e mantém o anterior'` (`erros['abrirRelatorio'] = Offline('x')`); no celular, `'Anteriores'` abre a folha com os itens.

- [ ] **Step 2: Rodar e ver falhar** — Run: `flutter test test/app/telas/relatorios/tela_relatorios_test.dart test/app/telas/casca_test.dart` → FAIL.

- [ ] **Step 3: Implementar** a aba, o controle e a tela; nos goldens, `_ServicosGolden` responde `relatorios()`/`atualizarRelatorios()` com a visão da fixture (`hoje: '2026-11-26'`, `ehHoje: true`, três itens de 24 a 26/11).

- [ ] **Step 4: Rodar e ver passar; regenerar e conferir os goldens**

Run: `flutter analyze`; `flutter test --exclude-tags golden,vivo`; `flutter test --tags golden test/app/goldens --update-goldens`; `flutter test --tags golden test/app/goldens`
Expected: `No issues found!`; `All tests passed!` (duas vezes nas rodadas sem update); `git status` mostra os 6 PNGs novos `relatorios_<tema>_<pc|celular>.png` e os de todas as abas alterados (barra com 6 destinos). Quem coordena passa os PNGs ao `conferidor-visual` com o checklist: barra com "Relatórios" entre "Notícias" e "Conta", rótulos inteiros no celular de 360 px, cores da paleta nos selos nos 3 temas, sem overflow, nada mais mudou nas outras telas além da barra.

- [ ] **Step 5: Commit**

```bash
git add app/lib/app/estado/estado_app.dart app/lib/app/telas app/test/app
git commit -m "Aba Relatórios: navegação, lista, Atualizar e goldens"
```

---

### Task 10: Release 2.7.0 — versão, notas e verificação completa

**Files:**
- Modify: `app/lib/versao.dart` (`'2.7.0'`), `app/test/versao_test.dart`
- Create: `docs/release/2.7.0.md`

**Interfaces:**
- Consumes: tudo acima.
- Produces: árvore pronta para a tag `2.7.0` (Task 11).

- [ ] **Step 1: Teste que falha** — `versao_test.dart`: título `'versaoApp tem formato x.y.z e vale 2.7.0'`, `expect(versaoApp, '2.7.0')`. Run: `flutter test test/versao_test.dart` → FAIL.

- [ ] **Step 2: Versão e notas** — `versao.dart` com `'2.7.0'`; `docs/release/2.7.0.md` no formato da 2.6.0:
```markdown
## Calculadora DARF 2.7.0

Nova aba Relatórios, no PC, no Android e na Web. Sem mudanças de cálculo nem da planilha.

### O que muda

- A aba Relatórios mostra o Relatório de Abertura de Mercado de cada dia de pregão (fica pronto até 9h30), com a lista dos anteriores. Os relatórios ficam salvos no aparelho e aparecem também sem internet.
- O app passa a pedir permissão para ler arquivos do Google Drive (somente leitura), para abrir os relatórios da pasta compartilhada. Na primeira vez, a aba pede para entrar de novo com o Google; a sincronização continua funcionando enquanto isso.
- Para ver os relatórios, a pasta "Calculadora DARF - Relatórios" precisa estar compartilhada com o seu e-mail.

### Voltar para a versão anterior

Sem migração de dados: é possível voltar para a 2.6.0 sem perda.
```

- [ ] **Step 3: Verificação completa**

Run (em `app/`): `flutter analyze`; `flutter test --exclude-tags golden,vivo`; `flutter test --tags golden test/app/goldens`; `flutter test --platform chrome test/web`; na raiz: `node --test web_servidor/test/`; `git diff 1cd0a9d --stat -- calculadora_darf.py android/ atualizador.py google_sync.py nucleo.py metas.py sugestoes.py mercado.py noticias.py`
Expected: `No issues found!`; `All tests passed!` (três vezes); `# fail 0`; o último diff vazio (Python intocado).

- [ ] **Step 4: Commit**

```bash
git add app/lib/versao.dart app/test/versao_test.dart docs/release/2.7.0.md
git commit -m "Versão 2.7.0: notas da release"
```

---

### Task 11: Google Cloud, CI, tag 2.7.0, publicação e verificação (controlador)

Executada pelo controlador, com o navegador do dono já logado (skill `anthropic-skills:chrome-browser`) e o agente `monitor-ci` para o GitHub Actions. Nenhum segredo vai para arquivo, commit ou relatório.

**Exige o dono (o controlador para e pede):**
- (D1) Compartilhar a pasta "Calculadora DARF - Relatórios" como leitor com os e-mails dos usuários (inclusive a conta do teste).
- (D2) Autorizar a tag `2.7.0`.
- (D3) Testar no Android real (atualização pelo app, aba na barra inferior, novo login, lista e abertura) e no iPhone (PWA na Tela de Início: aba, lista, abertura, link de fonte) e informar o resultado.

- [ ] **Step 1: Escopo no Google Cloud** — Google Cloud Console > projeto do app > APIs e serviços > Google Auth Platform > Acesso a dados > Adicionar ou remover escopos: marcar `https://www.googleapis.com/auth/drive.readonly` (".../auth/drive.readonly"), manter `drive.file` e `spreadsheets.readonly`, retirar `drive.metadata.readonly`; Salvar. Conferir que o app continua em "Teste". Aceite: a lista de escopos restritos mostra `drive.readonly` e o painel não pede verificação para o modo Teste.

- [ ] **Step 2: Push da branch e CI verde** — `git push origin migracao-flutter`; `monitor-ci` acompanha. Aceite: execução Success com `versao`, `testes`, `android`, `windows`, `web` verdes e os jobs de publicação pulados.

- [ ] **Step 3: Tag e publicação** (com D2) — `git tag 2.7.0` no commit verificado e `git push origin 2.7.0`; `monitor-ci` acompanha. Aceite: Success com `publicar`, `publicar-web` e `conferir-atualizador` verdes; `/releases/latest` = 2.7.0 estável com `.exe`, `.apk` e o corpo de `docs/release/2.7.0.md`; `https://calculadora-darf-web.vercel.app/version.json` mostra `2.7.0`; `curl -s -o /dev/null -w "%{redirect_url}" "https://calculadora-darf-web.vercel.app/api/auth/inicio?volta=https://calculadora-darf-web.vercel.app&n=<43 caracteres base64url>"` contém `drive.readonly` e não contém `drive.metadata.readonly`.

- [ ] **Step 4: Verificação ponta a ponta** (registrar o resultado de cada item)
  1. Windows, conta já logada na 2.6.0 (token antigo): atualizar pelo atualizador do app; a sincronização continua (Conta mostra o e-mail e "Sincronizado"); a aba Relatórios mostra "Para ver os relatórios, entre de novo com o Google"; nenhuma outra aba pede login.
  2. Windows: "Entrar de novo com o Google" → consentir com o Drive → a aba lista e abre o relatório de hoje (ou a mensagem das 9h30 e o mais recente); tocar num anterior abre; "Atualizar" funciona; um link de fonte abre no navegador padrão.
  3. Windows: desconectar a rede → reabrir a aba → aviso discreto de sem conexão e os relatórios salvos.
  4. Web (Chrome, conta de D1, janela larga): login → aba na barra lateral, lista e abre; F5 mantém; na aba Rede, `www.googleapis.com/drive/v3/files?q=...` e `files/<id>?alt=media` 200 com `Authorization: Bearer`, e nenhum pedido de relatório ao `/api` do Vercel; em Application > Local Storage há `darf:relatorios/indice.json` e no máximo 5 `darf:relatorios/relatorio-abertura-*`.
  5. Web em largura de celular (DevTools, 390 × 844): layout compacto, "Relatórios" na barra inferior entre "Notícias" e "Conta", botão "Anteriores" abre a lista, tabela rola na horizontal, sem texto cortado.
  6. Web com um token antigo (sessão aberta antes da publicação, se houver): a aba pede novo login e a sincronização segue.
  7. Conta sem acesso à pasta (se houver uma de teste): mensagem de pasta vazia, sem erro.
  8. (D3) Android e iPhone: resultado informado pelo dono.

  Aceite: itens 1–7 OK (8 quando o dono informar). Falha vira correção com `superpowers:systematic-debugging` antes de seguir; se a suposição do refresh sem `scope` ou do 403 não se confirmar, corrigir com teste e nova tag `2.7.1`.

- [ ] **Step 5: Registro** — `docs/superpowers/plans/2026-11-26-relatorios-resultado.md` no padrão dos resultados anteriores (feito, saídas dos comandos, itens do Step 4, pendências do dono); commit "Resultado da aba Relatórios".

---

## Self-review (feito ao escrever)

1. **Cobertura do pedido e do design:** fonte (pasta, consulta, campos, paginação, `alt=media`) → T4; escopo trocado no app e no servidor, token antigo só bloqueia a aba, sem desconectar → T3, T6, T7, T9; comportamento 1 (hoje em Brasília) → T2, T6, T9; 2 (mensagem e mais recente com data visível) → T9; 3 (lista ordenada, data por extenso, termômetro colorido, abrir) → T2, T9; 4 (Atualizar e leitura a cada abertura) → T9; 5 (cache por `modifiedTime`, sem internet com aviso) → T5, T6, T9; renderização a–k, paleta, direção, links → T8; formato schemaVersion 1 → T1; robustez (ausente, enum, extras, versão nova, JSON inválido e nome fora do padrão com log) → T1, T2, T6, T8; testes do pedido (parser com a fixture, 22 ativos e soma 22; escolha de hoje existe/não existe/fuso; ordenação e campos faltando) → T1, T2; esclarecimento dos ativos variáveis (0, 1, 60, layout no celular, divergência do termômetro) → T1, T6, T8; serviços em `ServicosApp`/`ServicosLocais`/isolate/Web → T7; reforço das três plataformas: Drive direto com Bearer na Web → T7 (teste de host) e T11; `localStorage` com relatórios descartáveis → T5 (VM e `@TestOn('browser')`); `inicio.js` → T3; layout compacto/expandido → T9 (widget nos 3 temas × 2 tamanhos e goldens); verificação Windows/Android/Web/iPhone → T11; 6ª aba → T9; goldens 3 temas × PC/celular → T9; release 2.7.0 e passo do Google Cloud → T10, T11. Fora do escopo respeitado.
2. **Passos:** cada passo de código traz arquivo, assinatura e os valores fixados; os de teste trazem nomes e asserções; os de verificação, comando e saída esperada.
3. **Tipos:** `Relatorio`/`Leitura`/`Direcao`/`Termometro`/`termometroDiverge` (T1 → T6, T8); `ResumoRelatorio`/`dataDoNome`/`hojeBrasilia`/`ordenarRelatorios`/`escolherRelatorio`/`dataPorExtenso` (T2 → T6, T9); `escopoRelatorios`/`escoposDaResposta` (T3 → T4); `EscopoInsuficiente`/`SessaoGoogle.escopos`/`FonteRelatorios`/`DriveRelatorios`/`ArquivoRelatorio`/`podeLerRelatorios` (T4 → T6, T7); `SituacaoRelatorios`/`VisaoRelatorios`/`RelatoriosLocal` (T6 → T7, T9); `relatorios`/`atualizarRelatorios`/`abrirRelatorio`/`entrarDeNovoGoogle` (T7 → T9); `VistaRelatorio`/`textoTermometro`/`coresLeitura`/`linkSeguro` (T8 → T9); `fixtureRelatorio`/`fixtureComAtivos` (T1 → T6, T8, T9).
4. **Review Focus:** os cinco casos têm teste na tarefa dona indicada em cada linha.
5. **Proporção:** os blocos de código são só testes-chave, a lista de escopos e os textos fixados; os corpos ficam com o implementador.
