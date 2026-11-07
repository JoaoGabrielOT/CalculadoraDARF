# Plano 3 (app, telas e temas): resultado e notas para o plano 4

Concluído em 07/11/2026 na branch `migracao-flutter` (commits 630e2e5..3e6cc17, mais o da Tarefa 24). 24 tarefas, cada uma revisada; as que tiveram achados importantes foram corrigidas e re-revisadas. O registro tarefa a tarefa está em `.superpowers/sdd/2026-11-01-plano-3-app/progress.md` (local).

## Estado verificado
Saídas de 07/11/2026, nesta máquina (Windows 11, sem o Modo Desenvolvedor):
- `flutter analyze` (em `app/`): `No issues found!`.
- `flutter test` (em `app/`): `All tests passed!` (29060 testes, goldens incluídos).
- `flutter test --tags golden` (em `app/`): `All tests passed!` (30 goldens).
- `flutter test integration_test -d windows` (em `app/`): **não roda aqui**. Saída: `Building with plugins requires symlink support. Please enable Developer Mode in your system settings.` Mesmo erro em `flutter build windows --release` e `flutter run -d windows`. Ativar o Modo Desenvolvedor foi negado na Tarefa 1 (não contornar); o build e o teste no Windows real passam para o CI do plano 4.
- Substituto local do teste de integração: o mesmo `integration_test/app_test.dart`, copiado temporariamente para `test/` (para carregar as fontes de `flutter_test_config.dart`) e rodado no `flutter_tester` com `debugDefaultTargetPlatformOverride = TargetPlatform.windows` e `--dart-define=CAPTURAS=...\build\capturas`: `All tests passed!` em 32 s, 15 capturas mais uma do radar rolado. O isolate de serviços, o disco e o cliente 503 são os reais do teste; o motor de janela do Windows não.
- `py -3.12 ferramentas/conferir_portados.py`: `147 de 147 portados`.
- `flutter test --tags ida_e_volta` + `py -3.12 ferramentas/conferir_ida_e_volta.py app/build/ida_e_volta`: `IDA E VOLTA OK (20 roteiros)`.
- `python -m unittest discover -s tests` (raiz): `Ran 147 tests ... OK` (Python intacto).

## Verificação visual (capturas do substituto)
As 15 capturas (`apuracao|caixa|radar|noticias|conta` × `terminal|claro|moderno`, 1366×768) foram abertas uma a uma e comparadas com os goldens:
- Tema certo em cada aba: Terminal (fundo grafite, destaque verde), Claro (fundo cinza-claro, cartões brancos, destaque grafite), Moderno (degradê azul-escuro, destaque roxo). O chip do tema escolhido fica marcado na Conta.
- Barra lateral com "Apuração / DARF", Caixa, Radar, Notícias e Conta; cabeçalho com Definir saldo, "Google não conectado", Meta de lucro, Amigos e Conectar Google.
- Apuração com as tabelas de ativos e vendas e o painel Detalhamento lado a lado; a compra gravada (PETR4, 01/11/2026, 100 × R$ 32,50 = R$ 3.250,00) aparece; Caixa com a liquidação dessa compra (-R$ 3.250,97, quarta-feira 04/11/2026).
- Radar com as 16 linhas de erro "Erro ao consultar o histórico: 503 Server …" (cortado na linha) e logos substituídas pelas iniciais; rolando até LREN3 as linhas de baixo também mostram o erro.
- Notícias com "falha em ABEV3, …" no subtítulo e "Nenhuma notícia nos últimos 7 dias com esse filtro."
- Textos em português em todas.
- Observações (sem correção neste plano): no Claro o ✓ do chip selecionado sai escuro sobre o fundo escuro (igual ao golden `conta_claro_pc.png`); na captura do radar rolado o conteúdo da aba aparece deslocado ~28 px para a esquerda, com uma barra de rolagem na borda direita. Provavelmente é o `Scrollable.ensureVisible` de `scrollUntilVisible` rolando um contêiner externo, mas vale conferir no Windows real se a aba Radar tem rolagem horizontal a 1366 px.

