// Tabela ordenável para o layout expandido (calculadora_darf.py:660-795).

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../nucleo/nucleo.dart';
import '../tema/cores_app.dart';

class ColunaTabela<T> {
  const ColunaTabela({
    required this.titulo,
    required this.largura,
    this.alinhamento = TextAlign.left,
    required this.texto,
    this.chave,
    this.cor,
  });

  final String titulo;

  /// Peso relativo da coluna na largura da tabela.
  final double largura;
  final TextAlign alinhamento;
  final String Function(T) texto;

  /// Valor de ordenação (número, texto ou booleano); sem ela a coluna não
  /// ordena. Null conta como -infinito, como no Python.
  final Object? Function(T)? chave;

  /// Cor do texto da célula (muted, neg...); null usa a cor do texto.
  final Color? Function(BuildContext, T)? cor;
}

/// Peso inteiro da coluna: duas casas, para larguras fracionárias (0,3 e 0,1)
/// manterem a proporção, e no mínimo 1.
int _flex(double largura) => math.max(1, (largura * 100).round());

/// Alturas reais do cabeçalho (com o divisor) e de uma linha da [Tabela] no
/// [context] (fonte do tema, densidade e escala de texto do usuário), para
/// quem limita a altura dela.
({double cabecalho, double linha}) alturasTabela(BuildContext context) {
  final estilo = DefaultTextStyle.of(context).style;
  final escala = MediaQuery.textScalerOf(context);
  double texto(FontWeight peso) {
    final tp = TextPainter(
      text: TextSpan(
        text: 'Ág',
        style: estilo.copyWith(fontWeight: peso),
      ),
      textDirection: TextDirection.ltr,
      textScaler: escala,
      maxLines: 1,
    )..layout();
    final altura = tp.height;
    tp.dispose();
    return altura;
  }

  final vertical = CoresApp.de(context).densa ? 6.0 : 10.0;
  return (
    cabecalho: texto(FontWeight.w500) + 20 + 1,
    linha: texto(FontWeight.w400) + 2 * vertical,
  );
}

/// Tabela ordenável. Com altura limitada pelo pai, o corpo rola e é lazy
/// (`ListView.builder`). Sem altura limitada, o corpo vira uma `Column` com
/// todas as linhas, que NÃO é lazy: telas com muitas linhas devem limitar a
/// altura (`Expanded`, `SizedBox`). A ordenação fica guardada com uma cópia
/// das linhas e das chaves: só é refeita se a coluna, o sentido, algum
/// elemento (por identidade) ou alguma chave mudar, então alterar a lista no
/// lugar também funciona. Cada rebuild custa uma passada O(n) nas chaves.
class Tabela<T> extends StatefulWidget {
  const Tabela({
    super.key,
    required this.colunas,
    required this.linhas,
    required this.vazio,
    this.aoSelecionar,
    this.aoDuploClique,
    this.selecionado,
    this.id,
    this.reiniciarOrdem,
    this.filhas,
    this.expandidas = const {},
  }) : assert(
         selecionado == null || id != null,
         'Tabela: para marcar uma linha selecionada informe `id`.',
       );

  final List<ColunaTabela<T>> colunas;
  final List<T> linhas;
  final String vazio;
  final ValueChanged<T>? aoSelecionar;
  final ValueChanged<T>? aoDuploClique;

  /// [id] da linha selecionada; exige [id].
  final String? selecionado;

  /// Identificador único de cada linha (Key e seleção; repetido dá assert em
  /// debug). Sem ele nenhuma linha
  /// é marcada e as Keys usam a posição.
  final String Function(T)? id;

  /// Quando este valor muda, a ordenação feita pelo clique no título é
  /// descartada (a rolagem fica): quem ordena por outro meio (chip) passa aqui
  /// a ordem escolhida.
  final Object? reiniciarOrdem;

  /// Linhas de detalhe de uma linha (exige [id]): aparecem logo abaixo dela,
  /// depois da ordenação, enquanto o id dela estiver em [expandidas]. O id
  /// delas também precisa ser único.
  final List<T> Function(T)? filhas;
  final Set<String> expandidas;

  @override
  State<Tabela<T>> createState() => _TabelaState<T>();
}

class _TabelaState<T> extends State<Tabela<T>> {
  int? _coluna;
  bool _decrescente = false;

  // Cache da ordenação: cópia das linhas e das chaves da última ordenação.
  // Vale se a coluna, o sentido, os elementos (por identidade) e as chaves
  // forem os mesmos; assim a lista alterada no lugar nunca serve dado velho.
  List<T>? _cacheLinhas;
  List<Object?> _cacheChaves = const [];
  int? _cacheColuna;
  bool _cacheDecrescente = false;
  List<T> _cacheResultado = const [];

  bool _cacheValido(int i, List<T> linhas, List<Object?> chaves) {
    final antigas = _cacheLinhas;
    if (antigas == null ||
        _cacheColuna != i ||
        _cacheDecrescente != _decrescente ||
        antigas.length != linhas.length) {
      return false;
    }
    for (var k = 0; k < linhas.length; k++) {
      if (!identical(antigas[k], linhas[k])) return false;
      final a = _cacheChaves[k];
      final b = chaves[k];
      final igual = a == b || (a is num && b is num && a.isNaN && b.isNaN);
      if (!igual) return false;
    }
    return true;
  }

  @override
  void didUpdateWidget(Tabela<T> antigo) {
    super.didUpdateWidget(antigo);
    if (widget.reiniciarOrdem != antigo.reiniciarOrdem) {
      _coluna = null;
      _decrescente = false;
    }
  }

  void _ordenarPor(int i) => setState(() {
    if (_coluna == i) {
      _decrescente = !_decrescente;
    } else {
      _coluna = i;
      _decrescente = false;
    }
  });

