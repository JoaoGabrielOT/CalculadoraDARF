// Gráfico do ativo: períodos de 1D a Máx, ponto sob o dedo ou o mouse,
// estatísticas e as ações do radar (calculadora_darf.py:3011-3232;
// android/main.py:352-567). Expandido é um diálogo de 960×640; compacto, tela
// cheia. O traçado é o `GraficoLinha` interativo; aqui ficam os rótulos.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../integracoes/integracoes.dart';
import '../../../nucleo/nucleo.dart';
import '../../componentes/cartao.dart';
import '../../componentes/carregando.dart';
import '../../componentes/grafico_linha.dart';
import '../../componentes/logo_ativo.dart';
import '../../regras/textos.dart';
import '../../servicos/api.dart';
import '../../tema/cores_app.dart';
import '../../tema/layout.dart';
import '../../tema/temas.dart';

const _textoToque = 'Toque no gráfico para ver o preço de cada ponto';
const _textoMouse =
    'Passe o mouse sobre o gráfico para ver o preço de cada ponto';

/// Abre o gráfico de [ticker]. As ações voltam ao radar pelos callbacks, depois
/// de fechar o gráfico; um botão só aparece se o callback existe ([aoVender]
/// nulo = ticker sem custódia). [amigo] e [jaTenho] decidem o "Meu radar".
Future<void> abrirGrafico(
  BuildContext c, {
  required String ticker,
  required String nome,
  DadosAtivo? dados,
  bool amigo = false,
  bool jaTenho = true,
  VoidCallback? aoComprar,
  VoidCallback? aoVender,
  VoidCallback? aoImportar,
  VoidCallback? aoVerNoticias,
}) {
  final servicos = c.read<ServicosApp>();
  Widget corpo(BuildContext ctx, bool grande) =>
      ChangeNotifierProvider<ControleGrafico>(
        create: (_) => ControleGrafico(servicos, ticker),
        child: _Conteudo(
          ticker: ticker,
          nome: nome,
          dados: dados,
          grande: grande,
          amigo: amigo,
          jaTenho: jaTenho,
          aoComprar: aoComprar,
          aoVender: aoVender,
          aoImportar: aoImportar,
          aoVerNoticias: aoVerNoticias,
        ),
      );
  if (expandido(c)) {
    return showDialog<void>(
      context: c,
      builder: (ctx) => Dialog(
        key: const Key('grafico-dialogo'),
        child: SizedBox(width: 960, height: 640, child: corpo(ctx, true)),
      ),
    );
  }
  return Navigator.of(c).push(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (ctx) => Scaffold(
        key: const Key('grafico-tela'),
        appBar: AppBar(title: Text('$ticker · gráfico')),
        body: SafeArea(child: corpo(ctx, false)),
      ),
    ),
  );
}

/// Gráfico do período em curso. Cada pedido tem uma geração: a resposta de um
/// período que já não é o atual é descartada (py:3128; android:432).
class ControleGrafico extends ChangeNotifier {
  ControleGrafico(this._servicos, this.ticker) {
    unawaited(carregar('1D'));
  }

  final ServicosApp _servicos;
  final String ticker;

  String periodo = '1D';
  Grafico? grafico;
  String? erro;
  bool carregandoGrafico = true;
  int _geracao = 0;
  bool _descartado = false;

  @override
  void dispose() {
    _descartado = true;
    super.dispose();
  }

  Future<void> carregar(String p) async {
    final minha = ++_geracao;
    periodo = p;
    grafico = null;
    erro = null;
    carregandoGrafico = true;
    notifyListeners();
    try {
      final g = await _servicos.grafico(ticker, p);
      if (_descartado || minha != _geracao) return;
      grafico = g;
    } catch (e) {
      if (_descartado || minha != _geracao) return;
      erro = textoErro(e);
    }
    carregandoGrafico = false;
    notifyListeners();
  }
}

String _dois(int n) => n.toString().padLeft(2, '0');

/// Rótulo de tempo no fuso do gráfico (py:3133-3143); [curto] é o do eixo.
String rotuloTempo(int ts, int desvio, String periodo, {bool curto = false}) {
  final d = DateTime.fromMillisecondsSinceEpoch(
    (ts + desvio) * 1000,
    isUtc: true,
  );
  final dia = '${_dois(d.day)}/${_dois(d.month)}';
  if (periodo == '1D') return '${_dois(d.hour)}:${_dois(d.minute)}';
  if (periodo == '5D') {
    return curto ? dia : '$dia ${_dois(d.hour)}:${_dois(d.minute)}';
  }
  if (periodo == '5A' || periodo == 'Máx') {
    return '${_dois(d.month)}/${d.year}';
  }
  return curto ? '$dia/${_dois(d.year % 100)}' : '$dia/${d.year}';
}

/// `x or None` do Python: zero e nulo contam como ausente.
bool _tem(double? v) => v != null && v != 0;

String _faixa(double? a, double? b) =>
    _tem(a) && _tem(b) ? '${brl(a!)} – ${brl(b!)}' : '—';

