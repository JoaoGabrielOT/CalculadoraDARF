# Plano 4: distribuição e transição (Implementation Plan)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deixar a 2.0.0 pronta para sair como pré-release: instalador do Windows publicado como `CalculadoraDARF.exe`, APK assinado que instala por cima do app Flet, migração dos dados da 1.12 nas duas plataformas e um `release.yml` que gera e confere os dois arquivos no CI.

**Architecture:** O `release.yml` da branch `migracao-flutter` passa a gerar só o app Flutter (as tags 1.12.x continuam saindo da `main`, cujo workflow Python não muda: o GitHub usa o workflow do commit marcado). Jobs: `versao` (lê a tag ou `versao.dart`, recusa tags 1.x), `testes`, `android` (APK único arm64-v8a + armeabi-v7a, assinado com a keystore atual e conferido contra o APK publicado), `windows` (build, teste de integração, instalador Inno Setup e teste do instalador) e `publicar` (só por tag, sempre `prerelease: true`). A migração de dados é código Dart testável localmente: o instalador só grava de onde veio (`migracao_origem.txt`); o app copia na partida, sem sobrescrever, valida e grava um marcador.

**Tech Stack:** Flutter 3.47.9 (stable, Dart 3.13.7), Inno Setup 6 (ISCC), GitHub Actions (`subosito/flutter-action@v2`, `actions/setup-java@v4` Temurin 17, `softprops/action-gh-release@v2`, `actions/upload-artifact@v4`, `actions/download-artifact@v4`), Android build-tools (`aapt2`, `apksigner`), `gh` CLI; pacote `image` 4.12.0 (já dependência) para os ícones.

**Spec:** `docs/superpowers/specs/2026-10-31-migracao-flutter-design.md` (§6.5 Distribuição e transição, §10). Notas obrigatórias: `docs/superpowers/plans/2026-11-01-plano-3-resultado.md` ("Notas para o plano 4"), `docs/superpowers/plans/2026-11-01-plano-2-resultado.md` e `docs/superpowers/plans/2026-10-31-plano-1-resultado.md` (validação `fromJson→toJson` dos arquivos migrados).

## Global Constraints

Do spec (§6.5):
- Instalador "publicado na release com o nome `CalculadoraDARF.exe`, porque o atualizador Python (atualizador.py) só procura esse nome. Ele baixa o arquivo, troca o exe antigo por ele e o executa."
- Instalação "pasta por usuário, sem exigir admin, atalho no menu Iniciar e opção na área de trabalho"; migra "os dados da pasta `dados/` ao lado do exe antigo (o próprio local de onde o instalador foi executado): config.json, token.json, meses, notícias e logos".
- A migração "copia `dados/` (não move nem apaga a pasta antiga) e grava um marcador no destino. Se o instalador for executado de novo, por exemplo por um atalho antigo que agora aponta para ele, não migra outra vez por cima de dados novos; só abre o app instalado."
- Atualizações seguintes: "o app Flutter baixa o instalador novo, confere tamanho e sha256 do campo `digest` do asset e o executa em modo silencioso" (já feito no plano 2/3; aqui só os argumentos).
- Android: "Mesmo applicationId" `io.github.joaogabrielot.calculadoradarf` "e mesma keystore (segredos `ANDROID_KEYSTORE_BASE64` e `ANDROID_KEYSTORE_PASSWORD`, alias `calculadoradarf`)"; "versionCode maior que o atual (fórmula M·10000 + m·100 + p mantida)"; migrar "do armazenamento do Flet (`FLET_APP_STORAGE_DATA`) se ainda forem acessíveis; senão, reler da planilha e pedir login uma vez"; o atualizador baixa `CalculadoraDARF.apk`.
- "A 2.0.0 sai primeiro como **pré-release** (o atualizador Python ignora `prerelease`)." Só depois da aprovação do dono vira "latest" (fora deste plano).
- CI: "Gatilho por tag igual ao atual" (`tags: ["v*", "[0-9]*"]` e `workflow_dispatch` sem publicar). "Jobs Windows (build Flutter + instalador) e Android (APK arm64-v8a e armeabi-v7a, assinado), e job de publicação com os dois arquivos."
- §10: a ferramenta do instalador é escolha do construtor: **Inno Setup 6**.

Do ambiente e das notas anteriores:
- Nesta máquina `flutter build windows`, `flutter run -d windows` e `flutter test integration_test -d windows` falham com "Building with plugins requires symlink support. Please enable Developer Mode". Não ativar o Modo Desenvolvedor nem contornar. Tudo que exige build Windows ou Android é verificado no CI por `gh workflow run release.yml --ref migracao-flutter` + `gh run watch <id> --exit-status`. Pré-requisito: a branch enviada ao `origin` (`git push origin migracao-flutter`); o push é feito pelo controlador ou com autorização do dono.
- Nada neste plano toca a `main`, o código Python da raiz, `android/` (Flet) ou o caminho de release 1.12.x.
- Pastas de dados do app novo: `%APPDATA%\JoaoGabrielOT\Calculadora DARF\dados` (Windows; `getApplicationSupportDirectory()` usa CompanyName e ProductName do `Runner.rc`) e `/data/data/io.github.joaogabrielot.calculadoradarf/files/dados` (Android). Layout igual ao da `dados/` da 1.12.
- Goldens só no Windows local: no CI, `flutter test --exclude-tags golden` (decisão do plano 3, `app/dart_test.yaml`).
- Flutter no CI fixado em `3.47.9` (o mesmo da máquina local).
- `app/lib/app/plataforma/` é a única pasta do app que usa `dart:io`/plugins; ordenações com `ordenadoPor` (nunca `.sort(`); textos em português.
- Segredos já cadastrados no repositório: `GOOGLE_CREDENTIALS`, `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`. O CI grava `app/assets/google/credentials.json` (ignorado pelo git) e confere a chave `installed`.

