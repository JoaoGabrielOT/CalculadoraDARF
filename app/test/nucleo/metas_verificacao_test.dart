import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:calculadoradarf/nucleo/ambiente.dart';
import 'package:calculadoradarf/nucleo/armazenamento.dart';
import 'package:calculadoradarf/nucleo/datas.dart';
import 'package:calculadoradarf/nucleo/erros.dart';
import 'package:calculadoradarf/nucleo/fechamento.dart';
import 'package:calculadoradarf/nucleo/metas/descricao.dart';
import 'package:calculadoradarf/nucleo/metas/verificacao.dart';
import 'package:calculadoradarf/nucleo/modelos/barras.dart';
import 'package:calculadoradarf/nucleo/modelos/config.dart';
import 'package:calculadoradarf/nucleo/modelos/meta.dart';
import 'package:calculadoradarf/nucleo/repositorio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'apoio/referencias.dart';

Map<String, Object?> _mapa(Object? o) => o! as Map<String, Object?>;

Barra _barra(Map<String, Object?> b) {
  final d = DataHora.parse(b['dt']! as String);
  return Barra(
    ts: d.utc.millisecondsSinceEpoch ~/ 1000,
    dt: d,
    alta: (b['alta']! as num).toDouble(),
    baixa: (b['baixa'] as num?)?.toDouble(),
    abre: (b['abre'] as num?)?.toDouble(),
  );
}

Diarias _diarias(Map<String, Object?> d) => Diarias(
  barras: [
    for (final b
        in (d['barras']! as List<Object?>).cast<Map<String, Object?>>())
      BarraDiaria(
        data: b['data']! as String,
        abre: (b['abre']! as num).toDouble(),
        alta: (b['alta']! as num).toDouble(),
        baixa: (b['baixa']! as num).toDouble(),
        fech: (b['fech']! as num).toDouble(),
      ),
  ],
  hoje: d['hoje']! as String,
);

/// O erro equivalente ao do Python para cada tipo do roteiro.
Object _excecao(String tipo, String texto) => switch (tipo) {
  'sem_dados' => SemDados(texto),
  'limite' => LimiteConsultas(texto),
  'conexao' => ErroConexao(texto),
  'timeout' => TimeoutException(texto),
  'geral' => ErroValidacao(texto),
  _ => throw ArgumentError(tipo),
};

HistoricoIntradiario _resultado(Map<String, Object?> spec) {
  if (spec.containsKey('erro')) {
    throw _excecao(spec['erro']! as String, spec['texto']! as String);
  }
  final r = _mapa(spec['ok']);
  return HistoricoIntradiario(
    barras: [
      for (final b
          in (r['barras']! as List<Object?>).cast<Map<String, Object?>>())
        _barra(b),
    ],
    fonte: r['fonte']! as String,
    intervalo: r['intervalo']! as String,
    diarias: r['diarias'] == null ? null : _diarias(_mapa(r['diarias'])),
  );
}

List<String> _ids(List<Meta> metas) => [for (final m in metas) m.id];

Map<String, Object?> _relatorio(RelatorioMetas rel) => {
  'executadas': _ids(rel.executadas),
  'invalidas': _ids(rel.invalidas),
  'reconciliadas': _ids(rel.reconciliadas),
  'aguardando': _ids(rel.aguardando),
  'erros': _ids(rel.erros),
  'mudou': rel.mudou,
  'avisos': [...rel.avisos],
};

Map<String, Object?> _descricao(DescricaoMeta d) => {
  'titulo': d.titulo,
  'status': d.status,
  'detalhe': d.detalhe,
  'cor': d.cor,
  'erro': d.erro,
};

Future<Object?> _executar(
  Repositorio repo,
  Config cfg,
  Map<String, Object?> op,
  Map<String, List<List<String>>> chamadas,
) async {
  final historicos = _mapa(op['historicos'] ?? <String, Object?>{});
  final diariasOp = op['diarias'] == null ? null : _mapa(op['diarias']);
  final agora = op['agora'] == null
      ? null
      : DataHora.parse(op['agora']! as String);

  Future<HistoricoIntradiario> historico(String ticker, DataHora desde) async {
    chamadas['historico']!.add([ticker, desde.iso()]);
    return _resultado(_mapa(historicos[ticker]));
  }

  Future<Diarias> barrasDiarias(String ticker, String desde) async {
    chamadas['diarias']!.add([ticker, desde]);
    final spec = _mapa(diariasOp![ticker]);
    if (spec.containsKey('erro')) {
      throw _excecao(spec['erro']! as String, spec['texto']! as String);
    }
    return _diarias(spec);
  }

  switch (op['op']) {
    case 'verificar':
      final rel = await verificar(
        repo,
        cfg,
        historico,
        agora: agora,
        diarias: diariasOp == null ? null : barrasDiarias,
      );
      return rel == null ? null : _relatorio(rel);
    case 'aplicar':
      final prontos = <String, ResultadoHistorico>{
        for (final e in historicos.entries)
          e.key: _mapa(e.value).containsKey('erro_msg')
              ? HistoricoErro(_mapa(e.value)['erro_msg']! as String)
              : HistoricoOk(_resultado(_mapa(e.value))),
      };
      return _relatorio(
        aplicar(
          repo,
          cfg,
          prontos,
          agora: agora,
          diarias: diariasOp == null
              ? null
              : {
                  for (final e in diariasOp.entries)
                    e.key: _diarias(_mapa(e.value)),
                },
        ),
      );
    case 'preparar_fechamento':
      final res = await prepararFechamento(
        repo,
        cfg,
        op['mes']! as String,
        historico,
        agora: agora,
        diarias: diariasOp == null ? null : barrasDiarias,
      );
      return {
        'bloqueio': res.bloqueio,
        'executadas': _ids(res.executadas),
        'invalidas': _ids(res.invalidas),
      };
    case 'fechar_mes':
      final (r, prox) = fecharMes(repo, repo.carregar(op['mes']! as String));
      return {'prox': prox, 'darf': r.darf};
    case 'descricao':
      return {
        'com_todas': [
          for (final m in cfg.metas) _descricao(descricao(m, todas: cfg.metas)),
        ],
        'sem_todas': [for (final m in cfg.metas) _descricao(descricao(m))],
      };
    case 'mensagem_erro':
      return mensagemErro(
        _excecao(op['erro']! as String, op['texto']! as String),
      );
  }
  throw StateError('operação desconhecida: ${op['op']}');
}

