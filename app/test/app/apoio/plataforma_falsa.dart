// Plataforma falsa para os testes de tela: grava URLs abertas, notificações e
// instalações; a resposta de `abrirUrl` é programável.

import 'package:calculadoradarf/app/plataforma/plataforma.dart';

class NotificacaoGravada {
  const NotificacaoGravada(this.id, this.titulo, this.corpo, this.link);

  final int id;
  final String titulo;
  final String corpo;
  final String link;
}

class PlataformaFalsa implements Plataforma {
  PlataformaFalsa({this.windows = true});

  @override
  final bool windows;

  final List<Uri> urlsAbertas = [];
  final List<NotificacaoGravada> notificacoes = [];
  final List<String> instalacoes = [];

  /// Resposta de `abrirUrl` (false = o navegador não abriu).
  bool respostaAbrirUrl = true;

  /// Resposta de `pedirPermissaoNotificacoes`.
  bool permissaoNotificacoes = true;

  /// Quando preenchido, os métodos de notificação e o instalador lançam isto
  /// (falha de plugin).
  Object? falhaPlugin;

  /// Quantas vezes `iniciarNotificacoes` foi chamado.
  int notificacoesIniciadas = 0;

  void Function(String link)? aoTocar;

  /// Simula o toque do usuário numa notificação.
  void tocar(String link) => aoTocar?.call(link);

  @override
  Future<bool> abrirUrl(Uri url) async {
    urlsAbertas.add(url);
    return respostaAbrirUrl;
  }

  @override
  Future<void> iniciarNotificacoes(void Function(String link) aoTocar) async {
    notificacoesIniciadas++;
    this.aoTocar = aoTocar;
    if (falhaPlugin != null) throw falhaPlugin!;
  }

  @override
  Future<bool> pedirPermissaoNotificacoes() async {
    if (falhaPlugin != null) throw falhaPlugin!;
    return permissaoNotificacoes;
  }

  @override
  Future<void> notificar(
    int id,
    String titulo,
    String corpo,
    String link,
  ) async {
    if (falhaPlugin != null) throw falhaPlugin!;
    notificacoes.add(NotificacaoGravada(id, titulo, corpo, link));
  }

  @override
  Future<void> instalarAtualizacao(String caminho) async {
    if (falhaPlugin != null) throw falhaPlugin!;
    instalacoes.add(caminho);
  }
}
