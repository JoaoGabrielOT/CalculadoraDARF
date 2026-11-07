// Casca adaptativa: barra lateral e cabeçalho no PC (>= 840), barra inferior
// e telas deslizáveis no celular. Os avisos viram diálogo no PC e SnackBar no
// celular.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../integracoes/integracoes.dart';
import '../estado/estado_app.dart';
import '../regras/textos.dart';
import '../tema/cores_app.dart';
import '../tema/layout.dart';
import 'amigos/tela_amigos.dart';
import 'apuracao/tela_apuracao.dart';
import 'caixa/tela_caixa.dart';
import 'falha_inicial.dart';
import 'metas/tela_metas.dart';
import 'noticias/tela_noticias.dart';
import 'radar/tela_radar.dart';

extension on Aba {
  String get rotulo => switch (this) {
    Aba.apuracao => 'Apuração',
    Aba.caixa => 'Caixa',
    Aba.radar => 'Radar',
    Aba.noticias => 'Notícias',
    Aba.conta => 'Conta',
  };

  /// Na barra lateral a primeira aba leva também o nome do DARF.
  String get rotuloLateral => this == Aba.apuracao ? 'Apuração / DARF' : rotulo;

  IconData get icone => switch (this) {
    Aba.apuracao => Icons.receipt_long,
    Aba.caixa => Icons.account_balance_wallet,
    Aba.radar => Icons.insights,
    Aba.noticias => Icons.newspaper,
    Aba.conta => Icons.account_circle,
  };
}

class Casca extends StatefulWidget {
  /// [telaDaAba] troca o conteúdo das abas (os testes e as tarefas seguintes);
  /// sem ele cada aba mostra um espaço reservado.
  const Casca({super.key, this.telaDaAba});

  final Widget Function(Aba aba)? telaDaAba;

  @override
  State<Casca> createState() => _CascaState();
}

class _CascaState extends State<Casca> {
  late final EstadoApp _estado = context.read<EstadoApp>();
  late final PageController _controlador = PageController(
    initialPage: _estado.aba.index,
  );
  late final AppLifecycleListener _ciclo;

  /// Mantém o estado das telas quando a casca troca de layout.
  final GlobalKey _chavePaginas = GlobalKey();
  bool _mostrandoAvisos = false;
  bool _quadroAgendado = false;

  @override
  void initState() {
    super.initState();
    _ciclo = AppLifecycleListener(onStateChange: _estado.aoMudarCiclo);
  }

