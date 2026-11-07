// Inicialização e raiz do app.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'componentes/logo_ativo.dart';
import 'estado/estado_app.dart';
import 'plataforma/licencas.dart';
import 'plataforma/pastas.dart';
import 'plataforma/plataforma.dart';
import 'regras/textos.dart';
import 'servicos/api.dart';
import 'servicos/parametros.dart';
import 'servicos/servicos_isolate.dart';
import 'telas/casca.dart';
import 'telas/falha_inicial.dart';
import 'tema/temas.dart';
import 'tema/tema_visual.dart';
import '../integracoes/integracoes.dart';

/// Raiz capturável (imagem da tela, usada pelos goldens e pela captura).
final chaveCaptura = GlobalKey();

/// Sobe o isolate de serviços e abre o app. [servicos], [plataforma] e
/// [criarServicos] só são trocados nos testes. Falha ao subir mostra o motivo
/// com "Tentar de novo".
Future<void> iniciarApp({
  ServicosApp? servicos,
  Plataforma? plataforma,
  Future<ServicosApp> Function(Plataforma plataforma)? criarServicos,
  Duration esperaEncerramento = const Duration(seconds: 5),
}) async {
  WidgetsFlutterBinding.ensureInitialized();
  registrarLicencaRoboto();
  final plat = plataforma ?? PlataformaReal();
  Future<void>? encerrando;
  Future<void>? emCurso;

  late final Future<void> Function() abrir;

  Future<void> tentar() async {
    ServicosApp? serv;
    EstadoApp? estado;
    try {
      // a tentativa anterior sai antes de criar outra, sem prender o botão
      // para sempre se o encerramento travar
      await encerrando?.timeout(esperaEncerramento, onTimeout: () {});
      serv = servicos ?? await (criarServicos ?? _criarServicos)(plat);
      // O estado assina os eventos já no construtor: o proxy só guarda os 256
      // últimos até a primeira assinatura.
      estado = EstadoApp(serv, plat);
      // O estado inicial chega antes do primeiro quadro: ele já sai com o
      // tema gravado, sem passar pelo padrão.
      estado.aplicarInicial(await serv.iniciar());
      runApp(AppCalculadora(servicos: serv, plataforma: plat, estado: estado));
      unawaited(estado.iniciar());
    } catch (e) {
      estado?.dispose();
      if (servicos == null && serv != null) {
        // serviços criados por esta tentativa: não ficam isolates órfãos
        encerrando = serv.encerrar().catchError((Object _) {});
      }
      runApp(AppFalhaInicial(textoFalha(e), aoTentar: abrir));
    }
  }

  // Toques repetidos em "Tentar de novo" enquanto uma tentativa corre não
  // criam outra.
  abrir = () => emCurso ??= tentar().whenComplete(() => emCurso = null);
  await abrir();
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
          // o app passa a ser dono do estado: ao sair da árvore ele é
          // descartado (e o timer da verificação de atualização some)
          ChangeNotifierProvider<EstadoApp>(create: (_) => dado)
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
          // a troca de tema em Configurações vale no mesmo quadro
          themeAnimationDuration: Duration.zero,
          // O escopo fica acima do Navigator: as logos valem também nos
          // diálogos e nas telas empilhadas.
          builder: (context, child) => RepaintBoundary(
            key: chaveCaptura,
            child: EscopoLogos(child: child!),
          ),
          home: const Casca(),
        ),
      ),
    );
  }
}

/// Mostrada quando os serviços não sobem (pasta de dados, isolate).
class AppFalhaInicial extends StatelessWidget {
  const AppFalhaInicial(this.mensagem, {super.key, required this.aoTentar});

  final String mensagem;
  final VoidCallback aoTentar;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Calculadora DARF',
    debugShowCheckedModeBanner: false,
    theme: temaDe(TemaVisual.claro),
    home: CorpoFalha(mensagem, aoTentar: aoTentar),
  );
}