class _Conteudo extends StatelessWidget {
  const _Conteudo({
    required this.ticker,
    required this.nome,
    required this.dados,
    required this.grande,
    required this.amigo,
    required this.jaTenho,
    required this.aoComprar,
    required this.aoVender,
    required this.aoImportar,
    required this.aoVerNoticias,
  });

  final String ticker;
  final String nome;
  final DadosAtivo? dados;
  final bool grande;
  final bool amigo;
  final bool jaTenho;
  final VoidCallback? aoComprar;
  final VoidCallback? aoVender;
  final VoidCallback? aoImportar;
  final VoidCallback? aoVerNoticias;

  @override
  Widget build(BuildContext context) {
    final controle = context.watch<ControleGrafico>();
    final miolo = <Widget>[
      _Cabecalho(ticker: ticker, nome: nome, dados: dados),
      const SizedBox(height: 12),
      _Periodos(controle: controle),
      const SizedBox(height: 8),
      if (grande)
        Expanded(
          child: _Area(controle: controle, grande: grande),
        )
      else
        SizedBox(
          height: 300,
          child: _Area(controle: controle, grande: grande),
        ),
      const SizedBox(height: 8),
      _Estatisticas(dados: dados, grande: grande),
      const SizedBox(height: 12),
      _Acoes(
        mostrarComprar: !amigo && aoComprar != null,
        mostrarVender: !amigo && aoVender != null,
        mostrarImportar: amigo && !jaTenho && aoImportar != null,
        aoComprar: aoComprar,
        aoVender: aoVender,
        aoImportar: aoImportar,
        aoVerNoticias: aoVerNoticias,
      ),
    ];
    return Padding(
      padding: const EdgeInsets.all(20),
      child: grande
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: miolo,
            )
          : SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: miolo,
              ),
            ),
    );
  }
}

class _Cabecalho extends StatelessWidget {
  const _Cabecalho({
    required this.ticker,
    required this.nome,
    required this.dados,
  });

  final String ticker;
  final String nome;
  final DadosAtivo? dados;

  @override
  Widget build(BuildContext context) {
    final c = CoresApp.de(context);
    final d = dados;
    final vp = d?.variacaoPct;
    final v = d?.variacao ?? 0;
    final nomeFinal = nome.isNotEmpty ? nome : (d?.nome ?? '');
    return Row(
      spacing: 12,
      children: [
        LogoAtivo(ticker: ticker, tamanho: 44),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                ticker,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                nomeFinal,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: c.textoSuave, fontSize: 12),
              ),
            ],
          ),
        ),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _tem(d?.preco) ? brl(d!.preco!) : '—',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                vp != null
                    ? '${fmtPct(vp)}  (${v > 0 ? '+' : ''}${brl(v)}) hoje'
                    : 'variação do dia indisponível',
                textAlign: TextAlign.end,
                style: TextStyle(
                  color: corVariacao(context, vp),
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Periodos extends StatelessWidget {
  const _Periodos({required this.controle});

  final ControleGrafico controle;

  @override
  Widget build(BuildContext context) {
    final g = controle.grafico;
    String? variacao;
    double? var_;
    if (g != null && g.referencia != 0) {
      var_ = (g.pontos.last.$2 / g.referencia - 1) * 100;
      final nome = switch (controle.periodo) {
        '1D' => 'hoje',
        'Máx' => 'desde o início',
        final p => 'em $p',
      };
      variacao = '${fmtPct(var_)} $nome';
    }
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final p in periodosGrafico.keys)
          ChipFiltro(
            rotulo: p,
            selecionado: p == controle.periodo,
            aoTocar: () => unawaited(controle.carregar(p)),
          ),
        if (variacao != null)
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Text(
              variacao,
              style: TextStyle(
                color: corVariacao(context, var_),
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
      ],
    );
  }
}

class _Area extends StatelessWidget {
  const _Area({required this.controle, required this.grande});

  final ControleGrafico controle;
  final bool grande;

  @override
  Widget build(BuildContext context) {
    if (controle.carregandoGrafico) {
      return const Carregando(texto: 'Carregando…');
    }
    final erro = controle.erro;
    if (erro != null) {
      return Center(
        child: Semantics(
          liveRegion: true,
          child: Text(
            erro,
            key: const Key('grafico-erro'),
            textAlign: TextAlign.center,
            style: TextStyle(color: CoresApp.de(context).queda),
          ),
        ),
      );
    }
    return _Grafico(
      key: ValueKey('${controle.ticker}-${controle.periodo}'),
      grafico: controle.grafico!,
      grande: grande,
    );
  }
}

/// A linha com o texto do ponto acima e as marcas de tempo abaixo.
class _Grafico extends StatefulWidget {
  const _Grafico({super.key, required this.grafico, required this.grande});

  final Grafico grafico;
  final bool grande;

  @override
  State<_Grafico> createState() => _GraficoState();
}

class _GraficoState extends State<_Grafico> {
  (int, double)? _ponto;

