// Tela Caixa: o fluxo disponível + a receber − a pagar = projetado, o alerta,
// as próximas liquidações e os lançamentos (calculadora_darf.py:582-642,
// 1795-1984); no celular, a agenda financeira (android/main.py:1549-1626).

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../nucleo/nucleo.dart';
import '../../componentes/cartao.dart';
import '../../componentes/carregando.dart';
import '../../componentes/tabela.dart';
import '../../estado/estado_app.dart';
import '../../servicos/api.dart';
import '../../tema/cores_app.dart';
import '../../tema/layout.dart';
import '../apuracao/lista_lotes.dart' show alturaTabela;
import '../apuracao/seletor_visao.dart';
import 'controle_caixa.dart';

/// Quantas liquidações futuras aparecem como cartão (py:1943).
const maxProximas = 8;

/// Lançamentos listados num cartão antes do "+ N lançamento(s)" (py:605).
const maxItensCartao = 5;

class TelaCaixa extends StatelessWidget {
  const TelaCaixa({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<ControleCaixa>(
      create: (c) => ControleCaixa(c.read<ServicosApp>(), c.read<EstadoApp>()),
      child: const _Corpo(),
    );
  }
}

class _Corpo extends StatelessWidget {
  const _Corpo();

  @override
  Widget build(BuildContext context) {
    final controle = context.watch<ControleCaixa>();
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: expandido(context)
          ? _Expandido(controle: controle)
          : _Compacto(controle: controle),
    );
  }
}

/// Verde para entrada, vermelho para saída, o texto comum para zero.
Color? _corValor(CoresApp c, double v) => v > 0.004
    ? c.alta
    : v < -0.004
    ? c.queda
    : null;

String _comSinal(double v) => (v > 0.004 ? '+' : '') + brl(v);

String _textoDono(String amigo) => 'Caixa de $amigo · somente leitura';

/// Faixa fina de progresso: o carregamento nunca cobre a tela.
class _Progresso extends StatelessWidget {
  const _Progresso(this.ativo);

  final bool ativo;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 3,
    child: ativo
        ? const LinearProgressIndicator(key: ValueKey('progresso-tela'))
        : null,
  );
}

/// Erro de carga, com o seletor de visão ainda à mão.
class _Erro extends StatelessWidget {
  const _Erro(this.texto);

  final String texto;

  @override
  Widget build(BuildContext context) {
    final c = CoresApp.de(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: c.aviso.withValues(alpha: .18),
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(Icons.warning_amber, color: c.aviso),
              const SizedBox(width: 12),
              Expanded(child: Semantics(liveRegion: true, child: Text(texto))),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Caixa de `email` · somente leitura".
class _Dono extends StatelessWidget {
  const _Dono(this.amigo);

  final String amigo;

  @override
  Widget build(BuildContext context) => Text(
    _textoDono(amigo),
    style: TextStyle(
      color: CoresApp.de(context).aviso,
      fontSize: 12,
      fontWeight: FontWeight.bold,
    ),
  );
}

// --- expandido (Windows)

class _Expandido extends StatelessWidget {
  const _Expandido({required this.controle});

  final ControleCaixa controle;

  @override
  Widget build(BuildContext context) {
    final c = CoresApp.de(context);
    final visao = controle.visao;
    final amigo = controle.amigo;
    final definido = visao?.resumo.definido ?? false;
    final livre = visao != null && amigo == null && !controle.editando;
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Progresso(controle.carregando),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
            child: Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  'Visualizando',
                  style: TextStyle(
                    color: c.textoSuave,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SeletorVisao(),
                if (amigo != null) _Dono(amigo),
                if (amigo == null && visao != null) ...[
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: livre
                        ? () => controle.editarSaldo(context)
                        : null,
                    child: Text(
                      definido ? '✎  Definir saldo' : '✎  Informar saldo',
                    ),
                  ),
                  OutlinedButton(
                    onPressed: livre && definido
                        ? () => controle.editarSaldo(context, ModoSaldo.aporte)
                        : null,
                    child: const Text('+  Aporte'),
                  ),
                  OutlinedButton(
                    onPressed: livre && definido
                        ? () =>
                              controle.editarSaldo(context, ModoSaldo.retirada)
                        : null,
                    child: const Text('−  Retirada'),
                  ),
                ],
              ],
            ),
          ),
          if (controle.erro != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: _Erro(controle.erro!),
            ),
          if (visao == null && controle.erro == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 64),
              child: Carregando(),
            )
          else if (visao != null) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 10),
              child: _Fluxo(resumo: visao.resumo, amigo: amigo),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 10),
              child: _Alerta(visao: visao, amigo: amigo),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 10),
              child: _Proximas(visao: visao),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: _Lancamentos(controle: controle, visao: visao),
            ),
          ],
        ],
      ),
    );
  }
}

