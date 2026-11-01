import 'dart:async';

import 'package:calculadoradarf/integracoes/integracoes.dart';
import 'package:calculadoradarf/nucleo/nucleo.dart';
import 'package:flutter_test/flutter_test.dart';

void _fixar(double agora) => ambiente = Ambiente.fixo(agora: agora);

void main() {
  tearDown(() => ambiente = Ambiente.sistema());

  test('validade de 60 s', () {
    expect(CacheCotacoes.validade, 60);
  });

  test('mantém o preço anterior quando a consulta falha', () async {
    var chamadas = 0;
    final cache = CacheCotacoes((t) async {
      chamadas++;
      if (chamadas == 1) return 10.5;
      throw LimiteConsultas('Too Many Requests');
    });
    const t = 1761000000.0;
    _fixar(t);
    expect(await cache.atualizar(['PETR4']), isTrue);
    expect(cache.preco('PETR4'), 10.5);
    _fixar(t + 61);
    expect(await cache.atualizar(['PETR4']), isTrue);
    expect(chamadas, 2);
    expect(cache.preco('PETR4'), 10.5);
    // A tentativa falha renovou a hora: nada vence logo em seguida.
    expect(cache.pendentes(['PETR4']), isEmpty);
  });

  test('falha na primeira consulta deixa o preço desconhecido', () async {
    final cache = CacheCotacoes((t) async => throw SemDados('x'));
    _fixar(1761000000);
    expect(await cache.atualizar(['PETR4']), isTrue);
    expect(cache.preco('PETR4'), isNull);
    expect(cache.pendentes(['PETR4']), isEmpty);
  });

  test('pendentes: só os vencidos há mais de 60 s, em ordem alfabética, '
      'sem repetir', () async {
    final cache = CacheCotacoes((t) async => 1.0);
    const t = 1761000000.0;
    _fixar(t);
    await cache.atualizar(['VALE3', 'ABEV3']);
    expect(cache.pendentes(['VALE3', 'PETR4', 'ABEV3', 'PETR4', 'BBAS3']), [
      'BBAS3',
      'PETR4',
    ]);
    _fixar(t + 60);
    expect(cache.pendentes(['VALE3', 'ABEV3']), isEmpty);
    _fixar(t + 61);
    expect(cache.pendentes(['VALE3', 'ABEV3', 'VALE3']), ['ABEV3', 'VALE3']);
  });

  test('nada vencido devolve false sem consultar', () async {
    var chamadas = 0;
    final cache = CacheCotacoes((t) async {
      chamadas++;
      return 1.0;
    });
    _fixar(1761000000);
    await cache.atualizar(['PETR4']);
    expect(await cache.atualizar(['PETR4']), isFalse);
    expect(chamadas, 1);
  });

  test('chamada durante outra em andamento devolve false', () async {
    final liberar = Completer<double>();
    final cache = CacheCotacoes((t) => liberar.future);
    _fixar(1761000000);
    final primeira = cache.atualizar(['PETR4']);
    expect(cache.rodando, isTrue);
    expect(await cache.atualizar(['VALE3']), isFalse);
    liberar.complete(9.0);
    expect(await primeira, isTrue);
    expect(cache.rodando, isFalse);
    expect(cache.preco('PETR4'), 9.0);
  });

  test('busca um a um, em ordem alfabética', () async {
    final ordem = <String>[];
    final cache = CacheCotacoes((t) async {
      ordem.add(t);
      return 1.0;
    });
    _fixar(1761000000);
    await cache.atualizar(['VALE3', 'ABEV3', 'PETR4']);
    expect(ordem, ['ABEV3', 'PETR4', 'VALE3']);
  });
}
