// Apoio dos testes portados de tests/test_metas.py: `Base` (linhas 33-56) e as
// metas-base de `BASE_ALVO` e `BASE_STOP` (linhas 836-839).

import 'package:calculadoradarf/nucleo/ambiente.dart';
import 'package:calculadoradarf/nucleo/armazenamento.dart';
import 'package:calculadoradarf/nucleo/constantes.dart';
import 'package:calculadoradarf/nucleo/datas.dart';
import 'package:calculadoradarf/nucleo/metas/criacao.dart';
import 'package:calculadoradarf/nucleo/modelos/config.dart';
import 'package:calculadoradarf/nucleo/modelos/barras.dart';
import 'package:calculadoradarf/nucleo/modelos/lote.dart';
import 'package:calculadoradarf/nucleo/modelos/mes.dart';
import 'package:calculadoradarf/nucleo/modelos/meta.dart';
import 'package:calculadoradarf/nucleo/repositorio.dart';
import 'package:flutter_test/flutter_test.dart';

/// `BASE_ALVO`: JSON de uma meta de preço-alvo.
const Map<String, Object?> baseAlvo = {
  'id': 'meta-a',
  'ticker': 'PETR4',
  'tipo': 'Ação',
  'lote_id': 'L1',
  'qtd': 100,
  'preco_alvo': 20.0,
  'criada_em': '2026-10-20T11:00:00-03:00',
};

/// `BASE_STOP`: JSON de uma meta de stop móvel.
const Map<String, Object?> baseStop = {
  'id': 'meta-s',
  'ticker': 'PETR4',
  'tipo': 'Ação',
  'lote_id': 'L1',
  'qtd': 100,
  'gatilho': 'stop',
  'stop_inicial': 5.0,
  'stop_atual': 5.0,
  'movel': true,
  'niveis': <Object?>[],
  'criada_em': '2026-10-20T11:00:00-03:00',
};

/// `dt` (tests/test_metas.py:12): texto sem fuso vale Brasília.
DataHora dt(String texto) => DataHora.parse(texto);

/// `barra` (tests/test_metas.py:16-18): barra horária só com a máxima.
Barra barra(String texto, double alta) {
  final d = dt(texto);
  return Barra(ts: d.utc.millisecondsSinceEpoch ~/ 1000, dt: d, alta: alta);
}

/// `barra_s` (tests/test_metas.py:480-482): barra com máxima, mínima e
/// abertura.
Barra barraS(String texto, double alta, double? baixa, [double? abre]) {
  final d = dt(texto);
  return Barra(
    ts: d.utc.millisecondsSinceEpoch ~/ 1000,
    dt: d,
    alta: alta,
    baixa: baixa,
    abre: abre,
  );
}

/// `dia` (tests/test_metas.py:485-487): pregão diário; a abertura padrão é o
/// fechamento.
BarraDiaria dia(
  String texto,
  double alta,
  double baixa,
  double fech, [
  double? abre,
]) => BarraDiaria(
  data: texto,
  abre: abre ?? fech,
  alta: alta,
  baixa: baixa,
  fech: fech,
);

/// `Base.setUp`: relógio e ids congelados, armazenamento em memória, a
/// configuração padrão e o mês 2026-10 com o lote L1 (PETR4, 100 a R$ 10).
class BaseMetas {
  late Repositorio repo;
  late Config cfg;
  final DataHora criada = DataHora.parse('2026-10-20T11:00:00-03:00');

  /// Chamar no `setUp` do teste. Restaura a corretagem e o ambiente no
  /// tearDown (`Base.tearDown`).
  void preparar() {
    final corretagem = corretagemPorOrdem;
    addTearDown(() {
      corretagemPorOrdem = corretagem;
      ambiente = Ambiente.sistema();
    });
    ambiente = Ambiente.fixo();
    repo = Repositorio(ArmazenamentoMemoria());
    cfg = repo.lerConfig();
    final d = mesVazio('2026-10');
    d.lotes.add(
      Lote(
        id: 'L1',
        ticker: 'PETR4',
        tipo: 'Ação',
        dataCompra: '2026-10-01',
        qtd: 100,
        preco: 10.0,
      ),
    );
    repo.salvar(d);
  }

  /// `Base.criar`: meta de alvo sobre o L1, com lucro desejado de R$ 1000.
  Meta criar({int qtd = 100, double alvo = 21.78}) =>
      criarMeta(repo, cfg, 'L1', qtd, alvo, lucroDesejado: 1000, agora: criada);

  /// `Base.lote`: o lote gravado no mês.
  Lote lote({String mes = '2026-10', String lid = 'L1'}) =>
      repo.carregar(mes).lotes.firstWhere((l) => l.id == lid);
}
