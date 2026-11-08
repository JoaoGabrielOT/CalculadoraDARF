import 'package:calculadoradarf/nucleo/ambiente.dart';
import 'package:calculadoradarf/nucleo/apuracao.dart';
import 'package:calculadoradarf/nucleo/armazenamento.dart';
import 'package:calculadoradarf/nucleo/migracoes.dart';
import 'package:calculadoradarf/nucleo/modelos/config.dart';
import 'package:calculadoradarf/nucleo/modelos/mes.dart';
import 'package:calculadoradarf/nucleo/planilha/montagem.dart';
import 'package:calculadoradarf/nucleo/repositorio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'apoio/base_2_0.dart';

/// Armazenamento em memória que registra as gravações em [ordem].
class _Registrado extends ArmazenamentoMemoria {
  _Registrado(this.ordem);

  final List<String> ordem;

  @override
  void gravar(String nome, String conteudo) {
    ordem.add('gravar $nome');
    super.gravar(nome, conteudo);
  }
}

const _fechados = ['2025-12', '2026-01', '2026-02', '2026-03'];

late List<String> ordem;
late ArmazenamentoMemoria disco;
late Repositorio repo;

Map<String, String> _arquivos() => {
  for (final n in disco.listar()) n: disco.ler(n)!,
};

/// Linhas do Resumo por mês (MM/AAAA), só as 13 colunas da 2.0.
Map<String, List<Object?>> _resumo() => {
  for (final l in montarLinhas(
    repo.carregarMeses().values.toList(),
    repo.lerConfig(),
  )['Resumo']!)
    '${l[0]}': l.sublist(0, 13),
};

Future<ResultadoMigracaoDados> _migrar({
  String Function()? backup,
  Future<bool> Function()? sincronizar,
}) => migrarCustoMedio(
  repo,
  fazerBackup:
      backup ??
      () {
        ordem.add('backup');
        return 'backup/pre';
      },
  sincronizar:
      sincronizar ??
      () async {
        ordem.add('sincronizar');
        return true;
      },
);

