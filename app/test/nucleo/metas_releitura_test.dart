import 'package:calculadoradarf/nucleo/nucleo.dart';
import 'package:flutter_test/flutter_test.dart';

const _meta = <String, Object?>{
  'id': 'meta-a',
  'ticker': 'PETR4',
  'tipo': 'Ação',
  'lote_id': 'L1',
  'qtd': 100,
  'preco_alvo': 20.0,
  'status': 'ativa',
  'criada_em': '2026-10-20T11:00:00-03:00',
};

late ArmazenamentoMemoria disco;
late Repositorio repo;

/// Busca falsa que, antes de responder, adiciona `XPTO3` ao radar (o usuário
/// mexendo na config durante a consulta) e depois falha.
Future<HistoricoIntradiario> _busca(String ticker, DataHora desde) async {
  final cfg = repo.lerConfig();
  adicionarRadar(cfg, 'XPTO3');
  repo.gravarConfig(cfg);
  throw SemDados('Sem dados para $ticker.');
}

void main() {
  setUp(() {
    ambiente = Ambiente.fixo();
    disco = ArmazenamentoMemoria();
    repo = Repositorio(disco);
    repo.gravarConfig(Config(metas: [Meta.fromJson(_meta)]), carimbar: false);
  });

  tearDown(() => ambiente = Ambiente.sistema());

  group('releitura', () {
    test(
      'config alterada durante a busca do histórico sobrevive à aplicação',
      () async {
        await verificar(
          repo,
          repo.lerConfig(),
          _busca,
          releitura: repo.lerConfig,
        );
        final cfg = repo.lerConfig();
        expect(cfg.radar.map((r) => r.ticker), ['XPTO3']);
        expect(cfg.excluidos.containsKey('radar:XPTO3'), isFalse);
        expect(cfg.metas.single.ultimoErro, 'Sem dados para PETR4.');
      },
    );

    test(
      'sem releitura a config velha apaga a mudança (comportamento antigo)',
      () async {
        await verificar(repo, repo.lerConfig(), _busca);
        final cfg = repo.lerConfig();
        expect(cfg.radar, isEmpty);
        expect(cfg.excluidos.containsKey('radar:XPTO3'), isTrue);
      },
    );

    test('prepararFechamento também relê a config depois da busca', () async {
      repo.salvar(
        Mes(
          mes: '2026-10',
          lotes: [
            Lote(
              id: 'L1',
              ticker: 'PETR4',
              tipo: 'Ação',
              dataCompra: '2026-10-05',
              qtd: 100,
              preco: 10,
            ),
          ],
        ),
      );
      await prepararFechamento(
        repo,
        repo.lerConfig(),
        '2026-10',
        _busca,
        releitura: repo.lerConfig,
      );
      final cfg = repo.lerConfig();
      expect(cfg.radar.map((r) => r.ticker), ['XPTO3']);
      expect(cfg.excluidos.containsKey('radar:XPTO3'), isFalse);
    });
  });

  group('gravarConfig com config ilegível', () {
    final ilegiveis = <String, String>{
      'JSON inválido': '{',
      'raiz que não é objeto': '[1, 2]',
      'JSON cortado no meio': '{"radar": [',
      'campo com valor inválido': '{"metas": [{"id": "m", "qtd": 1.5}]}',
    };
    for (final MapEntry(key: nome, value: texto) in ilegiveis.entries) {
      for (final carimbar in [true, false]) {
        test('$nome (carimbar: $carimbar): lança e o arquivo fica intacto', () {
          disco.gravar('config.json', texto);
          expect(
            () => repo.gravarConfig(Config(), carimbar: carimbar),
            throwsA(
              isA<ErroValidacao>().having(
                (e) => e.mensagem,
                'mensagem',
                mensagemConfigIlegivel,
              ),
            ),
          );
          expect(disco.ler('config.json'), texto);
        });
      }
    }
  });
}
