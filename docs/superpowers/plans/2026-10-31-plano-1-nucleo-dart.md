# Plano 1: núcleo de cálculo e planilha em Dart (Implementation Plan)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Portar para Dart puro (pasta `app/lib/nucleo/`) todo o cálculo, o armazenamento local e o formato/mesclagem da planilha da versão Python 1.12.x, com resultados idênticos aos do Python, provados por arquivos de referência gerados pelo próprio Python e pelos 147 testes portados.

**Architecture:** Projeto Flutter novo em `app/` (Windows e Android), mas o núcleo não importa Flutter, não faz rede e não tem UI. Modelos tipados e mutáveis espelham os dicts do Python (mesmas chaves JSON), uma camada `compat/` reproduz a aritmética e os textos do Python (arredondamento, `sum`, `repr`, `json.dumps`, ordenação estável), e cada tarefa porta um módulo Python com TDD contra JSON de referência (`app/test/referencias/<area>.json`) gerado por `ferramentas/gerar_referencias.py`. Rede (Google, Yahoo HTTP, RSS), telas e distribuição ficam para os planos 2, 3 e 4.

**Tech Stack:** Flutter estável (Dart 3), `flutter_test`, pacotes `collection`, `meta`, `unorm_dart` (NFKD para notícias); Python 3.12 para gerar as referências.

**Spec:** `docs/superpowers/specs/2026-10-31-migracao-flutter-design.md` (seções 4, 6.1, 7 e 9) e `docs/superpowers/specs/2026-10-31-inventario-python.md`. A fonte da verdade de cada função é o arquivo Python citado em cada tarefa (arquivo:linha).

## Global Constraints

Do spec:
- Resultados numéricos idênticos aos do Python (imposto, taxas, isenção, preço-alvo, sugestões, caixa, D+2). Nos testes de referência, `double` compara com `==` e com o mesmo sinal de zero, nunca com tolerância.
- Planilha é contrato congelado: abas, colunas e ordem de google_sync.py:13-45; números como número com ponto, booleanos "Sim"/"Não", datas como serial do Sheets (dias desde 30/12/1899), "Modificado" em epoch segundos com 3 casas, Mês "MM/AAAA", Execução e Detalhes das metas como JSON em texto.
- Compatibilidade de leitura igual à atual: colunas faltantes completadas, Posição do radar opcional, aba Metas com 12 colunas aceita.
- Mesclagem idêntica: maior `mod` vence; exclusão vence se exclusão ≥ mod; metas executada > cancelada > mod; OCO; venda `auto-<meta>` deduplicada entre meses; caixa por maior `mod`.
- Pendências da 1.12.x reproduzidas como estão (spec §9). Não há compensação de prejuízo entre meses no Python (só dentro do mês, nucleo.py:330-335); não inventar.
- Arquivos locais com o mesmo layout e as mesmas chaves do Python (`AAAA-MM.json`, `config.json`, `noticias.json`), porque a pasta `dados/` da 1.12.x será migrada (plano 4) e lida pelo app novo.
- Projeto: Flutter canal stable, `--org io.github.joaogabrielot`, `--project-name calculadoradarf`, plataformas `windows,android`, em `app/`.

Decisões deste plano (valem para todas as tarefas):
- `app/lib/nucleo/**` não importa `package:flutter`, `dart:ui` nem pacotes de rede; `dart:io` só em `lib/nucleo/armazenamento_arquivos.dart`. O teste de regras da Tarefa 1 garante isso.
- Nomes em português como no Python, em camelCase (`calcular_venda` → `calcularVenda`). Chaves JSON exatamente as do Python (`data_compra`, `lote_id`, `darf_anterior`...).
- Datas são `String` ISO `AAAA-MM-DD`, meses `String` `AAAA-MM`, instantes com fuso são `DataHora` (Tarefa 4). Fuso de Brasília fixo −03:00 (`fusoBrasilia = -10800`), como metas.py:22.
- Arredondamento: `round(x, n)` e `format(x, '.nf')` do Python arredondam o valor binário exato com meio-para-par (round(1.125, 2) = 1.12, round(2.675, 2) = 2.67). No núcleo, só `arredondar` e `fixoPython` (Tarefa 2) fazem isso; `toStringAsFixed`, `round()`, `roundToDouble()` são proibidos fora de `compat/`.
- `sum()` do Python 3.12 usa soma compensada de Neumaier; toda porta de `sum()` sobre floats usa `somaPython`. Acúmulos com `+=` (ex.: `defaultdict(float)`) continuam com `+` simples, na mesma ordem.
- `max`/`min` do Python devolvem o primeiro máximo (max(-0.0, 0) = -0.0): usar `maxPython`/`minPython`/`maxDe`/`minDe`, nunca `math.max`/`math.min`, fora de `compat/`.
- `sorted`/`list.sort` do Python são estáveis (inclusive com `reverse=True`, que mantém a ordem original dos empates); `List.sort` do Dart não é estável. Toda ordenação usa `ordenadoPor`/`ordenadoCom` (Tarefa 3); `.sort(` é proibido fora de `compat/`.
- Ordem das operações aritméticas igual à do Python, expressão por expressão (`(compra + venda) * taxa`, não `compra * taxa + venda * taxa`).
- Texto de float só por `fixoPython`/`reprPython`/`jsonPython`; nunca interpolar `double` direto em `String`.
- Erros para o usuário: `ErroValidacao(mensagem)` com o texto idêntico ao `ValueError` do Python; funções `parse_*` lançam `FormatException`.
- Relógio, ids e "hoje" vêm do `ambiente` global (Tarefa 6), substituível nos testes. Valores congelados usados pelo gerador Python e pelos testes Dart: `agora = 1761000000.123`, ids `id0001`, `id0002`... (contador reiniciado a cada caso), `hoje = '2026-10-28'`, `agoraBr = 2026-10-28T12:00:00-03:00`.
- O núcleo roda em um único isolate; a `TRAVA` do Python não é portada. O plano 3 garante acesso serial ao `Repositorio` e chama o núcleo fora da thread da interface.
- Referências geradas com Python 3.12 (a versão do CI e do Flet, release.yml:19, 62, 100). Os JSON de referência são commitados; os testes Dart não dependem de Python instalado.
- Testes portados: descrição do teste Dart = `'<ClassePython>.<metodo_python>'` exatamente, em arquivos sob `app/test/nucleo/portados/`, com as mesmas asserções do Python.
- Comandos `flutter` rodam dentro de `app/`; comandos `py`/`python` rodam na raiz do repositório. Mensagens de commit em português.

## Review Focus

1. Planilha editada à mão (ID numérico `123` ou `123.0`, quantidade `100.0`, data como texto `5/10/2026`, mês com espaço `" 10/2026"`, `TRUE` em coluna numérica): o Dart deve reconstruir exatamente o que o Python reconstrói, nem mais nem menos. Teste: casos `editadas_a_mao` da Tarefa 14.
2. Empates de ordenação (duas vendas na mesma data, lançamentos com a mesma liquidação/data/ticker, radar ordenado por variação igual, notícias com a mesma data): a ordem das linhas e da tela deve ser a do Python. Testes: casos `empate_*` das Tarefas 10, 11, 13 e 22.
3. Pasta `dados/` da 1.12.x migrada (config.json com `planilhas`, `pendente`, `noticias_notificar`, `radar_ordem_lista`; inteiros onde se espera float): o app novo carrega sem perder nada e regrava preservando as chaves que não conhece. Teste: `le arquivos gravados pelo Python 1.12 e preserva chaves desconhecidas` na Tarefa 6.
4. Títulos e nomes com acento ou fora do ASCII ("Itaú Unibanco", "Nestlé", "Ørsted", "ﬁ", emoji): relevância, chave de título e termo de busca iguais aos do Python. Teste: casos `unicode` da Tarefa 22.
5. Valores reais que caem exatamente no meio do centavo (compra de 1 ação a R$ 1,125; brl de 0,125): Total e textos iguais aos do Python (1,12, não 1,13). Testes: caso `total_com_empate_binario` da Tarefa 13 e casos `empate_centavo` da Tarefa 5.

## Fora deste plano

- Plano 2: HTTP do Yahoo (implementação de `ObterChart`, 429), Google (login, Sheets, Drive, pedidos `updateCells`/formatação a partir de `esquemaAbas`, e a verificação de `escrever` sem `endRowIndex`, spec §6.1), RSS/HTML de notícias (`ler_rss`, `ler_previa`), logos, atualizador, cotação/fechamento/gráfico (mercado.py:245-325, 441-466).
- Plano 3: telas, temas e a chamada do núcleo em segundo plano. Plano 4: CI, instalador, migração de dados.

---

### Task 1: Instalar o Flutter e criar o projeto `app/`

**Files:**
- Create: `app/` (gerado por `flutter create`)
- Modify: `app/analysis_options.yaml`, `app/pubspec.yaml`
- Create: `app/lib/nucleo/nucleo.dart` (barril de exports, vazio no início)
- Test: `app/test/nucleo/regras_test.dart`

**Interfaces:**
- Consumes: nada.
- Produces: pacote Dart `calculadoradarf`; import do núcleo `package:calculadoradarf/nucleo/nucleo.dart`; pastas `lib/nucleo/{compat,modelos,mercado,planilha,metas,sugestoes,noticias}` e `test/nucleo/{apoio,portados}`, `test/referencias/`.

- [ ] **Step 1: Instalar o Flutter estável (PowerShell)**

```powershell
git clone https://github.com/flutter/flutter.git -b stable C:\src\flutter
$p = [Environment]::GetEnvironmentVariable('Path', 'User'); [Environment]::SetEnvironmentVariable('Path', "$p;C:\src\flutter\bin", 'User'); $env:Path += ';C:\src\flutter\bin'
flutter --version
```
Expected: linha com `channel stable` e a versão do Dart 3.x. Se `C:\src\flutter` já existir, `git -C C:\src\flutter pull` no lugar do clone.

- [ ] **Step 2: Rodar o diagnóstico**

Run: `flutter doctor -v`
Expected: `[√] Flutter`. "Visual Studio" e "Android toolchain" podem aparecer com `[X]`: não são necessários para `flutter test` e ficam para o plano 4.

- [ ] **Step 3: Criar o projeto (na raiz do repositório)**

Run: `flutter create --org io.github.joaogabrielot --project-name calculadoradarf --platforms windows,android app`
Expected: `All done!`; `app/android/app/build.gradle*` com `applicationId "io.github.joaogabrielot.calculadoradarf"`.

- [ ] **Step 4: Dependências e análise estrita**

Run (em `app/`): `flutter pub add collection meta unorm_dart`. Se `unorm_dart` não resolver, parar e reportar (não trocar por outro pacote: a Tarefa 22 depende de NFKD igual ao `unicodedata` do Python).

`app/analysis_options.yaml`:
```yaml
include: package:flutter_lints/flutter.yaml
analyzer:
  language:
    strict-casts: true
    strict-inference: true
    strict-raw-types: true
linter:
  rules:
    - always_declare_return_types
    - avoid_dynamic_calls
    - prefer_final_locals
    - prefer_single_quotes
    - unawaited_futures
```

- [ ] **Step 5: Escrever o teste de regras de portabilidade**

`app/test/nucleo/regras_test.dart` varre `lib/nucleo/**/*.dart`:
```dart
test('núcleo não importa Flutter, dart:ui nem rede', ...);           // sem 'package:flutter', 'dart:ui', 'package:http'
test('dart:io só em armazenamento_arquivos.dart', ...);
test('fora de compat/ não usa toStringAsFixed, .sort(, math.max, math.min, .round(, .roundToDouble(', ...);
```

- [ ] **Step 6: Rodar testes e análise**

Run: `flutter test test/nucleo/regras_test.dart` e `flutter analyze`
Expected: `All tests passed!` (passa sem arquivos ainda) e `No issues found!`.

- [ ] **Step 7: Commit**

```bash
git add app
git commit -m "Plano 1, tarefa 1: projeto Flutter em app/ com análise estrita e regras do núcleo"
```

---

### Task 2: Infraestrutura de referências e aritmética do Python

**Files:**
- Create: `ferramentas/gerar_referencias.py`, `ferramentas/referencias/__init__.py`, `ferramentas/referencias/base.py`, `ferramentas/referencias/numeros.py`
- Create (gerado): `app/test/referencias/numeros.json`
- Create: `app/test/nucleo/apoio/referencias.dart`, `app/lib/nucleo/compat/numeros.dart`
- Test: `app/test/nucleo/compat/numeros_test.dart`

**Interfaces:**
- Consumes: nada.
- Produces (Python, usado por todas as tarefas seguintes):
  - `py -3.12 ferramentas/gerar_referencias.py [area ...]` grava `app/test/referencias/<area>.json` = `{"python": sys.version, "area": str, "casos": [{"nome", "funcao", "entrada", "saida"}]}`, em UTF-8 (`encoding="utf-8"`, `ensure_ascii=False`; não imprimir não-ASCII no console cp1252). Cada área é um módulo `ferramentas/referencias/<area>.py` com `def casos() -> list[dict]`. Recusa rodar fora do 3.12 (`sys.version_info[:2] != (3, 12)`).
  - `base.caso(nome, funcao, entrada, saida) -> dict`; `base.js(obj)` (date → ISO, datetime → `isoformat()`, tupla → lista, set → lista ordenada; recusa NaN/inf); `base.congelar()` (context manager: `nc.agora` → 1761000000.123; `nc.novo_id` → `id0001`, `id0002`...; `nc.date`, `mk.date`, `sg.date` trocados por subclasse de `date` cujo `today()` é 2026-10-28; `mt.agora_br` → 2026-10-28T12:00:00-03:00); `base.pasta_dados()` (context manager: pasta temporária + `nc.configurar`); `base.arquivos(pasta) -> dict[nome, json]`; `base.gravar_arquivos(pasta, dict)`. Cada caso roda dentro de `congelar()` novo (contador de ids reiniciado).