void main() {
  setUp(() {
    ambiente = Ambiente.fixo(hoje: '2026-05-06', agora: 1770000000.5);
    ordem = [];
    disco = _Registrado(ordem);
    repo = Repositorio(disco);
    montarBase20(repo);
    ordem.clear();
  });

  tearDown(() => ambiente = Ambiente.sistema());

  test('base 2.0 é representativa e não tem marcador', () {
    for (final t in _arquivos().values) {
      expect(t.contains('metodo'), isFalse);
      expect(t.contains('posicao_inicial'), isFalse);
    }
    for (final m in _fechados) {
      expect(repo.carregar(m).fechado, isTrue, reason: m);
      expect(repo.carregar(m).resumo, isNotNull, reason: m);
    }
    expect(repo.carregar('2025-12').retroativo, isTrue);
    expect(repo.carregar('2026-02').resumo!.isento, isTrue);
    final darfMar = repo.carregar('2026-03').resumo!.darf;
    expect(darfMar, greaterThan(0));
    expect(darfMar, lessThan(10));
    final abr = repo.carregar('2026-04');
    expect(abr.fechado, isFalse);
    expect(abr.darfAnterior, closeTo(darfMar, 1e-9));
    expect(abr.lotes.firstWhere((l) => l.ticker == 'TAEE11').qtd, 200);
    expect(repo.mesInicial(), '2026-04');
    expect(repo.lerConfig().migracoes, isEmpty);
  });

  test('migração de base antiga', () async {
    final antes = _arquivos();
    final resumoAntes = _resumo();
    final lotesAbrAntes = repo.carregar('2026-04').toJson()['lotes'];
    final modAbr = repo.carregar('2026-04').mod;
    final modMai = repo.carregar('2026-05').mod;
    ambiente = Ambiente.fixo(hoje: '2026-05-06', agora: 1780000000.5);

    final r = await _migrar();

    expect(r.aplicada, isTrue);
    expect(r.corte, '2026-04');
    expect(r.erro, isNull);
    expect(r.sincronizou, isTrue);
    expect(r.pulados, isEmpty);
    // backup antes de qualquer gravação, sincronização antes de marcar
    expect(ordem.first, 'backup');
    expect(ordem[1], 'sincronizar');
    expect(ordem.skip(2).every((x) => x.startsWith('gravar ')), isTrue);
    expect(ordem.skip(2), isNotEmpty);

    // meses fechados idênticos, byte a byte, e as linhas Resumo deles
    final depois = _arquivos();
    for (final m in _fechados) {
      expect(depois['$m.json'], antes['$m.json'], reason: m);
    }
    final resumoDepois = _resumo();
    for (final m in ['12/2025', '01/2026', '02/2026', '03/2026']) {
      expect(resumoDepois[m], resumoAntes[m], reason: m);
    }

    // abril: marcado, posição derivada da qtd levada, lotes intactos
    final abr = repo.carregar('2026-04');
    expect(abr.metodo, metodoCustoMedio);
    expect(abr.posicaoInicial!['VALE3']!.qtd, 1000);
    expect(abr.posicaoInicial!['VALE3']!.custo, closeTo(50015.00, 1e-9));
    expect(abr.posicaoInicial!['TAEE11']!.qtd, 200);
    expect(abr.prejuizoAnterior!.toJson(), {'comum': 0.0, 'day_trade': 0.0});
    expect(abr.toJson()['lotes'], lotesAbrAntes);
    // marcador sem carimbo: não vence pelo mod um mês fechado em outro
    // aparelho
    expect(abr.mod, modAbr);
    expect(repo.carregar('2026-05').mod, modMai);
    final a = apurar(abr);
    expect(a.metodo, metodoCustoMedio);
    expect(a.ops.single.resultadoFiscal, closeTo(4983.50, 1e-9));
    expect(a.impSt, closeTo(747.525, 1e-9));
    expect(a.irrf, closeTo(1.50, 1e-9));
    expect(a.inconsistentes, isEmpty);

    // maio, aberto depois do corte, também marcado
    expect(repo.carregar('2026-05').metodo, metodoCustoMedio);

    expect(repo.lerConfig().migracoes, ['2.1-custo-medio']);
    expect(repo.lerConfig().migracoes, [idMigracaoCustoMedio]);
  });

  test('rodar de novo não muda nada', () async {
    await _migrar();
    final antes = _arquivos();
    ordem.clear();
    final r = await _migrar();
    expect(r.aplicada, isFalse);
    expect(r.erro, isNull);
    expect(ordem, isEmpty); // nem backup, nem sincronização, nem gravação
    expect(_arquivos(), antes);
  });

  test('backup que falha impede a migração', () async {
    final antes = _arquivos();
    final r = await _migrar(backup: () => throw Exception('disco cheio'));
    expect(r.aplicada, isFalse);
    expect(r.erro, contains('disco cheio'));
    expect(ordem, isEmpty); // nem sincronização, nem gravação
    expect(_arquivos(), antes);
    for (final m in repo.listarMeses()) {
      expect(repo.carregar(m).metodo, isNull, reason: m);
    }
    expect(repo.lerConfig().migracoes, isEmpty);
  });

  test('sem rede usa os dados locais', () async {
    final r = await _migrar(
      // como em produção: a rodada falha (offline) sem lançar
      sincronizar: () async => false,
    );
    expect(r.aplicada, isTrue);
    expect(r.sincronizou, isFalse);
    expect(r.corte, '2026-04');
    expect(repo.carregar('2026-04').metodo, metodoCustoMedio);
    expect(repo.lerConfig().migracoes, [idMigracaoCustoMedio]);
  });

  test('mês já marcado (outro aparelho) fica como está', () async {
    final abr = repo.carregar('2026-04')
      ..metodo = metodoCustoMedio
      ..posicaoInicial = {'VALE3': PosicaoFiscal(qtd: 1000, custo: 50015.0)}
      ..prejuizoAnterior = PrejuizoAcumulado(comum: 12.5);
    repo.salvar(abr);
    final antes = disco.ler('2026-04.json');
    final r = await _migrar();
    expect(r.aplicada, isTrue);
    expect(disco.ler('2026-04.json'), antes);
    expect(repo.carregar('2026-05').metodo, metodoCustoMedio);
  });

  test('mês ilegível é pulado e os legíveis são marcados', () async {
    const ilegivel = '{"mes": "2026-02", "lotes": [{"qtd": 1.5}]}';
    disco.gravar('2026-02.json', ilegivel);
    final r = await _migrar();
    expect(r.aplicada, isTrue);
    expect(r.corte, '2026-04');
    expect(r.pulados, ['2026-02']);
    expect(disco.ler('2026-02.json'), ilegivel);
    expect(repo.carregar('2026-04').metodo, metodoCustoMedio);
    expect(repo.lerConfig().migracoes, [idMigracaoCustoMedio]);
    expect(
      textoMesesIlegiveis(r.pulados),
      'Estes meses não puderam ser lidos e ficaram fora da ativação do '
      'cálculo por custo médio: 02/2026. Confira esses arquivos.',
    );
  });

  test('primeiro mês aberto ilegível: o corte é o próximo legível', () async {
    disco.gravar('2026-04.json', '{"mes": "2026-04", "lotes": [{"qtd": 1.5}]}');
    final r = await _migrar();
    expect(r.corte, '2026-05');
    expect(r.pulados, ['2026-04']);
    expect(repo.carregar('2026-05').metodo, metodoCustoMedio);
  });

  test('instalação nova: nada criado, nenhum backup, não registra', () async {
    disco = _Registrado(ordem);
    repo = Repositorio(disco);
    final r = await _migrar();
    expect(r.aplicada, isFalse);
    expect(ordem, isEmpty);
    expect(disco.listar(), isEmpty);
    expect(migracaoCustoMedioPendente(repo), isFalse);
  });

  test(
    'sem mês aberto com arquivo: não cria o mês de hoje nem registra',
    () async {
      disco = _Registrado(ordem);
      repo = Repositorio(disco);
      repo.salvar(Mes(mes: '2026-03', fechado: true));
      ordem.clear();
      final r = await _migrar();
      expect(r.aplicada, isFalse);
      expect(r.corte, isNull);
      expect(repo.listarMeses(), ['2026-03']);
      expect(ordem.where((x) => x.startsWith('gravar ')), isEmpty);
      expect(repo.lerConfig().migracoes, isEmpty);
      expect(migracaoCustoMedioPendente(repo), isTrue);
    },
  );

  test('migracoes preserva as outras chaves da config', () async {
    final cfg = repo.lerConfig()..extras['tema_visual'] = 'terminal';
    repo.gravarConfig(cfg);
    await _migrar();
    final lida = repo.lerConfig();
    expect(lida.extras['tema_visual'], 'terminal');
    expect(lida.migracoes, [idMigracaoCustoMedio]);
    expect(Config.fromJson(lida.toJson()).migracoes, [idMigracaoCustoMedio]);
  });
}