  List<T> _ordenadas() {
    final i = _coluna;
    if (i == null || i >= widget.colunas.length) return widget.linhas;
    final chave = widget.colunas[i].chave;
    if (chave == null) return widget.linhas;
    final linhas = widget.linhas;
    final valores = [for (final l in linhas) chave(l)];
    if (_cacheValido(i, linhas, valores)) return _cacheResultado;
    // Só números (e booleanos) ordenam como número, com ausente e NaN em
    // -infinito; qualquer outra mistura cai para a comparação de texto.
    final numerico = valores.every((v) => v == null || v is bool || v is num);
    final indices = ordenadoPor<int>(List.generate(linhas.length, (k) => k), (
      k,
    ) {
      final v = valores[k];
      if (numerico) {
        return [
          v == null || (v is num && v.isNaN) ? double.negativeInfinity : v,
        ];
      }
      return [v == null ? '' : v.toString().toLowerCase()];
    }, reverso: _decrescente);
    _cacheLinhas = List.of(linhas);
    _cacheChaves = valores;
    _cacheColuna = i;
    _cacheDecrescente = _decrescente;
    return _cacheResultado = [for (final k in indices) linhas[k]];
  }

  String _titulo(int i) {
    final col = widget.colunas[i];
    if (col.chave == null) return col.titulo;
    if (_coluna != i) return '${col.titulo} ↕';
    return '${col.titulo} ${_decrescente ? '▼' : '▲'}';
  }

  @override
  Widget build(BuildContext context) {
    final c = CoresApp.de(context);
    assert(() {
      final ids = widget.id;
      if (ids != null) {
        final vistos = <String>{};
        for (final l in widget.linhas) {
          final id = ids(l);
          if (!vistos.add(id)) {
            throw AssertionError(
              'Tabela: o id "$id" se repete; cada linha precisa de um id '
              'único (Key e seleção).',
            );
          }
        }
      }
      return true;
    }());
    final ordenadas = _ordenadas();
    final filhas = widget.filhas;
    final ids = widget.id;
    final linhas = filhas == null || ids == null || widget.expandidas.isEmpty
        ? ordenadas
        : [
            for (final l in ordenadas) ...[
              l,
              if (widget.expandidas.contains(ids(l))) ...filhas(l),
            ],
          ];
    final cabecalho = Row(
      children: [
        for (final (i, col) in widget.colunas.indexed)
          Expanded(
            flex: _flex(col.largura),
            child: InkWell(
              onTap: col.chave == null ? null : () => _ordenarPor(i),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 10,
                ),
                child: Text(
                  _titulo(i),
                  textAlign: col.alinhamento,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: c.textoSuave,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
    Widget linha(int n) {
      final id = widget.id?.call(linhas[n]);
      return _Linha<T>(
        colunas: widget.colunas,
        dados: linhas[n],
        // Sem `id`, a posição mantém as Keys únicas com textos repetidos.
        chaveLinha: id ?? '#$n',
        zebra: n.isOdd,
        selecionada: id != null && widget.selecionado == id,
        aoSelecionar: widget.aoSelecionar,
        aoDuploClique: widget.aoDuploClique,
      );
    }

    return LayoutBuilder(
      builder: (context, caixa) {
        final Widget corpo;
        if (linhas.isEmpty) {
          corpo = Padding(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: Text(widget.vazio, style: TextStyle(color: c.textoSuave)),
            ),
          );
        } else if (caixa.hasBoundedHeight) {
          corpo = ListView.builder(
            itemCount: linhas.length,
            itemBuilder: (_, n) => linha(n),
          );
        } else {
          corpo = Column(
            children: [for (var n = 0; n < linhas.length; n++) linha(n)],
          );
        }
        return Column(
          mainAxisSize: caixa.hasBoundedHeight
              ? MainAxisSize.max
              : MainAxisSize.min,
          children: [
            cabecalho,
            Divider(height: 1, color: c.linha),
            if (caixa.hasBoundedHeight) Expanded(child: corpo) else corpo,
          ],
        );
      },
    );
  }
}

class _Linha<T> extends StatelessWidget {
  const _Linha({
    required this.colunas,
    required this.dados,
    required this.chaveLinha,
    required this.zebra,
    required this.selecionada,
    required this.aoSelecionar,
    required this.aoDuploClique,
  });

  final List<ColunaTabela<T>> colunas;
  final T dados;
  final String chaveLinha;
  final bool zebra;
  final bool selecionada;
  final ValueChanged<T>? aoSelecionar;
  final ValueChanged<T>? aoDuploClique;

  @override
  Widget build(BuildContext context) {
    final c = CoresApp.de(context);
    final fundo = selecionada
        ? c.destaque.withValues(alpha: .16)
        : (zebra
              ? c.linha.withValues(alpha: c.linha.a * .5)
              : Colors.transparent);
    final vertical = c.densa ? 6.0 : 10.0;
    return Semantics(
      key: Key('linha-$chaveLinha'),
      container: true,
      selected: selecionada,
      child: Material(
        color: fundo,
        child: InkWell(
          onTap: aoSelecionar == null ? null : () => aoSelecionar!(dados),
          onDoubleTap: aoDuploClique == null
              ? null
              : () => aoDuploClique!(dados),
          child: Row(
            children: [
              for (final (i, col) in colunas.indexed)
                Expanded(
                  flex: _flex(col.largura),
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: vertical,
                    ),
                    child: Text(
                      col.texto(dados),
                      key: Key('coluna-$i'),
                      textAlign: col.alinhamento,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: col.cor?.call(context, dados) ?? c.texto,
                        // Negrito na linha selecionada: pista além da cor.
                        fontWeight: selecionada
                            ? FontWeight.w700
                            : FontWeight.w400,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
