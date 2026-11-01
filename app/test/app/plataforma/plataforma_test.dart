import 'package:calculadoradarf/app/plataforma/instalador.dart';
import 'package:calculadoradarf/app/plataforma/notificacoes.dart';
import 'package:calculadoradarf/app/plataforma/pastas.dart';
import 'package:calculadoradarf/app/plataforma/plataforma.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
// ignore: depend_on_referenced_packages
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import '../apoio/plataforma_falsa.dart';

class _AdaptadorFalso implements AdaptadorNotificacoes {
  void Function(String payload)? aoTocar;
  final List<List<Object>> mostradas = [];
  bool permissao = true;
  String? partida;

  @override
  Future<String?> payloadDaPartida() async => partida;

  @override
  Future<void> iniciar(void Function(String payload) aoTocar) async {
    this.aoTocar = aoTocar;
  }

  @override
  Future<bool> pedirPermissao() async => permissao;

  @override
  Future<void> mostrar(
    int id,
    String titulo,
    String corpo,
    String payload,
  ) async {
    mostradas.add([id, titulo, corpo, payload]);
  }
}

class _LauncherFalso extends UrlLauncherPlatform {
  _LauncherFalso({this.falha = false});

  @override
  Null get linkDelegate => null;

  final bool falha;
  final List<String> urls = [];
  PreferredLaunchMode? modo;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    urls.add(url);
    modo = options.mode;
    if (falha) throw PlatformException(code: 'sem_navegador');
    return true;
  }
}

class _LauncherQueRecusa extends UrlLauncherPlatform {
  @override
  Null get linkDelegate => null;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async => false;
}

class _PathProviderFalso extends PathProviderPlatform {
  @override
  Future<String?> getApplicationSupportPath() async => r'C:\Apoio';

  @override
  Future<String?> getTemporaryPath() async => r'C:\Temp';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('instalador', () {
    test('no Windows inicia o processo destacado com os argumentos silenciosos e sai', () async {
      final chamadas = <String>[];
      List<String>? args;
      await executarInstalador(
        r'C:\Temp\Setup.exe',
        windows: true,
        iniciarProcesso: (exe, argumentos) async {
          chamadas.add('processo:$exe');
          args = argumentos;
        },
        sair: (codigo) => chamadas.add('sair:$codigo'),
      );
      expect(chamadas, [r'processo:C:\Temp\Setup.exe', 'sair:0']);
      expect(args, ['/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART']);
      expect(args, argumentosInstaladorSilencioso);
    });

    test('no Android chama o canal com o caminho', () async {
      final chamadas = <MethodCall>[];
      const canal = MethodChannel('calculadoradarf/plataforma');
      final mensageiro =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      mensageiro.setMockMethodCallHandler(canal, (c) async {
        chamadas.add(c);
        return null;
      });
      addTearDown(() => mensageiro.setMockMethodCallHandler(canal, null));
      await executarInstalador(
        '/cache/CalculadoraDARF.apk',
        windows: false,
        iniciarProcesso: (_, _) async => fail('não deve iniciar processo'),
        sair: (_) => fail('não deve sair'),
      );
      expect(chamadas, hasLength(1));
      expect(chamadas.single.method, 'instalarApk');
      expect(chamadas.single.arguments, {
        'caminho': '/cache/CalculadoraDARF.apk',
      });
    });
  });

