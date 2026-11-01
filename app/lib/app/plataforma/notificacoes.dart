// Notificações do sistema. O plugin fica atrás de [AdaptadorNotificacoes]
// para os testes trocarem por um falso.

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Canal das notícias do radar (android/main.py:43, 120).
const canalNoticias = 'noticias_radar';
const nomeCanalNoticias = 'Notícias do radar';

/// Identificação do app nas notificações do Windows (calculadora_darf.py:41).
const aumid = 'JoaoGabrielOT.CalculadoraDARF';

/// GUID fixo do app para o Windows (gerado uma vez; não mudar).
const guidNotificacoes = '493A1730-6D62-4281-B97C-2C3FDEB64E9D';

abstract interface class AdaptadorNotificacoes {
  /// Prepara o plugin; tocar numa notificação chama [aoTocar] com o payload
  /// (o link da notícia, ou vazio no resumo).
  Future<void> iniciar(void Function(String payload) aoTocar);

  /// Android 13+: pede a permissão; devolve se ela está concedida.
  Future<bool> pedirPermissao();

  Future<void> mostrar(int id, String titulo, String corpo, String payload);
}

class AdaptadorNotificacoesReal implements AdaptadorNotificacoes {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  @override
  Future<void> iniciar(void Function(String payload) aoTocar) async {
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        windows: WindowsInitializationSettings(
          appName: 'Calculadora DARF',
          appUserModelId: aumid,
          guid: guidNotificacoes,
        ),
      ),
      onDidReceiveNotificationResponse: (resposta) =>
          aoTocar(resposta.payload ?? ''),
    );
  }

  @override
  Future<bool> pedirPermissao() async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    return await android?.requestNotificationsPermission() ?? false;
  }

  @override
  Future<void> mostrar(int id, String titulo, String corpo, String payload) {
    return _plugin.show(
      id: id,
      title: titulo,
      body: corpo,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          canalNoticias,
          nomeCanalNoticias,
          styleInformation: BigTextStyleInformation(corpo),
        ),
        windows: const WindowsNotificationDetails(),
      ),
      payload: payload,
    );
  }
}
