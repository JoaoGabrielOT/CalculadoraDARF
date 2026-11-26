import 'package:calculadoradarf/nucleo/armazenamento_chave_valor.dart';
import 'package:flutter_test/flutter_test.dart';

/// Chave-valor que lança quando a soma dos valores passa do limite.
class ChaveValorLimitado extends ChaveValorMemoria {
  ChaveValorLimitado(this.limite);
  final int limite;

  @override
  void definir(String chave, String valor) {
    final outros = chaves()
        .where((c) => c != chave)
        .fold<int>(0, (s, c) => s + obter(c)!.length);
    if (outros + valor.length > limite) throw StateError('QuotaExceededError');
    super.definir(chave, valor);
  }
}

void main() {
  test('grava com o prefixo e lista só as chaves do app', () {
    final kv = ChaveValorMemoria()..definir('outro', 'x');
    final a = ArmazenamentoChaveValor(kv);
    a.gravar('2026-11.json', '{}');
    expect(kv.obter('darf:2026-11.json'), '{}');
    expect(a.listar(), ['2026-11.json']);
    expect(a.existe('2026-11.json'), isTrue);
    a.apagar('nao-existe.json');
    expect(a.ler('nao-existe.json'), isNull);
  });

  test('sem espaço, descarta o cache de notícias e grava', () {
    final kv = ChaveValorLimitado(30);
    final a = ArmazenamentoChaveValor(kv);
    a.gravar('noticias.json', 'n' * 25);
    a.gravar('config.json', 'c' * 10);
    expect(a.ler('config.json'), 'c' * 10);
    expect(a.existe('noticias.json'), isFalse);
  });

  test('sem espaço e sem o que descartar, lança ErroArmazenamentoCheio', () {
    final a = ArmazenamentoChaveValor(ChaveValorLimitado(30));
    expect(
      () => a.gravar('2026-11.json', 'x' * 100),
      throwsA(isA<ErroArmazenamentoCheio>()
          .having((e) => '$e', 'texto', textoArmazenamentoCheio)),
    );
  });

  test('gravar o próprio noticias.json só descarta o outro descartável', () {
    final kv = ChaveValorLimitado(30);
    final a = ArmazenamentoChaveValor(kv);
    a.gravar('noticias_detalhes.json', 'd' * 25);
    a.gravar('noticias.json', 'n' * 10);
    expect(a.existe('noticias_detalhes.json'), isFalse);
    expect(a.ler('noticias.json'), 'n' * 10);
  });

  test('armazenamento cheio descarta o cache dos relatórios', () {
    final kv = ChaveValorLimitado(30)
      ..definir('darf:relatorios/indice.json', 'i' * 10)
      ..definir('darf:relatorios/relatorio-abertura-2026-11-26.json', 'r' * 10);
    final a = ArmazenamentoChaveValor(kv);
    a.gravar('2026-11.json', 'm' * 25);
    expect(a.ler('2026-11.json'), 'm' * 25);
    expect(kv.chaves().where((c) => c.startsWith('darf:relatorios/')), isEmpty);
  });
}