- Produces (Dart):
  - `class Caso { final String nome; final String funcao; final Object? entrada; final Object? saida; }`
  - `List<Caso> carregarCasos(String area)` (lê `test/referencias/<area>.json`)
  - `void conferir(Object? atual, Object? esperado, {String caminho = r'$', Set<String> semOrdem = const {}})`: igualdade estrita; `num` por valor e sinal de zero (`int 0` = `0.0`); `Map` com o mesmo conjunto de chaves; `List` na ordem, exceto caminhos em `semOrdem` (comparação como multiconjunto); a falha cita o caminho.
  - `compat/numeros.dart`: `double arredondar(double x, int casas)`, `String fixoPython(double x, int casas, {bool sinal = false, bool milhar = false})`, `String reprPython(double x)`, `double somaPython(Iterable<double> valores)`, `T maxPython<T extends num>(T a, T b)`, `T minPython<T extends num>(T a, T b)`, `double maxDe(Iterable<double> v)`, `double minDe(Iterable<double> v)`.

- [ ] **Step 1: Instalar o Python 3.12 (o mesmo do CI e do Flet)**

Run: `winget install -e --id Python.Python.3.12` e depois `py -3.12 --version`
Expected: `Python 3.12.x`.

- [ ] **Step 2: Escrever `base.py`, `gerar_referencias.py` e a área `numeros`**

`numeros.py` gera, com `random.Random(1)`, ~2000 floats de magnitudes 1e-10 a 1e17 e sinais variados, mais os fixos `0.125, 0.375, 1.125, 2.5, -0.125, 2.675, 1.005, 0.005, -0.001, -0.0, 1e-05, 0.0001, 1e16, 123456789.125, 5e-324`. Funções: `round` (`round(x, n)`, n ∈ {0, 2, 3, 4, 6}), `format` (`format(x, '.nf')` n ∈ {1, 2, 8}, `'+.2f'`, `',.2f'`), `repr`, `sum` (500 listas de 0 a 60 floats, mais `[0.1] * 10`), `max`/`min` de pares com ±0.

Run: `py -3.12 ferramentas/gerar_referencias.py numeros`
Expected: arquivo `app/test/referencias/numeros.json` criado; `"python": "3.12.`.

- [ ] **Step 3: Escrever o teste que falha**

```dart
test('referências geradas com Python 3.12', () { /* cabeçalho "python" começa com "3.12" */ });
for (final caso in carregarCasos('numeros')) {
  test('${caso.funcao}: ${caso.nome}', () {
    final e = caso.entrada! as Map<String, Object?>;
    final atual = switch (caso.funcao) {
      'round' => arredondar((e['x']! as num).toDouble(), e['casas']! as int),
      'format' => fixoPython(...), 'repr' => reprPython(...), 'sum' => somaPython(...),
      'max' => maxPython(...), 'min' => minPython(...),
      _ => fail('função desconhecida'),
    };
    conferir(atual, caso.saida);
  });
}
test('round do Python é meio-para-par sobre o binário exato', () {
  expect(arredondar(1.125, 2), 1.12); expect(arredondar(2.675, 2), 2.67); expect(arredondar(0.375, 2), 0.38);
  expect(fixoPython(-0.001, 2), '-0.00'); expect(fixoPython(1234567.891, 2, milhar: true), '1,234,567.89');
});
test('sum do Python 3.12 é compensada', () => expect(somaPython(List.filled(10, 0.1)), 1.0));
```

- [ ] **Step 4: Rodar e ver falhar**

Run: `flutter test test/nucleo/compat/numeros_test.dart`
Expected: FAIL (funções não definidas).

- [ ] **Step 5: Implementar `compat/numeros.dart`**

- `arredondar`: decompor `x` em mantissa e expoente exatos (`ByteData` → `BigInt`), multiplicar por 10^casas como fração exata, arredondar meio-para-par com `BigInt`, montar o texto decimal com o sinal de `x` e devolver `double.parse` do texto (preserva -0.0, como o Python).
- `fixoPython`: mesmos dígitos do `arredondar`; prefixo `-` se `x.isNegative` (inclusive quando o resultado é zero, como `format(-0.001, '.2f')`), `+` quando `sinal` e não negativo; `milhar` agrupa a parte inteira com `,` de 3 em 3.
- `reprPython`: dígitos mínimos de `x.toStringAsExponential()` (sem argumento); expoente e em [-4, 16) → notação posicional com pelo menos `.0`; fora disso `d[.ddd]e±XX` (dois dígitos no mínimo: `1e-05`, `1e+16`); `inf`, `-inf`, `nan`, `-0.0`.
- `somaPython`, igual ao CPython 3.12 (bltinmodule.c, `builtin_sum_impl`):
```dart
double f = 0.0, c = 0.0;
for (final x in valores) {
  final t = f + x;
  c += f.abs() >= x.abs() ? (f - t) + x : (x - t) + f;
  f = t;
}
return (c != 0.0 && c.isFinite) ? f + c : f;
```
- `maxPython(a, b)` = `b > a ? b : a`; `minPython(a, b)` = `b < a ? b : a`; `maxDe`/`minDe` dobram com essas, a partir do primeiro elemento.

- [ ] **Step 6: Rodar e ver passar**

Run: `flutter test test/nucleo/compat/numeros_test.dart`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add ferramentas app/lib/nucleo/compat/numeros.dart app/test
git commit -m "Plano 1, tarefa 2: gerador de referências e aritmética idêntica ao Python 3.12"
```

---

### Task 3: Conversões, ordenação estável e JSON no estilo Python

**Files:**
- Create: `app/lib/nucleo/compat/conversao.dart`, `app/lib/nucleo/compat/ordenacao.dart`, `app/lib/nucleo/compat/json_python.dart`, `ferramentas/referencias/conversao.py`
- Create (gerado): `app/test/referencias/conversao.json`
- Test: `app/test/nucleo/compat/conversao_test.dart`

**Interfaces:**
- Consumes: `reprPython` (Tarefa 2).
- Produces:
  - `String strPython(Object? v)` (`None`, `True`/`False`, int decimal, double por `reprPython`, String igual)
  - `double floatPython(Object? v)` (num; bool → 1.0/0.0; String com `strip`, sinal, `_` entre dígitos, expoente, `inf`/`infinity`/`nan` sem diferenciar maiúsculas; senão `FormatException`)
  - `int intPython(Object? v)` (int; double truncado para zero, `FormatException` em inf/nan; bool → 1/0; String com `strip`, sinal e `_` entre dígitos, sem ponto)
  - `bool verdadeiroPython(Object? v)` (falso: null, false, 0, 0.0, "", lista/mapa vazios)
  - `double numOuPadrao(Object? v, [double padrao = 0.0])` (= `_num`, nucleo.py:770-774)
  - `List<T> ordenadoPor<T>(Iterable<T> itens, List<Object> Function(T) chave, {bool reverso = false})` (chave = tupla do Python: num, String ou bool; estável; com `reverso` os empates mantêm a ordem original)
  - `List<T> ordenadoCom<T>(Iterable<T> itens, int Function(T a, T b) comparar)` (estável; para `cmp_to_key`)
  - `int compararChaves(List<Object> a, List<Object> b)`
  - `String jsonPython(Object? valor, {bool compacto = false})` (= `json.dumps(ensure_ascii=False)`; separadores `", "`/`": "` ou `","`/`":"` com `compacto`; double por `reprPython` (inf → `Infinity`, nan → `NaN`); escapes `\"`, `\\`, `\n`, `\r`, `\t`, `\b`, `\f`, demais < 0x20 como `\u00xx` minúsculo; não-ASCII literal; ordem de inserção dos mapas)

- [ ] **Step 1: Escrever a área `conversao` do gerador**

Casos: `str` de `[0, -7, 1.0, 100.0, -0.0, 1e16, 21.78, True, False, None, "x"]`; `float` de `[" 12.5 ", "1_000", "1e3", "inf", "-Infinity", "nan", "12,5", "", "0x10", "1__0", 7, True]` (erro → `{"erro": "ValueError"}`); `int` de `["100", " 7 ", "1_0", "100.0", "", 100.9, -2.7, True]`; truthiness de valores variados; `json` de dicts como a execução de metas.py:528-531 (com `≥`, aspas, `\n`, `\u001f`, floats 9.0, 1e-05, 21.78) nos dois modos; `sorted` com chave tupla e `reverse` sobre listas com empates (saída = ordem dos índices originais).

Run: `py -3.12 ferramentas/gerar_referencias.py conversao`
Expected: `conversao.json` criado.

- [ ] **Step 2: Escrever o teste que falha**

Loop sobre `carregarCasos('conversao')` como na Tarefa 2 (erro esperado ↔ `throwsFormatException`), mais:
```dart
test('ordenação reversa mantém a ordem original dos empates', () {
  expect(ordenadoPor([(1, 'a'), (2, 'b'), (1, 'c')], (e) => [e.$1], reverso: true).map((e) => e.$2), ['b', 'a', 'c']);
});
```

- [ ] **Step 3: Rodar e ver falhar**

Run: `flutter test test/nucleo/compat/conversao_test.dart`
Expected: FAIL.

- [ ] **Step 4: Implementar os três arquivos**

Ordenação estável: decorar com o índice e desempatar pelo índice (crescente também no reverso); `List.sort` só aqui dentro.

- [ ] **Step 5: Rodar e ver passar**

Run: `flutter test test/nucleo/compat/conversao_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add ferramentas app/lib/nucleo/compat app/test
git commit -m "Plano 1, tarefa 3: conversões, ordenação estável e json.dumps do Python"
```

---

### Task 4: Datas e instantes com fuso

**Files:**
- Create: `app/lib/nucleo/datas.dart`, `ferramentas/referencias/datas.py`
- Create (gerado): `app/test/referencias/datas.json`
- Test: `app/test/nucleo/datas_test.dart`

**Interfaces:**
- Consumes: `intPython`, `strPython` (Tarefa 3).
- Produces:
  - `const int fusoBrasilia = -10800;`
  - `String somarDias(String iso, int dias)`, `int diasEntre(String de, String ate)`, `int diaDaSemana(String iso)` (0 = segunda, como `weekday()`), `String isoDeDateTime(DateTime d)`
  - `String proximoMes(String mes)` (nucleo.py:102-107), `(String, String) limitesMes(String mes)` (110-112), `String fmtData(String iso)` (89-90), `String fmtMes(String mes)` (93-95), `String parseData(String s)` (85-86: `dd/mm/aaaa` com dia e mês de 1 ou 2 dígitos, como `strptime`; `FormatException`)
  - `int serial(String iso)` (748-752), `String deSerial(Object? v)` (755-762: número não-bool → dias inteiros truncados; texto → `parseData`, senão ISO `AAAA-MM-DD` ou `AAAAMMDD`), `String mesIso(Object? rotulo)` (765-767)
  - `class DataHora implements Comparable<DataHora>`: `DataHora(DateTime utc, int desvio)`, `factory DataHora.deTimestamp(num ts, int desvio)`, `static DataHora parse(String texto)` (subconjunto de `datetime.fromisoformat`: `AAAA-MM-DD`, separador `T` ou espaço, `HH[:MM[:SS[.f{1,6}]]]`, `Z` ou `±HH[:MM[:SS]]`; sem fuso → Brasília, como metas.py:37-39), `static DataHora? tentarParse(String texto)`, `String get data`, `String get horaMinuto`, `String iso()` (= `isoformat(timespec="seconds")`, trunca frações), `DataHora noFuso(int desvio)`, `double get timestamp`, operadores `<`, `<=`, `>`, `>=`, `==`/`hashCode` pelo instante.

- [ ] **Step 1: Área `datas` do gerador**

Casos: `de_serial` de `[45000, 45000.7, 0, "05/10/2026", "5/1/2026", "2026-10-05", "20261005", "31/02/2026", "x"]`; `mes_iso` de `["10/2026", " 1/2026 ", "2026-10", 45000]`; `serial`; `proximo_mes` e `limites_mes` (inclui fevereiro de 2024 e 2100); `fmt_data`, `fmt_mes`; `weekday` de 1000 dias seguidos a partir de 2025-01-01; `fromisoformat` de `["2026-10-20T11:00:00-03:00", "2026-10-20 11:00", "2026-10-20", "2026-10-20T14:00:00Z", "2026-10-20T11:00:00.123456+00:00", "20/10/2026"]` → `{ts, desvio, data, hora, iso}` ou erro.

Run: `py -3.12 ferramentas/gerar_referencias.py datas`
Expected: `datas.json` criado.

- [ ] **Step 2: Teste que falha** (loop de referências + `test('DataHora.iso volta para -03:00 como metas.iso', ...)` com `DataHora.parse('2026-10-20T14:00:00Z').noFuso(fusoBrasilia).iso() == '2026-10-20T11:00:00-03:00'`)

- [ ] **Step 3: Rodar e ver falhar** — Run: `flutter test test/nucleo/datas_test.dart` — Expected: FAIL.

- [ ] **Step 4: Implementar `datas.dart`** com `DateTime.utc` em toda a aritmética de datas (nunca `DateTime` local).

