import 'dart:async';

/// Na Web não há isolates: a tarefa roda direto.
Future<R> executarEmIsolate<R>(FutureOr<R> Function() tarefa) async =>
    tarefa();