## Review Focus

1. **Atalho antigo depois de uma autoatualização:** o PC já está na 2.0.1 instalada e a pessoa abre o atalho velho, que aponta para o instalador 2.0.0 deixado na pasta antiga. Esperado: abre o app instalado, sem rebaixar a versão e sem migrar de novo (Tarefa 6, `InitializeSetup`; não testável no CI sem interface, entra no checklist do dono).
2. **Pasta antiga com acentos ou no OneDrive** (`C:\Users\João\OneDrive\Área de Trabalho\Calculadora DARF\dados`): o caminho gravado pelo Inno (UTF-8, talvez com BOM) chega intacto ao Dart (Tarefa 2, teste `origensWindows lê caminho com acentos e BOM`).
3. **Destino já com dados da 2.0** (a pessoa abriu o app novo antes de rodar o instalador pelo atalho velho): nada do destino é sobrescrito (Tarefa 2, teste `não sobrescreve arquivo que já existe no destino`).
4. **PC sem o Visual C++ Redistributable:** o app Flutter precisa de `msvcp140.dll`, `vcruntime140.dll` e `vcruntime140_1.dll`; o exe PyInstaller trazia tudo. Esperado: o app abre num Windows limpo (Tarefa 5 copia as DLLs para o pacote; Tarefa 6 confere no teste do instalador).
5. **Falha no meio da cópia** (disco cheio, arquivo travado): sem marcador, a próxima abertura tenta de novo e avisa (Tarefa 2, teste `erro na cópia não grava marcador e devolve o erro`).

---

## Estrutura de arquivos

| Arquivo | Responsabilidade |
|---|---|
| `app/tool/gerar_icones.dart` (novo) | Gera `app_icon.ico` e os mipmaps a partir de `assets/` da raiz |
| `app/lib/app/plataforma/migracao.dart` (novo) | Origens (Windows/Android), cópia sem sobrescrever, validação, marcador |
| `app/lib/app/app.dart` | Chama a migração antes de criar os serviços e avisa o resultado |
| `app/android/app/build.gradle.kts` | Assinatura release pela keystore do CI |
| `app/ci/conferir_apk.sh` (novo) | Confere pacote, ABIs, versionCode, ícone de notificação e certificado contra o APK publicado |
| `app/instalador/CalculadoraDARF.iss` (novo) | Instalador Inno Setup |
| `app/ci/testar_instalador.ps1` (novo) | Instala em silêncio a partir de uma pasta 1.12 falsa e confere app, DLLs, migração e desinstalação |
| `app/lib/app/plataforma/instalador.dart` | Comentário dos argumentos (valores ficam) |
| `.github/workflows/release.yml` | Pipeline Flutter |
| `docs/superpowers/plans/2026-11-08-plano-4-resultado.md` (novo) | Resultado, checklist do dono e passos da pré-release |

---

### Task 1: Ícones do app (Windows e Android)

**Files:**
- Create: `app/tool/gerar_icones.dart`
- Modify (gerados): `app/windows/runner/resources/app_icon.ico`, `app/android/app/src/main/res/mipmap-{mdpi,hdpi,xhdpi,xxhdpi,xxxhdpi}/ic_launcher.png`
- Test: `app/test/app/plataforma/icones_test.dart`

**Interfaces:**
- Produces: `Future<void> main()` em `app/tool/gerar_icones.dart`, rodado com `dart run tool/gerar_icones.dart` dentro de `app/`. A Tarefa 6 usa `assets\icone.ico` da raiz como `SetupIconFile`.

- [ ] **Step 1: Escrever o teste**

```dart
// app/test/app/plataforma/icones_test.dart
const tamanhos = {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192};
test('app_icon.ico do Windows é o assets/icone.ico da raiz', () {
  expect(File('windows/runner/resources/app_icon.ico').readAsBytesSync(),
         File('../assets/icone.ico').readAsBytesSync());
});
for (final e in tamanhos.entries) {
  test('mipmap-${e.key}/ic_launcher.png tem ${e.value}x${e.value}', () {
    final img = decodePng(File('android/app/src/main/res/mipmap-${e.key}/ic_launcher.png').readAsBytesSync())!;
    expect((img.width, img.height), (e.value, e.value));
  });
}
test('mipmap-xxxhdpi não é o ícone padrão do Flutter', () {
  // compara com o hash do arquivo atual (padrão do flutter create), anotado no Step 2
  expect(sha256.convert(File('android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png').readAsBytesSync()).toString(),
         isNot(hashPadraoAnotado));
});
```

- [ ] **Step 2: Rodar e ver falhar**

Antes, anote `sha256` do `mipmap-xxxhdpi/ic_launcher.png` atual como `hashPadraoAnotado` no teste. Run (em `app/`): `flutter test test/app/plataforma/icones_test.dart`. Expected: FAIL no teste do `.ico` (bytes diferem desde o byte 5) e no do hash.

- [ ] **Step 3: Implementar `app/tool/gerar_icones.dart`**

