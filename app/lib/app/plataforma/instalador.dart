// Instalação da atualização baixada. Windows: o instalador roda destacado e o
// app sai; Android: o Kotlin abre o instalador de pacotes (android/main.py:80).

import 'dart:io';

import 'package:flutter/services.dart';

/// Argumentos do Inno Setup (app/instalador/CalculadoraDARF.iss); o [Run] reabre o app.
const argumentosInstaladorSilencioso = [
  '/VERYSILENT',
  '/SUPPRESSMSGBOXES',
  '/NORESTART',
];

const canalPlataforma = MethodChannel('calculadoradarf/plataforma');

typedef IniciarProcesso = Future<void> Function(
  String executavel,
  List<String> argumentos,
);

Future<void> iniciarDestacado(String executavel, List<String> argumentos) =>
    Process.start(executavel, argumentos, mode: ProcessStartMode.detached);

Future<void> executarInstalador(
  String caminho, {
  required bool windows,
  IniciarProcesso iniciarProcesso = iniciarDestacado,
  void Function(int codigo) sair = exit,
}) async {
  if (windows) {
    await iniciarProcesso(caminho, argumentosInstaladorSilencioso);
    sair(0);
    return;
  }
  await canalPlataforma.invokeMethod<void>('instalarApk', {'caminho': caminho});
}
