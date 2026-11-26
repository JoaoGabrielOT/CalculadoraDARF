// Relatórios de abertura sobre a pasta do Drive, com cache em `relatorios/`.
// O índice guarda, por arquivo, o `modifiedTime` e o termômetro de todo
// relatório já baixado; o conteúdo fica só para os `limiteConteudo` mais
// recentes, o de hoje e o último que o usuário abriu.

import 'dart:convert';
import 'dart:developer' as developer;

import '../../../integracoes/integracoes.dart';
import '../../../nucleo/nucleo.dart';
import '../api.dart';

const arquivoIndiceRelatorios = 'relatorios/indice.json';

/// Erro de `abrir` quando o arquivo da pasta é ilegível, fora do formato ou
/// sumiu (404).
const textoRelatorioInvalido =
    'O arquivo deste relatório é inválido e não pode ser aberto.';

void registrarRelatorios(String texto) =>
    developer.log(texto, name: 'relatorios');

/// Campos de primeiro nível do schema: objeto sem nenhum deles (`{}`) não é
/// relatório.
const _camposRelatorio = {
  'schemaVersion',
  'tipo',
  'data',
  'dataExtenso',
  'geradoEm',
  'titulo',
  'origemAtivos',
  'avisosTopo',
  'alertas',
  'indicadores',
  'resumo',
  'termometro',
  'ativos',
  'educacaoRisco',
  'aviso',
  'fontesCenario',
};

String _caminho(String nome) => 'relatorios/$nome';

class _Entrada {
  _Entrada({
    required this.id,
    required this.modificado,
    this.invalido = false,
    this.termometro,
  });

  String id;
  final String modificado;

  /// JSON ilegível, fora do formato ou 404: não é baixado de novo com o mesmo
  /// [modificado].
  bool invalido;
  Termometro? termometro;

  Map<String, Object?> paraJson() {
    final t = termometro;
    return {
      'id': id,
      'modificado': modificado,
      'invalido': invalido,
      'termometro': t == null
          ? null
          : {for (final l in Leitura.values) l.name: t.de(l)},
    };
  }

  static _Entrada? deJson(Object? j) {
    if (j is! Map) return null;
    final id = j['id'], modificado = j['modificado'], t = j['termometro'];
    if (id is! String || modificado is! String) return null;
    return _Entrada(
      id: id,
      modificado: modificado,
      invalido: j['invalido'] == true,
      termometro: t is Map
          ? Termometro.deJson(t.cast<String, Object?>())
          : null,
    );
  }
}

class _Indice {
  _Indice({this.aberto});

  final arquivos = <String, _Entrada>{};

  /// Último relatório aberto pelo usuário: o limite não apaga o conteúdo dele.
  String? aberto;

  String paraJson() => jsonEncode({
    'versao': 1,
    'arquivos': {
      for (final MapEntry(:key, :value) in arquivos.entries)
        key: value.paraJson(),
    },
    'aberto': aberto,
  });
}

class RelatoriosLocal {
  RelatoriosLocal({
    required this.disco,
    required this.fonte,
    required this.conta,
    this.limiteConteudo = 10,
    this.registrar = registrarRelatorios,
  });

  final Armazenamento disco;
  final FonteRelatorios fonte;
  final ContaGoogle conta;
  final int limiteConteudo;
  final void Function(String) registrar;

  /// Índice que o disco não aceitou gravar; vale no lugar do gravado.
  _Indice? _pendente;

  /// Conteúdos que o disco não aceitou gravar.
  final _naMemoria = <String, Relatorio>{};
  Future<VisaoRelatorios>? _emCurso;

  /// `atualizar` e `abrir` leem e regravam o índice: um de cada vez.
  Future<void> _fila = Future.value();

  String get _hoje => hojeBrasilia(ambiente.agoraBr());

  /// Sem conta nem token (saiu da conta): `semConta`, sem o cache.
  Future<VisaoRelatorios> emCache() async =>
      conta.email == null && !conta.temToken()
      ? _semConta()
      : _visao(_lerIndice(), SituacaoRelatorios.ok);