Copia `../assets/icone.ico` byte a byte para `windows/runner/resources/app_icon.ico`; decodifica `../assets/icone_janela.png` com `package:image`, redimensiona (`copyResize`, `Interpolation.average`) para cada tamanho da tabela e grava os PNG. Se `icone_janela.png` for menor que 192 px, usar o maior quadro de `icone.ico` (`decodeIco`) como fonte. Sem ícone adaptativo (fica para depois). Rodar: `dart run tool/gerar_icones.dart`.

- [ ] **Step 4: Rodar e ver passar**

Run: `flutter test test/app/plataforma/icones_test.dart` e `flutter analyze`. Expected: `All tests passed!` e `No issues found!`. Abrir o `mipmap-xxxhdpi/ic_launcher.png` gerado e conferir que é o ícone da calculadora.

- [ ] **Step 5: Commit**

```bash
git add app/tool/gerar_icones.dart app/test/app/plataforma/icones_test.dart app/windows/runner/resources/app_icon.ico app/android/app/src/main/res/mipmap-*/ic_launcher.png
git commit -m "Plano 4, tarefa 1: ícones do app a partir de assets/"
```

---

### Task 2: Migração dos dados da 1.12 (Windows e Android)

**Files:**
- Create: `app/lib/app/plataforma/migracao.dart`
- Modify: `app/lib/app/app.dart` (`_criarServicos` e `tentar` em `iniciarApp`)
- Test: `app/test/app/plataforma/migracao_test.dart`

**Interfaces:**
- Consumes: `Mes.fromJson`/`toJson` (`app/lib/nucleo/modelos/mes.dart`), `Config.fromJson`/`toJson` (`app/lib/nucleo/modelos/config.dart`), `jsonPythonDecode` (`app/lib/nucleo/compat/json_python.dart`), `pastasDoApp()` (`app/lib/app/plataforma/pastas.dart`), `EstadoApp.avisar(String titulo, String texto)`.
- Produces (a Tarefa 6 depende dos dois nomes de arquivo):

```dart
const nomeMarcadorMigracao = '.migrado_1_12.json'; // dentro de dados/
const nomeArquivoOrigem = 'migracao_origem.txt';  // na pasta de suporte, pai de dados/

class ResultadoMigracao {
  const ResultadoMigracao({this.origem, this.copiados = 0, this.divergentes = const [], this.erro});
  final String? origem;            // null = nada migrado nesta partida
  final int copiados;
  final List<String> divergentes;  // caminhos relativos, ordenados
  final String? erro;
}

List<String> origensWindows(String pastaSuporte);
List<String> origensAndroid(List<String> raizes, {required String destino, int profundidade = 4});
ResultadoMigracao migrarDados112({required String destino, required List<String> origens});
bool preservaOriginal(Object? original, Object? reconstruido);
(String, String)? avisoMigracao(ResultadoMigracao r);
Future<ResultadoMigracao> migrarNaPartida({required String pastaSuporte, required String destino,
    required bool windows, List<String> raizesAndroid = const []});
```

Regras:
- `origensWindows`: lê `<pastaSuporte>/migracao_origem.txt` em UTF-8 tirando o BOM; devolve a primeira linha não vazia (sem espaços nas pontas) se a pasta existir; senão `[]`.
- `origensAndroid`: percorre cada raiz até `profundidade` níveis; candidata é a pasta que contém `config.json` ou um arquivo `^\d{4}-\d{2}\.json$`; ignora `destino` e o que estiver dentro dele. Ordem: as que têm `token.json` primeiro, depois a de `config.json` mais recente (`ordenadoPor`).
- `migrarDados112`: se `destino/.migrado_1_12.json` existe, devolve `ResultadoMigracao()` sem tocar em nada. Usa a primeira origem candidata (mesmas regras de candidata; origem igual ao destino é ignorada). Copia a árvore inteira (`config.json`, `token.json`, meses, `noticias*.json`, `logos/`, `logos/fontes/`, `noticias_img/`, o que houver) **sem sobrescrever** arquivo existente no destino e sem apagar nada na origem. Para cada `config.json` e `AAAA-MM.json` copiado: `preservaOriginal(json, Modelo.fromJson(json).toJson())`; falso ou JSON ilegível entra em `divergentes` (o arquivo é copiado mesmo assim). Por fim grava o marcador `{"origem":…, "em": <ISO 8601>, "copiados": n, "divergentes": [...]}`. Qualquer `FileSystemException` vira `erro` (texto da exceção) e o marcador não é gravado. Sem origem candidata: `ResultadoMigracao()` e nenhum marcador (no Android isso cai no caminho do spec: o app lê da planilha depois do login).
- `preservaOriginal`: mapas: toda chave do original existe no reconstruído com valor que preserva (chaves a mais no reconstruído são aceitas, são os padrões); listas: mesmo tamanho e item a item; números comparados por valor (`1 == 1.0`); demais por `==`.
- `avisoMigracao`: `erro != null` → `('Dados da versão anterior', 'Não foi possível copiar os dados da versão anterior: $erro. O app tenta de novo na próxima abertura.')`; `divergentes` não vazio → `('Dados da versão anterior', 'Copiados $copiados arquivos de $origem. Confira estes arquivos, que não foram lidos por inteiro: ${divergentes.join(', ')}.')`; senão `null`.
- `migrarNaPartida`: monta as origens (`windows` → `origensWindows(pastaSuporte)`; Android → `origensAndroid(raizesAndroid, destino: destino)`) e roda `migrarDados112` em `Isolate.run` (cópia de muitas imagens fora da thread da interface). Nunca lança: exceção vira `ResultadoMigracao(erro: …)`.
- `app.dart`: em `_criarServicos`, depois de `pastasDoApp()` e antes de `ServicosIsolate.criar`, `await migrarNaPartida(...)` com `pastaSuporte` = pai de `pastas.dados`; no Android `raizesAndroid` = `[getApplicationSupportDirectory().path, getApplicationDocumentsDirectory().path]` (as duas ficam em `/data/data/<appId>/`, onde o Flet guardava `FLET_APP_STORAGE_DATA`). Depois que `tentar` cria o `EstadoApp`, se `avisoMigracao(r)` não for nulo, `estado.avisar(titulo, texto)`. O resultado passa de `_criarServicos` para `tentar` por uma variável da closure de `iniciarApp` (testes que injetam `criarServicos` não migram).

