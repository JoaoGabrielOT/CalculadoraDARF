# Plano 4 (distribuição): resultado, checklist do dono e passos da pré-release

Concluído em 07/11/2026 na branch `migracao-flutter`. O registro tarefa a tarefa está em `.superpowers/sdd/2026-11-08-plano-4-distribuicao/` (local).

## Estado verificado
Saídas de 07/11/2026, nesta máquina (Windows 11, sem o Modo Desenvolvedor):
- `flutter analyze` (em `app/`): `No issues found!`.
- `flutter test` (em `app/`, goldens incluídos): `All tests passed!` (29090 testes).
- `python -m unittest discover -s tests` (raiz): `Ran 147 tests ... OK` (Python intacto).
- `git diff main...migracao-flutter --stat -- calculadora_darf.py android/ atualizador.py`: vazio (código Python e `android/` do Flet não mudaram).
- `gh` não existe nesta máquina: o CI foi lido pelas páginas públicas e pela API REST pública, sem credenciais. Os artefatos exigem login para baixar, então tamanho e sha256 dos arquivos não puderam ser conferidos aqui (ver "Não verificado").

## CI (workflow `release.yml`, `push` em `migracao-flutter`; nunca publica fora de tag)
- Execução final no commit `6095a14` (correção do passo `publicar`): ver "Rodada final" abaixo.
- 42404730209: verificações do APK. Pacote `io.github.joaogabrielot.calculadoradarf`; versionCode 20000 (maior que 11201 da 1.12.x); ABIs `arm64-v8a` e `armeabi-v7a`; recurso `ic_notificacao` presente; certificado SHA-256 `24063835ae4c917b5812e0ed54383af489a46daef98070e62e21f1370582b226`, igual ao do APK publicado da 1.12 (atualiza por cima sem desinstalar).
- 42410172566 e 42411159366: build do Windows. Teste de integração passou no `windows-latest`, 16 capturas geradas, DLLs do redistribuível VC 14.51.36247.0 empacotadas.
- 42412241198 e 42413357548: instalador Inno Setup. Instalação silenciosa com código 0; migração em caminho com acento (`copiados=3`); `dados` antigos intactos; desinstalar mantém os dados; atualização silenciosa com o app aberto; rebaixar é recusado.
- Rodada final: 42414378007 (https://github.com/JoaoGabrielOT/CalculadoraDARF/actions/runs/42414378007), commit `6095a14`: conclusão Success; jobs `versao`, `testes`, `android` e `windows` concluídos; `publicar` pulado (push na branch); sem anotações de erro. Artefatos: `android` (20 MB), `windows` (11,7 MB), `capturas-windows` (1,65 MB). Fonte: página pública da execução (sha256 não conferido, download exige login).

## Decisões tomadas
- Passo `publicar` baixa os artefatos em dois passos explícitos (`name: android` e `name: windows`, ambos com `path: saida`, sem `merge-multiple`), de modo que os arquivos caiam em `saida/CalculadoraDARF.apk` e `saida/CalculadoraDARF.exe` (correção da revisão da Tarefa 6; antes usava `pattern` com `merge-multiple`).
- A 2.0.0 sai como pré-release (`prerelease: true`, `make_latest: "false"`): o atualizador Python da 1.12 e o do Flutter usam `/releases/latest`, que ignora pré-release; usuários da 1.12 não a recebem.
- Tag sem prefixo `v` (`2.0.0`): casa com a regex estrita x.y.z do job `versao` e com a convenção da 1.12.x; o gatilho aceita `v*` e `[0-9]*`.
- Windows e Android não puderam ser compilados localmente (Modo Desenvolvedor negado); a verificação é toda do CI.

## Não verificado (só o dono consegue)
- Capturas e aparência: os artefatos `capturas-windows` exigem login para baixar; as 16 capturas não foram vistas.
- Ramo interativo de `InitializeSetup` com o atalho/exe antigo (só o silencioso foi exercitado no CI).
- Ícone do instalador e versão do produto nas propriedades do arquivo.
- Transição real 1.12 para 2.0 no PC e no celular do dono.
- Android: notificações, login loopback, rolagem do radar, FileProvider (abrir APK), isolate de serviços depois do botão voltar.
- Janela em 1366x768.
- Migração dos dados do Flet no Android (plano de contingência: o app mostra a folha de login e lê da planilha).
- Tamanho e sha256 dos dois artefatos (download exige login).

## Checklist do teste do dono
- PC, transição da 1.12.x: na pasta do exe antigo (com `dados/` real), colocar o `CalculadoraDARF.exe` da pré-release no lugar do exe antigo e abrir (é o que o atualizador Python faz; durante a pré-release ele não enxerga a 2.0.0). Esperado: assistente em português, sem pedir admin, opção de atalho na área de trabalho; o app abre com os meses, radar, metas, amigos e o login do Google (sem pedir login de novo); a pasta antiga continua intacta.
- PC: abrir de novo o atalho/exe antigo. Esperado: abre o app instalado, sem assistente e sem migrar outra vez.
- PC: o instalador mostra o ícone do app e a versão 2.0.0 nas propriedades do arquivo.
- PC: atualização silenciosa pelo app (fica para a 2.0.1: o app 2.0.0 instalado oferece a nova versão, baixa, fecha e reabre já atualizado).
- PC: janela inicial cabe na tela em 1366x768 e 1920x1080 a 125%; redimensionar abaixo de 840 px troca para a barra inferior e volta; arrastar a janela durante "Buscando notícias…" sem travar; radar sem rolagem horizontal a 1366 px.
- PC: notificação de notícia relevante com o app aberto e minimizado (nome e ícone do app no toast).
- PC: abrir as capturas do CI (artefato `capturas-windows`, exige login) e conferir temas, textos em português e o radar.
- Android: instalar o `CalculadoraDARF.apk` por cima do app 1.12.x, sem desinstalar. Esperado: instala; os dados aparecem (migrados do Flet) ou, se não, o app pede login uma vez e lê da planilha.
- Android: permissão de notificação no Android 13+ e notificação chegando; login loopback no navegador do celular; rolar o radar enquanto as cotações carregam; abrir o APK pelo atualizador (FileProvider, para a 2.0.1); o isolate de serviços continua vivo depois do botão voltar.
- Planilha real: uma gravação que encolhe a planilha (sobras limpas, colunas extras e formatação intactas), e o app Python de um amigo lendo os mesmos dados.
- Nota: compilar no Windows desta máquina exige ativar o Modo Desenvolvedor (Configurações > Sistema > Para desenvolvedores); a pasta `C:\dartmp_appcopia` ficou do plano 3 e pode ser apagada.

## Passos para publicar a 2.0.0 como pré-release (feitos pelo controlador)
1. Confirmar CI verde no commit `H` (cabeça de `migracao-flutter`, já no `origin`).
2. Criar a tag `2.0.0` no commit `H` e enviá-la: `git tag -a 2.0.0 -m "Calculadora DARF 2.0.0 (pré-release)" H` e `git push origin 2.0.0`. A tag não foi criada neste plano.
3. Acompanhar a execução disparada pela tag (o workflow é o da branch, por estar no commit marcado). O job `publicar` cria uma PRÉ-RELEASE (`prerelease: true`, `make_latest: "false"`) com `CalculadoraDARF.exe` e `CalculadoraDARF.apk`.
4. Conferir: a release `2.0.0` está marcada como pré-release com os dois arquivos, e `releases/latest` continua apontando a 1.12.x (`gh release view 2.0.0 --json isPrerelease,assets --jq '{p: .isPrerelease, a: [.assets[].name]}'` → `{"p":true,"a":["CalculadoraDARF.apk","CalculadoraDARF.exe"]}`; `gh api repos/JoaoGabrielOT/CalculadoraDARF/releases/latest --jq .tag_name`). Usuários do Python 1.12 não recebem a oferta.
5. Avisar o dono para o checklist. Depois da aprovação (passo posterior e manual, fora deste plano): `gh release edit 2.0.0 --prerelease=false --latest` e um commit trocando `prerelease: true`/`make_latest: "false"` por `false`/`"true"`; a partir daí o atualizador Python das outras máquinas baixa o instalador. Correções da 1.12 durante a pré-release continuam com tag na `main`.
