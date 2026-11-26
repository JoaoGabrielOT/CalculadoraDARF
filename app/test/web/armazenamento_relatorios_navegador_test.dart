@TestOn('browser')
library;

import 'package:calculadoradarf/app/web/chave_valor_navegador.dart';
import 'package:calculadoradarf/nucleo/armazenamento_chave_valor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web/web.dart' as web;

void limpar() {
  final chaves = [
    for (var i = 0; i < web.window.localStorage.length; i++)
      web.window.localStorage.key(i)!,
  ];
  for (final c in chaves.where((c) => c.startsWith('darf:'))) {
    web.window.localStorage.removeItem(c);
  }
}

void main() {
  setUp(limpar);
  tearDown(limpar);

  test('localStorage cheio: os relatórios saem e o mês é gravado', () {
    final kv = chaveValorDoNavegador()!;
    final a = ArmazenamentoChaveValor(kv);
    a.gravar('relatorios/indice.json', 'i' * 1000);
    a.gravar('relatorios/relatorio-abertura-2026-11-26.json', 'r' * 1000);
    // Enche fora de relatorios/, para o descarte não limpar o enchimento.
    var cheio = false;
    for (var i = 0; i < 100 && !cheio; i++) {
      try {
        kv.definir('darf:enchimento-$i', 'x' * 1000000);
      } catch (_) {
        cheio = true;
      }
    }
    expect(cheio, isTrue, reason: 'o localStorage deveria recusar');
    // Libera só o suficiente para o mês caber depois do descarte.
    kv.remover('darf:enchimento-0');
    a.gravar('relatorios/outro.json', 'o' * 1000);
    expect(() => a.gravar('2026-11.json', 'x' * 200000), returnsNormally);
    expect(a.ler('2026-11.json'), 'x' * 200000);
    expect(kv.chaves().where((c) => c.startsWith('darf:relatorios/')), isEmpty);
  });
}