- [ ] **Step 1: Escrever os testes** (todos com `Directory.systemTemp.createTempSync`, origem montada com um mês e uma config reais da 1.12 tirados de `app/test/referencias/`)

```dart
test('copia a árvore inteira e grava o marcador', ...);
  // origem: config.json, token.json, 2026-10.json, logos/PETR4.png, noticias_img/a.jpg
  // expect(r.origem, origem); expect(r.copiados, 5); expect(r.divergentes, isEmpty);
  // expect(File('$destino/logos/PETR4.png').existsSync(), isTrue);
  // expect(jsonDecode(File('$destino/.migrado_1_12.json').readAsStringSync())['copiados'], 5);
  // expect(File('$origem/config.json').existsSync(), isTrue); // origem intacta
test('com marcador não copia nada', ...);            // r.origem == null; arquivo novo na origem não aparece
test('não sobrescreve arquivo que já existe no destino', ...); // destino/config.json com 'novo' continua 'novo'
test('arquivo que perde dado na leitura entra em divergentes', ...);
  // 2026-10.json com um lote que tem a chave desconhecida "x": 1 (o modelo Lote descarta chaves desconhecidas, plano 1)
  // expect(r.divergentes, ['2026-10.json']); arquivo copiado igual ao original
test('JSON ilegível entra em divergentes e é copiado', ...);
test('erro na cópia não grava marcador e devolve o erro', ...); // destino é um arquivo, não pasta
test('sem origem candidata não grava marcador', ...);
test('origensWindows lê caminho com acentos e BOM', ...);
  // grava [0xEF,0xBB,0xBF] + utf8('<tmp>\\Área de Trabalho\\João\\dados\r\n')
  // expect(origensWindows(suporte), ['<tmp>\\Área de Trabalho\\João\\dados']);
test('origensWindows sem arquivo ou com pasta inexistente devolve vazio', ...);
test('origensAndroid acha a pasta do Flet e ignora o destino', ...);
  // raiz/flet/app_storage/config.json + token.json; raiz/dados/config.json (destino)
  // expect(origensAndroid([raiz], destino: '$raiz/dados'), ['$raiz/flet/app_storage']);
test('origensAndroid respeita a profundidade', ...); // config a 5 níveis não aparece
test('preservaOriginal aceita 1 e 1.0 e chaves a mais, recusa chave perdida', () {
  expect(preservaOriginal({'a': 1}, {'a': 1.0, 'b': 2}), isTrue);
  expect(preservaOriginal({'a': 1, 'x': 'y'}, {'a': 1}), isFalse);
  expect(preservaOriginal([1, 2], [1]), isFalse);
});
test('avisoMigracao: nada com sucesso limpo; texto com erro e com divergências', ...);
```

- [ ] **Step 2: Rodar e ver falhar**

Run (em `app/`): `flutter test test/app/plataforma/migracao_test.dart`. Expected: FAIL de compilação (`migracao.dart` não existe).

- [ ] **Step 3: Implementar `migracao.dart` e a chamada em `app.dart`** conforme as regras acima.

- [ ] **Step 4: Rodar e ver passar**

Run: `flutter test test/app/plataforma/migracao_test.dart`, depois `flutter analyze` e `flutter test` (suíte inteira, inclui o teste de regras de imports). Expected: `All tests passed!` e `No issues found!`.

- [ ] **Step 5: Commit**

```bash
git add app/lib/app/plataforma/migracao.dart app/lib/app/app.dart app/test/app/plataforma/migracao_test.dart
git commit -m "Plano 4, tarefa 2: migração dos dados da 1.12 na partida"
```

---

### Task 3: Workflow base (versão, testes, publicação como pré-release)

**Files:**
- Modify: `.github/workflows/release.yml` (substitui os jobs Python **só nesta branch**)

**Interfaces:**
- Produces: job `versao` com `outputs.versao` (ex.: `2.0.0`) e `outputs.numero` (ex.: `20000`); passo reutilizado pelas Tarefas 4 e 5 para gravar `app/lib/versao.dart` e `app/assets/google/credentials.json`; job `publicar` que as Tarefas 4 e 5 acrescentam em `needs`.