  @override
  void dispose() {
    _ciclo.dispose();
    _controlador.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final estado = context.watch<EstadoApp>();
    if (estado.falhaInicial != null) {
      return CorpoFalha(estado.falhaInicial!, aoTentar: estado.iniciar);
    }
    if (estado.carregando) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final grande = expandido(context);
    final fora =
        _controlador.hasClients &&
        _controlador.page?.round() != estado.aba.index;
    if (fora || estado.avisos.isNotEmpty) _agendarQuadro();

    final paginas = PageView(
      key: _chavePaginas,
      controller: _controlador,
      // no PC as abas só trocam pela barra lateral
      physics: grande ? const NeverScrollableScrollPhysics() : null,
      onPageChanged: (i) => estado.irPara(Aba.values[i]),
      children: [
        for (final a in Aba.values)
          _Pagina(
            key: ValueKey(a),
            child: widget.telaDaAba?.call(a) ?? _telaPadrao(a),
          ),
      ],
    );
    final corpo = Column(
      children: [
        ..._faixas(estado),
        Expanded(child: paginas),
      ],
    );

    final cores = CoresApp.de(context);
    final gradiente = cores.fundoGradiente;
    final fundo = gradiente == null ? null : Colors.transparent;
    final cena = grande
        ? Scaffold(
            backgroundColor: fundo,
            body: Row(
              children: [
                _BarraLateral(estado),
                Expanded(
                  child: Column(
                    children: [
                      _Cabecalho(estado),
                      ..._faixas(estado),
                      Expanded(child: paginas),
                    ],
                  ),
                ),
              ],
            ),
          )
        : Scaffold(
            backgroundColor: fundo,
            appBar: AppBar(
              backgroundColor: fundo,
              title: const Text(
                'Calculadora DARF',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              actions: [
                IconButton(
                  icon: Icon(_iconeSync(estado.conta.status)),
                  tooltip: textoStatusSync(estado.conta),
                  onPressed: () => estado.irPara(Aba.conta),
                ),
              ],
            ),
            body: corpo,
            bottomNavigationBar: NavigationBar(
              selectedIndex: estado.aba.index,
              onDestinationSelected: (i) => estado.irPara(Aba.values[i]),
              destinations: [
                for (final a in Aba.values)
                  NavigationDestination(
                    icon: _IconeAba(a, estado),
                    label: a.rotulo,
                  ),
              ],
            ),
          );
    if (gradiente == null) return cena;
    return DecoratedBox(
      decoration: BoxDecoration(gradient: gradiente),
      child: cena,
    );
  }

  /// Uma só chamada pendente por quadro, por mais que a casca reconstrua.
  void _agendarQuadro() {
    if (_quadroAgendado) return;
    _quadroAgendado = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _quadroAgendado = false;
      _depoisDoQuadro();
    });
  }

  List<Widget> _faixas(EstadoApp estado) => [
    if (estado.servicosEncerrados) const _FaixaAviso(textoServicosEncerrados),
    if (estado.erroConfig != null)
      _FaixaAviso(
        '${estado.erroConfig}\n'
        'Enquanto o config.json estiver vazio ou corrompido, nenhuma '
        'alteração é gravada. Feche o app, corrija ou mova esse '
        'arquivo (na pasta de dados do app) e abra o app de novo.',
      ),
  ];

  void _depoisDoQuadro() {
    if (!mounted) return;
    final destino = _estado.aba.index;
    if (_controlador.hasClients && _controlador.page?.round() != destino) {
      _controlador.jumpToPage(destino);
    }
    if (_estado.avisos.isNotEmpty) unawaited(_mostrarAvisos());
  }

  Future<void> _mostrarAvisos() async {
    if (_mostrandoAvisos) return;
    _mostrandoAvisos = true;
    try {
      while (true) {
        if (!mounted) break;
        final aviso = _estado.proximoAviso();
        if (aviso == null) break;
        if (expandido(context)) {
          await showDialog<void>(
            context: context,
            builder: (contexto) => AlertDialog(
              title: Text(aviso.titulo),
              content: SelectableText(aviso.texto),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(contexto).pop(),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${aviso.titulo}: ${aviso.texto}'),
              duration: const Duration(seconds: 6),
            ),
          );
        }
      }
    } finally {
      _mostrandoAvisos = false;
    }
  }
}

IconData _iconeSync(StatusSync s) => switch (s) {
  StatusSync.off => Icons.cloud_off,
  StatusSync.login || StatusSync.sync => Icons.sync,
  StatusSync.ok => Icons.cloud_done,
  StatusSync.pendente => Icons.cloud_upload,
  StatusSync.offline => Icons.cloud_off,
  StatusSync.erro => Icons.error_outline,
};

/// Ícone da aba; Notícias leva o selo de não lidas (some dentro da própria
/// aba, android/main.py:1944).
class _IconeAba extends StatelessWidget {
  const _IconeAba(this.aba, this.estado);

  final Aba aba;
  final EstadoApp estado;

  @override
  Widget build(BuildContext context) {
    final icone = Icon(aba.icone);
    if (aba != Aba.noticias) return icone;
    return Badge(
      isLabelVisible: estado.naoLidas > 0 && estado.aba != Aba.noticias,
      label: Text('${estado.naoLidas}'),
      child: icone,
    );
  }
}

class _BarraLateral extends StatelessWidget {
  const _BarraLateral(this.estado);

  final EstadoApp estado;

