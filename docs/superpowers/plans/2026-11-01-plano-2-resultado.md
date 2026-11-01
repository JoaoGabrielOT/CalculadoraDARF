# Plano 2 (integrações): resultado e notas para os planos 3 e 4

Concluído em 01/11/2026 na branch `migracao-flutter` (commits 2ce31ce..da94152, mais o da Tarefa 17). 17 tarefas, cada uma revisada; as que tiveram achados importantes foram corrigidas e re-revisadas.

## Estado verificado
- `flutter analyze` (em `app/`): `No issues found!`.
- `flutter test` (em `app/`): `All tests passed!` (28278 testes).
- `py -3.12 ferramentas/conferir_portados.py`: `147 de 147 portados`.
- `flutter test --tags ida_e_volta` + `py -3.12 ferramentas/conferir_ida_e_volta.py app/build/ida_e_volta`: `IDA E VOLTA OK (20 roteiros)`.
- `python -m unittest discover -s tests` (raiz): `Ran 147 tests ... OK` (Python intacto).
- `git grep -n "http.Client()\|IOClient(" -- app/test`: uma ocorrência, `app/test/integracoes/http/cancelar_test.dart:30`, que fala só com um `HttpServer` em `127.0.0.1` (loopback da Tarefa 8/2). Nenhum teste usa a internet.
- Referências: `py -3.12 ferramentas/gerar_referencias.py` (todas as áreas) executado duas vezes seguidas, `git diff --exit-code app/test/referencias` vazio nas duas (ver "Gerador do plano 1").

## Decisões tomadas durante a execução
- Renovação de token com 5xx/429 vira `Offline` (o Python apagaria o token): protege contra logout por instabilidade do Google. Custo se errado: token inválido mantido até o próximo 400/401.
- Renovação segue o google-auth (envia `scope = escoposGoogle`; `expiry` ausente conta como vencido) e ignora o `token_uri` do arquivo (segurança).
- Atualizador: com a mudança de plano, um destino já existente é preservado em falha (o Python apagava); a escrita vai por `.tmp` e só o rename muda o destino. Custo se errado: um instalador velho fica no disco.
- `juntarUrl` usa `Uri.resolve`, que normaliza (host minúsculo, %-encoding, porta padrão) diferente do `urljoin`; só afeta o texto do `img` no cache local de prévias. `noticias_detalhes.json` não é lido pelo Python durante a convivência.
- Teste de URL malformada em `Logos` removido: nenhuma entrada real faz `Uri.parse` lançar; o `catch` geral continua e está coberto.
- Tarefa 11 corrigiu antes do fim: janela do pendente, `agendar` sem tratamento, `prepararPlanilha` em paralelo (duplicaria a planilha no Drive e quebraria o compartilhamento), `conectarComToken` saindo da conta em erro transitório e `sair()` durante sincronização.
- Mensagens 404 do Yahoo diferem de propósito (cotação/fechamento "Sem cotação para X." e gráfico "Sem dados para X no Yahoo Finance."), como no Python. Meta nula é tratada como vazio.

## Notas para o plano 3 (telas)
Plano do brief:
- `http.Client` único por app, fechado ao sair; `carregarClienteOAuth()` com `rootBundle`; `AbrirUrl` com `url_launcher` (modo aplicativo externo); pastas com `path_provider` para `ArmazenamentoArquivos` e `CacheBinarioArquivos`.
- `DadosSincronizacao` sobre o isolate do núcleo (dono único dos arquivos, inclusive `noticias.json`).
- Timers do `Sincronizador.tick` (Python: 60 s no Windows, 30 s no Android); textos de status a partir de `StatusSync`; notificações do sistema.
- SVG da brapi com `flutter_svg`; notas da atualização cortadas em 600 (Windows) e 500 (Android) caracteres na tela; `InstalarAtualizacao` (APK pelo instalador do sistema).

Aprendidas na execução:
- Isolate dedicado e acesso serial ao `Repositorio`: `ambiente`, `corretagemPorOrdem` e a trava de verificação são globais por isolate. Nunca trocar a configuração pelo padrão e gravar depois de uma exceção de leitura.
- A interface não deve permitir conectar com sessão ativa (a troca de conta sem `sair()` junta-se ao Future da conta anterior). Também ficam para a tela: espera de janela modal e limpeza da visão no logout; o `tick` sobrescreve o status de login.
- Usar só o `File` retornado pelo download do atualizador: o destino pode sobrar de uma versão anterior.
- Avaliar visualmente o redimensionamento das imagens de notícias (resize cúbico sem pré-filtro pode serrilhar em reduções grandes; se ruim, `Interpolation.average`).
- A camada de rede já converte falhas de transporte em `ErroConexao`/`Offline`, 429 em `LimiteConsultas` e HTTP ≥ 400 em `ErroHttp`; a tela não precisa tratar `SocketException`. O Yahoo tem cache de 60 s por ticker e preserva o preço anterior em falha.
- `ClienteHttp.enviar` tem tempo limite TOTAL (não por leitura): passar `tempoLimite` maior para páginas e imagens grandes. `abrir` ignora `maxSimultaneas`; não usar para Yahoo/Google.
- `reservado` recalcula raízes por compra (O(n²)), `lerInt` com fração lança e `verificacaoEmAndamento` distingue "em andamento" de "sem metas" (notas do plano 1 que continuam valendo).