Conteúdo fixado:
- `on:` igual ao atual (`push: tags: ["v*", "[0-9]*"]`, `workflow_dispatch`); `permissions: contents: write`.
- Job `versao` (`ubuntu-latest`): por tag, exige `^v?(\d+)\.(\d+)\.(\d+)$` (senão `::error::Tag fora do formato x.y.z`) e major ≥ 2 (senão `::error::Tags 1.x são do app Python e saem da main.`); sem tag (dispatch), lê a versão de `app/lib/versao.dart` (nunca `0.0.0`: um build 0.0.0 ofereceria a 1.12 como atualização). `numero = M*10000 + m*100 + p`.
- Passo de preparação nos jobs de build (copiar igual em cada um): com tag, grava `app/lib/versao.dart` com as duas linhas atuais trocando o número (`const String versaoApp = '<versao>';`); grava `credentials.json` de `GOOGLE_CREDENTIALS` e confere `installed` (mensagem de erro igual à do workflow atual).
- Job `testes` (`windows-latest`, `needs: versao`): checkout, `subosito/flutter-action@v2` (`flutter-version: 3.47.9`, `channel: stable`, `cache: true`), em `app/`: `flutter pub get`, `flutter analyze`, `flutter test --exclude-tags golden`. Roda **antes** da troca de `versao.dart` (o `versao_test.dart` exige 2.0.0; para 2.0.x esse teste é ajustado no commit da versão).
- Job `publicar`: `if: github.ref_type == 'tag'`, `needs: [versao, testes]` (as Tarefas 4 e 5 acrescentam `android` e `windows`), `download-artifact` com `merge-multiple: true`, e:

```yaml
      - name: Publicar a release (pré-release até o dono aprovar)
        uses: softprops/action-gh-release@v2
        with:
          name: Calculadora DARF ${{ needs.versao.outputs.versao }}
          files: |
            saida/CalculadoraDARF.exe
            saida/CalculadoraDARF.apk
          prerelease: true     # o atualizador Python e o Flutter usam /releases/latest, que ignora pré-release
          make_latest: "false" # após a aprovação: gh release edit <tag> --prerelease=false --latest, e trocar estas duas linhas
          generate_release_notes: true
          fail_on_unmatched_files: true
```

- [ ] **Step 1: Escrever o workflow** com `versao`, `testes` e `publicar` (sem os jobs Python `windows`/`android`).
- [ ] **Step 2: Conferir a sintaxe localmente**

Run: `py -3.12 -c "import yaml,sys; d=yaml.safe_load(open('.github/workflows/release.yml',encoding='utf-8')); print(sorted(d['jobs']))"`. Expected: `['publicar', 'testes', 'versao']`.

- [ ] **Step 3: Commit, push e rodar no CI**

```bash
git add .github/workflows/release.yml
git commit -m "Plano 4, tarefa 3: workflow Flutter (versão, testes, pré-release)"
git push origin migracao-flutter
gh workflow run release.yml --ref migracao-flutter
gh run list --workflow release.yml --branch migracao-flutter -L 1   # pega o id
gh run watch <id> --exit-status
```

Expected: exit 0; `versao` com `versao=2.0.0` e `numero=20000` no log; `testes` verde; `publicar` "skipped". Se algum teste falhar só no executor (caminhos, fuso, fontes), investigar com `superpowers:systematic-debugging` e corrigir o teste ou o código; não pular testes.

---

### Task 4: APK assinado e compatível com o publicado

**Files:**
- Modify: `app/android/app/build.gradle.kts` (`signingConfigs`, `buildTypes.release`)
- Create: `app/ci/conferir_apk.sh`
- Modify: `.github/workflows/release.yml` (job `android`; `publicar.needs` ganha `android`)

**Interfaces:**
- Consumes: `needs.versao.outputs.versao`/`numero` (Tarefa 3).
- Produces: artefato `android` com `CalculadoraDARF.apk`.

Assinatura (Kotlin DSL, não óbvio; o Flet usava a mesma senha para a keystore e para a chave):

```kotlin
val caminhoChave = System.getenv("ANDROID_KEYSTORE_PATH")
val senhaChave = System.getenv("ANDROID_KEYSTORE_PASSWORD")
val temChave = !caminhoChave.isNullOrEmpty() && !senhaChave.isNullOrEmpty()
// em android { }:
signingConfigs {
    create("release") {
        if (temChave) {
            storeFile = file(caminhoChave!!)
            storePassword = senhaChave
            keyAlias = "calculadoradarf"
            keyPassword = senhaChave
        }
    }
}
buildTypes { release { signingConfig = signingConfigs.getByName(if (temChave) "release" else "debug") } }
```

(Sem os segredos o build local continua assinando com a chave de debug; o CI falha antes, ao conferir os segredos.)

`app/ci/conferir_apk.sh <novo.apk> <versionCode esperado> <anterior.apk>` (bash, `set -euo pipefail`, `aapt2` e `apksigner` da versão mais nova em `$ANDROID_HOME/build-tools/`). Cada conferência imprime `OK <o quê>` ou `ERRO <o quê>: <obtido>` e sai com 1:
1. `aapt2 dump badging novo` → `package: name='io.github.joaogabrielot.calculadoradarf'` e `versionCode='<esperado>'`.
2. `native-code:` contém exatamente `'arm64-v8a' 'armeabi-v7a'`.
3. `aapt2 dump resources novo` contém `drawable/ic_notificacao` (o `res/raw/keep.xml` resistiu ao `shrinkResources`).
4. Mesmo `name=` no anterior e `versionCode` do novo maior que o do anterior.
5. `apksigner verify --print-certs` dos dois: linhas `certificate SHA-256 digest` iguais.