  @override
  Widget build(BuildContext context) => NavigationRail(
    extended: true,
    minExtendedWidth: 210,
    selectedIndex: estado.aba.index,
    onDestinationSelected: (i) => estado.irPara(Aba.values[i]),
    destinations: [
      for (final a in Aba.values)
        NavigationRailDestination(
          icon: _IconeAba(a, estado),
          label: Text(a.rotuloLateral),
        ),
    ],
  );
}

/// Calculadora_darf.py:1297-1322: título, subtítulo e os botões da conta.
class _Cabecalho extends StatelessWidget {
  const _Cabecalho(this.estado);

  final EstadoApp estado;

  @override
  Widget build(BuildContext context) {
    final cores = CoresApp.de(context);
    final amigo = estado.amigo;
    final email = estado.conta.email;
    final ativas = estado.metasAtivas;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Calculadora DARF',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                Text(
                  amigo == null
                      ? 'Ações e BDRs · apuração mensal de IR'
                      : 'Dados de $amigo · somente leitura',
                  style: TextStyle(
                    color: amigo == null ? cores.textoSuave : cores.aviso,
                  ),
                ),
              ],
            ),
          ),
          Flexible(
            flex: 2,
            child: Wrap(
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  onPressed: () => estado.irPara(Aba.caixa),
                  child: Text(estado.textoSaldo),
                ),
                Text(
                  textoStatusSync(estado.conta),
                  style: TextStyle(
                    color: _corSync(cores, estado.conta.status),
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
                OutlinedButton(
                  onPressed: () => unawaited(abrirMetas(context)),
                  child: Text(
                    'Meta de lucro'
                    '${ativas > 0 ? ' · $ativas ativa${ativas == 1 ? '' : 's'}' : ''}',
                  ),
                ),
                OutlinedButton(
                  onPressed: () => unawaited(abrirAmigos(context)),
                  child: const Text('Amigos'),
                ),
                OutlinedButton(
                  onPressed: () => estado.irPara(Aba.conta),
                  child: Text(
                    email == null
                        ? 'Conectar Google'
                        : email.length <= 26
                        ? email
                        : '${email.substring(0, 24)}…',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Color _corSync(CoresApp cores, StatusSync s) => switch (s) {
  StatusSync.off || StatusSync.sync => cores.textoSuave,
  StatusSync.login || StatusSync.pendente || StatusSync.offline => cores.aviso,
  StatusSync.ok => cores.alta,
  StatusSync.erro => cores.queda,
};

/// Faixa fixa no topo (config ilegível, serviços encerrados).
class _FaixaAviso extends StatelessWidget {
  const _FaixaAviso(this.texto);

  final String texto;

  @override
  Widget build(BuildContext context) {
    final cores = CoresApp.de(context);
    return Material(
      color: cores.aviso.withValues(alpha: .18),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Icon(Icons.warning_amber, color: cores.aviso),
            const SizedBox(width: 12),
            Expanded(child: Text(texto)),
          ],
        ),
      ),
    );
  }
}

/// Mantém a aba viva fora da tela (estado, rolagem, formulários).
class _Pagina extends StatefulWidget {
  const _Pagina({super.key, required this.child});

  final Widget child;

  @override
  State<_Pagina> createState() => _PaginaState();
}

class _PaginaState extends State<_Pagina> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

/// A tela de cada aba; as que ainda não existem mostram um espaço reservado
/// (trocado tarefa a tarefa).
Widget _telaPadrao(Aba a) => switch (a) {
  Aba.apuracao => Builder(
    builder: (c) => TelaApuracao(
      aoAbrirMetas: () => unawaited(abrirMetas(c)),
      conteudo: listasApuracao,
      sliversCompactos: listasSliversApuracao,
    ),
  ),
  Aba.caixa => const TelaCaixa(),
  Aba.radar => const TelaRadar(),
  Aba.noticias => const TelaNoticias(),
  _ => _Provisoria(a),
};

/// Espaço da aba até a tela dela existir.
class _Provisoria extends StatelessWidget {
  const _Provisoria(this.aba);

  final Aba aba;

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      const Positioned.fill(child: Placeholder()),
      Center(child: Text('${aba.rotulo} (em construção)')),
    ],
  );
}
