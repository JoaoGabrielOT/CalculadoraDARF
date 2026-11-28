// Aba "Gráficos" do cartão do ativo: fechamento diário dos últimos 3 meses,
// último preço × alvos dos especialistas e, havendo posição aberta, preço
// médio × último preço e o resultado bruto da posição. Só monta (e só busca
// no Yahoo) quando o usuário toca na aba.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../nucleo/ambiente.dart';
import '../../../nucleo/datas.dart';
import '../../../nucleo/formatacao.dart';
import '../../../nucleo/modelos/barras.dart';
import '../../../nucleo/posicoes.dart';
import '../../../nucleo/relatorios/relatorio.dart';
import '../../componentes/grafico_barras.dart';
import '../../componentes/grafico_linha.dart';
import '../../servicos/api.dart';
import '../../tema/cores_app.dart';

const _faltaDados = 'Dados insuficientes para o gráfico';

final _moedaValor = RegExp(r'^\s*([^\d\s-]+)\s*(\d[\d.]*(?:,\d+)?)');

/// "R$ 56,90 em 26/11" -> ("R$", 56.9); null sem moeda ou sem número.
(String, double)? lerMoeda(String? texto) {
  final m = _moedaValor.firstMatch(texto ?? '');
  if (m == null) return null;
  return (m.group(1)!, parseValor(m.group(2)));
}

String _dinheiro(String moeda, double v) =>
    moeda == 'R\$' ? brl(v) : '$moeda ${brl(v).substring(3)}';

/// Barras "Último preço × Alvo médio/mín/máx" só com `alvoMedio` e preço na
/// mesma moeda; alvo mín ou máx em outra moeda (ou ilegível) fica de fora.
/// Usa só os campos agregados, não os itens por casa. Null se não comparar.
List<BarraGrafico>? barrasDeAlvo(
  Especialistas esp,
  String? precoDoAtivo,
  Color alta,
  Color queda,
  Color neutra,
) {
  final ultimo = lerMoeda(esp.precoReferencia ?? precoDoAtivo);
  final medio = lerMoeda(esp.alvoMedio);
  if (ultimo == null || medio == null || medio.$1 != ultimo.$1) return null;
  final moeda = ultimo.$1;
  BarraGrafico alvo(String rotulo, (String, double) a) => BarraGrafico(
    rotulo,
    a.$2,
    _dinheiro(moeda, a.$2),
    cor: a.$2 >= ultimo.$2 ? alta : queda,
  );
  final min = lerMoeda(esp.alvoMin), max = lerMoeda(esp.alvoMax);
  return [
    BarraGrafico(
      'Último preço',
      ultimo.$2,
      _dinheiro(moeda, ultimo.$2),
      cor: neutra,
    ),
    alvo('Alvo médio', medio),
    if (min != null && min.$1 == moeda) alvo('Alvo mín', min),
    if (max != null && max.$1 == moeda) alvo('Alvo máx', max),
  ];
}

String _dm(String iso) => '${iso.substring(8, 10)}/${iso.substring(5, 7)}';

int _dia(String iso) =>
    DateTime.parse(iso).difference(DateTime.utc(1970)).inDays;

class _Dados {
  _Dados(this.barras, this.posicao);

  final List<BarraDiaria> barras;
  final PosicaoAtivo? posicao;
}

class GraficosAtivo extends StatefulWidget {
  const GraficosAtivo(this.ativo, {super.key});

  final AtivoRelatorio ativo;

  @override
  State<GraficosAtivo> createState() => _GraficosAtivoState();
}

class _GraficosAtivoState extends State<GraficosAtivo> {
  late final ServicosApp _servicos = context.read<ServicosApp>();
  _Dados? _dados;
  Object? _erro;
  int _geracao = 0;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void didUpdateWidget(GraficosAtivo antigo) {
    super.didUpdateWidget(antigo);
    // Outro ativo na mesma posição: os dados na tela não valem mais.
    if (antigo.ativo != widget.ativo) _carregar();
  }

  Future<void> _carregar() async {
    final geracao = ++_geracao;
    setState(() {
      _dados = null;
      _erro = null;
    });
    final ticker = widget.ativo.ticker;
    try {
      // Posição aberta do ativo (a mesma fonte da carteira do relatório), em
      // paralelo com as barras; se falhar, só os gráficos de posição somem.
      final fPos = _servicos
          .posicoes(ambiente.hoje().substring(0, 7))
          .then<VisaoPosicoes?>((v) => v, onError: (Object _) => null);
      final fBarras = _servicos.barrasDiarias(ticker);
      final r = await Future.wait<Object?>([fPos, fBarras]);
      final v = r[0] as VisaoPosicoes?;
      PosicaoAtivo? posicao;
      for (final p in v?.posicoes ?? const <PosicaoAtivo>[]) {
        if (p.ticker == ticker && p.qtd > 0) posicao = p;
      }
      var d = r[1]! as Diarias;
      // O período padrão não cobre a compra mais antiga: busca de novo.
      final desde = _compraMaisAntiga(posicao);
      if (desde != null &&
          (d.barras.isEmpty || d.barras.first.data.compareTo(desde) > 0)) {
        d = await _servicos.barrasDiarias(ticker, desde: desde);
      }
      if (!mounted || geracao != _geracao) return;
      setState(() => _dados = _Dados(d.barras, posicao));
    } catch (e) {
      if (!mounted || geracao != _geracao) return;
      setState(() => _erro = e);
    }
  }