Job `android` (`ubuntu-latest`, `needs: versao`):
- Conferir os segredos `ANDROID_KEYSTORE_BASE64` e `ANDROID_KEYSTORE_PASSWORD` (mesmas mensagens do workflow atual); `echo "$KEYSTORE_B64" | base64 -d > "$RUNNER_TEMP/upload.jks"`.
- `actions/setup-java@v4` (`distribution: temurin`, `java-version: 17`), Flutter 3.47.9, passo de preparação (Tarefa 3).
- Em `app/`, com `ANDROID_KEYSTORE_PATH=$RUNNER_TEMP/upload.jks` e `ANDROID_KEYSTORE_PASSWORD`: `flutter build apk --release --target-platform android-arm,android-arm64 --build-name "$VERSAO" --build-number "$NUMERO"` (APK único, sem `--split-per-abi`, para o versionCode ser exatamente a fórmula) e copiar `build/app/outputs/flutter-apk/app-release.apk` para `CalculadoraDARF.apk` na raiz.
- `gh release download --repo "$GITHUB_REPOSITORY" --pattern CalculadoraDARF.apk --dir anterior` (sem tag = a release latest, hoje a 1.12.x Flet) com `GH_TOKEN: ${{ github.token }}`; depois `bash app/ci/conferir_apk.sh CalculadoraDARF.apk "$NUMERO" anterior/CalculadoraDARF.apk`.
- `upload-artifact` `name: android`, `path: CalculadoraDARF.apk`.

- [ ] **Step 1: Escrever a assinatura no gradle, `conferir_apk.sh` e o job `android`.**
- [ ] **Step 2: Conferir o script localmente** (Git Bash): `bash -n app/ci/conferir_apk.sh` → sem saída; `bash app/ci/conferir_apk.sh` sem argumentos → mensagem de uso e saída 2.
- [ ] **Step 3: Commit, push e rodar no CI**

```bash
git add app/android/app/build.gradle.kts app/ci/conferir_apk.sh .github/workflows/release.yml
git commit -m "Plano 4, tarefa 4: APK assinado e conferido contra o publicado"
git push origin migracao-flutter
gh workflow run release.yml --ref migracao-flutter   # depois gh run watch <id> --exit-status
```

Expected: exit 0; no log do `android`, as cinco linhas `OK` (versionCode `20000`, maior que o da 1.12.x); `gh run download <id> -n android` traz `CalculadoraDARF.apk`. Falha de Kotlin, manifesto, FileProvider ou desugaring (nunca compilados antes) se corrige nesta tarefa.

---

### Task 5: Build do Windows, DLLs do runtime e teste de integração

**Files:**
- Modify: `.github/workflows/release.yml` (job `windows`, parte do build)

**Interfaces:**
- Consumes: `needs.versao.outputs.*`, passo de preparação (Tarefa 3).
- Produces: pasta `app\build\windows\x64\runner\Release\` com `calculadoradarf.exe`, `data\`, DLLs dos plugins e `msvcp140.dll`, `vcruntime140.dll`, `vcruntime140_1.dll` (a Tarefa 6 empacota tudo); artefato `capturas-windows`.

Job `windows` (`windows-latest`, `needs: versao`):
- Checkout, `actions/setup-java@v4` (Temurin 17; o `jni` de `flutter_local_notifications_windows` pode pedir JDK no build), Flutter 3.47.9, preparação.
- Em `app/`: `flutter build windows --release --build-name $env:VERSAO --build-number $env:NUMERO`.
- Copiar as três DLLs de `C:\Windows\System32\` para `build\windows\x64\runner\Release\` (implantação local do runtime; falha se alguma faltar).
- `flutter test integration_test -d windows --dart-define=CAPTURAS=$env:GITHUB_WORKSPACE\app\build\capturas` (primeira execução no motor real do Windows; janela inicial limitada pela `AjustarJanelaInicial` de `windows/runner/main.cpp`).
- `upload-artifact` `name: capturas-windows`, `path: app/build/capturas`, `if: always()`.

- [ ] **Step 1: Escrever a parte de build do job `windows`.**
- [ ] **Step 2: Commit, push e rodar no CI**

```bash
git add .github/workflows/release.yml
git commit -m "Plano 4, tarefa 5: build do Windows e teste de integração no CI"
git push origin migracao-flutter
gh workflow run release.yml --ref migracao-flutter   # depois gh run watch <id> --exit-status
```

Expected: exit 0; `All tests passed!` no passo de integração. `gh run download <id> -n capturas-windows`: abrir as 15 capturas e a do radar rolado e comparar com as do plano 3 (tema certo por aba, textos em português, sem conteúdo deslocado). Anotar no relatório se o deslocamento de ~28 px do radar rolado (plano 3) aparece no motor real. Falha de C++ (`main.cpp`) ou de plugin se corrige nesta tarefa.

---

### Task 6: Instalador Inno Setup e teste do instalador no CI

**Files:**
- Create: `app/instalador/CalculadoraDARF.iss`
- Create: `app/ci/testar_instalador.ps1`
- Modify: `app/lib/app/plataforma/instalador.dart` (só o comentário de `argumentosInstaladorSilencioso`)
- Modify: `.github/workflows/release.yml` (job `windows`, parte do instalador; `publicar.needs` ganha `windows`)

**Interfaces:**
- Consumes: pasta Release da Tarefa 5; `nomeMarcadorMigracao` e `nomeArquivoOrigem` (Tarefa 2); `aumid = 'JoaoGabrielOT.CalculadoraDARF'` (`notificacoes.dart`).
- Produces: `app\build\instalador\CalculadoraDARF.exe`, artefato `windows`.

`[Setup]` fixado (o `AppId` não muda nunca):

```ini
#ifndef Versao
  #define Versao "0.0.0"
