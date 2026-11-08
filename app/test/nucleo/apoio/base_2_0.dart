// Base de dados de um usuário da 2.0 (antes da migração 2.1-custo-medio):
// lotes e vendas no formato JSON de `test/referencias`, meses fechados pelo
// fluxo do app sem marcador (método por compra, como na 2.0).
//
// - 2025-12: mês retroativo (venda antiga de TAEE11 registrada em abril).
// - 2026-01, fechado: VALE3 1.000 @ 50,00 levada até abril; duas compras de
//   ITUB4 com venda parcial; PETR4 swing e day trade; BDR AAPL34 parcial.
// - 2026-02, fechado: isento com perda (WEGE3), venda automática
//   `auto-m1` da cópia de AAPL34, venda parcial da cópia de ITUB4.
// - 2026-03, fechado: BDR com DARF abaixo de R$ 10, levada para abril.
// - 2026-04, aberto: cópia VALE3 vendida 500 @ 60,00 em 04-20, cópia de
//   ITUB4, compra antiga de TAEE11 já reduzida pela venda retroativa.
// - 2026-05, aberto: uma compra (aberto depois do primeiro mês aberto).

import 'package:calculadoradarf/nucleo/fechamento.dart';
import 'package:calculadoradarf/nucleo/modelos/config.dart';
import 'package:calculadoradarf/nucleo/modelos/lote.dart';
import 'package:calculadoradarf/nucleo/repositorio.dart';

Map<String, Object?> _lote(
  String id,
  String ticker,
  String tipo,
  String data,
  int qtd,
  double preco, [
  List<Map<String, Object?>> vendas = const [],
]) => {
  'id': id,
  'ticker': ticker,
  'tipo': tipo,
  'data_compra': data,
  'qtd': qtd,
  'preco': preco,
  'vendas': vendas,
  'mod': 50.5,
};

Map<String, Object?> _venda(String id, String data, int qtd, double preco) => {
  'id': id,
  'data': data,
  'qtd': qtd,
  'preco': preco,
  'mod': 50.5,
};

/// Acrescenta [lotes] e as [vendas] (por id de lote) ao mês e grava.
void _acrescentar(
  Repositorio repo,
  String mes, {
  List<Map<String, Object?>> lotes = const [],
  Map<String, List<Map<String, Object?>>> vendas = const {},
}) {
  final d = repo.carregar(mes);
  for (final l in d.lotes) {
    for (final v in vendas[l.id] ?? const <Map<String, Object?>>[]) {
      l.vendas.add(Venda.fromJson(v));
    }
  }
  d.lotes.addAll(lotes.map(Lote.fromJson));
  repo.salvar(d);
}

/// Grava em [repo] a base da 2.0 descrita no topo do arquivo. Usa o
/// `ambiente` atual (relógio e ids).
void montarBase20(Repositorio repo) {
  repo.gravarConfig(Config());
  _acrescentar(
    repo,
    '2026-01',
    lotes: [
      _lote('v1', 'VALE3', 'Ação', '2026-01-15', 1000, 50.0),
      _lote('i1', 'ITUB4', 'Ação', '2026-01-05', 300, 30.0, [
        _venda('vi1', '2026-01-20', 300, 35.0),
      ]),
      _lote('i2', 'ITUB4', 'Ação', '2026-01-12', 200, 32.0, [
        _venda('vi2', '2026-01-20', 100, 35.0),
      ]),
      _lote('p1', 'PETR4', 'Ação', '2026-01-06', 800, 30.0, [
        _venda('vp1', '2026-01-27', 800, 33.0),
      ]),
      _lote('d1', 'PETR4', 'Ação', '2026-01-22', 200, 31.0, [
        _venda('vd1', '2026-01-22', 200, 31.8),
      ]),
      _lote('a1', 'AAPL34', 'BDR', '2026-01-08', 100, 40.0, [
        _venda('va1', '2026-01-28', 50, 45.0),
      ]),
    ],
  );
  fecharMes(repo, repo.carregar('2026-01'));

  _acrescentar(
    repo,
    '2026-02',
    lotes: [
      _lote('w1', 'WEGE3', 'Ação', '2026-02-03', 300, 40.0, [
        _venda('vw1', '2026-02-18', 300, 35.0),
      ]),
    ],
    vendas: {
      'a1~2026-02': [_venda('auto-m1', '2026-02-10', 50, 44.0)],
      'i2~2026-02': [_venda('vi3', '2026-02-20', 40, 33.0)],
    },
  );
  fecharMes(repo, repo.carregar('2026-02'));

  _acrescentar(
    repo,
    '2026-03',
    lotes: [
      _lote('t1', 'T1TW34', 'BDR', '2026-03-02', 30, 9.5, [
        _venda('vt1', '2026-03-10', 30, 10.5),
      ]),
    ],
  );
  fecharMes(repo, repo.carregar('2026-03'));

  _acrescentar(
    repo,
    '2026-04',
    lotes: [_lote('e1', 'TAEE11', 'Ação', '2025-10-01', 300, 35.0)],
    vendas: {
      'v1~2026-02~2026-03~2026-04': [_venda('vv1', '2026-04-20', 500, 60.0)],
    },
  );
  registrarVendaRetroativa(repo, repo.carregar('2026-04'), 'e1', (
    data: '2025-12-15',
    qtd: 100,
    preco: 38.0,
  ));

  _acrescentar(
    repo,
    '2026-05',
    lotes: [_lote('b1', 'BBAS3', 'Ação', '2026-05-05', 100, 25.0)],
  );
}