  group('notificações', () {
    test('notificar repassa título, corpo e link', () async {
      final adaptador = _AdaptadorFalso();
      final p = PlataformaReal(windows: true, adaptador: adaptador);
      await p.notificar(7, 'PETR4', 'Resultado do dia', 'https://x.com/n');
      expect(adaptador.mostradas, [
        [7, 'PETR4', 'Resultado do dia', 'https://x.com/n'],
      ]);
    });

    test('tocar na notificação chama aoTocar com o link', () async {
      final adaptador = _AdaptadorFalso();
      final p = PlataformaReal(windows: true, adaptador: adaptador);
      final tocados = <String>[];
      await p.iniciarNotificacoes(tocados.add);
      adaptador.aoTocar!('https://x.com/n');
      adaptador.aoTocar!('');
      expect(tocados, ['https://x.com/n', '']);
    });

    test('partida a frio pela notificação chama aoTocar uma vez', () async {
      final adaptador = _AdaptadorFalso()..partida = 'https://x.com/n';
      final p = PlataformaReal(windows: false, adaptador: adaptador);
      final tocados = <String>[];
      await p.iniciarNotificacoes(tocados.add);
      expect(tocados, ['https://x.com/n']);
    });

    test('partida normal ou sem link não chama aoTocar', () async {
      final adaptador = _AdaptadorFalso();
      final tocados = <String>[];
      final p = PlataformaReal(windows: false, adaptador: adaptador);
      await p.iniciarNotificacoes(tocados.add);
      adaptador.partida = '';
      await p.iniciarNotificacoes(tocados.add);
      expect(tocados, isEmpty);
    });

    test('permissão: Windows devolve true; Android pergunta', () async {
      final adaptador = _AdaptadorFalso()..permissao = false;
      expect(
        await PlataformaReal(
          windows: true,
          adaptador: adaptador,
        ).pedirPermissaoNotificacoes(),
        isTrue,
      );
      expect(
        await PlataformaReal(
          windows: false,
          adaptador: adaptador,
        ).pedirPermissaoNotificacoes(),
        isFalse,
      );
    });
  });

  group('abrirUrl', () {
    final original = UrlLauncherPlatform.instance;
    tearDown(() => UrlLauncherPlatform.instance = original);

    test('abre no aplicativo externo', () async {
      final launcher = _LauncherFalso();
      UrlLauncherPlatform.instance = launcher;
      final p = PlataformaReal(windows: true, adaptador: _AdaptadorFalso());
      expect(await p.abrirUrl(Uri.parse('https://exemplo.com/a')), isTrue);
      expect(launcher.urls, ['https://exemplo.com/a']);
      expect(launcher.modo, PreferredLaunchMode.externalApplication);
    });

    test('devolve false quando o launcher falha', () async {
      UrlLauncherPlatform.instance = _LauncherFalso(falha: true);
      final p = PlataformaReal(windows: true, adaptador: _AdaptadorFalso());
      expect(await p.abrirUrl(Uri.parse('https://exemplo.com')), isFalse);
    });

    test('devolve false quando o launcher recusa', () async {
      UrlLauncherPlatform.instance = _LauncherQueRecusa();
      final p = PlataformaReal(windows: true, adaptador: _AdaptadorFalso());
      expect(await p.abrirUrl(Uri.parse('https://exemplo.com')), isFalse);
    });
  });

  test('pastasDoApp: dados dentro da pasta de suporte e temporária', () async {
    final original = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _PathProviderFalso();
    addTearDown(() => PathProviderPlatform.instance = original);
    final pastas = await pastasDoApp();
    expect(pastas.dados.replaceAll('\\', '/'), 'C:/Apoio/dados');
    expect(pastas.temporaria, r'C:\Temp');
  });

  test('PlataformaFalsa grava URLs, notificações e instalações', () async {
    final f = PlataformaFalsa()..respostaAbrirUrl = false;
    expect(await f.abrirUrl(Uri.parse('https://a.com')), isFalse);
    await f.notificar(1, 't', 'c', 'l');
    await f.instalarAtualizacao('x.exe');
    final tocados = <String>[];
    await f.iniciarNotificacoes(tocados.add);
    f.tocar('l');
    expect(f.urlsAbertas, [Uri.parse('https://a.com')]);
    expect(f.notificacoes.single.titulo, 't');
    expect(f.instalacoes, ['x.exe']);
    expect(tocados, ['l']);
  });
}