## Notas para o plano 4 (CI e migração)
- CI grava `app/assets/google/credentials.json` a partir de `GOOGLE_CREDENTIALS` e sobrescreve `app/lib/versao.dart` pela tag.
- Migrar `token.json` sem conversão (formato authorized_user do google-auth; nomes e chaves do Python também em `noticias_detalhes.json`, `logos/`, `logos/fontes/`, `noticias_img/`).
- `InstalarAtualizacao` do Windows: instalador em modo silencioso. O asset é `CalculadoraDARF.exe` (Windows) e `CalculadoraDARF.apk` (Android).
- Teste manual na pré-release, numa planilha real: gravação que encolhe a planilha (sobras limpas, colunas extras e formatação intactas), exercitando `escrever` sem `endRowIndex`.
- Se o plano 4 acrescentar áreas de referência, qualquer dict derivado de conjunto precisa de ordem explícita no gerador (regra de `js()` em `base.py`); e a validação `fromJson→toJson` dos arquivos migrados, já exigida pelo plano 1.

## Gerador do plano 1 não determinístico (corrigido)
Regenerar todas as áreas mudava 1 linha de `app/test/referencias/repositorio.json`: a ordem das chaves do objeto `excluidos` (vinda de iteração de conjunto de strings no Python, hash aleatório por execução). O conteúdo era igual e os testes Dart comparam mapas, mas violava a restrição "regenerar não muda o JSON". Correção na origem: `js()` em `ferramentas/referencias/base.py` ordena as chaves de `excluidos`. Os JSON de 5 áreas (mesclagem, planilha_montagem, planilha_reconstrucao, repositorio, sincronizacao) mudaram só na ordem dessas chaves; suíte Dart, conferir_portados e ida e volta seguem verdes. Depois disso, duas regenerações seguidas deixam o diff vazio.

## Pendências menores registradas (não bloqueiam), por área
- Infraestrutura (regras, executor, rede): detector de imports só olha linhas iniciadas por `//` (`.sort (` com espaço e `.roundToDouble(` fora); `Retry-After` enorme estoura `Duration` (comparar antes); `abrir` com erro sem drain deixa a conexão aberta; `utf8.decode` sem remover BOM; faltam teste com `TlsException` e com o texto original; `somaPythonNum` dá a volta em int64 (Python tem inteiros arbitrários).
- Referências e Yahoo: `decode_unicode` ignorado na rede falsa e cabeçalhos em minúsculas; dados sem deduplicação em voo (`_emVoo`); corpo 200 não JSON vira "FormatException:" na mensagem (deveria ser `SemDados`/`ErroConexao`); falta teste de 429 persistente mantendo o cache.
- Google (token, sessão, login, planilha): strings vazias contam como ausentes; 403 transitório pede login; `expiry` não textual ignorado; `rapt_token`/`quota_project_id` não preservados; `fromJson` mantém os `scopes` do arquivo; 200 não JSON vira `FormatException`/`TypeError` cru (deveria ser `ErroGoogle` "Resposta inválida"); `rgb` remove um só `#`; qualquer `?error=` com `state` errado encerra a espera do login (igual ao Python); `finally` marca respondido também para não GET; `_get` dentro de `unawaited` sem `completeError`; `erro_401` renova e repete (como `AuthorizedSession`); aba fora do esquema gera erro de null; faltam testes de `Offline`, de `batchUpdate` falhando após GET e de `descompartilhar` com maiúsculas.
- Sincronização: `conta.sair()` em `_tratarErro` sem `try`; `catch` do `tick` sem conferir geração; ramo `LoginNecessario` de `conectarComToken` e `finally` de `_conectandoToken` sem conferir geração; `lerAmigo` com e-mail nulo.
- Notícias e imagens: `\W`/`\S` dentro de colchetes no `erPython` geram regex errada em silêncio (deveria lançar `ArgumentError`); RSS sempre UTF-8; `lerRssRegex` aparece no barril; dígitos Unicode; charset `ascii` lança e `windows-1252`/`shift_jis` caem em UTF-8; 429 em página grava texto diferente no cache; decodificação leve e `jsonDecode` do batch ficam fora do isolate; `lerDetalhes` só captura `FormatException`; `Uri.parse` de URL com espaço; `enriquecer` concorrente sem trava; assinar blocos após `cancelar` lança (documentar); `ClienteHttp` do teste não fechado; sem teste no isolate real nem de 429 nas imagens.
- Atualizador: release sem `digest` pula a conferência de hash (igual ao Python); `cancelar` em fluxo parado só após 30 s; tag nula → null; `_apagar` só captura `FileSystemException`; a mensagem "Verifique o espaço livre" aparece também para rename/open travados; o teste de limpeza não prova que o `delete` falhou; `close()` no `finally` pode trocar o erro de cancelamento.
- Testes: o teste "método que não é GET recebe 501" (Tarefa 8) foi estabilizado na rodada 2; vigiar a CI por qualquer instabilidade em testes de loopback.
