import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:calculadoradarf/app/servicos/api.dart';
import 'package:calculadoradarf/app/servicos/locais/relatorios_local.dart';
import 'package:calculadoradarf/integracoes/integracoes.dart';
import 'package:calculadoradarf/nucleo/armazenamento_chave_valor.dart';
import 'package:calculadoradarf/nucleo/nucleo.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../nucleo/apoio/fixture_relatorio.dart';
import '../apoio/conta_falsa.dart';

/// Os escopos da 2.6.0, antes do `drive.readonly`.
const _escoposAntigos = [
  'https://www.googleapis.com/auth/drive.file',
  'https://www.googleapis.com/auth/drive.metadata.readonly',
  'https://www.googleapis.com/auth/spreadsheets.readonly',
];

/// Pasta falsa: [conteudos] mapeia id -> mapa do JSON ou erro a lançar; id
/// ausente é 404.
class FonteFalsa implements FonteRelatorios {
  FonteFalsa({
    List<ArquivoRelatorio>? arquivos,
    Map<String, Object>? conteudos,
    this.escopos = escoposGoogle,
  }) : arquivos = arquivos ?? [],
       conteudos = conteudos ?? {};

  @override
  List<String>? escopos;
  List<ArquivoRelatorio> arquivos;
  Map<String, Object> conteudos;
  Object? erroListar;
  int listagens = 0;
  int downloads = 0;

  @override
  Future<List<ArquivoRelatorio>> listar() async {
    listagens++;
    await Future<void>.delayed(Duration.zero);
    if (erroListar != null) throw erroListar!;
    return List.of(arquivos);
  }

  @override
  Future<Map<String, Object?>> baixar(String id) async {
    downloads++;
    await Future<void>.delayed(Duration.zero);
    final c = conteudos[id];
    if (c is Map) {
      return (jsonDecode(jsonEncode(c)) as Map).cast<String, Object?>();
    }
    throw c ?? ErroGoogle('File not found', 404);
  }
}

/// A listagem `i` espera `portoes[i]`.
class _FonteComPortoes extends FonteFalsa {
  _FonteComPortoes(this.portoes);

  final List<Completer<void>> portoes;
  var _pedidas = 0;

  @override
  Future<List<ArquivoRelatorio>> listar() async {
    await portoes[_pedidas++].future;
    return super.listar();
  }
}

/// Disco que recusa toda gravação, como o `localStorage` cheio.
class DiscoCheio extends ArmazenamentoMemoria {
  @override
  void gravar(String nome, String conteudo) => throw ErroArmazenamentoCheio();
}

/// Disco cujo `listar` falha, como uma pasta inacessível.
class DiscoQueNaoLista extends ArmazenamentoMemoria {
  @override
  List<String> listar() => throw const FileSystemException('sem acesso');
}

/// Disco que conta as leituras do conteúdo dos relatórios (fora o índice).
class DiscoContado extends ArmazenamentoMemoria {
  final leituras = <String>[];

  @override
  String? ler(String nome) {
    if (nome != arquivoIndiceRelatorios) leituras.add(nome);
    return super.ler(nome);
  }
}

String _nome(String data) => 'relatorio-abertura-$data.json';

ArquivoRelatorio _arq(
  String data, {
  String? id,
  String modificado = '2026-11-26T12:00:00.000Z',
}) => ArquivoRelatorio(
  id: id ?? 'id-$data',
  nome: _nome(data),
  modificado: modificado,
);

Map<String, Object?> _doDia(String data) => fixtureRelatorio()..['data'] = data;

late List<String> registrados;

RelatoriosLocal _local(
  FonteFalsa f,
  Armazenamento disco, {
  ContaGoogle? conta,
  int limite = 10,
}) => RelatoriosLocal(
  disco: disco,
  fonte: f,
  conta: conta ?? ContaFalsa(email: 'ana@gmail.com'),
  limiteConteudo: limite,
  registrar: registrados.add,
);

Map<String, Object?> _indice(Armazenamento disco) =>
    ((jsonDecode(disco.ler(arquivoIndiceRelatorios)!) as Map)['arquivos']
            as Map)
        .cast<String, Object?>();

bool _temConteudo(Armazenamento disco, String data) =>
    disco.existe('relatorios/${_nome(data)}');

