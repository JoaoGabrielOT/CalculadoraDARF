import 'dart:async';
import 'dart:isolate';

/// Executa uma tarefa (parsing pesado, por exemplo) fora da thread da interface.
typedef Executar = Future<R> Function<R>(FutureOr<R> Function() tarefa);

/// Roda a tarefa em um isolate novo; o resultado e as exceções voltam ao chamador.
Future<R> executarEmIsolate<R>(FutureOr<R> Function() tarefa) =>
    Isolate.run<R>(tarefa);

/// Roda a tarefa na hora, no mesmo isolate (para testes).
Future<R> executarDireto<R>(FutureOr<R> Function() tarefa) async => tarefa();