- [ ] **Step 5: Rodar e ver passar** — Run: o mesmo comando do passo de falha — Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add ferramentas app/lib/nucleo/datas.dart app/test
git commit -m "Plano 1, tarefa 4: datas ISO, serial do Sheets e DataHora com fuso"
```

---

### Task 5: Formatação e leitura de valores digitados

**Files:**
- Create: `app/lib/nucleo/formatacao.dart`, `ferramentas/referencias/formatacao.py`
- Create (gerado): `app/test/referencias/formatacao.json`
- Test: `app/test/nucleo/formatacao_test.dart`

**Interfaces:**
- Consumes: `fixoPython`, `floatPython`, `intPython`.
- Produces: `String brl(double v)` (nucleo.py:45-47), `double parseNum(String s)` (50-57), `double parseValor(String? s)` (60-68), `String fmtNum(double v)` (71-75), `int parseQtd(String s)` (78-82), `String precoTexto(double v)` (98-99), `String fmtResultado((double, double)? res)` (527-533), `String fmtPct(double? v, {bool sinal = true})` (mercado.py:551-554), `String fmtVolume(num? v)` (mercado.py:557-563), `String fmtDec(double v, [int casas = 1])` (sugestoes.py:44-45).

- [ ] **Step 1: Área `formatacao`**

Casos de cada função; `brl` com 500 valores aleatórios e os fixos `-0.004, -0.005, 0.125, 1.125, 1234567.891, -1234.5`, agrupados como `empate_centavo` (Review Focus 5); `parse_num`/`parse_valor` com `"10.000,50", "-250", "R$ 0", "1.234", "10.000", "12,5", " R$ 1.234,56 ", "inf", "nan", "abc", "0", ""`; `fmt_num(32.5)`, `fmt_num(1e-9)`, `fmt_num(123.456789012)`; `fmt_resultado(None)`, `((10.0, 2.5))`, `((-0.003, -0.01))`; `fmt_pct(None)`, `0.004`, `-0.004`, `12.345` com e sem sinal; `fmt_volume(None, 0, 999, 1000, 1.5e6, 2.3e9, 999999.9)`.

Run: `py -3.12 ferramentas/gerar_referencias.py formatacao` — Expected: arquivo criado.

- [ ] **Step 2: Escrever o teste que falha** (loop de referências; `ValueError` ↔ `throwsFormatException`)

- [ ] **Step 3: Rodar e ver falhar** — Run: `flutter test test/nucleo/formatacao_test.dart` — Expected: FAIL.

- [ ] **Step 4: Implementar `formatacao.dart`** (o `float(s)` do Python vira `floatPython`; regex `\d{1,3}(\.\d{3})+` de nucleo.py:65 com `RegExp(...).hasMatch` ancorado).

- [ ] **Step 5: Rodar e ver passar** — Run: o mesmo comando do passo de falha — Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add ferramentas app/lib/nucleo/formatacao.dart app/test
git commit -m "Plano 1, tarefa 5: formatação de moeda, percentuais e leitura de valores"
```

---

### Task 6: Modelos, constantes, erros e ambiente

**Files:**
- Create: `app/lib/nucleo/constantes.dart`, `app/lib/nucleo/erros.dart`, `app/lib/nucleo/ambiente.dart`, `app/lib/nucleo/modelos/com_mod.dart`, `modelos/lote.dart`, `modelos/mes.dart`, `modelos/config.dart`, `modelos/meta.dart`, `modelos/barras.dart`, `ferramentas/referencias/modelos.py`
- Create (gerado): `app/test/referencias/modelos.json`
- Test: `app/test/nucleo/modelos_test.dart`

**Interfaces:**
- Consumes: `arredondar`, `DataHora`, `fusoBrasilia`.
- Produces:
  - `constantes.dart` (nucleo.py:16-24, 459, 539): `taxaB3Swing = 0.0003`, `taxaB3Daytrade = 0.00023`, `double corretagemPorOrdem = 0.0` (variável, os testes mudam), `aliqSwing = 0.15`, `aliqDaytrade = 0.20`, `irrfSwing = 0.00005`, `irrfDaytrade = 0.01`, `limiteIsencao = 20000.0`, `darfMinimo = 10.0`, `diasLiquidacao = 2`, `sufixosBdr = ['31', '32', '33', '34', '35', '39']`.
  - `erros.dart`: `ErroValidacao(String mensagem)`, `SemDados(String mensagem)`, `LimiteConsultas(String mensagem)`, `ErroConexao(String mensagem)`, `SemSugestao(String mensagem)`; `toString()` devolve a mensagem.
  - `ambiente.dart`: `class Ambiente { final double Function() agora; final String Function() novoId; final String Function() hoje; final DataHora Function() agoraBr; }`, `Ambiente.sistema()` (agora = `arredondar(epoch, 3)`, como nucleo.py:39-40; `novoId` = 32 hex de `Random.secure()`, como `uuid4().hex`; `hoje` = data local; `agoraBr` = agora em −03:00), `Ambiente.fixo({double agora = 1761000000.123, String hoje = '2026-10-28', String? agoraBr})` (ids `id0001`...), `Ambiente ambiente = Ambiente.sistema();` (global).
  - `abstract interface class ComMod { double get mod; }`
  - Modelos mutáveis com `fromJson` tolerante (int onde há double, chave ausente → padrão) e `toJson` com as chaves do Python, omitindo campos opcionais nulos:
    - `Venda {String id; String data; int qtd; double preco; double mod = 0}`
    - `Lote {String id; String? origem; String ticker; String tipo; String dataCompra; int qtd; double preco; List<Venda> vendas; double mod = 0}`
    - `ResumoApuracao {double vendasAcoesSt; bool isento; double bruto, custos, impSt, impDt, impostoTotal, irrf, lucroLiquido, darfMes, darfAnterior, darf}`
    - `Mes {String mes; bool fechado = false; double darfAnterior = 0; List<Lote> lotes; Map<String, double> excluidos; double mod = 0; ResumoApuracao? resumo; bool retroativo = false}` (`retroativo` só vai para o JSON quando true), `Mes mesVazio(String mes)` (nucleo.py:121-122)
    - `Amigo {String email; String desde; double mod = 0}`, `ItemRadar {String ticker; String nome = ''; String desde; int? pos; double mod = 0}`, `Caixa {double saldo = 0; String data = ''; double mod = 0}`
    - `Config {String tema = 'Dark'; List<Amigo> amigos; List<ItemRadar> radar; Map<String, String> planilhas; bool pendente = false; Map<String, double> excluidos; Caixa caixa; List<Meta> metas; Map<String, Object?> extras}` (padrões de nucleo.py:179-180; `extras` guarda e regrava toda chave desconhecida)
    - `Nivel {String desde; double stop; String calcEm}` (chaves `desde`, `stop`, `calc_em`, nessa ordem)
    - `Meta {String id; String ticker; String tipo = ''; String loteId; int qtd; double? precoAlvo; double? lucroDesejado; String criadaEm; String status = 'ativa'; String? ultimoErro; Map<String, Object?>? execucao; double mod = 0; String? gatilho; double? stopInicial; double? stopAtual; bool? movel; List<Nivel>? niveis; String? oco; String? canceladaPor; String? canceladaDetalhe; Map<String, Object?>? sugestao; Map<String, Object?> extras}`, `Meta copiar()`. Campo nulo = chave ausente no dict do Python; `movel: false` e `niveis: []` são presentes.
    - `Barra {int ts; DataHora dt; double alta; double? baixa; double? abre}`, `BarraDiaria {String data; double? abre; double alta, baixa, fech}`, `HistoricoIntradiario {List<Barra> barras; String fonte; String intervalo; Diarias? diarias}`, `Diarias {List<BarraDiaria> barras; String? hoje; double? preco; String? fonte}`
  - `bool mesmosCampos(Map<String, Object?> a, Map<String, Object?> b, {Set<String> ignorar = const {}})` (= `_campos` de nucleo.py:134-135: compara sem `mod`, `vendas` e `ignorar`, com `DeepCollectionEquality`)

- [ ] **Step 1: Área `modelos`**

Em `pasta_dados()`, executar com o Python: `salvar` de meses (com venda, com compra levada `origem`, fechado com `resumo`, retroativo), `gravar_config` com amigos, radar com e sem `pos`, caixa, metas (alvo, stop móvel com níveis, OCO, executada com execução, cancelada, sugestão) e as chaves `planilhas`, `pendente`, `noticias_notificar`, `radar_ordem_lista`; e arquivos escritos à mão como a 1.12 deixaria (mês sem `excluidos`, `qtd` 100.0, `preco` 12). Saída: o conteúdo bruto de cada arquivo.

Run: `py -3.12 ferramentas/gerar_referencias.py modelos` — Expected: arquivo criado.

- [ ] **Step 2: Teste que falha**

```dart
test('le arquivos gravados pelo Python 1.12 e preserva chaves desconhecidas', () {
  // para cada arquivo: X.fromJson(json).toJson() conferido contra o json (com excluidos {} acrescentado como carregar faz)
  // Config: extras contém noticias_notificar e radar_ordem_lista e eles voltam no toJson
});
test('Meta.toJson omite campos ausentes e mantém movel false e niveis vazio', ...);
test('Ambiente.fixo devolve ids sequenciais e relógio fixo', ...);
```

- [ ] **Step 3: Rodar e ver falhar** — Run: `flutter test test/nucleo/modelos_test.dart` — Expected: FAIL.

- [ ] **Step 4: Implementar constantes, erros, ambiente e modelos.**

- [ ] **Step 5: Rodar e ver passar** — Run: o mesmo comando do passo de falha — Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add ferramentas app/lib/nucleo app/test
git commit -m "Plano 1, tarefa 6: modelos com as chaves do Python, constantes, erros e ambiente"
```

---

### Task 7: Apuração do mês

**Files:**
- Create: `app/lib/nucleo/apuracao.dart`, `ferramentas/referencias/apuracao.py`
- Create (gerado): `app/test/referencias/apuracao.json`
- Test: `app/test/nucleo/apuracao_test.dart`

**Interfaces:**
- Consumes: modelos, constantes, `somaPython`, `maxPython`, `fmtData`, `fmtMes`, `proximoMes`, `brl`.
- Produces (nucleo.py:259-304, 307-375, 444-452, 459-485, 520-524):
  - `int vendido(Lote l)`, `int restante(Lote l)`, `Lote semVenda(Lote l, String vendaId)`, `String? erroEdicaoLote(Lote lote, Lote novo)`, `String statusLote(Lote l)`
  - `class ResultadoVenda {bool dt; double compra, venda, taxas, corretagem, bruto, liquido;}` (chaves `dt, compra, venda, taxas, corretagem, bruto, liquido`)
  - `ResultadoVenda calcularVendaQtd(Lote lote, num qtd, double preco, String data)`; `ResultadoVenda calcularVenda(Lote lote, Venda v)`
  - `class Operacao extends ResultadoVenda {String ticker, tipo, data; int qtd; double preco; String loteId, vendaId; String regime; double imposto;}`
  - `class Apuracao {List<Operacao> ops; double vendasAcoesSt; bool isento; double bruto, custos, impSt, impDt, impostoTotal, irrf, lucroLiquido, darfMes, darfAnterior, darf; ResumoApuracao get resumo;}`
  - `Apuracao apurar(Mes d)`, `String infoDarf(Apuracao r, String mes)`, `String mensagemFechamento(Apuracao r, String prox)`
  - `String tipoPorTicker(String? ticker)`, `bool corrigirTiposMes(Mes d)`, `(double, double)? resultadoAberto(Lote lote, double? precoAtual)`

- [ ] **Step 1: Área `apuracao`**

Com `random.Random(2)`, ~60 meses sintéticos (floats em todos os preços): day trade (venda na data da compra), swing de ações e BDRs, isenção na fronteira (vendas de ações swing de exatamente 20000.0 e 20000.01), meses de prejuízo, IRRF swing acima de R$ 1 num dia, IRRF day trade acima de R$ 1, várias vendas no mesmo dia, `darf_anterior`. Para cada mês: `apurar` (com `ops`), `info_darf`, `mensagem_fechamento(r, proximo_mes)`. Também `calcular_venda`, `erro_edicao_lote`, `status_lote`, `tipo_por_ticker` de `["AAPL34", "T1TW34", "PETR4", "TAEE11", "PETR4F", "AAPL34F", "abcd34", "", None]`, `resultado_aberto`.

Run: `py -3.12 ferramentas/gerar_referencias.py apuracao` — Expected: arquivo criado.

- [ ] **Step 2: Escrever o teste que falha** (loop de referências com `apurar(Mes.fromJson(e['mes'])).toJson()` etc.; mais `test('prejuízo de um mês não abate o mês seguinte', ...)` documentando nucleo.py:307-367)

- [ ] **Step 3: Rodar e ver falhar** — Run: `flutter test test/nucleo/apuracao_test.dart` — Expected: FAIL.

- [ ] **Step 4: Implementar `apuracao.dart`** (somas por `somaPython` na ordem do Python; `irrf_st_dia`/`res_dt_dia` como mapas com `+=` na ordem de inserção; `max(o["liquido"], 0)` por `maxPython`; corretagem lê `corretagemPorOrdem`).

- [ ] **Step 5: Rodar e ver passar** — Run: o mesmo comando do passo de falha — Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add ferramentas app/lib/nucleo app/test
git commit -m "Plano 1, tarefa 7: apuração do mês (day trade, swing, isenção, IRRF)"
```

---

### Task 8: Repositório local com carimbo de alterações

**Files:**
- Create: `app/lib/nucleo/armazenamento.dart`, `app/lib/nucleo/armazenamento_arquivos.dart`, `app/lib/nucleo/repositorio.dart`, `ferramentas/referencias/repositorio.py`
- Create (gerado): `app/test/referencias/repositorio.json`
- Test: `app/test/nucleo/repositorio_test.dart`

