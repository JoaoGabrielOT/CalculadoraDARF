// Inicialização e raiz do app.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'estado/estado_app.dart';
import 'plataforma/licencas.dart';
import 'plataforma/pastas.dart';
import 'plataforma/plataforma.dart';
import 'regras/textos.dart';
import 'servicos/api.dart';
import 'servicos/parametros.dart';
import 'servicos/servicos_isolate.dart';
import 'telas/casca.dart';
import 'tema/temas.dart';
import 'tema/tema_visual.dart';
import '../integracoes/integracoes.dart';

/// Largura lógica a partir da qual o app usa o layout de PC.
const larguraExpandida = 840.0;

bool expandido(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= larguraExpandida;

/// Raiz capturável (imagem da tela, usada pelos goldens e pela captura).
final chaveCaptura = GlobalKey();

/// Sobe o isolate de serviços e abre o app. [servicos] e [plataforma] só são
/// trocados nos testes.
Future<void> iniciarApp({ServicosApp? servicos, Plataforma? plataforma}) async {
  WidgetsFlutterBinding.ensureInitialized();
  registrarLicencaRoboto();
  try {
    final plat = plataforma ?? PlataformaReal();
    final serv = servicos ?? await _criarServicos(plat);
    // O estado assina os eventos já no construtor: o proxy só guarda os 256
    // últimos até a primeira assinatura.
    final estado = EstadoApp(serv, plat);
    runApp(AppCalculadora(servicos: serv, plataforma: plat, estado: estado));
    unawaited(estado.iniciar());
  } catch (e) {
    runApp(AppFalhaInicial(textoErro(e)));
  }
}

Future<ServicosApp> _criarServicos(Plataforma plataforma) async {
  final pastas = await pastasDoApp();
  ClienteOAuth? cliente;
  try {
    cliente = await carregarClienteOAuth();
  } on ErroGoogle {
    cliente = null; // sem credencial: o app abre, sem login do Google
  }
  return ServicosIsolate.criar(
    ParametrosServicos(
      pastaDados: pastas.dados,
      pastaTemporaria: pastas.temporaria,
      windows: plataforma.windows,
      clienteOAuth: cliente,
    ),
    abrirUrl: plataforma.abrirUrl,
  );
}

class AppCalculadora extends StatelessWidget {
  /// Com [estado] (o de `iniciarApp`), quem chamou o inicia; sem ele o app cria
  /// e inicia o seu.
  const AppCalculadora({
    super.key,
    required this.servicos,
    required this.plataforma,
    this.estado,
  });

  final ServicosApp servicos;
  final Plataforma plataforma;
  final EstadoApp? estado;

  @override
  Widget build(BuildContext context) {
    final dado = estado;
    return MultiProvider(
      providers: [
        Provider<ServicosApp>.value(value: servicos),
        Provider<Plataforma>.value(value: plataforma),
        if (dado != null)
          ChangeNotifierProvider<EstadoApp>.value(value: dado)
        else
          ChangeNotifierProvider<EstadoApp>(
            lazy: false,
            create: (_) => EstadoApp(servicos, plataforma)..iniciar(),
          ),
      ],
      child: const _AppMaterial(),
    );
  }
}

class _AppMaterial extends StatelessWidget {
  const _AppMaterial();

  @override
  Widget build(BuildContext context) {
    final escolhido = context.select<EstadoApp, TemaVisual>(
      (e) => e.preferencias.tema,
    );
    // Acima do MaterialApp ainda não há MediaQuery: este traz o do sistema,
    // para o tema Automático reagir ao claro/escuro.
    return MediaQuery.fromView(
      view: View.of(context),
      child: Builder(
        builder: (context) => MaterialApp(
          title: 'Calculadora DARF',
          debugShowCheckedModeBanner: false,
          locale: const Locale('pt', 'BR'),
          supportedLocales: const [Locale('pt', 'BR')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          theme: temaDe(
            resolverTema(escolhido, MediaQuery.platformBrightnessOf(context)),
          ),
          builder: (context, child) =>
              RepaintBoundary(key: chaveCaptura, child: child),
          home: const Casca(),
        ),
      ),
    );
  }
}

/// Mostrada quando os serviços não sobem (pasta de dados, isolate).
class AppFalhaInicial extends StatelessWidget {
  const AppFalhaInicial(this.mensagem, {super.key});

  final String mensagem;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Calculadora DARF',
    debugShowCheckedModeBanner: false,
    theme: temaDe(TemaVisual.claro),
    home: Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Não foi possível iniciar a Calculadora DARF.\n$mensagem',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    ),
  );
}