  /// Sair da conta: apaga o índice e os conteúdos já, e de novo depois do que
  /// estiver em curso na fila (um `atualizar` em voo regravaria o índice).
  Future<void> limpar() {
    _limparAgora();
    return _naFila(() async => _limparAgora());
  }

  /// Nunca lança: o `sair()` não pode parecer falho por causa do cache.
  void _limparAgora() {
    _pendente = null;
    _naMemoria.clear();
    try {
      final nomes = <String>{
        for (final nome in _indiceDoDisco().arquivos.keys) _caminho(nome),
        // conteúdos fora do índice (o disco do app lista só a raiz)
        ...disco.listar().where((n) => n.startsWith('relatorios/')),
      }..remove(arquivoIndiceRelatorios);
      nomes.forEach(_apagar);
    } on Exception catch (e) {
      registrar('Falha ao limpar os relatórios: $e');
    }
    _apagar(arquivoIndiceRelatorios);
  }

  /// Lista a pasta e baixa o que mudou; chamadas simultâneas compartilham o
  /// mesmo pedido.
  Future<VisaoRelatorios> atualizar() =>
      _emCurso ??= _naFila(_atualizar).whenComplete(() => _emCurso = null);

  /// Conteúdo do cache; sem cache baixa e guarda. Arquivo inválido é marcado
  /// e vira `ErroValidacao(textoRelatorioInvalido)`.
  Future<Relatorio> abrir(String nome) => _naFila(() => _abrir(nome));

  Future<T> _naFila<T>(Future<T> Function() tarefa) {
    final r = _fila.then((_) => tarefa());
    _fila = r.then<void>((_) {}, onError: (_) {});
    return r;
  }

  Future<Relatorio> _abrir(String nome) async {
    final indice = _lerIndice();
    final e = indice.arquivos[nome];
    if (e == null || e.invalido) {
      throw ErroValidacao('Relatório não encontrado.');
    }
    var r = _conteudo(nome);
    if (r == null) {
      try {
        r = await _baixar(nome, e);
      } on Exception catch (erro) {
        if (!_ehInvalido(erro)) rethrow;
        _marcarInvalido(nome, e, erro);
        _descartarConteudo(nome);
        _gravarIndice(indice);
        throw ErroValidacao(textoRelatorioInvalido);
      }
    }
    indice.aberto = nome;
    _gravarIndice(indice);
    return r;
  }

