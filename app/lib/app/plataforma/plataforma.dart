// Camada Plataforma: a única que usa plugins (url_launcher, notificações,
// instalador). Roda na thread da interface, nunca no isolate de serviços.

import 'dart:io';

import 'package:url_launcher/url_launcher.dart';

import 'instalador.dart';
import 'notificacoes.dart';

abstract interface class Plataforma {
  bool get windows;

  /// Abre no navegador externo; false quando não abriu.
  Future<bool> abrirUrl(Uri url);

  /// [aoTocar] recebe o link da notificação tocada (vazio no resumo).
  Future<void> iniciarNotificacoes(void Function(String link) aoTocar);

  /// Android 13+; no Windows devolve true.
  Future<bool> pedirPermissaoNotificacoes();

  Future<void> notificar(int id, String titulo, String corpo, String link);

  Future<void> instalarAtualizacao(String caminho);
}

class PlataformaReal implements Plataforma {
  PlataformaReal({
    bool? windows,
    AdaptadorNotificacoes? adaptador,
    this.iniciarProcesso = iniciarDestacado,
    this.sair = exit,
  }) : windows = windows ?? Platform.isWindows,
       _adaptador = adaptador ?? AdaptadorNotificacoesReal();

  @override
  final bool windows;

  final AdaptadorNotificacoes _adaptador;

  /// Trocáveis nos testes do instalador.
  final IniciarProcesso iniciarProcesso;
  final void Function(int codigo) sair;

  @override
  Future<bool> abrirUrl(Uri url) async {
    try {
      return await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> iniciarNotificacoes(void Function(String link) aoTocar) =>
      _adaptador.iniciar(aoTocar);

  @override
  Future<bool> pedirPermissaoNotificacoes() async {
    if (windows) return true;
    return _adaptador.pedirPermissao();
  }

  @override
  Future<void> notificar(int id, String titulo, String corpo, String link) =>
      _adaptador.mostrar(id, titulo, corpo, link);

  @override
  Future<void> instalarAtualizacao(String caminho) => executarInstalador(
    caminho,
    windows: windows,
    iniciarProcesso: iniciarProcesso,
    sair: sair,
  );
}