**Interfaces:**
- Consumes: modelos, `mesmosCampos`, `ambiente`.
- Produces:
  - `abstract class Armazenamento { String? ler(String nome); void gravar(String nome, String conteudo); bool existe(String nome); List<String> listar(); void apagar(String nome); }`
  - `class ArmazenamentoMemoria implements Armazenamento` (mapa nome → texto)
  - `class ArmazenamentoArquivos implements Armazenamento { ArmazenamentoArquivos(String pasta); }` (UTF-8, grava em `.tmp` e renomeia)
  - `class Repositorio { Repositorio(Armazenamento armazenamento); final Armazenamento armazenamento; Mes carregar(String mes); void salvar(Mes d, {bool carimbar = true}); bool existeMes(String mes); List<String> listarMeses(); String mesInicial(); Map<String, Mes> carregarMeses(); Config lerConfig(); void gravarConfig(Config cfg, {bool carimbar = true}); }`
  - Regras: `carregar` (nucleo.py:125-131), `salvar` (138-167), `listarMeses` = nomes `^.{4}-.{2}\.json$` ordenados, como o glob `????-??.json` (170-171), `mesInicial` (174-176, com `ambiente.hoje()`), `lerConfig` (183-190, JSON inválido → padrão), `gravarConfig` (193-226, `SEM_CARIMBO = {'metas': {'niveis', 'stop_atual'}}`, chave da lista `email`/`id`/`ticker`). `carregarMeses` = `{m: carregar(m)}` em ordem (metas.py:116-117).

- [ ] **Step 1: Área `repositorio`**

Roteiros executados no Python em `pasta_dados()`, cada um com arquivos iniciais, uma sequência de operações e o conteúdo final de todos os arquivos: salvar mês novo; editar preço de um lote (só ele recebe mod novo); excluir uma venda (vai para `excluidos`); `carimbar=False`; `gravar_config` incluindo e removendo radar, amigos e metas (exclusões `radar:X`, `metas:id`); mudança só de `stop_atual`/`niveis` não carimba; `listar_meses` com `config.json`, `2026-1.json`, `abcd-ef.json`; `mes_inicial` com todos os meses fechados.

Run: `py -3.12 ferramentas/gerar_referencias.py repositorio` — Expected: arquivo criado.

- [ ] **Step 2: Escrever o teste que falha** (roteiros em `ArmazenamentoMemoria` com `Ambiente.fixo()`, conferindo cada arquivo final como JSON; mais `test('ArmazenamentoArquivos grava em UTF-8 e substitui o arquivo inteiro', ...)` numa pasta temporária)

- [ ] **Step 3: Rodar e ver falhar** — Run: `flutter test test/nucleo/repositorio_test.dart` — Expected: FAIL.

- [ ] **Step 4: Implementar os três arquivos.**

- [ ] **Step 5: Rodar e ver passar** — Run: o mesmo comando do passo de falha — Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add ferramentas app/lib/nucleo app/test
git commit -m "Plano 1, tarefa 8: repositório local com o mesmo layout e carimbo do Python"
```

---

### Task 9: Fechamento de mês, venda retroativa e tickers frequentes

**Files:**
- Create: `app/lib/nucleo/fechamento.dart`, `ferramentas/referencias/fechamento.py`
- Create (gerado): `app/test/referencias/fechamento.json`
- Test: `app/test/nucleo/fechamento_test.dart`, `app/test/nucleo/portados/venda_retroativa_test.dart`

**Interfaces:**
- Consumes: `Repositorio`, `apurar`, `restante`, `corrigirTiposMes`, `ambiente`.
- Produces (nucleo.py:378-441, 488-517, 742-743):
  - `(Apuracao, String) fecharMes(Repositorio repo, Mes d)` (id da cópia `'<id>~<prox>'`)
  - `bool mesAceitaVendaRetroativa(Repositorio repo, String mes, String mesAtual)`
  - `String registrarVendaRetroativa(Repositorio repo, Mes d, String loteId, ({String data, int qtd, double preco}) venda)` (chama `ambiente.novoId()` primeiro para o lote, depois para a venda; `ErroValidacao` com o texto de nucleo.py:420)
  - `bool corrigirTipos(Repositorio repo)`
  - `(Map<String, int>, Map<String, String>) historicoTickers(Repositorio repo, {int mesesRecentes = 6})`
  - `(List<String>, Map<String, String>) sugestoesTickers(Repositorio repo, Mes d, {bool soCustodia = false})` (= `sugestoes`, renomeada para não colidir com o módulo de sugestões)
  - `Set<String> custodiaAtual(Repositorio repo)`

- [ ] **Step 1: Área `fechamento`**

Roteiro de janeiro a junho de 2026 com fechamentos em sequência (compras levadas, DARF abaixo de R$ 10 indo para `darf_anterior`, DARF ≥ 10), vendas retroativas para mês sem arquivo, para mês retroativo e para mês fechado sem compras abertas; arquivos após cada passo, retorno de cada função; `historico_tickers` e `sugestoes` com empates de frequência.

Run: `py -3.12 ferramentas/gerar_referencias.py fechamento` — Expected: arquivo criado.

- [ ] **Step 2: Testes que falham**

Referências + os 9 testes de tests/test_venda_retroativa.py (`TestVendaRetroativa.test_meses_livres_e_bloqueados`, `test_mes_retroativo_vale_sem_a_marcacao`, `test_grava_no_mes_da_venda_e_reduz_compra_atual`, `test_venda_total_remove_compra_do_mes_atual`, `test_segunda_venda_no_mesmo_mes`, `test_recusa_compra_com_venda_no_mes_atual`, `test_darf_pequena_vai_para_o_mes_aberto`, `test_lote_levado_nao_gera_novo_debito`, `test_caixa_nao_duplica_compra`), com `ArmazenamentoMemoria` e `Ambiente.fixo()`. Os dois últimos usam `lancamentosCaixa` (Tarefa 10): escrevê-los agora marcados com `skip: 'Tarefa 10'` e tirar o `skip` na Tarefa 10.


- [ ] **Step 3: Rodar e ver falhar** — Run: `flutter test test/nucleo/fechamento_test.dart test/nucleo/portados/venda_retroativa_test.dart` — Expected: FAIL.

- [ ] **Step 4: Implementar `fechamento.dart`.**

- [ ] **Step 5: Rodar e ver passar** — Run: o mesmo comando do passo de falha — Expected: PASS (2 ignorados).

- [ ] **Step 6: Commit**

```bash
git add ferramentas app/lib/nucleo app/test
git commit -m "Plano 1, tarefa 9: fechamento de mês e venda retroativa"
```

---

### Task 10: Caixa, liquidação D+2 e feriados da B3

**Files:**
- Create: `app/lib/nucleo/caixa.dart`, `ferramentas/referencias/caixa.py`
- Create (gerado): `app/test/referencias/caixa.json`
- Test: `app/test/nucleo/caixa_test.dart`; Modify: `app/test/nucleo/portados/venda_retroativa_test.dart` (tirar os `skip`)

**Interfaces:**
- Consumes: modelos, `calcularVenda`, `somaPython`, `arredondar`, datas, `ambiente`.
- Produces (nucleo.py:538-739):
  - `const diasSemana = ['Segunda-feira', 'Terça-feira', 'Quarta-feira', 'Quinta-feira', 'Sexta-feira', 'Sábado', 'Domingo'];`
  - `String pascoa(int ano)`, `Set<String> feriadosB3(int ano)` (com cache; fixos 01/01, 21/04, 01/05, 07/09, 12/10, 02/11, 15/11, 24/12, 25/12, 31/12; 20/11 a partir de 2024; Páscoa −48, −47, −2, +60), `bool diaUtil(String iso)`, `String calcularDataLiquidacao(String dataOperacao, {int diasUteis = diasLiquidacao})`, `String fmtLiquidacao(String iso)`, `int diasUteisEntre(String inicio, String fim)`, `String rotuloVencimento(String d, {String? hoje})`
  - `class ResumoOrdem {double bruto, taxas, irrf, liquido; bool dayTrade; String liquidacao;}`, `ResumoOrdem resumoOrdem(String lado, num qtd, double preco, String dataOperacao, {double? precoCompra, bool dayTrade = false})`
  - `class LancamentoCaixa {String id, data, ticker, tipo; int qtd; double valor; String liquidacao; String? status;}`
  - `List<LancamentoCaixa> lancamentosCaixa(Map<String, Mes> meses)` (itera os meses em ordem de chave, como nucleo.py:646; quem chama passa `repo.carregarMeses()` ou os meses do amigo)
  - `class ResumoCaixa {bool definido; String? base; double saldoBase, entrou, disponivel, aDebitar, aReceber, transito, projetado; List<LancamentoCaixa> itens;}`, `ResumoCaixa resumoCaixa(Config cfg, Map<String, Mes> meses, {String? hoje})`
  - `typedef GrupoAgenda = ({String data, String rotulo, double total, List<LancamentoCaixa> itens});` `List<GrupoAgenda> agendaCaixa(ResumoCaixa r, {String? hoje, int diasHistorico = 15})`
  - `typedef DiaProjecao = ({String data, String rotulo, double total, List<LancamentoCaixa> itens, double saldoApos});` `List<DiaProjecao> projecaoCaixa(ResumoCaixa r, {String? hoje})`
  - `void definirSaldo(Config cfg, double valor, {String? hoje})`, `void ajustarSaldo(Config cfg, Map<String, Mes> meses, double delta, {String? hoje})`

- [ ] **Step 1: Área `caixa`**

`feriados_b3` de 1990 a 2070; `calcular_data_liquidacao` e `dia_util` de todos os dias de 2023-01-01 a 2027-12-31; `dias_uteis_entre` e `rotulo_vencimento` com hoje fixo e datas de hoje−3 a hoje+10; `resumo_ordem` em grade (compra, venda swing, day trade, IRRF acima e abaixo de R$ 1); `lancamentos_caixa`, `resumo_caixa`, `agenda_caixa`, `projecao_caixa` sobre os meses do roteiro da Tarefa 9 com vários `hoje` e saldos (definido/indefinido, base antes e depois das liquidações); caso `empate_lancamentos` (compra e venda do mesmo ticker liquidando no mesmo dia, Review Focus 2); `definir_saldo` e `ajustar_saldo` (resultado `cfg["caixa"]`).

Run: `py -3.12 ferramentas/gerar_referencias.py caixa` — Expected: arquivo criado.

- [ ] **Step 2: Escrever o teste que falha** (loop de referências)

- [ ] **Step 3: Rodar e ver falhar** — Run: `flutter test test/nucleo/caixa_test.dart` — Expected: FAIL.

- [ ] **Step 4: Implementar `caixa.dart`** (`itens.sort(key=(liquidacao, data, ticker))` por `ordenadoPor`).

- [ ] **Step 5: Rodar e ver passar, inclusive os 2 portados liberados** — Run: `flutter test test/nucleo/caixa_test.dart test/nucleo/portados/venda_retroativa_test.dart` — Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add ferramentas app/lib/nucleo app/test
git commit -m "Plano 1, tarefa 10: caixa, D+2 e feriados da B3"
```

---

### Task 11: Radar e indicadores de mercado

**Files:**
- Create: `app/lib/nucleo/radar.dart`, `app/lib/nucleo/mercado/indicadores.dart`, `app/lib/nucleo/mercado/dados_ativo.dart`, `ferramentas/referencias/mercado.py`, `app/test/nucleo/apoio/barras.dart`
- Create (gerado): `app/test/referencias/mercado.json`
- Test: `app/test/nucleo/mercado_test.dart`, `app/test/nucleo/portados/indicadores_test.dart`

**Interfaces:**
- Consumes: `somaPython`, `maxDe`, `ordenadoPor`, modelos, `ambiente`.
- Produces:
  - `indicadores.dart` (mercado.py:6-15, 22-102): `double? calcularAtr(List<double> maximas, List<double> minimas, List<double> fechamentos, [int n = 14])`, `({double pp, double r1, double s1}) calcularPivos(double alta, double baixa, double fech)`, `double? calcularChandelier(List<BarraDiaria> barras, {int n = 22, int mult = 3})`, `List<double?> serieChandelier(List<BarraDiaria> barras, {int n = 22, int mult = 3})`, `({String rotulo, String fundo, String texto}) classificarRisco(double atrPct)` (faixas verbatim de mercado.py:10-15), `bool valido(Object? v)`, `(double?, double?) variacao(double? preco, double? anterior)`, `double? anteriorDe(List<(String, double)> pares, String diaAtual)`, `const periodosGrafico` (mercado.py:86-89).
  - `dados_ativo.dart`: `class DadosAtivo {String ticker, nome; double? preco, media6m, atr, atrPct; ({String rotulo, String fundo, String texto})? risco; double hora; double? anterior, variacao, variacaoPct, min6m, max6m, variacao6mPct, vsMediaPct, maxDia, minDia, max52, min52, volume;}` (chaves JSON do Python: `var`, `var_pct`, `var6m_pct`, `vs_media_pct`, `max_dia`...; `risco` como lista de 3 textos)
  - `radar.dart` (nucleo.py:231-254; mercado.py:514-548): `List<ItemRadar> ordenarRadar(List<ItemRadar> radar)`, `ItemRadar? adicionarRadar(Config cfg, String ticker, {String nome = ''})`, `void reordenarRadar(Config cfg, List<String> tickers)`, `const filtrosRadar`, `const ordensRadar`, `List<ItemRadar> filtrarOrdenar(List<ItemRadar> itens, Map<String, DadosAtivo> dados, {String filtro = 'Todos', String ordem = 'manual', Set<String> custodia = const {}})`, `(int, int, double?) resumoDia(List<String> tickers, Map<String, DadosAtivo> dados)`.