  Future<VisaoRelatorios> _atualizar() async {
    if (conta.email == null) {
      return conta.temToken()
          ? _visao(_lerIndice(), SituacaoRelatorios.semConexao)
          : _semConta();
    }
    if (!podeLerRelatorios(fonte.escopos)) return _novoLogin();
    final List<ArquivoRelatorio> arquivos;
    try {
      arquivos = await fonte.listar();
    } on EscopoInsuficiente {
      return _novoLogin();
    } on Offline {
      return _visao(_lerIndice(), SituacaoRelatorios.semConexao);
    } on LoginNecessario {
      return _visao(_lerIndice(), SituacaoRelatorios.semConexao);
    } on ErroGoogle catch (e) {
      registrar('Falha ao listar os relatórios: $e');
      return _visao(_lerIndice(), SituacaoRelatorios.semConexao);
    }

    final pasta = <String, ArquivoRelatorio>{};
    for (final a in arquivos) {
      if (dataDoNome(a.nome) == null) {
        registrar('Arquivo fora do padrão de nome ignorado: ${a.nome}');
        continue;
      }
      final outro = pasta[a.nome];
      if (outro != null) {
        registrar('Nome repetido na pasta: ${a.nome}; vale o mais novo.');
      }
      if (outro == null || a.modificado.compareTo(outro.modificado) > 0) {
        pasta[a.nome] = a;
      }
    }

    final antigo = _lerIndice();
    final novo = _Indice(
      aberto: pasta.containsKey(antigo.aberto) ? antigo.aberto : null,
    );
    // modifiedTime novo: a entrada antiga (e o conteúdo dela) fica até o
    // download novo dar certo.
    final mudados = <String, _Entrada>{};
    for (final a in pasta.values) {
      final e = antigo.arquivos[a.nome];
      final nova = _Entrada(id: a.id, modificado: a.modificado);
      if (e != null && (e.modificado == a.modificado || !e.invalido)) {
        novo.arquivos[a.nome] = e..id = a.id;
        if (e.modificado != a.modificado) mudados[a.nome] = nova;
      } else {
        novo.arquivos[a.nome] = nova;
        _descartarConteudo(a.nome);
      }
    }

    final ordenados = _itens(novo);
    final hoje = _hoje;
    // Só o escolhido é decodificado; se estiver ilegível, é apagado aqui e
    // baixado no laço.
    final lidos = <String, Relatorio>{};
    final escolhido = escolherRelatorio(ordenados, hoje).escolhido?.nome;
    if (escolhido != null && !mudados.containsKey(escolhido)) {
      final r = _conteudo(escolhido);
      if (r != null) lidos[escolhido] = r;
    }
    final manter = <String>{
      ?novo.aberto,
      ?ordenados.where((r) => r.data == hoje).firstOrNull?.nome,
    };
    var guardados = 0;
    // Sem conexão: segue só com o que já está em cache.
    var parar = false;
    for (final r in ordenados) {
      if (guardados >= limiteConteudo && !manter.contains(r.nome)) continue;
      final nova = mudados.remove(r.nome);
      if (nova != null || !_temConteudo(r.nome)) {
        final e = nova ?? novo.arquivos[r.nome]!;
        if (!parar) {
          try {
            lidos[r.nome] = await _baixar(r.nome, e);
            novo.arquivos[r.nome] = e;
          } on EscopoInsuficiente {
            return _novoLogin();
          } on Exception catch (erro) {
            if (_ehInvalido(erro)) {
              _marcarInvalido(r.nome, e, erro);
              novo.arquivos[r.nome] = e;
              manter.remove(r.nome);
              continue;
            }
            // Rede, 429, 5xx: fica o que havia; tenta de novo na próxima.
            registrar('Falha ao baixar ${r.nome}: $erro');
            parar = true;
          }
        }
        if (!_temConteudo(r.nome)) continue;
      }
      manter.add(r.nome);
      guardados++;
    }
    // Mudados fora do limite: entrada nova, sem o termômetro da versão velha.
    novo.arquivos.addAll(mudados);

    for (final nome in {...antigo.arquivos.keys, ...novo.arquivos.keys}) {
      if (!manter.contains(nome)) _descartarConteudo(nome);
    }
    _gravarIndice(novo);
    return _visao(
      novo,
      parar ? SituacaoRelatorios.semConexao : SituacaoRelatorios.ok,
      lidos: lidos,
    );
  }

  /// Ruling 1: só JSON ilegível ou fora do formato e 404 marcam `invalido`;
  /// rede, 429 e 5xx são passageiros.
  static bool _ehInvalido(Object erro) =>
      erro is RespostaInvalida ||
      erro is FormatException ||
      (erro is ErroGoogle && erro.status == 404);

  bool _temConteudo(String nome) =>
      _naMemoria.containsKey(nome) || disco.existe(_caminho(nome));

  VisaoRelatorios _semConta() => VisaoRelatorios(
    itens: const [],
    hoje: _hoje,
    situacao: SituacaoRelatorios.semConta,
  );

  VisaoRelatorios _novoLogin() => VisaoRelatorios(
    itens: const [],
    hoje: _hoje,
    situacao: SituacaoRelatorios.novoLogin,
  );

  List<ResumoRelatorio> _itens(_Indice indice) => ordenarRelatorios([
    for (final MapEntry(key: nome, value: e) in indice.arquivos.entries)
      if (!e.invalido)
        ResumoRelatorio(
          nome: nome,
          data: dataDoNome(nome)!,
          termometro: e.termometro,
        ),
  ]);