#endif
[Setup]
AppId={{ABE8CE4E-E03F-4D9C-8B54-DA1CA348A2DD}
AppName=Calculadora DARF
AppVersion={#Versao}
VersionInfoVersion={#Versao}
AppPublisher=JoaoGabrielOT
DefaultDirName={localappdata}\Programs\Calculadora DARF
DefaultGroupName=Calculadora DARF
DisableProgramGroupPage=yes
DisableDirPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=..\build\instalador
OutputBaseFilename=CalculadoraDARF
SetupIconFile=..\..\assets\icone.ico
UninstallDisplayIcon={app}\calculadoradarf.exe
UninstallDisplayName=Calculadora DARF
CloseApplications=force
RestartApplications=no
WizardStyle=modern
Compression=lzma2/max
SolidCompression=yes
ShowLanguageDialog=no

[Languages]
Name: "pt"; MessagesFile: "compiler:Languages\BrazilianPortuguese.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; Flags: unchecked

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{userprograms}\Calculadora DARF"; Filename: "{app}\calculadoradarf.exe"; AppUserModelID: "JoaoGabrielOT.CalculadoraDARF"
Name: "{userdesktop}\Calculadora DARF"; Filename: "{app}\calculadoradarf.exe"; Tasks: desktopicon

[Run]
; sem skipifsilent: no modo silencioso (atualização pelo app) o app reabre sozinho
Filename: "{app}\calculadoradarf.exe"; Description: "{cm:LaunchProgram,Calculadora DARF}"; Flags: nowait postinstall
```

`[Code]` (comportamento fixado; funções do Inno à escolha):
- `CurStepChanged(ssPostInstall)`: se `{src}\dados` existe, cria `{userappdata}\JoaoGabrielOT\Calculadora DARF` e grava nele `migracao_origem.txt` com uma linha, `ExpandConstant('{src}\dados')`, em UTF-8 (`SaveStringsToUTF8File`; o Dart tolera o BOM). A cópia é do app (Tarefa 2).
- `InitializeSetup`: quando **não** é silencioso (`WizardSilent` falso), `{src}\dados` existe, `{userappdata}\JoaoGabrielOT\Calculadora DARF\dados\.migrado_1_12.json` existe e a versão instalada (`DisplayVersion` em `HKCU\Software\Microsoft\Windows\CurrentVersion\Uninstall\{ABE8CE4E-E03F-4D9C-8B54-DA1CA348A2DD}_is1`) é maior ou igual a `{#Versao}`: abre `{app}` instalado (`InstallLocation` da mesma chave + `calculadoradarf.exe`, `ShellExec` sem esperar) e devolve `False` (sai sem instalar e sem mensagem). Caso do atalho antigo (Review Focus 1).
- Desinstalar não apaga `%APPDATA%\JoaoGabrielOT\Calculadora DARF` (sem `[UninstallDelete]`).

`argumentosInstaladorSilencioso` continua `['/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART']` (o teste existente em `plataforma_test.dart:94` segue valendo); o comentário passa a dizer "argumentos do Inno Setup (app/instalador/CalculadoraDARF.iss); o [Run] reabre o app".

`app/ci/testar_instalador.ps1 -Instalador <caminho>` (sai com 1 e `::error::` na primeira falha):
1. Cria `$env:RUNNER_TEMP\Área de Trabalho\Calculadora DARF\dados\` com `config.json` (`{"tema": "Dark", "radar": []}`), `2026-10.json` (o `mes_vazio` da 1.12: `{"mes": "2026-10", "fechado": false, "darf_anterior": 0.0, "lotes": [], "excluidos": {}}`) e `logos\X.png`; copia o instalador para essa pasta como `CalculadoraDARF.exe` (o que o atualizador Python faz).
2. Roda `CalculadoraDARF.exe /VERYSILENT /SUPPRESSMSGBOXES /NORESTART` a partir dali e espera terminar.
3. Confere `$env:LOCALAPPDATA\Programs\Calculadora DARF\calculadoradarf.exe` e as três DLLs da Tarefa 5 ao lado; o atalho em `$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Calculadora DARF.lnk`; `migracao_origem.txt` com o caminho acentuado.
4. Espera até 60 s o app aberto pelo `[Run]` gravar `$env:APPDATA\JoaoGabrielOT\Calculadora DARF\dados\.migrado_1_12.json`; confere `2026-10.json` e `logos\X.png` no destino e o marcador sem divergências; encerra `calculadoradarf`.
5. Roda `unins000.exe /VERYSILENT` e confere: exe removido, pasta de dados nova mantida, `dados\` antiga intacta.

Job `windows`, depois da Tarefa 5: ISCC em `${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe` (se faltar, `choco install innosetup --no-progress -y`), `ISCC.exe /DVersao=$env:VERSAO app\instalador\CalculadoraDARF.iss`; `pwsh app\ci\testar_instalador.ps1 -Instalador app\build\instalador\CalculadoraDARF.exe`; `upload-artifact` `name: windows`, `path: app/build/instalador/CalculadoraDARF.exe`.

- [ ] **Step 1: Escrever o `.iss`, o script de teste, o comentário em `instalador.dart` e os passos do job.**
- [ ] **Step 2: Conferir localmente o que dá**

Run (em `app/`): `flutter test test/app/plataforma/plataforma_test.dart` → `All tests passed!`. Run: `pwsh -NoProfile -Command "[System.Management.Automation.Language.Parser]::ParseFile('app/ci/testar_instalador.ps1',[ref]$null,[ref]$e) | Out-Null; $e.Count"` → `0`. Se o ISCC estiver instalado aqui, compilar o `.iss` com uma pasta Release vazia só para ver a sintaxe (opcional).

- [ ] **Step 3: Commit, push e rodar no CI**

```bash
git add app/instalador/CalculadoraDARF.iss app/ci/testar_instalador.ps1 app/lib/app/plataforma/instalador.dart .github/workflows/release.yml
git commit -m "Plano 4, tarefa 6: instalador Inno Setup e teste do instalador no CI"
git push origin migracao-flutter
gh workflow run release.yml --ref migracao-flutter   # depois gh run watch <id> --exit-status
```

Expected: exit 0; o log de `testar_instalador.ps1` mostra os cinco blocos sem erro (incluindo o marcador gravado pelo app real em `%APPDATA%`); `gh run download <id> -n windows` traz `CalculadoraDARF.exe` com ícone da calculadora e "Versão do produto 2.0.0" nas propriedades.

---

### Task 7: Verificação final, checklist do dono e passos da pré-release

**Files:**
- Create: `docs/superpowers/plans/2026-11-08-plano-4-resultado.md`

**Interfaces:**
- Consumes: tudo acima. Não cria tag nem release (a publicação é do controlador depois do plano).

- [ ] **Step 1: Verificação local**

Run (em `app/`): `flutter analyze`; `flutter test` (com goldens); na raiz: `python -m unittest discover -s tests`. Expected: `No issues found!`, `All tests passed!`, `Ran 147 tests ... OK`.

- [ ] **Step 2: Rodada final do CI no último commit**

`gh workflow run release.yml --ref migracao-flutter`; `gh run watch <id> --exit-status` → exit 0 com `versao`, `testes`, `android`, `windows` verdes e `publicar` skipped. `gh run download <id> -n windows -n android` e `Get-FileHash -Algorithm SHA256` dos dois. Conferir que a `main` não mudou: `git diff main...migracao-flutter --stat -- calculadora_darf.py android/ atualizador.py` vazio.

- [ ] **Step 3: Escrever o resultado** (formato dos resultados dos planos 1-3: estado verificado com as saídas, id e link da execução do CI, tamanhos e sha256 dos dois artefatos, decisões tomadas), com estas duas seções:

**Checklist do teste do dono** (cada item com o resultado esperado):
- PC, transição da 1.12.x: na pasta do exe antigo (com `dados/` real), colocar o `CalculadoraDARF.exe` da pré-release no lugar do exe antigo e abrir (é o que o atualizador Python faz; durante a pré-release ele não enxerga a 2.0.0). Esperado: assistente em português, sem pedir admin, opção de atalho na área de trabalho; o app abre com os meses, radar, metas, amigos e o login do Google (sem pedir login de novo); a pasta antiga continua intacta.
- PC: abrir de novo o atalho/exe antigo. Esperado: abre o app instalado, sem assistente e sem migrar outra vez.
- PC: atualização silenciosa pelo app (fica para a 2.0.1: o app 2.0.0 instalado oferece a nova versão, baixa, fecha e reabre já atualizado).
- PC: janela inicial cabe na tela em 1366x768 e 1920x1080 a 125%; redimensionar abaixo de 840 px troca para a barra inferior e volta; arrastar a janela durante "Buscando notícias…" sem travar; radar sem rolagem horizontal a 1366 px.
- PC: notificação de notícia relevante com o app aberto e minimizado (nome e ícone do app no toast).
- Android: instalar o `CalculadoraDARF.apk` por cima do app 1.12.x, sem desinstalar. Esperado: instala; os dados aparecem (migrados do Flet) ou, se não, o app pede login uma vez e lê da planilha.
- Android: permissão de notificação no Android 13+ e notificação chegando; login loopback no navegador do celular; rolar o radar enquanto as cotações carregam; abrir o APK pelo atualizador (para a 2.0.1).
- Planilha real: uma gravação que encolhe a planilha (sobras limpas, colunas extras e formatação intactas), e o app Python de um amigo lendo os mesmos dados.
- Nota: compilar no Windows desta máquina exige ativar o Modo Desenvolvedor (Configurações > Sistema > Para desenvolvedores); a pasta `C:\dartmp_appcopia` ficou do plano 3 e pode ser apagada.

**Passos para publicar a 2.0.0 como pré-release** (feitos pelo controlador):
1. Confirmar CI verde no commit `H` (cabeça de `migracao-flutter`, já no `origin`).
2. `git tag -a v2.0.0 -m "Calculadora DARF 2.0.0 (pré-release)" H` e `git push origin v2.0.0`.
3. `gh run watch <id> --exit-status` da execução disparada pela tag (o workflow é o da branch, por estar no commit marcado).
4. `gh release view v2.0.0 --json isPrerelease,assets --jq '{p: .isPrerelease, a: [.assets[].name]}'` → `{"p":true,"a":["CalculadoraDARF.apk","CalculadoraDARF.exe"]}`; `gh api repos/JoaoGabrielOT/CalculadoraDARF/releases/latest --jq .tag_name` continua a 1.12.x.
5. Avisar o dono para o checklist. Depois da aprovação (fora deste plano): `gh release edit v2.0.0 --prerelease=false --latest` e um commit trocando `prerelease: true`/`make_latest: "false"` por `false`/`"true"`; a partir daí o atualizador Python das outras máquinas baixa o instalador. Correções da 1.12 durante a pré-release continuam com tag na `main`.

- [ ] **Step 4: Commit**

```bash
git add docs/superpowers/plans/2026-11-08-plano-4-resultado.md
git commit -m "Plano 4, tarefa 7: verificação final, checklist do dono e passos da pré-release"
```