void main() {
  setUp(() {
    ambiente = Ambiente.fixo(agoraBr: '2026-11-26T10:00:00-03:00');
    registrados = [];
  });
  tearDown(() => ambiente = Ambiente.sistema());

  test('primeira atualização baixa, grava e escolhe o de hoje', () async {
    final f = FonteFalsa(
      arquivos: [_arq('2026-11-25'), _arq('2026-11-26')],
      conteudos: {
        'id-2026-11-26': fixtureRelatorio(),
        'id-2026-11-25': fixtureRelatorio()..['data'] = '2026-11-25',
      },
    );
    final disco = ArmazenamentoMemoria();
    final v = await _local(f, disco).atualizar();
    expect(v.situacao, SituacaoRelatorios.ok);
    expect(v.itens.map((r) => r.data), ['2026-11-26', '2026-11-25']);
    expect(
      (v.atual!.data, v.ehHoje, v.hoje),
      ('2026-11-26', true, '2026-11-26'),
    );
    expect(v.itens.first.termometro!.total, 22);
    expect(disco.existe('relatorios/indice.json'), isTrue);
    expect(
      disco.existe('relatorios/relatorio-abertura-2026-11-26.json'),
      isTrue,
    );
  });

  test('modifiedTime igual não baixa de novo; diferente baixa', () async {
    final f = FonteFalsa(
      arquivos: [_arq('2026-11-25'), _arq('2026-11-26')],
      conteudos: {
        'id-2026-11-26': _doDia('2026-11-26'),
        'id-2026-11-25': _doDia('2026-11-25'),
      },
    );
    final disco = ArmazenamentoMemoria();
    await _local(f, disco).atualizar();
    expect(f.downloads, 2);
    await _local(f, disco).atualizar();
    expect(f.downloads, 2);
    f.arquivos[1] = _arq('2026-11-26', modificado: '2026-11-26T13:00:00.000Z');
    final v = await _local(f, disco).atualizar();
    expect(f.downloads, 3);
    expect(v.atual!.data, '2026-11-26');
  });

  test('sem o de hoje mostra o mais recente', () async {
    final f = FonteFalsa(
      arquivos: [_arq('2026-11-24'), _arq('2026-11-25')],
      conteudos: {
        'id-2026-11-24': _doDia('2026-11-24'),
        'id-2026-11-25': _doDia('2026-11-25'),
      },
    );
    final v = await _local(f, ArmazenamentoMemoria()).atualizar();
    expect(v.ehHoje, isFalse);
    expect(v.atual!.data, '2026-11-25');
    expect(v.hoje, '2026-11-26');
  });

  test('sem internet mostra o cache com aviso', () async {
    final f = FonteFalsa(
      arquivos: [_arq('2026-11-25'), _arq('2026-11-26')],
      conteudos: {
        'id-2026-11-26': _doDia('2026-11-26'),
        'id-2026-11-25': _doDia('2026-11-25'),
      },
    );
    final disco = ArmazenamentoMemoria();
    final antes = await _local(f, disco).atualizar();
    f.erroListar = Offline('x');
    final v = await _local(f, disco).atualizar();
    expect(v.situacao, SituacaoRelatorios.semConexao);
    expect(v.itens.map((r) => r.nome), antes.itens.map((r) => r.nome));
    expect(v.itens.first.termometro!.total, 22);
    expect(v.atual!.data, '2026-11-26');
    f.erroListar = LoginNecessario('x');
    expect(
      (await _local(f, disco).atualizar()).situacao,
      SituacaoRelatorios.semConexao,
    );
  });

  test('primeira abertura sem internet e sem cache', () async {
    final f = FonteFalsa(arquivos: [_arq('2026-11-26')])
      ..erroListar = Offline('x');
    final v = await _local(f, ArmazenamentoMemoria()).atualizar();
    expect(v.situacao, SituacaoRelatorios.semConexao);
    expect(v.itens, isEmpty);
    expect(v.atual, isNull);
  });

  test('token sem drive.readonly pede novo login sem tocar no Drive', () async {
    final f = FonteFalsa(
      arquivos: [_arq('2026-11-26')],
      conteudos: {'id-2026-11-26': _doDia('2026-11-26')},
      escopos: _escoposAntigos,
    );
    final v = await _local(f, ArmazenamentoMemoria()).atualizar();
    expect(v.situacao, SituacaoRelatorios.novoLogin);
    expect(v.itens, isEmpty);
    expect((f.listagens, f.downloads), (0, 0));
  });

  test('escopo insuficiente no download pede novo login', () async {
    final f = FonteFalsa(
      arquivos: [_arq('2026-11-26')],
      conteudos: {'id-2026-11-26': EscopoInsuficiente('sem escopo', 403)},
    );
    final v = await _local(f, ArmazenamentoMemoria()).atualizar();
    expect(v.situacao, SituacaoRelatorios.novoLogin);
  });

  test('escopo insuficiente na listagem pede novo login', () async {
    final f = FonteFalsa(arquivos: [_arq('2026-11-26')])
      ..erroListar = EscopoInsuficiente('sem escopo', 403);
    final v = await _local(f, ArmazenamentoMemoria()).atualizar();
    expect(v.situacao, SituacaoRelatorios.novoLogin);
  });

  test('sem conta e sem token: semConta', () async {
    final f = FonteFalsa(arquivos: [_arq('2026-11-26')]);
    final v = await _local(
      f,
      ArmazenamentoMemoria(),
      conta: ContaFalsa(),
    ).atualizar();
    expect(v.situacao, SituacaoRelatorios.semConta);
    expect(f.listagens, 0);
  });

  test('token sem sessão: cache e semConexao', () async {
    final f = FonteFalsa(
      arquivos: [_arq('2026-11-26')],
      conteudos: {'id-2026-11-26': _doDia('2026-11-26')},
    );
    final disco = ArmazenamentoMemoria();
    await _local(f, disco).atualizar();
    final v = await _local(
      f,
      disco,
      conta: ContaFalsa()..token = true,
    ).atualizar();
    expect(v.situacao, SituacaoRelatorios.semConexao);
    expect(v.itens.map((r) => r.data), ['2026-11-26']);
    expect(v.atual!.data, '2026-11-26');
    expect(f.listagens, 1);
  });

  test('pasta vazia: ok e lista vazia', () async {
    final v = await _local(FonteFalsa(), ArmazenamentoMemoria()).atualizar();
    expect(v.situacao, SituacaoRelatorios.ok);
    expect(v.itens, isEmpty);
    expect(v.atual, isNull);
  });

  test('nome fora do padrão e data impossível vão para o log', () async {
    final f = FonteFalsa(
      arquivos: [
        _arq('2026-11-26'),
        const ArquivoRelatorio(
          id: 'a',
          nome: 'relatorio-abertura-2026-11-26 (1).json',
          modificado: '2026-11-26T12:00:00.000Z',
        ),
        const ArquivoRelatorio(
          id: 'b',
          nome: 'relatorio-abertura-2026-02-30.json',
          modificado: '2026-11-26T12:00:00.000Z',
        ),
      ],
      conteudos: {'id-2026-11-26': _doDia('2026-11-26')},
    );
    final v = await _local(f, ArmazenamentoMemoria()).atualizar();
    expect(v.itens.map((r) => r.nome), [_nome('2026-11-26')]);
    expect(
      registrados.any(
        (t) => t.contains('relatorio-abertura-2026-11-26 (1).json'),
      ),
      isTrue,
    );
    expect(
      registrados.any((t) => t.contains('relatorio-abertura-2026-02-30.json')),
      isTrue,
    );
    expect(f.downloads, 1);
  });

  test('JSON inválido é ignorado e não é baixado de novo', () async {
    // `[1, 2]`: a sessão recusa o corpo que não é objeto com RespostaInvalida.
    final f = FonteFalsa(
      arquivos: [_arq('2026-11-25'), _arq('2026-11-26')],
      conteudos: {
        'id-2026-11-26': RespostaInvalida('Resposta inválida do Google.', 200),
        'id-2026-11-25': _doDia('2026-11-25'),
      },
    );
    final disco = ArmazenamentoMemoria();
    final v = await _local(f, disco).atualizar();
    expect(v.situacao, SituacaoRelatorios.ok);
    expect(v.itens.map((r) => r.data), ['2026-11-25']);
    expect((v.atual!.data, v.ehHoje), ('2026-11-25', false));
    expect(registrados.any((t) => t.contains(_nome('2026-11-26'))), isTrue);
    expect(f.downloads, 2);
    final v2 = await _local(f, disco).atualizar();
    expect(f.downloads, 2);
    expect(v2.itens.map((r) => r.data), ['2026-11-25']);
    // modifiedTime novo: tenta de novo.
    f.arquivos[1] = _arq('2026-11-26', modificado: '2026-11-26T13:00:00.000Z');
    f.conteudos['id-2026-11-26'] = _doDia('2026-11-26');
    final v3 = await _local(f, disco).atualizar();
    expect(f.downloads, 3);
    expect(v3.atual!.data, '2026-11-26');
  });

  test('404, corpo vazio e FormatException marcam inválido', () async {
    final f = FonteFalsa(
      arquivos: [_arq('2026-11-24'), _arq('2026-11-25'), _arq('2026-11-26')],
      conteudos: {
        'id-2026-11-24': const FormatException('x'),
        'id-2026-11-25': <String, Object?>{},
        // 'id-2026-11-26' ausente: 404
      },
    );
    final disco = ArmazenamentoMemoria();
    final v = await _local(f, disco).atualizar();
    expect(v.situacao, SituacaoRelatorios.ok);
    expect(v.itens, isEmpty);
    final indice = _indice(disco);
    for (final d in ['2026-11-24', '2026-11-25', '2026-11-26']) {
      expect((indice[_nome(d)]! as Map)['invalido'], isTrue, reason: d);
    }
    await _local(f, disco).atualizar();
    expect(f.downloads, 3);
  });

  test('429, 5xx e rede no download: sem conexão, sem marcar', () async {
    for (final erro in [
      ErroGoogle('Too many requests', 429),
      ErroGoogle('Backend error', 503),
      Offline('sem rede'),
    ]) {
      final f = FonteFalsa(
        arquivos: [_arq('2026-11-25'), _arq('2026-11-26')],
        conteudos: {
          'id-2026-11-26': erro,
          'id-2026-11-25': _doDia('2026-11-25'),
        },
      );
      final disco = ArmazenamentoMemoria();
      final v = await _local(f, disco).atualizar();
      expect(v.situacao, SituacaoRelatorios.semConexao, reason: '$erro');
      expect(v.itens.map((r) => r.data), contains('2026-11-26'));
      expect(
        (_indice(disco)[_nome('2026-11-26')]! as Map)['invalido'],
        isFalse,
      );
      f.conteudos['id-2026-11-26'] = _doDia('2026-11-26');
      final v2 = await _local(f, disco).atualizar();
      expect(v2.situacao, SituacaoRelatorios.ok);
      expect(v2.atual!.data, '2026-11-26');
    }
  });

  test('hoje sem conteúdo por falta de rede: o mais recente em cache', () async {
    final f = FonteFalsa(
      arquivos: [_arq('2026-11-24'), _arq('2026-11-25')],
      conteudos: {
        'id-2026-11-24': _doDia('2026-11-24'),
        'id-2026-11-25': _doDia('2026-11-25'),
        'id-2026-11-26': Offline('sem rede'),
      },
    );
    final disco = ArmazenamentoMemoria();
    await _local(f, disco).atualizar();
    f.arquivos.add(_arq('2026-11-26'));
    final v = await _local(f, disco).atualizar();
    expect(v.situacao, SituacaoRelatorios.semConexao);
    expect(v.itens.first.data, '2026-11-26');
    expect(v.ehHoje, isFalse);
    expect(v.atual?.data, '2026-11-25');
    expect(v.nomeAtual, _nome('2026-11-25'));
    // a listagem também falha: o mesmo, pelo índice
    f.erroListar = Offline('x');
    final c = await _local(f, disco).atualizar();
    expect((c.atual?.data, c.nomeAtual, c.ehHoje), (
      '2026-11-25',
      _nome('2026-11-25'),
      false,
    ));
  });

  test('nome repetido: vale o modifiedTime mais novo', () async {
    final f = FonteFalsa(
      arquivos: [
        _arq('2026-11-26', id: 'novo', modificado: '2026-11-26T12:00:00.000Z'),
        _arq('2026-11-26', id: 'velho', modificado: '2026-11-26T11:00:00.000Z'),
      ],
      conteudos: {
        'novo': _doDia('2026-11-26'),
        'velho': _doDia('2026-11-26')..['titulo'] = 'velho',
      },
    );
    final disco = ArmazenamentoMemoria();
    final v = await _local(f, disco).atualizar();
    expect(v.itens, hasLength(1));
    expect(v.atual!.titulo, isNot('velho'));
    expect(f.downloads, 1);
    expect((_indice(disco)[_nome('2026-11-26')]! as Map)['id'], 'novo');
  });

  test('termômetro divergente só vai para o log', () async {
    final f = FonteFalsa(
      arquivos: [_arq('2026-11-26')],
      conteudos: {
        'id-2026-11-26': _doDia('2026-11-26')
          ..['termometro'] = {
            'positiva': 22,
            'mista': 0,
            'neutra': 0,
            'negativa': 0,
          },
      },
    );
    final v = await _local(f, ArmazenamentoMemoria()).atualizar();
    expect(v.situacao, SituacaoRelatorios.ok);
    expect(v.itens.single.termometro!.positiva, 22);
    expect(v.atual!.termometro.positiva, 22);
    expect(
      registrados.any(
        (t) => t.contains(_nome('2026-11-26')) && t.contains('diverge'),
      ),
      isTrue,
    );
  });

  test('só os N mais recentes têm conteúdo', () async {
    final datas = ['2026-11-23', '2026-11-24', '2026-11-25', '2026-11-26'];
    FonteFalsa fonte() => FonteFalsa(
      arquivos: [for (final d in datas) _arq(d)],
      conteudos: {for (final d in datas) 'id-$d': _doDia(d)},
    );
    // Primeira vez com limite 2: só os 2 mais recentes são baixados.
    final f = fonte();
    final disco = ArmazenamentoMemoria();
    final v = await _local(f, disco, limite: 2).atualizar();
    expect(f.downloads, 2);
    expect(v.itens, hasLength(4));
    expect(v.itens.map((r) => r.termometro?.total), [22, 22, null, null]);
    expect(_temConteudo(disco, '2026-11-24'), isFalse);
    // Cache com os 4: o limite apaga o conteúdo dos antigos e mantém o
    // termômetro no índice.
    final f2 = fonte();
    final disco2 = ArmazenamentoMemoria();
    await _local(f2, disco2).atualizar();
    expect(_temConteudo(disco2, '2026-11-24'), isTrue);
    final v2 = await _local(f2, disco2, limite: 2).atualizar();
    expect(f2.downloads, 4);
    expect(_temConteudo(disco2, '2026-11-26'), isTrue);
    expect(_temConteudo(disco2, '2026-11-25'), isTrue);
    expect(_temConteudo(disco2, '2026-11-24'), isFalse);
    expect(_temConteudo(disco2, '2026-11-23'), isFalse);
    expect(v2.itens.map((r) => r.termometro?.total), [22, 22, 22, 22]);
  });

  test('o último relatório aberto mantém o conteúdo fora do limite', () async {
    final datas = ['2026-11-24', '2026-11-25', '2026-11-26'];
    final f = FonteFalsa(
      arquivos: [for (final d in datas) _arq(d)],
      conteudos: {for (final d in datas) 'id-$d': _doDia(d)},
    );
    final disco = ArmazenamentoMemoria();
    final local = _local(f, disco, limite: 1);
    await local.atualizar();
    expect((await local.abrir(_nome('2026-11-24'))).data, '2026-11-24');
    await _local(f, disco, limite: 1).atualizar();
    expect(_temConteudo(disco, '2026-11-24'), isTrue);
    // Abrir outro libera o anterior.
    await local.abrir(_nome('2026-11-25'));
    await _local(f, disco, limite: 1).atualizar();
    expect(_temConteudo(disco, '2026-11-24'), isFalse);
    expect(_temConteudo(disco, '2026-11-25'), isTrue);
  });

  test('arquivo removido da pasta sai do índice e do disco', () async {
    final f = FonteFalsa(
      arquivos: [_arq('2026-11-25'), _arq('2026-11-26')],
      conteudos: {
        'id-2026-11-26': _doDia('2026-11-26'),
        'id-2026-11-25': _doDia('2026-11-25'),
      },
    );
    final disco = ArmazenamentoMemoria();
    await _local(f, disco).atualizar();
    f.arquivos.removeAt(0);
    final v = await _local(f, disco).atualizar();
    expect(v.itens.map((r) => r.data), ['2026-11-26']);
    expect(_indice(disco).keys, [_nome('2026-11-26')]);
    expect(_temConteudo(disco, '2026-11-25'), isFalse);
  });

  test(
    'abrir usa o cache; sem cache baixa; Offline sem cache relança',
    () async {
      final f = FonteFalsa(
        arquivos: [_arq('2026-11-24'), _arq('2026-11-25'), _arq('2026-11-26')],
        conteudos: {
          'id-2026-11-26': _doDia('2026-11-26'),
          'id-2026-11-25': _doDia('2026-11-25'),
          'id-2026-11-24': Offline('sem rede'),
        },
      );
      final disco = ArmazenamentoMemoria();
      final local = _local(f, disco, limite: 1);
      await local.atualizar();
      expect(f.downloads, 1);
      expect((await local.abrir(_nome('2026-11-26'))).data, '2026-11-26');
      expect(f.downloads, 1);
      expect((await local.abrir(_nome('2026-11-25'))).data, '2026-11-25');
      expect(f.downloads, 2);
      expect(_temConteudo(disco, '2026-11-25'), isTrue);
      expect(
        (_indice(disco)[_nome('2026-11-25')]! as Map)['termometro'],
        isNotNull,
      );
      await expectLater(
        local.abrir(_nome('2026-11-24')),
        throwsA(isA<Offline>()),
      );
      await expectLater(
        local.abrir(_nome('2000-01-01')),
        throwsA(
          isA<ErroValidacao>().having(
            (e) => e.mensagem,
            'mensagem',
            'Relatório não encontrado.',
          ),
        ),
      );
    },
  );

  test('índice ilegível vira vazio', () async {
    final disco = ArmazenamentoMemoria()..gravar(arquivoIndiceRelatorios, '{x');
    final f = FonteFalsa(
      arquivos: [_arq('2026-11-26')],
      conteudos: {'id-2026-11-26': _doDia('2026-11-26')},
    );
    expect((await _local(f, disco).emCache()).itens, isEmpty);
    final v = await _local(f, disco).atualizar();
    expect(v.situacao, SituacaoRelatorios.ok);
    expect(v.atual!.data, '2026-11-26');
  });

  test('conteúdo ilegível é apagado e baixado de novo', () async {
    final f = FonteFalsa(
      arquivos: [_arq('2026-11-26')],
      conteudos: {'id-2026-11-26': _doDia('2026-11-26')},
    );
    final disco = ArmazenamentoMemoria();
    await _local(f, disco).atualizar();
    disco.gravar('relatorios/${_nome('2026-11-26')}', '{x');
    expect((await _local(f, disco).emCache()).atual, isNull);
    final v = await _local(f, disco).atualizar();
    expect(f.downloads, 2);
    expect(v.atual!.data, '2026-11-26');
  });

  test(
    'índice sem o conteúdo (apagado pelo navegador) baixa de novo',
    () async {
      final f = FonteFalsa(
        arquivos: [_arq('2026-11-26')],
        conteudos: {'id-2026-11-26': _doDia('2026-11-26')},
      );
      final disco = ArmazenamentoMemoria();
      await _local(f, disco).atualizar();
      disco.apagar('relatorios/${_nome('2026-11-26')}');
      final c = await _local(f, disco).emCache();
      expect(c.itens.single.termometro!.total, 22);
      expect(c.atual, isNull);
      final v = await _local(f, disco).atualizar();
      expect(f.downloads, 2);
      expect(v.atual!.data, '2026-11-26');
    },
  );

  test('limpar apaga o índice e todos os conteúdos (sair da conta)', () async {
    final f = FonteFalsa(
      arquivos: [_arq('2026-11-25'), _arq('2026-11-26')],
      conteudos: {
        'id-2026-11-26': _doDia('2026-11-26'),
        'id-2026-11-25': _doDia('2026-11-25'),
      },
    );
    final disco = ArmazenamentoMemoria();
    final local = _local(f, disco);
    await local.atualizar();
    // conteúdo órfão (fora do índice) também sai
    disco.gravar('relatorios/relatorio-abertura-2026-01-02.json', '{}');
    disco.gravar('config.json', '{}');

    await local.limpar();

    expect(disco.listar(), ['config.json']);
    expect((await local.emCache()).itens, isEmpty);
  });

  test(
    'limpar com o disco recusando gravações esquece o que está na memória',
    () async {
      final f = FonteFalsa(
        arquivos: [_arq('2026-11-26')],
        conteudos: {'id-2026-11-26': _doDia('2026-11-26')},
      );
      final local = _local(f, DiscoCheio());
      expect((await local.atualizar()).atual, isNotNull);
      await local.limpar();
      final v = await local.emCache();
      expect(v.itens, isEmpty);
      expect(v.atual, isNull);
    },
  );

  test('limpar não lança quando o disco falha; só registra', () async {
    final f = FonteFalsa();
    final local = _local(f, DiscoQueNaoLista());
    await local.limpar();
    expect(registrados, isNotEmpty);
    expect(registrados.first, startsWith('Falha ao limpar os relatórios'));
  });

  test('emCache sem conta nem token: semConta, sem itens', () async {
    final f = FonteFalsa(
      arquivos: [_arq('2026-11-26')],
      conteudos: {'id-2026-11-26': _doDia('2026-11-26')},
    );
    final disco = ArmazenamentoMemoria();
    await _local(f, disco).atualizar();
    final v = await _local(f, disco, conta: ContaFalsa()).emCache();
    expect(v.situacao, SituacaoRelatorios.semConta);
    expect(v.itens, isEmpty);
    // com o token (sessão ainda abrindo) o cache aparece
    final comToken = ContaFalsa()..token = true;
    expect(
      (await _local(f, disco, conta: comToken).emCache()).itens,
      hasLength(1),
    );
  });

  test('emCache mostra o que está guardado sem pedir nada', () async {
    final f = FonteFalsa(
      arquivos: [_arq('2026-11-25'), _arq('2026-11-26')],
      conteudos: {
        'id-2026-11-26': _doDia('2026-11-26'),
        'id-2026-11-25': _doDia('2026-11-25'),
      },
    );
    final disco = ArmazenamentoMemoria();
    expect((await _local(f, disco).emCache()).itens, isEmpty);
    await _local(f, disco).atualizar();
    final v = await _local(f, disco).emCache();
    expect(v.situacao, SituacaoRelatorios.ok);
    expect(v.itens.map((r) => r.data), ['2026-11-26', '2026-11-25']);
    expect((v.atual!.data, v.ehHoje), ('2026-11-26', true));
    expect(f.listagens, 1);
  });

  test('armazenamento cheio não derruba a visão', () async {
    final f = FonteFalsa(
      arquivos: [_arq('2026-11-25'), _arq('2026-11-26')],
      conteudos: {
        'id-2026-11-26': _doDia('2026-11-26'),
        'id-2026-11-25': _doDia('2026-11-25'),
      },
    );
    final local = _local(f, DiscoCheio());
    final v = await local.atualizar();
    expect(v.situacao, SituacaoRelatorios.ok);
    expect(v.itens.map((r) => r.data), ['2026-11-26', '2026-11-25']);
    expect(v.itens.first.termometro!.total, 22);
    expect(v.atual!.data, '2026-11-26');
    expect(registrados, isNotEmpty);
    final c = await local.emCache();
    expect(c.itens, hasLength(2));
    expect((await local.abrir(_nome('2026-11-25'))).data, '2026-11-25');
  });

  test('erro comum na listagem: cache com semConexao e log', () async {
    final f = FonteFalsa(arquivos: [_arq('2026-11-26')])
      ..erroListar = ErroGoogle('Backend falhou', 500);
    final v = await _local(f, ArmazenamentoMemoria()).atualizar();
    expect(v.situacao, SituacaoRelatorios.semConexao);
    expect(registrados.any((t) => t.contains('Backend falhou')), isTrue);
  });

  test('duas atualizações simultâneas listam uma vez', () async {
    final f = FonteFalsa(
      arquivos: [_arq('2026-11-26')],
      conteudos: {'id-2026-11-26': _doDia('2026-11-26')},
    );
    final local = _local(f, ArmazenamentoMemoria());
    final r = await Future.wait([local.atualizar(), local.atualizar()]);
    expect(f.listagens, 1);
    expect(f.downloads, 1);
    expect(identical(r[0], r[1]), isTrue);
    await local.atualizar();
    expect(f.listagens, 2);
  });

  test('limpar: o atualizar seguinte não recebe o da conta anterior', () async {
    final portoes = [Completer<void>(), Completer<void>()];
    final f = _FonteComPortoes(portoes)
      ..arquivos = [_arq('2026-11-26')]
      ..conteudos = {'id-2026-11-26': _doDia('2026-11-26')};
    final conta = ContaFalsa(email: 'ana@gmail.com');
    final disco = ArmazenamentoMemoria();
    final local = _local(f, disco, conta: conta);
    final antigo = local.atualizar();
    await pumpEventQueue();
    final limpo = local.limpar();
    conta.email = 'bia@gmail.com';
    final depois = local.atualizar();
    expect(identical(depois, antigo), isFalse);
    portoes[0].complete();
    await antigo;
    // o fim do pedido antigo não solta o novo
    expect(identical(local.atualizar(), depois), isTrue);
    portoes[1].complete();
    await limpo;
    expect((await depois).situacao, SituacaoRelatorios.ok);
    // o novo listou depois da limpeza
    expect(f.listagens, 2);
    expect(disco.existe(arquivoIndiceRelatorios), isTrue);
  });

  test('abrir durante uma atualização espera a vez e não se perde', () async {
    final f = FonteFalsa(
      arquivos: [_arq('2026-11-24'), _arq('2026-11-25')],
      conteudos: {
        'id-2026-11-24': _doDia('2026-11-24'),
        'id-2026-11-25': _doDia('2026-11-25'),
        'id-2026-11-26': _doDia('2026-11-26'),
      },
    );
    final disco = ArmazenamentoMemoria();
    final local = _local(f, disco, limite: 1);
    await local.atualizar();
    f.arquivos.add(_arq('2026-11-26'));
    final r = await Future.wait<Object>([
      local.atualizar(),
      local.abrir(_nome('2026-11-24')),
    ]);
    expect((r[1] as Relatorio).data, '2026-11-24');
    expect(_temConteudo(disco, '2026-11-24'), isTrue);
    expect(_temConteudo(disco, '2026-11-26'), isTrue);
    final j = jsonDecode(disco.ler(arquivoIndiceRelatorios)!) as Map;
    expect(j['aberto'], _nome('2026-11-24'));
    expect((j['arquivos'] as Map).keys, contains(_nome('2026-11-26')));
    // A atualização seguinte respeita o aberto.
    await local.atualizar();
    expect(_temConteudo(disco, '2026-11-24'), isTrue);
  });

  test('modifiedTime novo com falha no download mantém o antigo', () async {
    for (final erro in [
      ErroGoogle('Backend error', 503),
      ErroGoogle('Too many requests', 429),
      Offline('sem rede'),
    ]) {
      final f = FonteFalsa(
        arquivos: [_arq('2026-11-26')],
        conteudos: {'id-2026-11-26': _doDia('2026-11-26')},
      );
      final disco = ArmazenamentoMemoria();
      await _local(f, disco).atualizar();
      f.arquivos[0] = _arq(
        '2026-11-26',
        modificado: '2026-11-26T13:00:00.000Z',
      );
      f.conteudos['id-2026-11-26'] = erro;
      final v = await _local(f, disco).atualizar();
      expect(v.situacao, SituacaoRelatorios.semConexao, reason: '$erro');
      expect(v.itens.single.termometro!.total, 22);
      expect(v.atual!.data, '2026-11-26');
      expect(_temConteudo(disco, '2026-11-26'), isTrue);
      // A próxima atualização tenta de novo e troca pelo novo.
      f.conteudos['id-2026-11-26'] = _doDia('2026-11-26')
        ..['titulo'] = 'Versão nova';
      final v2 = await _local(f, disco).atualizar();
      expect(v2.situacao, SituacaoRelatorios.ok);
      expect(v2.atual!.titulo, 'Versão nova');
      expect(f.downloads, 3);
    }
  });

  test('abrir marca inválido e avisa com mensagem clara', () async {
    for (final erro in <Object>[
      RespostaInvalida('Resposta inválida do Google.', 200),
      const FormatException('x'),
      ErroGoogle('File not found', 404),
      <String, Object?>{},
    ]) {
      final f = FonteFalsa(
        arquivos: [_arq('2026-11-25'), _arq('2026-11-26')],
        conteudos: {
          'id-2026-11-26': _doDia('2026-11-26'),
          'id-2026-11-25': erro,
        },
      );
      final disco = ArmazenamentoMemoria();
      final local = _local(f, disco, limite: 1);
      await local.atualizar();
      await expectLater(
        local.abrir(_nome('2026-11-25')),
        throwsA(
          isA<ErroValidacao>().having(
            (e) => e.mensagem,
            'mensagem',
            textoRelatorioInvalido,
          ),
        ),
        reason: '$erro',
      );
      expect((_indice(disco)[_nome('2026-11-25')]! as Map)['invalido'], isTrue);
      final v = await local.atualizar();
      expect(v.itens.map((r) => r.data), ['2026-11-26']);
      expect(f.downloads, 2);
    }
  });

  test('a atualização só lê do disco o conteúdo do escolhido', () async {
    final datas = ['2026-11-23', '2026-11-24', '2026-11-25', '2026-11-26'];
    final f = FonteFalsa(
      arquivos: [for (final d in datas) _arq(d)],
      conteudos: {for (final d in datas) 'id-$d': _doDia(d)},
    );
    final disco = DiscoContado();
    await _local(f, disco).atualizar();
    disco.leituras.clear();
    final v = await _local(f, disco).atualizar();
    expect(v.atual!.data, '2026-11-26');
    expect(disco.leituras, ['relatorios/${_nome('2026-11-26')}']);
  });

  test('índice corrompido mas legível: entradas estranhas saem', () async {
    final disco = ArmazenamentoMemoria()
      ..gravar(
        arquivoIndiceRelatorios,
        jsonEncode({
          'versao': 1,
          'aberto': 5,
          'arquivos': {
            'x': 1,
            _nome('2026-11-23'): 'texto',
            _nome('2026-11-24'): {'id': 3, 'modificado': 'm'},
            _nome('2026-11-25'): {
              'id': 'id-2026-11-25',
              'modificado': '2026-11-26T12:00:00.000Z',
              'invalido': 'sim',
              'termometro': 'sete',
            },
            _nome('2026-11-26'): {
              'id': 'id-2026-11-26',
              'modificado': '2026-11-26T12:00:00.000Z',
              'invalido': false,
              'termometro': {'positiva': 'sete', 'mista': 2, 'neutra': null},
            },
          },
        }),
      );
    final f = FonteFalsa();
    final v = await _local(f, disco).emCache();
    expect(v.itens.map((r) => r.data), ['2026-11-26', '2026-11-25']);
    expect(v.itens.first.termometro!.total, 2);
    expect(v.itens.last.termometro, isNull);
    for (final outro in [
      '{"arquivos": {"x": 1}}',
      '{"arquivos": [1]}',
      '[1]',
    ]) {
      disco.gravar(arquivoIndiceRelatorios, outro);
      expect((await _local(f, disco).emCache()).itens, isEmpty, reason: outro);
    }
  });

  test('0, 1 e 60 ativos', () async {
    for (final n in [0, 1, 60]) {
      final f = FonteFalsa(
        arquivos: [_arq('2026-11-26')],
        conteudos: {'id-2026-11-26': fixtureComAtivos(n)},
      );
      final v = await _local(f, ArmazenamentoMemoria()).atualizar();
      expect(v.atual!.ativos.length, n, reason: '$n');
      expect(v.itens.single.termometro!.total, n);
    }
  });
}