/// Um termo da conta do caixa (BlocoCaixa, py:582-596).
class _Bloco extends StatelessWidget {
  const _Bloco({
    required super.key,
    required this.titulo,
    required this.valor,
    required this.sub,
    this.corValor,
    this.destaque = false,
  });

  final String titulo;
  final String valor;
  final String sub;
  final Color? corValor;
  final bool destaque;

  @override
  Widget build(BuildContext context) {
    final c = CoresApp.de(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: destaque
            ? c.seloAltaFundo
            : Color.alphaBlend(c.chipFundo, c.cartao),
        borderRadius: BorderRadius.circular(12),
        border: destaque ? Border.all(color: c.destaque, width: 2) : null,
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              titulo.toUpperCase(),
              style: TextStyle(
                color: c.textoSuave,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                valor,
                style: TextStyle(
                  color: corValor ?? c.texto,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Text(sub, style: TextStyle(color: c.textoSuave, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}

/// disponível + a receber − a pagar = projetado (py:1820-1832, 1895-1908).
class _Fluxo extends StatelessWidget {
  const _Fluxo({required this.resumo, required this.amigo});

  final ResumoCaixa resumo;
  final String? amigo;

  @override
  Widget build(BuildContext context) {
    final c = CoresApp.de(context);
    final r = resumo;
    Widget operador(String op) => SizedBox(
      width: 36,
      child: Center(
        child: Text(
          op,
          style: TextStyle(
            color: c.textoSuave,
            fontSize: 26,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
    return Cartao(
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: _Bloco(
                key: const Key('bloco-disponivel'),
                titulo: 'Disponível agora',
                valor: r.definido ? brl(r.disponivel) : '—',
                sub: r.definido
                    ? 'livre para operar hoje'
                    : (amigo != null
                          ? 'não informado'
                          : 'clique em Informar saldo'),
                corValor: r.definido && r.disponivel < 0 ? c.queda : null,
              ),
            ),
            operador('+'),
            Expanded(
              child: _Bloco(
                key: const Key('bloco-receber'),
                titulo: 'A receber',
                valor: r.aReceber > 0.004 ? '+${brl(r.aReceber)}' : brl(0),
                sub: 'vendas ainda não liquidadas',
                corValor: r.aReceber > 0.004 ? c.alta : null,
              ),
            ),
            operador('−'),
            Expanded(
              child: _Bloco(
                key: const Key('bloco-pagar'),
                titulo: 'A pagar',
                valor: r.aDebitar < -0.004 ? brl(-r.aDebitar) : brl(0),
                sub: 'compras e IRRF ainda não liquidados',
                corValor: r.aDebitar < -0.004 ? c.queda : null,
              ),
            ),
            operador('='),
            Expanded(
              child: _Bloco(
                key: const Key('bloco-projetado'),
                titulo: 'Saldo projetado',
                valor: r.definido ? brl(r.projetado) : '—',
                sub: 'depois de tudo liquidar',
                corValor: r.definido && r.projetado < 0 ? c.queda : null,
                destaque: true,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Faixa de alerta (py:1910-1928): sem saldo, saldo negativo na projeção ou
/// saldo disponível negativo; some quando está tudo certo.
class _Alerta extends StatelessWidget {
  const _Alerta({required this.visao, required this.amigo});

  final VisaoCaixa visao;
  final String? amigo;

  @override
  Widget build(BuildContext context) {
    final c = CoresApp.de(context);
    final r = visao.resumo;
    final String texto;
    final bool perigo;
    if (!r.definido) {
      texto = amigo != null
          ? '$amigo ainda não informou o saldo da conta.'
          : 'ⓘ  Informe quanto você tem livre na corretora hoje. Depois disso '
                'o app soma as vendas e desconta as compras sozinho, na data '
                'em que cada uma liquida.';
      perigo = false;
    } else {
      final negativo = visao.projecao
          .where((p) => p.saldoApos < -0.004)
          .firstOrNull;
      if (negativo != null) {
        final quem = amigo != null ? 'O saldo de $amigo' : 'Seu saldo';
        texto =
            '⚠  $quem fica negativo (${brl(negativo.saldoApos)}) na '
            'liquidação de ${fmtLiquidacao(negativo.data).toLowerCase()}. '
            'Deposite a diferença até essa data para cobrir as compras.';
        perigo = true;
      } else if (r.disponivel < -0.004) {
        texto = '⚠  O saldo disponível está negativo.';
        perigo = true;
      } else {
        return const SizedBox.shrink();
      }
    }
    // Perigo com borda na cor de queda: o fundo do selo é transparente no
    // Terminal, e o Python mostra este aviso como faixa vermelha.
    return Material(
      color: perigo ? c.seloQuedaFundo : c.seloAltaFundo,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: perigo ? BorderSide(color: c.queda) : BorderSide.none,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Semantics(
          liveRegion: true,
          child: Text(
            texto,
            style: TextStyle(
              color: perigo ? c.queda : c.texto,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }
}

/// Próximas liquidações: até [maxProximas] cartões em até quatro colunas.
class _Proximas extends StatelessWidget {
  const _Proximas({required this.visao});

  final VisaoCaixa visao;

  @override
  Widget build(BuildContext context) {
    final c = CoresApp.de(context);
    final dias = visao.projecao.take(maxProximas).toList();
    return Cartao(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text(
                'Próximas liquidações',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              Text(
                'o dinheiro entra ou sai da conta 2 dias úteis depois da '
                'operação (D+2)',
                style: TextStyle(color: c.textoSuave, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (dias.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: Text(
                  'Nada a liquidar nos próximos dias. Compras e vendas '
                  'aparecem aqui com a data em que o dinheiro entra ou sai '
                  'da conta.',
                  style: TextStyle(color: c.textoSuave, fontSize: 13),
                ),
              ),
            )
          else
            LayoutBuilder(
              builder: (context, caixa) {
                const espaco = 12.0;
                // Quatro colunas como no Python; em janela estreita, menos,
                // para cada cartão manter uns 200 px.
                final colunas = ((caixa.maxWidth + espaco) / (200 + espaco))
                    .floor()
                    .clamp(1, 4);
                final largura =
                    (caixa.maxWidth - (colunas - 1) * espaco) / colunas;
                return Wrap(
                  spacing: espaco,
                  runSpacing: espaco,
                  children: [
                    for (final d in dias)
                      SizedBox(
                        width: largura,
                        child: _CartaoLiquidacao(
                          dia: d,
                          definido: visao.resumo.definido,
                        ),
                      ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }
}

/// Um dia com liquidações (CardLiquidacao, py:598-642).
class _CartaoLiquidacao extends StatelessWidget {
  const _CartaoLiquidacao({required this.dia, required this.definido});

  final DiaProjecao dia;
  final bool definido;

  @override
  Widget build(BuildContext context) {
    final c = CoresApp.de(context);
    final partes = dia.rotulo.split(' (');
    final nome = partes.first.split(',').first;
    final dmais = partes.length > 1
        ? partes.sublist(1).join(' (').replaceFirst(RegExp(r'\)$'), '')
        : null;
    final itens = dia.itens;
    return DecoratedBox(
      key: ValueKey('liquidacao-${dia.data}'),
      decoration: BoxDecoration(
        color: Color.alphaBlend(c.chipFundo, c.cartao),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.linha),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    nome,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (dmais != null) Pilula(texto: dmais),
              ],
            ),
            Text(
              fmtLiquidacao(dia.data),
              style: TextStyle(color: c.textoSuave, fontSize: 11),
            ),
            const SizedBox(height: 8),
            for (final it in itens.take(maxItensCartao))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Text(
                      it.ticker,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        it.tipo,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: c.textoSuave, fontSize: 11),
                      ),
                    ),
                    Text(
                      _comSinal(it.valor),
                      style: TextStyle(
                        color: _corValor(c, it.valor) ?? c.textoSuave,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            if (itens.length > maxItensCartao)
              Text(
                '+ ${itens.length - maxItensCartao} lançamento(s)',
                style: TextStyle(color: c.textoSuave, fontSize: 11),
              ),
            Divider(height: 16, color: c.linha),
            _Linha(
              rotulo: 'Total do dia',
              valor: _comSinal(dia.total),
              cor: _corValor(c, dia.total) ?? c.textoSuave,
              tamanho: 14,
            ),
            if (definido)
              _Linha(
                rotulo: 'Saldo depois',
                valor: brl(dia.saldoApos),
                cor: dia.saldoApos < -0.004 ? c.queda : c.texto,
                tamanho: 13,
              ),
          ],
        ),
      ),
    );
  }
}

class _Linha extends StatelessWidget {
  const _Linha({
    required this.rotulo,
    required this.valor,
    required this.cor,
    required this.tamanho,
  });

  final String rotulo;
  final String valor;
  final Color cor;
  final double tamanho;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(
        rotulo,
        style: TextStyle(color: CoresApp.de(context).textoSuave, fontSize: 12),
      ),
      Text(
        valor,
        style: TextStyle(
          color: cor,
          fontSize: tamanho,
          fontWeight: FontWeight.bold,
        ),
      ),
    ],
  );
}

/// Lançamentos: filtro por situação e tabela ordenável (py:1852-1872).
class _Lancamentos extends StatelessWidget {
  const _Lancamentos({required this.controle, required this.visao});

  final ControleCaixa controle;
  final VisaoCaixa visao;

  @override
  Widget build(BuildContext context) {
    final c = CoresApp.de(context);
    final r = visao.resumo;
    final linhas = controle.lancamentos;
    final colunas = <ColunaTabela<LancamentoCaixa>>[
      ColunaTabela(
        titulo: 'LIQUIDAÇÃO',
        largura: 190,
        texto: (l) => fmtLiquidacao(l.liquidacao),
        chave: (l) => l.liquidacao,
        cor: _suave,
      ),
      ColunaTabela(
        titulo: 'OPERAÇÃO',
        largura: 100,
        alinhamento: TextAlign.center,
        texto: (l) => fmtData(l.data),
        chave: (l) => l.data,
        cor: _suave,
      ),
      ColunaTabela(
        titulo: 'TICKER',
        largura: 90,
        texto: (l) => l.ticker,
        chave: (l) => l.ticker,
        cor: _suave,
      ),
      ColunaTabela(
        titulo: 'TIPO',
        largura: 140,
        texto: (l) => l.tipo,
        cor: _suave,
      ),
      ColunaTabela(
        titulo: 'VALOR NA CONTA',
        largura: 150,
        alinhamento: TextAlign.right,
        texto: (l) => _comSinal(l.valor),
        chave: (l) => l.valor,
        cor: (ctx, l) => _corValor(c, l.valor) ?? _suave(ctx, l),
      ),
      ColunaTabela(
        titulo: 'SITUAÇÃO',
        largura: 110,
        alinhamento: TextAlign.center,
        texto: (l) => l.status == 'Liquidado' ? 'Liquidado' : 'A liquidar',
        cor: _suave,
      ),
    ];
    return Cartao(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text(
                'Lançamentos',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              if (r.definido) _InfoSaldo(resumo: r),
              BotaoSegmentado<FiltroAgenda>(
                opcoes: [for (final f in FiltroAgenda.values) (f, f.rotulo)],
                valor: controle.filtro,
                aoMudar: controle.definirFiltro,
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: alturaTabela(context, linhas.length),
            child: Tabela<LancamentoCaixa>(
              key: const Key('tabela-lancamentos'),
              colunas: colunas,
              linhas: linhas,
              id: (l) => l.id,
              vazio:
                  'Nenhum lançamento. Compras e vendas aparecem aqui com a '
                  'data em que o dinheiro entra ou sai.',
            ),
          ),
        ],
      ),
    );
  }

  /// Liquidados em cor suave (py:1957).
  static Color? _suave(BuildContext ctx, LancamentoCaixa l) =>
      l.status == 'Liquidado' ? CoresApp.de(ctx).textoSuave : null;
}

/// "Saldo informado em dd/mm/aaaa: R$ … · liquidado desde então: +R$ …".
class _InfoSaldo extends StatelessWidget {
  const _InfoSaldo({required this.resumo});

  final ResumoCaixa resumo;

  @override
  Widget build(BuildContext context) {
    final r = resumo;
    final extra = r.entrou.abs() > 0.004
        ? ' · liquidado desde então: ${r.entrou > 0 ? '+' : ''}${brl(r.entrou)}'
        : '';
    return Text(
      'Saldo informado em ${fmtData(r.base!)}: ${brl(r.saldoBase)}$extra',
      style: TextStyle(color: CoresApp.de(context).textoSuave, fontSize: 12),
    );
  }
}

// --- compacto (celular)

class _Compacto extends StatelessWidget {
  const _Compacto({required this.controle});

  final ControleCaixa controle;

  @override
  Widget build(BuildContext context) {
    final visao = controle.visao;
    final amigo = controle.amigo;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        _Progresso(controle.carregando),
        const SizedBox(height: 12),
        const SeletorVisao(largura: double.infinity),
        if (amigo != null) ...[const SizedBox(height: 8), _Dono(amigo)],
        const SizedBox(height: 12),
        if (controle.erro != null) _Erro(controle.erro!),
        if (visao == null && controle.erro == null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 48),
            child: Carregando(),
          )
        else if (visao != null)
          ..._agenda(context, visao, amigo),
      ],
    );
  }

  List<Widget> _agenda(BuildContext context, VisaoCaixa v, String? amigo) {
    final c = CoresApp.de(context);
    final r = v.resumo;
    final info = r.definido
        ? 'Saldo informado em ${fmtData(r.base!)}. As liquidações seguintes '
              'entram sozinhas quando a data chega.'
        : (amigo != null
              ? '$amigo ainda não informou o saldo da conta.'
              : 'Informe o saldo livre na conta da corretora para '
                    'acompanhar o caixa.');
    final partes = [
      if (r.aDebitar != 0) '${brl(r.aDebitar)} a debitar',
      if (r.aReceber != 0) '+${brl(r.aReceber)} a receber',
    ];
    final pendentes = [
      for (final g in v.agenda)
        if (g.data.compareTo(v.hoje) > 0) g,
    ];
    final liquidados = [
      for (final g in v.agenda)
        if (g.data.compareTo(v.hoje) <= 0) g,
    ].reversed.toList();
    Widget cartao(String titulo, String valor, String sub, Color? cor) =>
        Expanded(
          child: Cartao(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Rotulo(titulo),
                const SizedBox(height: 4),
                Text(
                  valor,
                  style: TextStyle(
                    color: cor ?? c.texto,
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(sub, style: TextStyle(color: c.textoSuave, fontSize: 11)),
              ],
            ),
          ),
        );
    return [
      Cartao(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(child: _Rotulo('Saldo disponível (D+0)')),
                if (amigo == null)
                  FilledButton.icon(
                    onPressed: controle.editando
                        ? null
                        : () => controle.editarSaldo(context),
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Editar'),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              r.definido ? brl(r.disponivel) : '—',
              style: TextStyle(
                color: r.definido && r.disponivel < 0 ? c.queda : c.texto,
                fontSize: 32,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Text(info, style: TextStyle(color: c.textoSuave, fontSize: 12)),
          ],
        ),
      ),
      const SizedBox(height: 12),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 10,
        children: [
          cartao(
            'Em trânsito (D+1/D+2)',
            brl(r.transito),
            partes.isEmpty ? 'Nada pendente' : partes.join('\n'),
            _corValor(c, r.transito),
          ),
          cartao(
            'Saldo projetado',
            r.definido ? brl(r.projetado) : '—',
            'Disponível + liquidações futuras',
            r.definido && r.projetado < 0 ? c.queda : null,
          ),
        ],
      ),
      const SizedBox(height: 12),
      const Text(
        'Agenda financeira',
        style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 12),
      if (v.agenda.isEmpty)
        Column(
          children: [
            Icon(Icons.event_available, size: 40, color: c.textoSuave),
            const SizedBox(height: 8),
            const Text(
              'Nenhum lançamento',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Compras e vendas aparecem aqui com a data de liquidação '
              '(D+2 úteis).',
              textAlign: TextAlign.center,
              style: TextStyle(color: c.textoSuave, fontSize: 12),
            ),
          ],
        )
      else if (pendentes.isEmpty)
        Text(
          'Nenhuma liquidação pendente.',
          style: TextStyle(color: c.textoSuave, fontSize: 13),
        ),
      for (final g in pendentes) ...[
        _GrupoAgenda(grupo: g),
        const SizedBox(height: 12),
      ],
      if (liquidados.isNotEmpty) ...[
        const _Rotulo('Liquidados recentemente'),
        const SizedBox(height: 12),
        for (final g in liquidados) ...[
          _GrupoAgenda(grupo: g),
          const SizedBox(height: 12),
        ],
      ],
    ];
  }
}

class _Rotulo extends StatelessWidget {
  const _Rotulo(this.texto);

  final String texto;

  @override
  Widget build(BuildContext context) => Text(
    texto,
    style: TextStyle(
      color: CoresApp.de(context).textoSuave,
      fontSize: 12,
      fontWeight: FontWeight.bold,
    ),
  );
}

/// Um dia da agenda: rótulo, total e os lançamentos dele.
class _GrupoAgenda extends StatelessWidget {
  const _GrupoAgenda({required this.grupo});

  final GrupoAgenda grupo;

  @override
  Widget build(BuildContext context) {
    final c = CoresApp.de(context);
    return Cartao(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  grupo.rotulo,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Text(
                _comSinal(grupo.total),
                style: TextStyle(
                  color: _corValor(c, grupo.total),
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          Divider(height: 20, color: c.linha),
          for (final it in grupo.itens)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${it.ticker} · ${it.tipo}',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Operação ${fmtData(it.data)} · ${it.status}',
                          style: TextStyle(color: c.textoSuave, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    _comSinal(it.valor),
                    style: TextStyle(
                      color: _corValor(c, it.valor),
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
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
