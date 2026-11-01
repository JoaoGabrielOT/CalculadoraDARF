import 'package:calculadoradarf/integracoes/integracoes.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('10 tarefas com máximo 3 nunca passam de 3 ao mesmo tempo', () async {
    final semaforo = Semaforo(3);
    var picoVisto = 0;
    var ativas = 0;
    final resultados = await Future.wait([
      for (var i = 0; i < 10; i++)
        semaforo.usar(() async {
          ativas++;
          if (ativas > picoVisto) picoVisto = ativas;
          expect(semaforo.emUso, lessThanOrEqualTo(3));
          await Future<void>.delayed(const Duration(milliseconds: 10));
          ativas--;
          return i;
        }),
    ]);
    expect(picoVisto, 3);
    expect(resultados, [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]);
    expect(semaforo.emUso, 0);
  });

  test('exceção libera a vaga', () async {
    final semaforo = Semaforo(1);
    final falha = semaforo.usar<int>(() async => throw StateError('x'));
    await expectLater(falha, throwsStateError);
    expect(semaforo.emUso, 0);
    expect(await semaforo.usar(() async => 7), 7);
  });

  test('exceção com tarefa na fila passa a vaga adiante', () async {
    final semaforo = Semaforo(1);
    final a = semaforo.usar<int>(() async {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      throw StateError('x');
    });
    final b = semaforo.usar(() async => 2);
    await expectLater(a, throwsStateError);
    expect(await b, 2);
    expect(semaforo.emUso, 0);
  });
}