void main() {
  tearDown(() => ambiente = Ambiente.sistema());

  test('referências geradas com Python 3.12', () {
    expect(versaoPythonDasReferencias('metas_verificacao'), startsWith('3.12'));
  });

  for (final caso in carregarCasos('metas_verificacao')) {
    test('roteiro: ${caso.nome}', () async {
      final entrada = _mapa(caso.entrada);
      final memoria = ArmazenamentoMemoria();
      for (final e in _mapa(entrada['arquivos']).entries) {
        memoria.gravar(e.key, jsonEncode(e.value));
      }
      final repo = Repositorio(memoria);
      final cfg = repo.lerConfig();
      final fixo = Ambiente.fixo();
      var agora = 0.0;
      ambiente = Ambiente(
        agora: () => agora,
        novoId: fixo.novoId,
        hoje: fixo.hoje,
        agoraBr: fixo.agoraBr,
      );
      final esperados = _mapa(caso.saida)['resultados']! as List<Object?>;
      final operacoes = entrada['operacoes']! as List<Object?>;
      for (final (i, bruta) in operacoes.indexed) {
        final op = _mapa(bruta);
        agora = (op['t']! as num).toDouble();
        final esperado = _mapa(esperados[i]);
        final caminho = '\$.resultados[$i]';
        final chamadas = {
          'historico': <List<String>>[],
          'diarias': <List<String>>[],
        };
        final retorno = await _executar(repo, cfg, op, chamadas);
        conferir(retorno, esperado['retorno'], caminho: '$caminho.retorno');
        conferir(chamadas, esperado['chamadas'], caminho: '$caminho.chamadas');
        // a descrição não altera nada, e o modelo tipado completa o status
        // ausente de uma meta ("ativa"), que o dicionário do Python não tem
        if (op['op'] != 'descricao') {
          conferir(
            jsonDecode(jsonEncode(cfg.toJson())),
            esperado['cfg'],
            caminho: '$caminho.cfg',
          );
        }
        final arquivos = _mapa(esperado['arquivos']);
        expect(
          memoria.listar().toSet(),
          arquivos.keys.toSet(),
          reason: '$caminho: arquivos',
        );
        for (final a in arquivos.entries) {
          conferir(
            jsonDecode(memoria.ler(a.key)!),
            a.value,
            caminho: '$caminho.${a.key}',
          );
        }
      }
    });
  }

  group('mensagemErro (tipos do Dart sem equivalente no Python)', () {
    test('SocketException vira sem conexão', () {
      expect(
        mensagemErro(const SocketException('Failed host lookup')),
        'Sem conexão com a internet.',
      );
    });

    test('LimiteConsultas e texto com Too Many viram o aviso do Yahoo', () {
      const aviso =
          'Limite de consultas do Yahoo atingido. Tente em alguns minutos.';
      expect(mensagemErro(LimiteConsultas('qualquer')), aviso);
      expect(mensagemErro(StateError('HTTP 429 Too Many Requests')), aviso);
    });

    test('erro desconhecido leva os 120 primeiros caracteres', () {
      expect(
        mensagemErro(ErroValidacao('é' * 130)),
        'Erro ao consultar o histórico: ${'é' * 120}',
      );
    });
  });

  group('trava da verificação', () {
    test('tentarIniciarVerificacao só vale uma vez até encerrar', () {
      expect(verificacaoEmAndamento, isFalse);
      expect(tentarIniciarVerificacao(), isTrue);
      expect(verificacaoEmAndamento, isTrue);
      expect(tentarIniciarVerificacao(), isFalse);
      encerrarVerificacao();
      expect(verificacaoEmAndamento, isFalse);
      expect(tentarIniciarVerificacao(), isTrue);
      encerrarVerificacao();
    });

    test('a trava é liberada quando o histórico lança exceção', () async {
      final memoria = ArmazenamentoMemoria();
      memoria.gravar(
        'config.json',
        jsonEncode({
          'metas': [
            {
              'id': 'meta-a',
              'ticker': 'PETR4',
              'tipo': 'Ação',
              'lote_id': 'L1',
              'qtd': 1,
              'preco_alvo': 20.0,
              'criada_em': '2026-10-20T11:00:00-03:00',
              'status': 'ativa',
            },
          ],
        }),
      );
      final repo = Repositorio(memoria);
      final cfg = repo.lerConfig();
      ambiente = Ambiente.fixo();
      final rel = await verificar(
        repo,
        cfg,
        (t, d) async => throw StateError('boom'),
      );
      expect(rel!.erros.length, 1);
      expect(verificacaoEmAndamento, isFalse);
      // erro que escapa de aplicar (data inválida na meta) também libera
      cfg.metas[0].criadaEm = 'lixo';
      await expectLater(
        verificar(repo, cfg, (t, d) async => throw StateError('x')),
        throwsA(isA<FormatException>()),
      );
      expect(verificacaoEmAndamento, isFalse);
    });
  });
}
