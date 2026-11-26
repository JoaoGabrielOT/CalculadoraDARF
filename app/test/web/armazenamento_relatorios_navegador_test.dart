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

  /// Enche o localStorage com [tamanho] caracteres por bloco até a recusa.
  void encher(int tamanho, int limite) {
    final kv = chaveValorDoNavegador()!;
    for (var i = 0; i < limite; i++) {
      try {
        kv.definir('darf:enchimento-$tamanho-$i', 'x' * tamanho);
      } catch (_) {
        return;
      }
    }
    fail('o localStorage deveria recusar');
  }

  test('localStorage cheio: os relatórios saem e o mês é gravado', () {
    final kv = chaveValorDoNavegador()!;
    final a = ArmazenamentoChaveValor(kv);
    a.gravar('relatorios/indice.json', 'i' * 1000);
    a.gravar('relatorios/peso.json', 'p' * 300000);
    // Enche fora de relatorios/, para o descarte não limpar o enchimento.
    encher(1000000, 100);
    encher(10000, 200);
    encher(100, 200);
    expect(
      () => kv.definir('darf:teste', 'x' * 200000),
      throwsA(anything),
      reason: 'sem folga: o descarte é necessário',
    );
    kv.remover('darf:teste');
    a.gravar('2026-11.json', 'x' * 200000);
    expect(a.ler('2026-11.json'), 'x' * 200000);
    expect(kv.chaves().where((c) => c.startsWith('darf:relatorios/')), isEmpty);
  });
}