- [ ] **Step 1: Área `mercado`**

Séries de barras com `random.Random(3)` (0 a 120 barras): `calcular_atr` (n 14 e 22), `calcular_chandelier`, `serie_chandelier`; `calcular_pivos`; `classificar_risco` numa grade com 2.2, 3.0, 4.5 exatos; `variacao` com entradas inválidas (None, 0, NaN não, negativo); `anterior_de`; `ordenar_radar` com e sem `pos` e com `pos` repetida; `adicionar_radar`, `reordenar_radar`; `filtrar_ordenar` para todos os filtros × ordens, com ativos sem cotação e caso `empate_variacao` (Review Focus 2); `resumo_dia`.

Run: `py -3.12 ferramentas/gerar_referencias.py mercado` — Expected: arquivo criado.

- [ ] **Step 2: Testes que falham**

Referências + portados `TestIndicadores.test_atr_de_barras_planas`, `TestIndicadores.test_pivos`, `TestIndicadores.test_chandelier` (tests/test_sugestoes.py:27-42; helper `barrasPlanas` em `test/nucleo/apoio/barras.dart`).

- [ ] **Step 3: Rodar e ver falhar** — Run: `flutter test test/nucleo/mercado_test.dart test/nucleo/portados/indicadores_test.dart` — Expected: FAIL.

- [ ] **Step 4: Implementar os três arquivos.**

- [ ] **Step 5: Rodar e ver passar** — Run: o mesmo comando do passo de falha — Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add ferramentas app/lib/nucleo app/test
git commit -m "Plano 1, tarefa 11: radar, ATR, Chandelier, pivôs e filtros do radar"
```

---

### Task 12: Dados do Yahoo sem rede (interpretação do chart)

**Files:**
- Create: `app/lib/nucleo/mercado/chart.dart`, `ferramentas/referencias/yahoo.py`
- Create (gerado): `app/test/referencias/yahoo.json`
- Test: `app/test/nucleo/yahoo_test.dart`, `app/test/nucleo/portados/historico_yahoo_test.dart`

**Interfaces:**
- Consumes: `DataHora`, `valido`, `calcularAtr`, `classificarRisco`, `variacao`, `anteriorDe`, `somaPython`, `DadosAtivo`, `HistoricoIntradiario`, `Diarias`, `SemDados`, `ambiente`.
- Produces (mercado.py:119-231, 336-375):
  - `typedef ObterChart = Future<Map<String, Object?>> Function(String ticker, Map<String, String> params);` (devolve `chart.result[0]`; a implementação HTTP do plano 2 lança `SemDados` no 404/vazio e `LimiteConsultas('Too Many Requests')` no 429)
  - `List<String> intervalosHistorico(double dias)`
  - `Future<HistoricoIntradiario> historicoDesde(String ticker, DataHora desde, {DataHora? agora, required ObterChart obterChart})` (params `period1`, `period2`, `interval`, `includePrePost: 'false'`, com os mesmos valores de mercado.py:144-147)
  - `String rangeDiarias(String? desde, {String? hoje})`
  - `class CacheDiarias { static const validadeSegundos = 900; Future<Diarias> barrasDiarias(String ticker, {String? desde, required ObterChart obterChart}); void limpar(); }` (relógio = `ambiente.agora()`)
  - `DadosAtivo dadosAtivoDeChart(String ticker, Map<String, Object?> resultado, {String nomeConhecido = '', double? hora})` (`SemDados('Histórico insuficiente para <ticker>.')` com menos de 15 linhas válidas)

- [ ] **Step 1: Área `yahoo`**

JSONs de chart sintéticos (com `gmtoffset`, `regularMarketTime`, valores `None`, listas mais curtas que `timestamp`) passados por um `_get_chart` falso: saída de `historico_desde` (com os params pedidos em cada tentativa), `barras_diarias`, `_range_diarias` (hoje fixo) e `Mercado()._dados_api` (com `time.time` congelado), inclusive erro de histórico insuficiente.

Run: `py -3.12 ferramentas/gerar_referencias.py yahoo` — Expected: arquivo criado.

- [ ] **Step 2: Testes que falham**

Referências + 8 portados com `ObterChart` falso: `TestHistoricoMercado.test_intervalos`, `TestHistoricoMercado.test_historico_desde_usa_chart_e_fuso`, `TestHistoricoMercado.test_sem_barras_levanta`, `TestHistoricoComBaixaEAbertura.test_barras_trazem_baixa_e_abre`, `TestHistoricoComBaixaEAbertura.test_baixa_ausente_fica_none` (tests/test_metas.py:442-477, 1184-1205); `TestBarrasDiarias.test_barras_data_e_cache`, `TestBarrasDiarias.test_sem_barras_levanta`, `TestBarrasDiarias.test_range_pelo_alcance` (tests/test_sugestoes.py:264-306; `date.today()` vira `ambiente.hoje()` do `Ambiente.fixo`).

- [ ] **Step 3: Rodar e ver falhar** — Run: `flutter test test/nucleo/yahoo_test.dart test/nucleo/portados/historico_yahoo_test.dart` — Expected: FAIL.

- [ ] **Step 4: Implementar `chart.dart`.**

- [ ] **Step 5: Rodar e ver passar** — Run: o mesmo comando do passo de falha — Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add ferramentas app/lib/nucleo app/test
git commit -m "Plano 1, tarefa 12: interpretação do chart do Yahoo com busca injetada"
```

---

### Task 13: Planilha: esquema, célula e montagem das linhas

**Files:**
- Create: `app/lib/nucleo/planilha/abas.dart`, `planilha/celula.dart`, `planilha/montagem.dart`, `ferramentas/referencias/planilha_montagem.py`
- Create (gerado): `app/test/referencias/planilha_montagem.json`
- Test: `app/test/nucleo/planilha_montagem_test.dart`, `app/test/nucleo/portados/planilha_esquema_test.dart`

**Interfaces:**
- Consumes: modelos, `apurar`, `vendido`, `restante`, `statusLote`, `serial`, `fmtMes`, `arredondar`, `jsonPython`, `ordenarRadar`, `ordenadoPor`.
- Produces:
  - `typedef Linha = List<Object?>;`
  - `abas.dart` (google_sync.py:9, 13-45): `class ColunaAba {final String titulo; final String tipo; final int largura;}`, `class EsquemaAba {final String nome; final String cor; final bool oculta; final List<ColunaAba> colunas;}`, `const List<EsquemaAba> esquemaAbas` (as 8 abas na ordem, verbatim), `EsquemaAba esquemaDe(String nome)`, `const nomePlanilha = 'Calculadora DARF'`
  - `celula.dart`: `Map<String, Object?> celula(Object? v)` (google_sync.py:76-83), `Map<String, List<Linha>> normalizarLeitura(Map<String, List<List<Object?>>> lidas)` (google_sync.py:427-441: toda aba do esquema presente; linhas completadas com `""` e cortadas na largura do esquema)
  - `montagem.dart`: `const camposDetalhes` (nucleo.py:777-778), `Linha linhaMeta(Meta m)` (781-795: Execução = `jsonPython(execucao)`, Detalhes = `jsonPython(detalhes, compacto: true)`), `Map<String, List<Linha>> montarLinhas(List<Mes> meses, Config cfg)` (797-834; recebe os meses já carregados, na ordem; inteiros continuam `int`, valores monetários por `arredondar(x, 2)`).

- [ ] **Step 1: Área `planilha_montagem`**

`montar_linhas` para os arquivos do roteiro da Tarefa 9 mais um `cfg` com amigos, radar com e sem `pos` (com empate de `pos`), caixa definido e indefinido, metas (alvo com lucro, stop móvel com níveis e sugestão, par OCO, executada com execução contendo `≥`, cancelada com detalhe), exclusões de registro e de configuração; caso `total_com_empate_binario` (lote de 1 ação a 1.125, Review Focus 5); caso `empate_vendas_mesma_data` (duas vendas na mesma data gravadas fora da ordem de id, Review Focus 2). `celula` de `[None, "", True, False, 0, 0.0, 21.78, -0.0, "texto", 1e16]`.

Run: `py -3.12 ferramentas/gerar_referencias.py planilha_montagem` — Expected: arquivo criado.

- [ ] **Step 2: Testes que falham**

Referências (aba `Exclusões` em `semOrdem`, porque a ordem vem de um `set` no Python, nucleo.py:165-166) + portados `TestMesclagem.test_aba_metas_no_google` e `TestCompatibilidadeStop.test_planilha_tem_14_colunas_na_aba_metas` (sobre `esquemaAbas`).

- [ ] **Step 3: Rodar e ver falhar** — Run: `flutter test test/nucleo/planilha_montagem_test.dart test/nucleo/portados/planilha_esquema_test.dart` — Expected: FAIL.

- [ ] **Step 4: Implementar os três arquivos.**

- [ ] **Step 5: Rodar e ver passar** — Run: o mesmo comando do passo de falha — Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add ferramentas app/lib/nucleo app/test
git commit -m "Plano 1, tarefa 13: esquema das abas e montagem das linhas da planilha"
```

---

### Task 14: Planilha: reconstrução e compatibilidade de leitura

**Files:**
- Create: `app/lib/nucleo/planilha/reconstrucao.dart`, `ferramentas/referencias/planilha_reconstrucao.py`
- Create (gerado): `app/test/referencias/planilha_reconstrucao.json`
- Test: `app/test/nucleo/planilha_reconstrucao_test.dart`

**Interfaces:**
- Consumes: `Linha`, modelos, `strPython`, `floatPython`, `intPython`, `verdadeiroPython`, `numOuPadrao`, `deSerial`, `mesIso`, `DataHora.parse`, `corrigirTiposMes`, `mesVazio`, `ambiente`.
- Produces (nucleo.py:837-972):
  - `class DadosPlanilha {Map<String, Mes> meses; List<Amigo> amigos; List<ItemRadar> radar; Map<String, double> excluidos; Caixa? caixa;}`
  - `DadosPlanilha reconstruir(Map<String, List<Linha>> abas)` (larguras de nucleo.py:839 completam sem cortar; linha inválida é pulada como no `except (ValueError, TypeError, IndexError)`; ID vazio → `ambiente.novoId()` na ordem das linhas, Compras antes de Vendas; data inválida em Amigos/Radar → `ambiente.hoje()`)
  - `List<Meta> reconstruirMetas(Map<String, List<Linha>> abas)` (linha completada e cortada em 14; Detalhes só valem com o mesmo id; `criada_em` validada por `DataHora.parse`)

- [ ] **Step 1: Área `planilha_reconstrucao`**

Entradas = saídas da Tarefa 13 (ida e volta) e casos de compatibilidade: Metas com 12 colunas (alvo), Radar com 4 colunas e com Posição `""`, colunas faltando em todas as abas, linhas malformadas (mês `"abc"`, qtd `"x"`, data inválida), ticker repetido no radar, e-mail com maiúsculas e espaços, Caixa com duas linhas, exclusão de registro com mês inválido; Metas com Detalhes de outro id, JSON inválido, níveis malformados, gatilho stop com preço válido, `criada_em` inválida, id vazio, lucro desejado 0, execução com JSON inválido, sugestão que não é objeto; grupo `editadas_a_mao` (Review Focus 1): ID `123` e `123.0`, qtd `100.0` e `100.9`, data `"5/10/2026"`, mês `" 10/2026"`, `True` em coluna numérica.

Run: `py -3.12 ferramentas/gerar_referencias.py planilha_reconstrucao` — Expected: arquivo criado.

- [ ] **Step 2: Escrever o teste que falha** (loop: `reconstruir(abas)` e `reconstruirMetas(abas)` convertidos em JSON e conferidos, com `Ambiente.fixo()` por caso)

- [ ] **Step 3: Rodar e ver falhar** — Run: `flutter test test/nucleo/planilha_reconstrucao_test.dart` — Expected: FAIL.

- [ ] **Step 4: Implementar `reconstrucao.dart`** (cada `int(...)`/`float(...)`/`str(...)` do Python pelo helper correspondente; `if row[11]:` por `verdadeiroPython`; erros capturados: `FormatException`, `RangeError`, `TypeError`).

- [ ] **Step 5: Rodar e ver passar** — Run: o mesmo comando do passo de falha — Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add ferramentas app/lib/nucleo app/test
git commit -m "Plano 1, tarefa 14: reconstrução da planilha com a compatibilidade da 1.12"
```

---

### Task 15: Mesclagem entre aparelhos

**Files:**
- Create: `app/lib/nucleo/planilha/mesclagem.dart`, `ferramentas/referencias/mesclagem.py`, `app/test/nucleo/apoio/base_metas.dart`
- Create (gerado): `app/test/referencias/mesclagem.json`
- Test: `app/test/nucleo/mesclagem_test.dart`, `app/test/nucleo/portados/mesclagem_metas_test.dart`

