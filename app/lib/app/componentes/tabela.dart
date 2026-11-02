// Tabela ordenável para o layout expandido (calculadora_darf.py:660-795).

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
  });

  final List<ColunaTabela<T>> colunas;
  final List<T> linhas;
  final String vazio;
  final ValueChanged<T>? aoSelecionar;
  final ValueChanged<T>? aoDuploClique;

  /// Identificador da linha selecionada (veja [id]).
  final String? selecionado;

  /// Identificador de cada linha; sem ele vale o texto da primeira coluna.
  final String Function(T)? id;

  @override
  State<Tabela<T>> createState() => _TabelaState<T>();
}

class _TabelaState<T> extends State<Tabela<T>> {
  int? _coluna;
  bool _decrescente = false;

  String _id(T l) => widget.id?.call(l) ?? widget.colunas.first.texto(l);

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
    final temTexto = widget.linhas.any((l) => chave(l) is String);
    return ordenadoPor<T>(widget.linhas, (l) {
      final v = chave(l);
      if (v == null) return [temTexto ? '' : double.negativeInfinity];
      if (v is String) return [v.toLowerCase()];
      return [v];
    }, reverso: _decrescente);
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
    final linhas = _ordenadas();
    final cabecalho = Row(
      children: [
        for (final (i, col) in widget.colunas.indexed)
          Expanded(
            flex: col.largura.round(),
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
    Widget linha(int n) => _Linha<T>(
      colunas: widget.colunas,
      dados: linhas[n],
      id: _id(linhas[n]),
      zebra: n.isOdd,
      selecionada: widget.selecionado == _id(linhas[n]),
      aoSelecionar: widget.aoSelecionar,
      aoDuploClique: widget.aoDuploClique,
    );

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
    required this.id,
    required this.zebra,
    required this.selecionada,
    required this.aoSelecionar,
    required this.aoDuploClique,
  });

  final List<ColunaTabela<T>> colunas;
  final T dados;
  final String id;
  final bool zebra;
  final bool selecionada;
  final ValueChanged<T>? aoSelecionar;
  final ValueChanged<T>? aoDuploClique;

  @override
  Widget build(BuildContext context) {
    final c = CoresApp.de(context);
    final fundo = selecionada
        ? c.destaque.withValues(alpha: .16)
        : (zebra ? c.linha.withValues(alpha: .5) : Colors.transparent);
    final vertical = c.densa ? 6.0 : 10.0;
    return Semantics(
      key: Key('linha-$id'),
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
                  flex: col.largura.round(),
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
