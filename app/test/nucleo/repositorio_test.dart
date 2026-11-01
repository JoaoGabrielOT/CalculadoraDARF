import 'dart:convert';
import 'dart:io';

import 'package:calculadoradarf/nucleo/ambiente.dart';
import 'package:calculadoradarf/nucleo/armazenamento.dart';
import 'package:calculadoradarf/nucleo/armazenamento_arquivos.dart';
import 'package:calculadoradarf/nucleo/erros.dart';
import 'package:calculadoradarf/nucleo/modelos/config.dart';
import 'package:calculadoradarf/nucleo/planilha/sincronizacao.dart';
import 'package:calculadoradarf/nucleo/modelos/lote.dart';
import 'package:calculadoradarf/nucleo/modelos/mes.dart';
import 'package:calculadoradarf/nucleo/repositorio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'apoio/referencias.dart';

Map<String, Object?> _mapa(Object? o) => o! as Map<String, Object?>;

/// Executa uma operação do roteiro; devolve o resultado como JSON.
Object? _executar(Repositorio repo, Map<String, Object?> op) {
  switch (op['op']) {
    case 'salvar':
      repo.salvar(
        Mes.fromJson(_mapa(op['dados'])),
        carimbar: op['carimbar']! as bool,
      );
      return null;
    case 'gravar_config':
      repo.gravarConfig(
        Config.fromJson(_mapa(op['dados'])),
        carimbar: op['carimbar']! as bool,
      );
      return null;
    case 'carregar':
      return repo.carregar(op['mes']! as String).toJson();
    case 'ler_config':
      return repo.lerConfig().toJson();
    case 'listar_meses':
      return repo.listarMeses();
    case 'mes_inicial':
      return repo.mesInicial();
  }
  throw StateError('operação desconhecida: ${op['op']}');
}