**Interfaces:**
- Consumes: modelos, `ComMod`, `fmtMes`, `ordenadoPor`, `ordenadoCom`, `maxDe`, `ambiente`, `Repositorio`.
- Produces (nucleo.py:977-1168):
  - `T? escolher<T extends ComMod>(T? a, T? b)` (`a` vence empate)
  - `Mes? mesclarMes(Mes? local, Mes? remoto)` (devolve a mesma instância quando um lado é nulo; senão objetos novos; saída sem `retroativo`; `resumo` só se a vencedora tem resumo e está fechada)
  - `Set<String> deduplicarAuto(Map<String, Mes> meses)`
  - `List<T> mesclarLista<T extends ComMod>(List<T> local, List<T> remoto, String Function(T) chave, Map<String, double> excl, String prefixo)`
  - `List<Nivel> unirNiveis(List<Nivel>? a, List<Nivel>? b)`, `Meta completarMeta(Meta vencedora, Meta perdedora)` (`camposStop`, `camposNovos` de nucleo.py:1058-1059; presença = campo não nulo), `int precedencia(Meta m)`
  - `List<Meta> mesclarMetas(List<Meta> local, List<Meta> remoto)` (cópia nova só onde o Python monta dict novo)
  - `int execucaoAntes(Meta a, Meta b)`, `Set<String> resolverOco(Map<String, Mes> meses, List<Meta> metas, {List<String>? avisos})` (altera no lugar; `mod` e exclusões com `ambiente.agora()`)
  - `apoio/base_metas.dart`: `class BaseMetas { late Repositorio repo; late Config cfg; final DataHora criada = DataHora.parse('2026-10-20T11:00:00-03:00'); void preparar(); Lote lote({String mes = '2026-10', String lid = 'L1'}); }` (= `Base.setUp` de tests/test_metas.py:33-50, com `ArmazenamentoMemoria` e `Ambiente.fixo()`; restaura `corretagemPorOrdem` no tearDown) e as constantes `baseAlvo`, `baseStop` (tests/test_metas.py:836-839).

- [ ] **Step 1: Área `mesclagem`**

`mesclar_mes` sobre pares gerados de um mês base (edições com mods diferentes, exclusões com exclusão ≥ e < mod, empates com local vencendo, venda trocando de lote, resumo com mês aberto e fechado, um lado `None`); `deduplicar_auto`; `mesclar_lista` de amigos e radar com exclusões; `mesclar_metas` numa matriz status × mod × gatilho, incluindo registro de 12 colunas e stop móvel nos dois lados; `_unir_niveis`; `resolver_oco` com mês aberto e fechado (avisos); `_execucao_antes` com data, `barra_ts`, hora vazia e id.

Run: `py -3.12 ferramentas/gerar_referencias.py mesclagem` — Expected: arquivo criado.

- [ ] **Step 2: Testes que falham**

Referências + 14 portados: `TestMesclagem.test_executada_vence_ativa_mesmo_mais_antiga`, `TestMesclagem.test_mais_recente_vence_nos_demais`, `TestCompatibilidadeStop.test_mesclagem_do_stop_movel_fica_com_o_maior`, `TestCompatibilidadeStop.test_mesclagem_nao_une_stop_executado`, `TestRevisaoMesclagem.test_aparelho_antigo_nao_apaga_o_oco_na_mesclagem`, `TestRevisaoMesclagem.test_campos_novos_do_perdedor_em_meta_cancelada`, `TestRevisaoMesclagem.test_stop_nao_vira_alvo_nem_alvo_vira_stop_na_uniao`, `TestRevisaoMesclagem.test_stop_de_12_colunas_vencedor_recupera_os_campos_do_outro`, `TestRevisaoMesclagem.test_cancelada_vence_ativa_mesmo_mais_antiga`, `TestOCO.test_resolver_oco_com_as_duas_executadas`, `TestRevisaoOco.test_empate_de_data_com_hora_vazia_prefere_o_stop`, `TestRevisaoOco.test_barra_ts_desempata_quando_disponivel`, `TestRevisaoOco.test_data_mais_cedo_continua_vencendo`, `TestRevisaoOco.test_meta_cancelada_pelo_oco_recebe_mod_novo`.

- [ ] **Step 3: Rodar e ver falhar** — Run: `flutter test test/nucleo/mesclagem_test.dart test/nucleo/portados/mesclagem_metas_test.dart` — Expected: FAIL.

- [ ] **Step 4: Implementar `mesclagem.dart` e `base_metas.dart`.**

- [ ] **Step 5: Rodar e ver passar** — Run: o mesmo comando do passo de falha — Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add ferramentas app/lib/nucleo app/test
git commit -m "Plano 1, tarefa 15: mesclagem de meses, listas e metas com OCO"
```

---

### Task 16: Metas: preço-alvo e projeção

**Files:**
- Create: `app/lib/nucleo/metas/preco_alvo.dart`, `ferramentas/referencias/metas_preco.py`
- Create (gerado): `app/test/referencias/metas_preco.json`
- Test: `app/test/nucleo/metas_preco_test.dart`, `app/test/nucleo/portados/metas_preco_alvo_test.dart`

**Interfaces:**
- Consumes: `calcularVendaQtd`, `ResultadoVenda`, constantes, `arredondar`, `maxPython`, `ErroValidacao`, `BaseMetas`.
- Produces (metas.py:42-111):
  - `double tetoCentavo(double v)` (= `ceil(arredondar(v * 100, 6)) / 100`), `double pisoCentavo(double v)`
  - `String gatilho(Meta m)` (`'alvo'` quando nulo), `double precoGatilho(Meta m)`
  - `class Projecao extends ResultadoVenda {double imposto, irrf, darfEstimado, custos, lucroAposImposto;}`, `Projecao projetar(Lote lote, num qtd, double preco, {bool dayTrade = false})`
  - `class PrecoAlvo extends Projecao {double preco, precoExato, precoMedio, brutoNecessario, lucroDesejado; num qtd; bool dayTrade;}`, `PrecoAlvo calcularPrecoAlvo(Lote lote, num qtd, double lucroLiquido, {bool dayTrade = false})` (mensagens de metas.py:92-106)

- [ ] **Step 1: Área `metas_preco`**

Grade qtd {1, 7, 100, 333, 100000} × lucro {-200, 0, 0.01, 1000, 12345.67, 1e6} × day trade × preço do lote {0.37, 10.0, 33.33} × corretagem {0.0, 2.5}, mais os erros; `teto_centavo`/`piso_centavo` de 500 valores e dos fixos 21.7743, 21.77, 21.770000000001, 5.999999999, 5.989, 5.981.

Run: `py -3.12 ferramentas/gerar_referencias.py metas_preco` — Expected: arquivo criado.

- [ ] **Step 2: Testes que falham**

Referências + 8 portados: os 7 de `TestPrecoAlvo` (tests/test_metas.py:59-125: `test_exemplo_de_referencia`, `test_swing`, `test_day_trade`, `test_com_corretagem`, `test_lucro_zero_e_negativo`, `test_irrf_nao_altera_preco_nem_imposto`, `test_teto_centavo`) e `TestIndicadores.test_piso_e_teto_de_centavo` (tests/test_sugestoes.py:44-47).

- [ ] **Step 3: Rodar e ver falhar** — Run: `flutter test test/nucleo/metas_preco_test.dart test/nucleo/portados/metas_preco_alvo_test.dart` — Expected: FAIL.

- [ ] **Step 4: Implementar `preco_alvo.dart`.**

- [ ] **Step 5: Rodar e ver passar** — Run: o mesmo comando do passo de falha — Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add ferramentas app/lib/nucleo app/test
git commit -m "Plano 1, tarefa 16: preço-alvo e projeção de venda"
```

---

### Task 17: Metas: compras abertas, criação, cancelamento e ida e volta pela planilha

**Files:**
- Create: `app/lib/nucleo/metas/cadeia.dart`, `app/lib/nucleo/metas/criacao.dart`, `ferramentas/referencias/metas_criacao.py`
- Create (gerado): `app/test/referencias/metas_criacao.json`
- Modify: `app/test/nucleo/apoio/base_metas.dart` (acrescentar `criar`)
- Test: `app/test/nucleo/portados/metas_criacao_test.dart`, `app/test/nucleo/metas_criacao_test.dart`

**Interfaces:**
- Consumes: `Repositorio`, `restante`, `brl`, `arredondar`, `ErroValidacao`, `DataHora`, `fusoBrasilia`, `gatilho`, `montarLinhas`, `reconstruirMetas`, `ambiente`.
- Produces (metas.py:116-353, 431-432, 463-472):
  - `typedef ElosCadeia = ({String mes, Mes dados, Lote lote});` `List<ElosCadeia> cadeia(Map<String, Mes> meses, String loteId)`, `(Lote, Venda)? vendaExistente(Map<String, Mes> meses, String vendaId)`, `Map<String, String> raizes(Map<String, Mes> meses)`
  - `int reservado(Repositorio repo, Config cfg, String loteId, {Map<String, Mes>? meses, Set<String> ignorar = const {}})`
  - `List<ElosCadeia> lotesAbertos(Map<String, Mes> meses)`
  - `typedef PosicaoAberta = ({String mes, Lote lote, int restante, int livre, List<Meta> ativas});` `List<PosicaoAberta> posicoesAbertas(Repositorio repo, Config cfg)`
  - `typedef LoteLivre = ({String mes, Lote lote, int livre});` `List<LoteLivre> lotesParaMeta(Repositorio repo, Config cfg)`
  - `List<Meta> metasAtivas(Config cfg)`, `Meta? parceiraOco(Repositorio repo, Config cfg, String loteId, String gatilhoNovo, {Map<String, Mes>? meses})`
  - `Meta criarMeta(Repositorio repo, Config cfg, String loteId, num qtd, num precoAlvo, {num? lucroDesejado, DataHora? agora, String? ocoCom})`
  - `Meta criarStop(Repositorio repo, Config cfg, String loteId, num qtd, num precoStop, {bool movel = false, String? ocoCom, double? precoAtual, DataHora? agora, Map<String, Object?>? sugestao})`
  - `void cancelarMeta(Repositorio repo, Config cfg, String metaId)`, `void reconciliar(Repositorio repo, Config cfg, Meta meta)` (= `_reconciliar`, usada também na Tarefa 19)
  - Ids: `'meta-${ambiente.novoId()}'`, `'oco-${ambiente.novoId()}'`; `criada_em` = `(agora ?? ambiente.agoraBr()).noFuso(fusoBrasilia).iso()`; mensagens de erro idênticas às de metas.py:220-353.
  - `BaseMetas.criar({int qtd = 100, double alvo = 21.78})` (tests/test_metas.py:52-53).

- [ ] **Step 1: Área `metas_criacao`**

Roteiro com compra original e cópias levadas por fechamentos (cadeia), metas ativas, canceladas e OCO: `_cadeia`, `_raizes`, `reservado`, `_lotes_abertos`, `posicoes_abertas`, `lotes_para_meta`, `parceira_oco`, e `criar_meta`/`criar_stop` com config resultante e erros.

Run: `py -3.12 ferramentas/gerar_referencias.py metas_criacao` — Expected: arquivo criado.

- [ ] **Step 2: Testes que falham**

Referências + 23 portados (asserções do Python; entradas de texto como `"x"` são impossíveis com os tipos Dart e saem do teste, mantendo os demais valores):
`TestCriacao.test_criacao_valida`, `TestCriacao.test_quantidade_insuficiente_bloqueada`, `TestCriacao.test_quantidade_reservada_por_outra_meta`, `TestCriacao.test_preco_e_lote_invalidos`, `TestStop.test_criacao`, `TestStop.test_meta_sem_gatilho_e_alvo`, `TestStop.test_validacoes`, `TestOCO.test_par_compartilha_o_mesmo_oco_e_a_reserva_conta_uma_vez`, `TestOCO.test_posicoes_abertas_mostra_livre_zero`, `TestOCO.test_recusas`, `TestOCO.test_parceira_oco_pelo_gatilho_oposto`, `TestCorrecoesRevisao.test_reserva_atravessa_virada_de_mes`, `TestCorrecoesRevisao.test_valores_nao_finitos`, `TestRevisaoMesclagem.test_lotes_abertos_escolhe_a_ultima_copia_antes_de_filtrar`, `TestMesclagem.test_planilha_ida_e_volta`, `TestCompatibilidadeStop.test_planilha_ida_e_volta_do_stop`, `TestCompatibilidadeStop.test_detalhes_de_outro_id_sao_ignorados`, `TestCompatibilidadeStop.test_linha_de_12_colunas_e_alvo`, `TestCompatibilidadeStop.test_parser_antigo_de_12_colunas_pula_o_stop` (em Dart: `floatPython(linha[5])` lança `FormatException`), `TestRevisaoReconstruir.test_gatilho_stop_com_detalhes_invalidos_e_preco_valido_vira_alvo`, `TestRevisaoReconstruir.test_detalhes_sem_campos_de_stop_nunca_levantam_keyerror`, `TestRevisaoReconstruir.test_detalhes_de_niveis_malformados`, `TestRevisaoReconstruir.test_stop_valido_continua_stop`.

- [ ] **Step 3: Rodar e ver falhar** — Run: `flutter test test/nucleo/metas_criacao_test.dart test/nucleo/portados/metas_criacao_test.dart` — Expected: FAIL.

- [ ] **Step 4: Implementar `cadeia.dart` e `criacao.dart`** (o laço de `_cadeia` com proteção contra ciclo, metas.py:129).

