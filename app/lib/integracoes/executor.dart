import 'dart:async';

export 'executor_isolate.dart'
    if (dart.library.js_interop) 'executor_sem_isolate.dart';

/// Executa uma tarefa (parsing pesado, por exemplo) fora da thread da interface.
typedef Executar = Future<R> Function<R>(FutureOr<R> Function() tarefa);

/// Roda a tarefa na hora, no mesmo isolate (para testes).
Future<R> executarDireto<R>(FutureOr<R> Function() tarefa) async => tarefa();