  @override
  Widget build(BuildContext context) {
    final g = widget.grafico;
    final c = CoresApp.de(context);
    final n = g.pontos.length;
    final marcas = n < 4 ? n : 4;
    final tocado = _ponto;
    final String texto;
    Color? corTexto;
    if (tocado == null) {
      texto = widget.grande ? _textoMouse : _textoToque;
    } else {
      final var_ = g.referencia != 0
          ? (tocado.$2 / g.referencia - 1) * 100
          : null;
      texto =
          '${rotuloTempo(tocado.$1, g.desvio, g.periodo)} · ${brl(tocado.$2)} '
          '· ${fmtPct(var_)}';
      corTexto = corVariacao(context, var_);
    }
    final estilo = TextStyle(color: c.textoSuave, fontSize: 11);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          spacing: 12,
          children: [
            Text(
              texto,
              style: TextStyle(
                color: corTexto ?? c.textoSuave,
                fontWeight: tocado == null ? null : FontWeight.bold,
                fontSize: 12,
              ),
            ),
            if (g.periodo == '1D')
              Text('Fech. anterior ${brl(g.referencia)}', style: estilo),
          ],
        ),
        const SizedBox(height: 4),
        Expanded(
          child: GraficoLinha(
            pontos: g.pontos,
            referencia: g.periodo == '1D' ? g.referencia : null,
            interativo: true,
            aoTocar: (p) {
              if (mounted) setState(() => _ponto = p);
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (var k = 0; k < marcas; k++)
                Text(
                  rotuloTempo(
                    g
                        .pontos[(k * (n - 1) / (marcas > 1 ? marcas - 1 : 1))
                            .round()]
                        .$1,
                    g.desvio,
                    g.periodo,
                    curto: true,
                  ),
                  style: estilo,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Estatisticas extends StatelessWidget {
  const _Estatisticas({required this.dados, required this.grande});

  final DadosAtivo? dados;
  final bool grande;

  @override
  Widget build(BuildContext context) {
    final d = dados;
    final c = CoresApp.de(context);
    final itens = <(String, String)>[
      ('Fech. anterior', _tem(d?.anterior) ? brl(d!.anterior!) : '—'),
      ('Mín./máx. do dia', _faixa(d?.minDia, d?.maxDia)),
      ('Mín./máx. 52 sem.', _faixa(d?.min52, d?.max52)),
      (
        'Média 6 meses',
        _tem(d?.media6m)
            ? brl(d!.media6m!) +
                  (d.vsMediaPct != null ? ' (${fmtPct(d.vsMediaPct)})' : '')
            : '—',
      ),
      (
        'ATR (14)',
        _tem(d?.atr)
            ? brl(d!.atr!) +
                  (_tem(d.atrPct) ? ' · ${fmtPct(d.atrPct, sinal: false)}' : '')
            : '—',
      ),
      ('Volume', fmtVolume(d?.volume)),
    ];
    Widget item((String, String) i) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: grande
            ? CrossAxisAlignment.center
            : CrossAxisAlignment.start,
        children: [
          Text(i.$1, style: TextStyle(color: c.textoSuave, fontSize: 10)),
          Text(
            i.$2,
            textAlign: grande ? TextAlign.center : TextAlign.start,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
    return Material(
      color: c.cartao,
      borderRadius: BorderRadius.circular(12),
      child: grande
          ? Row(children: [for (final i in itens) Expanded(child: item(i))])
          : LayoutBuilder(
              builder: (context, caixa) => Wrap(
                children: [
                  for (final i in itens)
                    SizedBox(width: caixa.maxWidth / 2, child: item(i)),
                ],
              ),
            ),
    );
  }
}

class _Acoes extends StatelessWidget {
  const _Acoes({
    required this.mostrarComprar,
    required this.mostrarVender,
    required this.mostrarImportar,
    required this.aoComprar,
    required this.aoVender,
    required this.aoImportar,
    required this.aoVerNoticias,
  });

  final bool mostrarComprar;
  final bool mostrarVender;
  final bool mostrarImportar;
  final VoidCallback? aoComprar;
  final VoidCallback? aoVender;
  final VoidCallback? aoImportar;
  final VoidCallback? aoVerNoticias;

  /// Fecha o gráfico e só então devolve a ação ao radar (py:3014-3016).
  VoidCallback _depois(BuildContext context, VoidCallback? acao) => () {
    Navigator.of(context).pop();
    acao?.call();
  };

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.spaceBetween,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (mostrarComprar)
              FilledButton(
                onPressed: _depois(context, aoComprar),
                child: const Text('Comprar'),
              ),
            if (mostrarVender)
              OutlinedButton(
                onPressed: _depois(context, aoVender),
                child: const Text('Vender'),
              ),
            if (mostrarImportar)
              FilledButton(
                onPressed: _depois(context, aoImportar),
                child: const Text('Meu radar'),
              ),
          ],
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (aoVerNoticias != null)
              OutlinedButton(
                onPressed: _depois(context, aoVerNoticias),
                child: const Text('Ver notícias'),
              ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Fechar'),
            ),
          ],
        ),
      ],
    );
  }
}