- [ ] **Step 5: Rodar e ver passar** — Run: o mesmo comando do passo de falha — Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add ferramentas app/lib/nucleo app/test
git commit -m "Plano 1, tarefa 17: criação e cancelamento de metas e ida e volta pela planilha"
```

---

### Task 18: Metas: detecção do gatilho e stop móvel

**Files:**
- Create: `app/lib/nucleo/metas/deteccao.dart`, `ferramentas/referencias/metas_deteccao.py`
- Create (gerado): `app/test/referencias/metas_deteccao.json`
- Modify: `app/test/nucleo/apoio/base_metas.dart` (acrescentar `barra`, `barraS`, `dia`)
- Test: `app/test/nucleo/metas_deteccao_test.dart`, `app/test/nucleo/portados/metas_deteccao_test.dart`

**Interfaces:**
- Consumes: `Barra`, `BarraDiaria`, `Nivel`, `Meta`, `DataHora`, `serieChandelier`, `calcularChandelier`, `pisoCentavo`, `gatilho`, `maxDe`, `ordenadoPor`, `somarDias`, `criarStop`, `Repositorio`.
- Produces (metas.py:358-417):
  - `Barra? acharBarra(List<Barra> barras, double precoAlvo, DataHora criadaEm)`
  - `double? nivelVigente(List<Nivel> niveis, String dataIso)`
  - `(Barra, double)? acharBarraStop(List<Barra> barras, List<Nivel> niveis, DataHora criadaEm)`
  - `(double, bool) precoExecucaoStop(Barra barra, double nivel)`
  - `bool atualizarStopMovel(Meta meta, List<BarraDiaria> barras, String hoje, {List<double?> Function(List<BarraDiaria>) serie = serieChandelier})` (o parâmetro `serie` existe para o teste que, no Python, troca `calcular_atr`)

- [ ] **Step 1: Área `metas_deteccao`**

Cenários de barras horárias e diárias (com `random.Random(4)`) para `achar_barra`, `nivel_vigente`, `achar_barra_stop`, `preco_execucao_stop` e `atualizar_stop_movel` (meta antes e depois). Exportar também as barras de `barras_aleatorias(120)` e `barras_aleatorias(60)` de tests/test_metas.py:1113-1123 (Random(7)), porque o Dart não reproduz o gerador do Python.

Run: `py -3.12 ferramentas/gerar_referencias.py metas_deteccao` — Expected: arquivo criado.

- [ ] **Step 2: Testes que falham**

Referências + 14 portados: `TestDeteccao.test_achar_barra`, `TestDeteccao.test_barra_anterior_ignorada`, `TestDeteccao.test_barra_na_hora_da_criacao_vale`, `TestDeteccao.test_sem_barra_atingindo`, `TestStop.test_dispara_com_minima_igual_ao_stop`, `TestStopMovel.test_subida_acrescenta_nivel_a_partir_do_dia_seguinte`, `TestStopMovel.test_idempotente_e_nunca_desce`, `TestStopMovel.test_stop_acima_do_chandelier_nao_muda`, `TestStopMovel.test_so_pregoes_fechados_e_desde_a_criacao`, `TestStopMovel.test_nivel_com_desde_posterior_nao_vale`, `TestRevisaoStopMovel.test_passada_incremental_equivale_ao_recalculo_completo` (barras do JSON; o algoritmo de referência de tests/test_metas.py:1125-1142 vai para o teste), `TestRevisaoStopMovel.test_serie_chandelier_igual_ao_calculo_por_prefixo`, `TestRevisaoStopMovel.test_nao_recalcula_o_atr_a_cada_pregao` (em Dart: `serie` contadora chamada exatamente 1 vez), `TestRevisaoMesclagem.test_subida_do_stop_movel_nao_carimba_mod`. Helpers `barra`, `barraS`, `dia` em `base_metas.dart` (tests/test_metas.py:16-22, 480-487).

- [ ] **Step 3: Rodar e ver falhar** — Run: `flutter test test/nucleo/metas_deteccao_test.dart test/nucleo/portados/metas_deteccao_test.dart` — Expected: FAIL.

- [ ] **Step 4: Implementar `deteccao.dart`** (tolerâncias `1e-9` como no Python).

- [ ] **Step 5: Rodar e ver passar** — Run: o mesmo comando do passo de falha — Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add ferramentas app/lib/nucleo app/test
git commit -m "Plano 1, tarefa 18: detecção de alvo e stop e stop móvel"
```

---

### Task 19: Metas: verificação, execução automática e descrição

**Files:**
- Create: `app/lib/nucleo/metas/verificacao.dart`, `app/lib/nucleo/metas/descricao.dart`, `ferramentas/referencias/metas_verificacao.py`
- Create (gerado): `app/test/referencias/metas_verificacao.json`
- Modify: `app/test/nucleo/apoio/base_metas.dart` (acrescentar `verificar`)
- Test: `app/test/nucleo/portados/metas_verificacao_test.dart`, `app/test/nucleo/metas_verificacao_test.dart`

**Interfaces:**
- Consumes: Tarefas 15 a 18 (`resolverOco`, `cadeia`, `vendaExistente`, `raizes`, `reconciliar`, `metasAtivas`, `acharBarra`, `acharBarraStop`, `precoExecucaoStop`, `atualizarStopMovel`, `gatilho`), `Repositorio`, `precoTexto`, `fmtData`, `fmtMes`, `brl`, `HistoricoIntradiario`, `Diarias`, erros, `ambiente`.
- Produces (metas.py:23-24, 420-460, 463-742, 747-781):
  - `typedef BuscarHistorico = Future<HistoricoIntradiario> Function(String ticker, DataHora desde);`
  - `typedef BuscarDiarias = Future<Diarias> Function(String ticker, String desde);`
  - `sealed class ResultadoHistorico`; `class HistoricoOk extends ResultadoHistorico {final HistoricoIntradiario historico;}`; `class HistoricoErro extends ResultadoHistorico {final String mensagem;}`
  - `class RelatorioMetas {List<Meta> executadas, invalidas, reconciliadas, aguardando, erros; bool mudou; List<String> avisos;}`
  - `class PreparoFechamento {String? bloqueio; List<Meta> executadas, invalidas;}`
  - `String mensagemErro(Object e)` (`SemDados` → texto dele; `LimiteConsultas` ou "Too Many" no texto → limite do Yahoo; `ErroConexao`, `TimeoutException`, nome do tipo com "Connection", "Socket" ou "Timeout", ou "resolve" no texto → "Sem conexão com a internet."; senão `'Erro ao consultar o histórico: '` + 120 primeiros caracteres)
  - `Future<Map<String, ResultadoHistorico>> buscarHistoricos(List<Meta> metas, BuscarHistorico historico, {BuscarDiarias? diarias})`
  - `RelatorioMetas aplicar(Repositorio repo, Config cfg, Map<String, ResultadoHistorico> historicos, {DataHora? agora, Map<String, Diarias>? diarias})` (síncrona; textos `motivo` com `≥`/`≤` exatos)
  - `Future<RelatorioMetas?> verificar(Repositorio repo, Config cfg, BuscarHistorico historico, {DataHora? agora, BuscarDiarias? diarias})` (null quando já há verificação em andamento ou não há metas ativas, como metas.py:704-716)
  - `bool get verificacaoEmAndamento`, `bool tentarIniciarVerificacao()`, `void encerrarVerificacao()` (permitem à tela distinguir "em andamento" de "sem metas", corrigindo no plano 3 o bug do Android do spec §9)
  - `Future<PreparoFechamento> prepararFechamento(Repositorio repo, Config cfg, String mes, BuscarHistorico historico, {DataHora? agora, BuscarDiarias? diarias})`
  - `const statusRotulo`, `const avisoRegistro`; `class DescricaoMeta {String titulo, status, detalhe, cor; bool erro;}`, `DescricaoMeta descricao(Meta meta, {List<Meta>? todas})`
  - `BaseMetas.verificar(List<Barra> barras, {DataHora? agora})` (tests/test_metas.py:55-56).

- [ ] **Step 1: Área `metas_verificacao`**

Roteiros com arquivos e `cfg` iniciais, históricos fixos (ok e erro) e `agora`: execução de alvo e de stop, gap, mês seguinte aguardando, mês fechado, quantidade insuficiente, reconciliação, OCO (mesma barra, barras diferentes, órfãs de 12 colunas, duas vendas), stop móvel subindo antes de disparar; saída = arquivos finais, `cfg` final e relatório (ids por lista, `mudou`, `avisos`); `descricao` de metas variadas.

Run: `py -3.12 ferramentas/gerar_referencias.py metas_verificacao` — Expected: arquivo criado.

- [ ] **Step 2: Testes que falham**

Referências + 37 portados: `TestCriacao.test_cancelar`; os 12 de `TestExecucao` (tests/test_metas.py:180-303; em `test_falha_generica_vira_mensagem` o histórico lança `ErroConexao('x')`; em `test_trava_concorrente` usar `tentarIniciarVerificacao`/`encerrarVerificacao`); `TestStop.test_maxima_acima_do_alvo_nao_dispara_stop`, `TestStop.test_execucao_no_stop`, `TestStop.test_gap_de_baixa_usa_a_abertura`, `TestStop.test_abertura_acima_do_stop_executa_no_stop`; `TestStopMovel.test_falha_de_dados_mantem_o_stop`, `TestStopMovel.test_verificar_sobe_o_stop_e_depois_dispara`; `TestOCO.test_alvo_executa_e_cancela_o_stop`, `TestOCO.test_stop_executa_e_cancela_o_alvo`, `TestOCO.test_mesma_barra_vence_o_stop`, `TestOCO.test_barras_diferentes_vence_a_mais_cedo`, `TestOCO.test_stop_antes_do_alvo`; `TestCorrecoesRevisao.test_fechar_mes_com_verificacao_falha_e_bloqueado`, `TestCorrecoesRevisao.test_fechar_mes_registra_meta_atingida_antes`, `TestCorrecoesRevisao.test_fechar_mes_sem_metas_nao_consulta`, `TestCorrecoesRevisao.test_fechar_mes_com_verificacao_em_andamento_bloqueia`; `TestRevisaoOco.test_alvo_executado_sem_oco_cancela_o_stop_com_oco`, `TestRevisaoOco.test_stop_executado_sem_oco_cancela_o_alvo_com_oco`, `TestRevisaoOco.test_stop_de_outro_par_nao_e_cancelado`, `TestRevisaoOco.test_quantidade_diferente_nao_cancela`, `TestRevisaoOco.test_resolver_oco_mes_fechado_nao_apaga_a_venda`, `TestRevisaoOco.test_reconciliacao_com_as_duas_vendas_remove_a_perdedora`, `TestRevisaoOco.test_reconciliacao_com_as_duas_vendas_em_mes_fechado_avisa`; `TestRevisaoStopMovel.test_hoje_do_stop_movel_nao_fica_atras_do_relogio`; `TestCompatibilidadeStop.test_descricao_do_stop`. O `setUp` de `TestRevisaoOco` (qtd 200) e o helper `registrar_venda` (tests/test_metas.py:953-976) vão para o arquivo de teste.

- [ ] **Step 3: Rodar e ver falhar** — Run: `flutter test test/nucleo/metas_verificacao_test.dart test/nucleo/portados/metas_verificacao_test.dart` — Expected: FAIL.

- [ ] **Step 4: Implementar `verificacao.dart` e `descricao.dart`** (reler `repo.carregarMeses()` nos mesmos pontos em que o Python chama `_carregar_meses()`; `gravarConfig` nos mesmos pontos).

- [ ] **Step 5: Rodar e ver passar** — Run: o mesmo comando do passo de falha — Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add ferramentas app/lib/nucleo app/test
git commit -m "Plano 1, tarefa 19: verificação e execução automática de metas"
```

---

### Task 20: Sincronização sem rede (mesclar_tudo e linhas a gravar)

**Files:**
- Create: `app/lib/nucleo/planilha/sincronizacao.dart`, `ferramentas/referencias/sincronizacao.py`
- Create (gerado): `app/test/referencias/sincronizacao.json`
- Test: `app/test/nucleo/sincronizacao_test.dart`, `app/test/nucleo/portados/sincronizacao_test.dart`

**Interfaces:**
- Consumes: `reconstruir`, `reconstruirMetas`, `DadosPlanilha`, `mesclarMes`, `mesclarMetas`, `mesclarLista`, `deduplicarAuto`, `resolverOco`, `ordenarRadar`, `montarLinhas`, `corrigirTipos`, `Repositorio`, `Linha`.
- Produces:
  - `bool mesclarTudo(Repositorio repo, DadosPlanilha remoto, Config cfg, {List<Meta>? metasR, List<String>? avisos})` (nucleo.py:1171-1211; "mudou" por igualdade profunda de `toJson()` do local como carregado contra o mesclado, no lugar do `json.dumps(sort_keys=True)` do Python)
  - `class ResultadoSincronizacao {bool mudou; List<String> avisos; Map<String, List<Linha>> linhas;}`
  - `ResultadoSincronizacao sincronizarLinhas(Repositorio repo, Config cfg, Map<String, List<Linha>> abasLidas)` (= calculadora_darf.py:2865-2876 e android/main.py:2357-2359: `reconstruir` + `reconstruirMetas` → `mesclarTudo` → `montarLinhas(todos os meses locais, cfg)`; recebe as abas já passadas por `normalizarLeitura`)

- [ ] **Step 1: Área `sincronizacao`**

Roteiros com arquivos locais, `cfg` e abas lidas: primeira sincronização com planilha vazia, edição remota mais nova, local mais novo, exclusão nos dois sentidos, meta executada contra ativa com venda automática em meses diferentes, OCO duplo, mês fechado com aviso, caixa remoto mais novo e mais velho, radar com e sem Posição, planilha antiga (Metas com 12 colunas, Radar com 4). Saída: arquivos finais, `cfg` final, `mudou`, `avisos` e linhas montadas.

Run: `py -3.12 ferramentas/gerar_referencias.py sincronizacao` — Expected: arquivo criado.

- [ ] **Step 2: Testes que falham**

Referências (Exclusões em `semOrdem`) + 5 portados: `TestMesclagem.test_mesclar_tudo_nao_duplica_venda_nem_meta`, `TestMesclagem.test_aparelho_com_meta_ativa_recebe_executada`, `TestMesclagemEntreMeses.test_venda_auto_em_meses_diferentes_fica_so_no_mais_antigo`, `TestOCO.test_mesclar_tudo_resolve_oco_duplo`, `TestRevisaoOco.test_mesclar_tudo_devolve_aviso_de_mes_fechado`.

- [ ] **Step 3: Rodar e ver falhar** — Run: `flutter test test/nucleo/sincronizacao_test.dart test/nucleo/portados/sincronizacao_test.dart` — Expected: FAIL.

- [ ] **Step 4: Implementar `sincronizacao.dart`.**

- [ ] **Step 5: Rodar e ver passar** — Run: o mesmo comando do passo de falha — Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add ferramentas app/lib/nucleo app/test
git commit -m "Plano 1, tarefa 20: sincronização sem rede (mesclagem e linhas a gravar)"
```