void main() {
  tearDown(() => ambiente = Ambiente.sistema());

  test('referências geradas com Python 3.12', () {
    expect(versaoPythonDasReferencias('repositorio'), startsWith('3.12'));
  });

  for (final caso in carregarCasos('repositorio')) {
    test('roteiro: ${caso.nome}', () {
      final entrada = _mapa(caso.entrada);
      final saida = _mapa(caso.saida);
      final memoria = ArmazenamentoMemoria();
      for (final e in _mapa(entrada['arquivos']).entries) {
        memoria.gravar(e.key, jsonEncode(e.value));
      }
      final repo = Repositorio(memoria);
      final esperados = saida['resultados']! as List<Object?>;
      final operacoes = entrada['operacoes']! as List<Object?>;
      for (final (i, bruta) in operacoes.indexed) {
        final op = _mapa(bruta);
        ambiente = Ambiente.fixo(agora: (op['agora']! as num).toDouble());
        final resultado = _executar(repo, op);
        final esperado = esperados[i];
        // mes_vazio do Python não tem `mod`; o modelo sempre tem (0).
        if (resultado is Map<String, Object?> &&
            esperado is Map &&
            !esperado.containsKey('mod') &&
            resultado['mod'] == 0) {
          resultado.remove('mod');
        }
        conferir(
          resultado,
          esperado,
          caminho:
              r'$.resultados['
              '$i]',
        );
      }
      final arquivos = _mapa(saida['arquivos']);
      expect(memoria.listar().toSet(), arquivos.keys.toSet());
      for (final e in arquivos.entries) {
        conferir(jsonDecode(memoria.ler(e.key)!), e.value, caminho: e.key);
      }
    });
  }

  group('ArmazenamentoMemoria', () {
    test('ler, gravar, existe, listar e apagar', () {
      final m = ArmazenamentoMemoria();
      expect(m.ler('a.json'), isNull);
      expect(m.existe('a.json'), isFalse);
      m.gravar('a.json', '1');
      m.gravar('a.json', '22');
      m.gravar('b.json', '3');
      expect(m.ler('a.json'), '22');
      expect(m.existe('a.json'), isTrue);
      expect(m.listar(), ['a.json', 'b.json']);
      m.apagar('a.json');
      m.apagar('nao-existe.json');
      expect(m.listar(), ['b.json']);
    });
  });

  group('Repositorio', () {
    test('mês e config com NaN/Infinity são lidos e regravados iguais', () {
      const mes =
          '{"mes": "2026-10", "fechado": false, "darf_anterior": Infinity, '
          '"lotes": [{"id": "a", "ticker": "X", "tipo": "Ação", '
          '"data_compra": "2026-10-01", "qtd": 1, "preco": NaN, '
          '"vendas": [], "mod": 0}], "excluidos": {}}';
      const cfg = '{"radar": [], "excluidos": {"k": -Infinity}}';
      final m = ArmazenamentoMemoria()
        ..gravar('2026-10.json', mes)
        ..gravar('config.json', cfg);
      final repo = Repositorio(m);
      final d = repo.carregar('2026-10');
      expect(d.darfAnterior, double.infinity);
      expect(d.lotes.single.preco.isNaN, isTrue);
      expect(repo.mesInicial(), '2026-10');
      expect(repo.carregarMeses().keys, ['2026-10']);
      repo.salvar(d, carimbar: false);
      expect(m.ler('2026-10.json'), contains('"darf_anterior": Infinity'));
      expect(m.ler('2026-10.json'), contains('"preco": NaN'));
      final c = repo.lerConfig();
      expect(c.excluidos['k'], double.negativeInfinity);
      repo.gravarConfig(c, carimbar: false);
      expect(m.ler('config.json'), contains('-Infinity'));
    });

    test('sincronização com Preço "nan" não deixa o mês ilegível', () {
      ambiente = Ambiente.fixo(agora: 100.5);
      final m = ArmazenamentoMemoria();
      final repo = Repositorio(m);
      final cfg = repo.lerConfig();
      final r = sincronizarLinhas(repo, cfg, {
        'Compras': [
          [
            '10/2026',
            'PETR4',
            'Ação',
            46000,
            10,
            'nan',
            '',
            0,
            10,
            '',
            'c1',
            '',
            5,
          ],
        ],
      });
      expect(r.mudou, isTrue);
      final d = repo.carregar('2026-10');
      expect(d.lotes.single.id, 'c1');
      expect(d.lotes.single.preco.isNaN, isTrue);
      // relê o que foi gravado (com NaN), em todos os caminhos de leitura
      expect(repo.mesInicial(), '2026-10');
      expect(repo.carregarMeses().keys, ['2026-10']);
      final r2 = sincronizarLinhas(repo, repo.lerConfig(), {});
      expect(r2.linhas['Compras'], isNotEmpty);
    });

    test('JSON inválido no config.json é lido como padrão, mas gravarConfig '
        'recusa e não sobrescreve (decisão do app: nunca trocar a config '
        'do usuário pelo padrão)', () {
      final m = ArmazenamentoMemoria()..gravar('config.json', '{quebrado');
      final repo = Repositorio(m);
      expect(repo.lerConfig().toJson(), Config().toJson());
      final cfg = repo.lerConfig()
        ..radar.add(ItemRadar(ticker: 'PETR4', desde: '2026-10-28'));
      expect(() => repo.gravarConfig(cfg), throwsA(isA<ErroValidacao>()));
      expect(m.ler('config.json'), '{quebrado');
    });

    test('config sem arquivo: existeMes e carregar de mês ausente', () {
      final repo = Repositorio(ArmazenamentoMemoria());
      expect(repo.existeMes('2026-10'), isFalse);
      final d = repo.carregar('2026-10');
      expect(d.mes, '2026-10');
      expect(d.lotes, isEmpty);
      expect(d.fechado, isFalse);
      expect(repo.listarMeses(), isEmpty);
      repo.salvar(d);
      expect(repo.existeMes('2026-10'), isTrue);
    });

    test('carregarMeses devolve os meses em ordem', () {
      final repo = Repositorio(ArmazenamentoMemoria());
      for (final m in ['2026-10', '2026-08', '2026-09']) {
        repo.salvar(mesVazio(m));
      }
      expect(repo.carregarMeses().keys.toList(), [
        '2026-08',
        '2026-09',
        '2026-10',
      ]);
    });

    test('salvar com carimbo deixa o arquivo igual ao objeto em memória', () {
      ambiente = Ambiente.fixo(agora: 77.25);
      final m = ArmazenamentoMemoria();
      final repo = Repositorio(m);
      final d = mesVazio('2026-10')
        ..lotes.add(
          Lote(
            id: 'l1',
            ticker: 'PETR4',
            tipo: 'Ação',
            dataCompra: '2026-10-02',
            qtd: 10,
            preco: 30.5,
          ),
        );
      repo.salvar(d);
      expect(d.mod, 77.25);
      expect(d.lotes.single.mod, 77.25);
      conferir(jsonDecode(m.ler('2026-10.json')!), d.toJson());
    });
  });

  group('ArmazenamentoArquivos', () {
    late Directory pasta;
    setUp(() => pasta = Directory.systemTemp.createTempSync('repo_test_'));
    tearDown(() => pasta.deleteSync(recursive: true));

    test('grava em UTF-8 e substitui o arquivo inteiro', () {
      final a = ArmazenamentoArquivos(pasta.path);
      a.gravar('config.json', '{"nome": "Itaú Unibanco ção 😀", "x": 1}');
      final arquivo = File('${pasta.path}${Platform.pathSeparator}config.json');
      expect(
        arquivo.readAsBytesSync().take(3).toList(),
        isNot([0xEF, 0xBB, 0xBF]),
        reason: 'sem BOM',
      );
      expect(
        utf8.decode(arquivo.readAsBytesSync()),
        '{"nome": "Itaú Unibanco ção 😀", "x": 1}',
      );
      a.gravar('config.json', '{}');
      expect(utf8.decode(arquivo.readAsBytesSync()), '{}');
      expect(a.ler('config.json'), '{}');
      // nenhum .tmp sobra e só arquivos aparecem na listagem
      Directory('${pasta.path}${Platform.pathSeparator}sub').createSync();
      expect(a.listar(), ['config.json']);
    });

    test('ler, existe e apagar', () {
      final a = ArmazenamentoArquivos(pasta.path);
      expect(a.ler('2026-10.json'), isNull);
      expect(a.existe('2026-10.json'), isFalse);
      a.gravar('2026-10.json', 'ç');
      expect(a.ler('2026-10.json'), 'ç');
      expect(a.existe('2026-10.json'), isTrue);
      a.apagar('2026-10.json');
      a.apagar('2026-10.json');
      expect(a.existe('2026-10.json'), isFalse);
    });

    test('cria a pasta que ainda não existe ao gravar', () {
      final nova =
          '${pasta.path}${Platform.pathSeparator}a${Platform.pathSeparator}b';
      final a = ArmazenamentoArquivos(nova);
      expect(a.listar(), isEmpty);
      a.gravar('x.json', '1');
      expect(a.ler('x.json'), '1');
    });

    test('Repositorio funciona sobre arquivos reais', () {
      ambiente = Ambiente.fixo(agora: 5.5);
      final repo = Repositorio(ArmazenamentoArquivos(pasta.path));
      repo.salvar(mesVazio('2026-10'));
      repo.gravarConfig(Config());
      expect(repo.listarMeses(), ['2026-10']);
      expect(repo.carregar('2026-10').mod, 5.5);
      expect(repo.lerConfig().tema, 'Dark');
    });
  });
}

class ItemRadarParaTeste {
  static ItemRadar novo(String ticker) =>
      ItemRadar(ticker: ticker, desde: '2026-10-28');
}