  /// Data da compra mais antiga com saldo; null sem posição.
  static String? _compraMaisAntiga(PosicaoAtivo? p) {
    String? mais;
    for (final c in p?.compras ?? const <CompraNaPosicao>[]) {
      if (c.restante > 0 &&
          (mais == null || c.dataCompra.compareTo(mais) < 0)) {
        mais = c.dataCompra;
      }
    }
    return mais;
  }

  @override
  Widget build(BuildContext context) {
    final c = CoresApp.de(context);
    final ticker = widget.ativo.ticker;
    if (_erro != null) {
      return Column(
        key: Key('graficos-erro-$ticker'),
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 6,
        children: [
          Text(
            'Não foi possível carregar os gráficos de $ticker.',
            style: TextStyle(color: c.queda, fontSize: 13),
          ),
          TextButton(onPressed: _carregar, child: const Text('Tentar de novo')),
        ],
      );
    }
    final dados = _dados;
    if (dados == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(12),
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    final barras = dados.barras;
    final alvos = barrasDeAlvo(
      widget.ativo.especialistas,
      widget.ativo.preco?.texto,
      c.alta,
      c.queda,
      c.textoSuave,
    );
    final pos = dados.posicao, medio = dados.posicao?.precoMedio;
    final corte = somarDias(ambiente.hoje(), -92);
    final tres = [
      for (final b in barras)
        if (b.data.compareTo(corte) >= 0) b,
    ];
    return Column(
      key: Key('graficos-$ticker'),
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 14,
      children: [
        _Bloco(
          titulo: 'Fechamento diário dos últimos 3 meses',
          resumo: tres.length < 2
              ? null
              : 'Fechamento de ${brl(tres.first.fech)} a ${brl(tres.last.fech)} '
                    'entre ${_dm(tres.first.data)} e ${_dm(tres.last.data)}',
          grafico: SizedBox(
            height: 140,
            child: GraficoLinha(
              pontos: [for (final b in tres) (_dia(b.data), b.fech)],
              referencia: tres.isEmpty ? null : tres.first.fech,
            ),
          ),
        ),
        if (alvos != null)
          _Bloco(
            titulo: 'Último preço × alvos dos especialistas',
            resumo: [for (final b in alvos) '${b.rotulo} ${b.texto}']
                .join('; '),
            grafico: GraficoBarras(barras: alvos),
          ),
        if (pos != null && medio != null && barras.isNotEmpty) ...[
          _Bloco(
            titulo: 'Preço médio de compra × último preço',
            resumo:
                'Preço médio de compra ${brl(medio)}; último preço '
                '${brl(barras.last.fech)}',
            grafico: GraficoBarras(
              barras: [
                BarraGrafico(
                  'Preço médio',
                  medio,
                  brl(medio),
                  cor: c.textoSuave,
                ),
                BarraGrafico(
                  'Último preço',
                  barras.last.fech,
                  brl(barras.last.fech),
                  cor: barras.last.fech >= medio ? c.alta : c.queda,
                ),
              ],
            ),
          ),
          _blocoResultado(pos, medio, barras),
        ],
      ],
    );
  }

  Widget _blocoResultado(
    PosicaoAtivo pos,
    double medio,
    List<BarraDiaria> barras,
  ) {
    final desde = _compraMaisAntiga(pos);
    final serie = [
      for (final b in barras)
        if (desde == null || b.data.compareTo(desde) >= 0)
          (b.data, pos.qtd * (b.fech - medio)),
    ];
    return _Bloco(
      titulo: 'Resultado bruto da posição desde a compra mais antiga',
      resumo: serie.length < 2
          ? null
          : 'Resultado bruto de ${brl(serie.first.$2)} a ${brl(serie.last.$2)} '
                'entre ${_dm(serie.first.$1)} e ${_dm(serie.last.$1)}',
      grafico: SizedBox(
        height: 140,
        child: GraficoLinha(
          pontos: [for (final (d, v) in serie) (_dia(d), v)],
          referencia: 0,
        ),
      ),
    );
  }
}

/// Título, gráfico e legenda textual (o `resumo`, que também é o rótulo de
/// acessibilidade). Sem [resumo] (menos de 2 pontos), só o aviso.
class _Bloco extends StatelessWidget {
  const _Bloco({
    required this.titulo,
    required this.resumo,
    required this.grafico,
  });

  final String titulo;
  final String? resumo;
  final Widget grafico;

  @override
  Widget build(BuildContext context) {
    final c = CoresApp.de(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 4,
      children: [
        Text(
          titulo,
          style: TextStyle(
            color: c.textoSuave,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (resumo == null)
          const Text(_faltaDados, style: TextStyle(fontSize: 13))
        else ...[
          Semantics(
            label: '$titulo. $resumo',
            excludeSemantics: true,
            child: grafico,
          ),
          Text(resumo!, style: TextStyle(color: c.textoSuave, fontSize: 12)),
        ],
      ],
    );
  }
}