---

### Task 21: Sugestões de alvo e stop

**Files:**
- Create: `app/lib/nucleo/sugestoes/sugestoes.dart`, `sugestoes/patrimonio.dart`, `sugestoes/textos.dart`, `ferramentas/referencias/sugestoes.py`
- Create (gerado): `app/test/referencias/sugestoes.json`
- Test: `app/test/nucleo/sugestoes_test.dart`, `app/test/nucleo/portados/sugestoes_test.dart`

**Interfaces:**
- Consumes: `calcularAtr`, `calcularChandelier`, `calcularPivos`, `pisoCentavo`, `tetoCentavo`, `projetar`, `Projecao`, `mensagemErro`, `resumoCaixa`, `lotesAbertos`, `restante`, `calcularVenda`, `somaPython`, `brl`, `fmtData`, `fmtPct`, `fmtDec`, `SemSugestao`, `Repositorio`, `ambiente`.
- Produces (sugestoes.py:20-284):
  - Constantes verbatim: `minBarras = 15`, `multStopSwing = 2`, `multChandelier = 3`, `periodoChandelier = 22`, `rr = 2`, `multStopDt = 1`, `limiteRisco = 0.02`, `limiteMes = 0.06`, `avisoSugestao`, `avisoProventos`, `avisoGap`.
  - `class Sugestao {String modo; double atr14; double? atr22, stopInicial, chandelier, pp, r1, s1; double stop, alvo; bool movelDisponivel; String baseData; double? precoAtual; bool stopValido = true, alvoImediato = false; List<String> avisos;}`
  - `Sugestao sugestaoSwing(double compra, List<BarraDiaria> barras)`, `Sugestao sugestaoDayTrade(double compra, BarraDiaria diaAnterior, double? atr14)`, `Sugestao sugerir(Lote lote, List<BarraDiaria> barras, String hoje, double? precoAtual)`
  - `class Avaliacao {Projecao projAlvo, projStop; double lucroAlvo, perdaStop; double? distAlvoPct, distStopPct, rrPreco, rrLiquido;}`, `Avaliacao avaliar(Lote lote, num qtd, Sugestao sug, double? precoAtual, bool dayTrade)`
  - `class Patrimonio {double valor, caixa, posicoes; bool caixaDefinido; List<String> semCotacao;}`, `Patrimonio patrimonio(Config cfg, Map<String, double>? cotacoes, Map<String, Mes> meses, {String? hoje})`, `(Patrimonio, double) resumoPatrimonio(Repositorio repo, Config cfg, Map<String, double>? cotacoes, {String? hoje})`
  - `class AlertaRisco {double? pct; double limite; bool excede;}`, `AlertaRisco alertaRisco(double resultado, double? valorPatrimonio)`, `double resultadoMes(Map<String, Mes> meses, String mes)`
  - `class ItemSugestao {Lote lote; int qtd; Sugestao? sug; Avaliacao? aval; AlertaRisco? alerta; String? erro; double? precoAtual;}`, `ItemSugestao montarItem(Lote lote, int qtd, Object diarias, {double? valorPatrimonio, String? hoje})` (`diarias` é `Diarias`, uma exceção ou um texto, como sugestoes.py:196-205)
  - `typedef LinhaCard = (String rotulo, String valor, String? cor);` `List<LinhaCard> linhasCard(ItemSugestao item)`, `List<LinhaCard> linhasRodape(Patrimonio? pat, double resultado)`

- [ ] **Step 1: Área `sugestoes`**

Com `random.Random(5)`: conjuntos de barras diárias (0 a 60, inclusive voláteis e planas) × lotes (preço, data hoje/anterior) × cotação (None, abaixo do stop, acima do alvo, longe da compra): `sugerir` (ou mensagem de `SemSugestao`), `avaliar`, `montar_item` e `linhas_card`; `alerta_risco` numa grade; `patrimonio` e `resultado_mes` sobre o roteiro da Tarefa 9 com caixa definido e indefinido; `linhas_rodape`.

Run: `py -3.12 ferramentas/gerar_referencias.py sugestoes` — Expected: arquivo criado.

- [ ] **Step 2: Testes que falham**

Referências + 24 portados de tests/test_sugestoes.py: os 10 de `TestSugestoes`, os 2 de `TestAvaliacaoERisco`, os 4 de `TestStopAcimaDaCompra`, os 5 de `TestPatrimonio` (com `ArmazenamentoMemoria`; `patrimonio(cfg, cotacoes, repo.carregarMeses(), hoje: ...)`), os 3 de `TestTextos`. O dict `{"valor": 11000.0}` passado como patrimônio vira `valorPatrimonio: 11000.0`.

- [ ] **Step 3: Rodar e ver falhar** — Run: `flutter test test/nucleo/sugestoes_test.dart test/nucleo/portados/sugestoes_test.dart` — Expected: FAIL.

- [ ] **Step 4: Implementar os três arquivos.**

- [ ] **Step 5: Rodar e ver passar** — Run: o mesmo comando do passo de falha — Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add ferramentas app/lib/nucleo app/test
git commit -m "Plano 1, tarefa 21: sugestões de alvo e stop, patrimônio e textos dos cartões"
```

---

### Task 22: Notícias: relevância, mesclagem e estado de lidas

**Files:**
- Create: `app/lib/nucleo/noticias/texto.dart`, `app/lib/nucleo/noticias/estado.dart`, `ferramentas/referencias/noticias.py`
- Create (gerado): `app/test/referencias/noticias.json`
- Test: `app/test/nucleo/noticias_test.dart`

**Interfaces:**
- Consumes: `tipoPorTicker`, `Armazenamento`, `ordenadoPor`, `ambiente`.
- Produces (noticias.py:17-130, 178-195, 209-314, 460-470):
  - Constantes verbatim: URLs (17-20), `intervalo = 600`, `janelaNotificacao = 86400`, `maxItens = 150`, `maxVistos = 3000`, `maxNotificacoes = 3`, `maxDetalhes = 40`, `tentarDetalheDeNovo = 21600`, `validadeLogoAusente = 604800`, `temasNoticias` (36-54), padrões `sufixosNome` (56-58) e `ruido` (92).
  - `texto.dart`: `String semAcento(String? s)` (NFKD por `unorm_dart`, remove marcas `\p{Mn}`, minúsculas), `List<String> temas(String titulo)`, `String nomeBusca(String? nome)`, `String consulta(String ticker, {String nome = ''})`, `bool pertinente(String titulo, String ticker, {String nome = ''})`, `String dominio(String url)` (`authority` minúscula sem `www.`; erro → `''`), `String urlFavicon(Noticia item)`, `String tempoRelativo(double ts, {double? agora})`, `String chaveTitulo(String titulo)`, `String iniciais(String ticker)`, `(List<String>, String) urlsLogo(String ticker)`. Regex: `\w`/`\W` do Python viram `[\p{L}\p{N}_]`/`[^\p{L}\p{N}_]` com `unicode: true`; `re.I` vira `caseSensitive: false`; `re.escape` vira `RegExp.escape`.
  - `estado.dart`: `class Noticia {String id, titulo, link, fonte, fonteUrl; double data; List<String> tickers, temas;}` (chave `fonte_url`), `class EstadoNoticias {List<Noticia> itens; Map<String, double> vistos; List<String> conhecidos; double hora, lidasAte; Map<String, String> erros;}` (chave `lidas_ate`), `List<Noticia> mesclar(List<List<Noticia>> listas)`, `EstadoNoticias lerEstado(Armazenamento a)`, `void gravarEstado(Armazenamento a, EstadoNoticias d)` (corta `vistos` em 3000 pelos mais recentes, ordenação estável), `List<Noticia> aplicarBusca(EstadoNoticias d, List<(String, String)> tickers, List<List<Noticia>> listas, Map<String, String> erros, double agora)` (parte sem rede de `atualizar`, noticias.py:252-271; devolve as novas relevantes), `bool precisaAtualizar(EstadoNoticias d, {double? agora})`, `bool ehNova(EstadoNoticias d, Noticia item)`, `int naoLidas(EstadoNoticias d)`, `EstadoNoticias marcarLidas(Armazenamento a, {double? agora})`, `List<(String, String, String)> textosNotificacao(List<Noticia> novas)`.

- [ ] **Step 1: Área `noticias`**

`sem_acento`, `temas`, `chave_titulo`, `pertinente` sobre ~300 títulos (lista escrita no gerador cobrindo cada tema e ruídos); grupo `unicode` (Review Focus 4) com "Itaú Unibanco", "Nestlé", "Ørsted", "ﬁnanças", "x²", emoji, "Ação"; `nome_busca` e `consulta` de nomes de empresas (ações e BDRs, "Apple Inc.", "BRF S.A.", "Itaú Unibanco Holding S.A."); `dominio`; `mesclar` com caso `empate_mesma_data` (Review Focus 2); roteiros de `aplicar_busca` (primeira busca marca como vista, janela de 24 h, ativo com erro mantendo itens antigos, limite de 150, `lidas_ate`); `textos_notificacao` com 2, 4 e 8 tickers; `tempo_relativo` com `agora` fixo e diferenças menores que 7 dias; corte de `vistos` com 3005 entradas e empates; `iniciais`, `urls_logo`.

Run: `py -3.12 ferramentas/gerar_referencias.py noticias` — Expected: arquivo criado.

- [ ] **Step 2: Escrever o teste que falha** (referências + `test('tempoRelativo acima de 7 dias usa a data local dd/mm/aaaa', ...)`)

- [ ] **Step 3: Rodar e ver falhar** — Run: `flutter test test/nucleo/noticias_test.dart` — Expected: FAIL.

- [ ] **Step 4: Implementar `texto.dart` e `estado.dart`.**

- [ ] **Step 5: Rodar e ver passar** — Run: o mesmo comando do passo de falha — Expected: PASS. Se algum caso `unicode` divergir só por `\b` ao lado de letra que o NFKD não decompõe (ex.: "ø"), registrar a divergência no teste com comentário e avisar o revisor em vez de forçar.

- [ ] **Step 6: Commit**

```bash
git add ferramentas app/lib/nucleo app/test
git commit -m "Plano 1, tarefa 22: relevância, mesclagem e estado de lidas das notícias"
```

---

### Task 23: Ida e volta Dart → Python e conferência final

**Files:**
- Create: `app/test/nucleo/ida_e_volta_test.dart`, `app/dart_test.yaml` (declara a tag `ida_e_volta`), `ferramentas/conferir_ida_e_volta.py`, `ferramentas/conferir_portados.py`

**Interfaces:**
- Consumes: `sincronizarLinhas`, `montarLinhas`, `celula`, modelos, os roteiros de `sincronizacao.json`.
- Produces:
  - Teste Dart com tag `ida_e_volta` que, para cada roteiro de `sincronizacao.json`, grava em `app/build/ida_e_volta/<nome>.json` as linhas montadas pelo Dart, as células (`celula` de cada valor) e o estado (meses, `cfg` com metas, radar, amigos, caixa, exclusões) em JSON.
  - `py -3.12 ferramentas/conferir_ida_e_volta.py app/build/ida_e_volta`: para cada arquivo, confere que `google_sync.celula` dá as mesmas células, passa as linhas pelo completamento de `ler` (google_sync.py:441), roda `nc.reconstruir` e `nc.reconstruir_metas` e compara com o estado exportado pelo Dart; imprime `IDA E VOLTA OK (<n> roteiros)` ou as diferenças e sai com código 1.
  - `py -3.12 ferramentas/conferir_portados.py`: lista `Classe.metodo` de tests/*.py (via `ast`) e as descrições de teste em `app/test/nucleo/portados/**/*.dart`; imprime `147 de 147 portados` ou os faltantes e sobrantes.

- [ ] **Step 1: Escrever o teste de ida e volta e os dois conferidores.**

- [ ] **Step 2: Rodar a ida e volta**

Run: `flutter test --tags ida_e_volta` (em `app/`) e depois `py -3.12 ferramentas/conferir_ida_e_volta.py app/build/ida_e_volta`
Expected: `IDA E VOLTA OK`.

- [ ] **Step 3: Conferir os testes portados**

Run: `py -3.12 ferramentas/conferir_portados.py`
Expected: `147 de 147 portados`.

- [ ] **Step 4: Conferência completa**

Run: `flutter analyze`, `flutter test` (em `app/`) e `python -m unittest discover -s tests` (na raiz)
Expected: `No issues found!`; `All tests passed!`; `Ran 147 tests ... OK` (o Python continua intacto).

- [ ] **Step 5: Commit**

```bash
git add app/test app/dart_test.yaml ferramentas
git commit -m "Plano 1, tarefa 23: ida e volta Dart para Python e conferência dos 147 testes portados"
```
