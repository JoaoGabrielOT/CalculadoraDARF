// Plataforma do navegador (só Web): abas, Notification API, Web Locks,
// endereço da página e áreas seguras do celular.

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show EdgeInsets;
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:web/web.dart' as html;

import 'plataforma.dart';

class PlataformaWeb implements Plataforma {
  /// [nomeTrava] só muda nos testes.
  PlataformaWeb({this.nomeTrava = 'calculadora-darf'});

  final String nomeTrava;

  @override
  bool get windows => false;

  @override
  bool get web => true;

  void Function(String link)? _aoTocar;
  Future<bool>? _trava;

  @override
  late final ValueListenable<EdgeInsets>? areasSeguras = _lerAreasSeguras();

  @override
  Future<bool> abrirUrl(Uri url) async {
    try {
      return await launchUrl(url, webOnlyWindowName: '_blank');
    } catch (_) {
      return false;
    }
  }

  /// Sai da página rumo a [url] (o login pelo servidor).
  Future<void> navegar(Uri url) async {
    if (!await launchUrl(url, webOnlyWindowName: '_self')) {
      throw StateError('navegação recusada');
    }
  }

  bool get _temNotificacao => globalContext.has('Notification');

  @override
  Future<void> iniciarNotificacoes(void Function(String link) aoTocar) async =>
      _aoTocar = aoTocar;

  @override
  Future<bool> pedirPermissaoNotificacoes() async {
    if (!_temNotificacao) return false;
    try {
      final r = await html.Notification.requestPermission().toDart;
      return r.toDart == 'granted';
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> notificar(
    int id,
    String titulo,
    String corpo,
    String link,
  ) async {
    if (!_temNotificacao || html.Notification.permission != 'granted') return;
    try {
      final n = html.Notification(
        titulo,
        html.NotificationOptions(body: corpo, tag: 'darf-$id'),
      );
      n.onclick = ((html.Event _) {
        html.window.focus();
        n.close();
        _aoTocar?.call(link);
      }).toJS;
    } catch (_) {}
  }

  @override
  Future<void> instalarAtualizacao(String caminho) async {}

  @override
  Future<void> copiarTexto(String texto) =>
      Clipboard.setData(ClipboardData(text: texto));

  /// Trava de aba única (Web Locks): true se esta página a tem. Uma vez
  /// obtida, fica com a página até ela fechar. Sem a API, true. Chamadas
  /// simultâneas recebem o mesmo futuro; só um false permite pedir de novo
  /// (a outra aba pode ter fechado).
  Future<bool> travarAbaUnica() => _trava ??= _pedirTrava().then((ok) {
    if (!ok) _trava = null;
    return ok;
  });

  Future<bool> _pedirTrava() async {
    final nav = html.window.navigator;
    if (!(nav as JSObject).has('locks')) return true;
    final pronto = Completer<bool>();
    try {
      final pedido = nav.locks.request(
        nomeTrava,
        html.LockOptions(ifAvailable: true),
        ((html.Lock? trava) {
          pronto.complete(trava != null);
          // uma promessa que nunca termina segura a trava
          return trava == null ? null : Completer<JSAny?>().future.toJS;
        }).toJS,
      );
      unawaited(
        pedido.toDart.then<void>(
          (_) {},
          onError: (Object _) {
            if (!pronto.isCompleted) pronto.complete(true);
          },
        ),
      );
    } catch (_) {
      return true;
    }
    return pronto.future;
  }

  /// O menu do botão direito passa a ser o do app, não o do navegador.
  void usarMenuDoApp() => unawaited(BrowserContextMenu.disableContextMenu());

  /// Tira o fragmento (a volta do login) do endereço, sem recarregar.
  void limparEndereco() {
    final l = html.window.location;
    html.window.history.replaceState(null, '', '${l.pathname}${l.search}');
  }

  ValueListenable<EdgeInsets>? _lerAreasSeguras() {
    final corpo = html.document.body;
    if (corpo == null) return null;
    final el = html.document.createElement('div') as html.HTMLElement;
    el.style.cssText =
        'position:fixed;top:0;left:0;visibility:hidden;pointer-events:none;'
        'padding:env(safe-area-inset-top) env(safe-area-inset-right) '
        'env(safe-area-inset-bottom) env(safe-area-inset-left);';
    corpo.append(el);
    EdgeInsets ler() {
      final s = html.window.getComputedStyle(el);
      double px(String lado) =>
          double.tryParse(
            s.getPropertyValue('padding-$lado').replaceAll('px', '').trim(),
          ) ??
          0;
      return EdgeInsets.fromLTRB(
        px('left'),
        px('top'),
        px('right'),
        px('bottom'),
      );
    }

    final areas = ValueNotifier(ler());
    html.window.addEventListener(
      'resize',
      ((html.Event _) {
        areas.value = ler();
      }).toJS,
    );
    return areas;
  }
}
