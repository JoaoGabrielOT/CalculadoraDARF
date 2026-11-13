import 'dart:async';
import 'dart:isolate';

/// Roda a tarefa em um isolate novo; o resultado e as exceções voltam ao chamador.
Future<R> executarEmIsolate<R>(FutureOr<R> Function() tarefa) =>
    Isolate.run<R>(tarefa);