  /// [lidos]: conteúdos já decodificados nesta chamada.
  VisaoRelatorios _visao(
    _Indice indice,
    SituacaoRelatorios situacao, {
    Map<String, Relatorio> lidos = const {},
  }) {
    final itens = _itens(indice);
    final hoje = _hoje;
    final (:escolhido, :ehHoje) = escolherRelatorio(itens, hoje);
    return VisaoRelatorios(
      itens: itens,
      hoje: hoje,
      atual: escolhido == null
          ? null
          : lidos[escolhido.nome] ?? _conteudo(escolhido.nome),
      ehHoje: ehHoje,
      situacao: situacao,
    );
  }

  /// Baixa, confere e guarda; o termômetro vai para [e]. Lança o erro do
  /// Drive ou `FormatException` para JSON fora do formato.
  Future<Relatorio> _baixar(String nome, _Entrada e) async {
    final m = await fonte.baixar(e.id);
    if (!m.keys.any(_camposRelatorio.contains)) {
      throw const FormatException('o JSON não tem os campos do relatório');
    }
    final r = Relatorio.deJson(m, dataDoArquivo: dataDoNome(nome));
    if (r.termometroDiverge) {
      registrar(
        'Termômetro de $nome diverge das leituras dos ativos: '
        'JSON ${_contagem(r.termometro)}, ativos ${_contagem(r.contagemAtivos)}',
      );
    }
    e.termometro = r.termometro;
    if (_gravar(_caminho(nome), jsonEncode(m))) {
      _naMemoria.remove(nome);
    } else {
      _naMemoria[nome] = r;
    }
    return r;
  }

  void _marcarInvalido(String nome, _Entrada e, Object erro) {
    registrar('Relatório inválido ignorado: $nome ($erro)');
    e.invalido = true;
    e.termometro = null;
  }

  static String _contagem(Termometro t) =>
      Leitura.values.map((l) => '${t.de(l)} ${l.name}').join(', ');

  _Indice _lerIndice() => _pendente ?? _indiceDoDisco();

  /// Índice ilegível vale como vazio.
  _Indice _indiceDoDisco() {
    final Object? j;
    try {
      final texto = disco.ler(arquivoIndiceRelatorios);
      if (texto == null) return _Indice();
      j = jsonDecode(texto);
    } on Exception catch (e) {
      registrar('Índice dos relatórios ilegível; começa vazio ($e)');
      return _Indice();
    }
    if (j is! Map) return _Indice();
    final aberto = j['aberto'], arquivos = j['arquivos'];
    final indice = _Indice(aberto: aberto is String ? aberto : null);
    if (arquivos is Map) {
      for (final MapEntry(:key, :value) in arquivos.entries) {
        final e = _Entrada.deJson(value);
        if (key is String && dataDoNome(key) != null && e != null) {
          indice.arquivos[key] = e;
        }
      }
    }
    return indice;
  }

  /// Conteúdo em cache (o navegador pode ter apagado); o ilegível é apagado.
  Relatorio? _conteudo(String nome) {
    final m = _naMemoria[nome];
    if (m != null) return m;
    try {
      final texto = disco.ler(_caminho(nome));
      if (texto == null) return null;
      return Relatorio.deJson(
        jsonDecode(texto),
        dataDoArquivo: dataDoNome(nome),
      );
    } on Exception catch (e) {
      registrar('Cache ilegível de $nome apagado ($e)');
      _apagar(_caminho(nome));
      return null;
    }
  }

  void _descartarConteudo(String nome) {
    _naMemoria.remove(nome);
    _apagar(_caminho(nome));
  }

  void _gravarIndice(_Indice indice) {
    _pendente = _gravar(arquivoIndiceRelatorios, indice.paraJson())
        ? null
        : indice;
  }

  /// `ErroArmazenamentoCheio` ou `FileSystemException`: só log.
  bool _gravar(String nome, String texto) {
    try {
      disco.gravar(nome, texto);
      return true;
    } on Exception catch (e) {
      registrar('Falha ao gravar $nome: $e');
      return false;
    }
  }

  void _apagar(String nome) {
    try {
      disco.apagar(nome);
    } on Exception catch (e) {
      registrar('Falha ao apagar $nome: $e');
    }
  }
}
