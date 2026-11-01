import 'package:calculadoradarf/nucleo/ambiente.dart';
import 'package:calculadoradarf/nucleo/armazenamento.dart';
import 'package:calculadoradarf/nucleo/metas/cadeia.dart';
import 'package:calculadoradarf/nucleo/metas/criacao.dart';
import 'package:calculadoradarf/nucleo/metas/descricao.dart';
import 'package:calculadoradarf/nucleo/metas/verificacao.dart';
import 'package:calculadoradarf/nucleo/modelos/config.dart';
import 'package:calculadoradarf/nucleo/modelos/lote.dart';
import 'package:calculadoradarf/nucleo/modelos/mes.dart';
import 'package:calculadoradarf/nucleo/planilha/montagem.dart';
import 'package:calculadoradarf/nucleo/repositorio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'apoio/base_metas.dart';

/// Meta gravada sem a chave `status` (o Python a trata como "ativa" só na
/// descrição e na planilha; `metas_ativas` exige `status == "ativa"`).
Config _configSemStatus() => Config.fromJson({
  'metas': [Map<String, Object?>.of(baseAlvo)],
});

void main() {
  tearDown(() => ambiente = Ambiente.sistema());

  test('meta sem status não é ativa, não reserva e não é reescrita', () {
    final cfg = _configSemStatus();
    final meta = cfg.metas.single;
    expect(meta.status, isNull);
    expect(meta.statusOuAtiva, 'ativa');
    expect(metasAtivas(cfg), isEmpty);
    final m = Mes(mes: '2026-10');
    m.lotes.add(
      Lote(
        id: 'L1',
        ticker: 'PETR4',
        tipo: 'Ação',
        dataCompra: '2026-10-01',
        qtd: 100,
        preco: 10.0,
      ),
    );
    final repo = Repositorio(ArmazenamentoMemoria())..salvar(m);
    expect(reservado(repo, cfg, 'L1'), 0);
    expect(meta.toJson().containsKey('status'), isFalse);
    expect(meta.copiar().status, isNull);
  });

  test('aplicar e verificar não executam meta sem status', () async {
    ambiente = Ambiente.fixo(agora: 1761000000.123);
    final cfg = _configSemStatus();
    final m = Mes(mes: '2026-10');
    m.lotes.add(
      Lote(
        id: 'L1',
        ticker: 'PETR4',
        tipo: 'Ação',
        dataCompra: '2026-10-01',
        qtd: 100,
        preco: 10.0,
      ),
    );
    final memoria = ArmazenamentoMemoria();
    final repo = Repositorio(memoria)..salvar(m);
    final rel = await verificar(repo, cfg, (t, d) async {
      fail('não deve buscar histórico');
    });
    expect(rel, isNull);
    final r2 = aplicar(repo, cfg, {});
    expect(r2.executadas, isEmpty);
    expect(repo.carregar('2026-10').lotes.single.vendas, isEmpty);
    expect(cfg.metas.single.status, isNull);
  });

  test('descrição e planilha mostram a meta sem status como ativa', () {
    final meta = _configSemStatus().metas.single;
    expect(descricao(meta).status, 'Ativa');
    expect(linhaMeta(meta)[8], 'ativa');
  });

  test('cancelarMeta recusa meta sem status (só ativas, status bruto)', () {
    final cfg = _configSemStatus();
    final repo = Repositorio(ArmazenamentoMemoria());
    expect(
      () => cancelarMeta(repo, cfg, 'meta-a'),
      throwsA(
        predicate(
          (e) => e.toString() == 'Só metas ativas podem ser canceladas.',
        ),
      ),
    );
  });
}