## Não verificado à mão (fica para o teste do dono na pré-release)
- `flutter run -d windows` com internet e pasta de dados real: adicionar 3 ativos ao radar e ver cotações, logos e mini-gráficos chegando com a lista rolando; arrastar a janela durante "Buscando notícias…" (não pode travar); abrir o gráfico; redimensionar a janela abaixo de 840 px e voltar. O teste de integração cobre a troca barra lateral ↔ barra inferior mudando `tester.view.physicalSize` (600 e 1366 px), mas não o redimensionamento da janela de verdade.
- O teste de integração e as capturas no motor do Windows (fontes do sistema, DPI real, janela de 1360×860).

## Decisões tomadas durante a execução
- Verificação automática de atualização só no executável final (`EstadoApp(verificarAtualizacaoAutomatica: kReleaseMode)`), como o `pode_atualizar` do Windows (atualizador.py:26-28). A verificação manual da Conta vale sempre. Custo se errado: um build de perfil não procura versão nova sozinho.
- Goldens são pulados com o motivo ("Goldens só no Windows: falta …\Fonts\seguisym.ttf") quando falta a fonte dos símbolos, em vez de 30 falhas de pixel.
- Telas: GraficoLinha posiciona por índice (paridade com o Python, py:3164); cores auxiliares ajustadas para contraste AA 4,5 sem mexer nas cores do mockup; guarda única `Repositorio.lerConfigParaGravar` para todo escritor de `config.json`; erro solto no isolate vira `EventoAviso` e o isolate segue vivo; a busca de notícias é do estado (acontece com a aba fechada); day trade corrigido em `calcularPrecoAlvo`/`projetarPreco` (metas.py:87).

## Notas para o plano 4 (CI, instalador e migração)
- Pasta de dados nova: `%APPDATA%\JoaoGabrielOT\Calculadora DARF\dados` (Windows) e `/data/data/io.github.joaogabrielot.calculadoradarf/files/dados` (Android), mesmo layout da `dados/` da 1.12; o instalador copia para ela.
- Preferências novas em `config.json`: `tema_visual` (ausente = Automático; a chave `tema` da 1.12 é ignorada).
- Argumentos do instalador silencioso (`argumentosInstaladorSilencioso`) a conferir com o instalador real; o instalador reabre o app depois de atualizar.
- Android não compilado localmente: `MainActivity.kt` (canal `calculadoradarf/plataforma`, `instalarApk`), FileProvider `${applicationId}.provider` com `res/xml/caminhos_arquivos.xml`, permissões, desugaring; testar em aparelho: notificação (permissão no Android 13+), abrir APK, login loopback, rolagem do radar durante a carga, `reservado` O(n²) com dados reais.
- Goldens só no Windows (`--exclude-tags golden` em outro SO; sem `seguisym.ttf` eles se pulam com o motivo).
- Ícones do app (Windows `app_icon.ico`, Android mipmap) a partir de `assets/icone.ico` e `assets/icone_janela.png`.
- Windows: build e `flutter test integration_test -d windows --dart-define=CAPTURAS=...` no executor `windows-latest` (aqui exigem o Modo Desenvolvedor); publicar as capturas como artefato. FFI de `flutter_local_notifications_windows`/`jni` pode exigir JDK no build.
- Windows troca o .exe portátil por instalador destacado (o Python usava script .cmd, atualizador.py:122-139); registrar AUMID/atalho para o toast.
- Android: `ic_notificacao` referenciado só por nome pode sumir com `shrinkResources`; conferir `res/raw/keep.xml`.

## Pendências menores registradas (não bloqueiam)
Ficam no `progress.md` por tarefa ("minor (deferred)"). As que tocam o teste do dono: altura de linha de 44 px e "Total a pagar" fora da vista em 768 px; tabela do radar rola abaixo de 1040 px; dois convites de atualização podem empilhar; timer de 60 s segue no Android em segundo plano (igual ao Python); custo de rebuild da Tabela com dezenas de milhares de linhas não medido.
