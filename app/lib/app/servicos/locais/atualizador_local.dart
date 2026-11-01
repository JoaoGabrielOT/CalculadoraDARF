// Verificação e download da atualização. Usa só o `File` devolvido por
// `baixarAtualizacao` (o destino definitivo só existe depois de conferido).

import 'dart:io';

import '../../../integracoes/integracoes.dart'
    hide baixarAtualizacao, verificarAtualizacao;
import '../../../integracoes/integracoes.dart'
    as ig
    show baixarAtualizacao, verificarAtualizacao;
import '../eventos.dart';

const _intervaloProgresso = Duration(milliseconds: 300);

class AtualizadorLocal {
  AtualizadorLocal({
    required this.http,
    required this.pastaTemporaria,
    required this.windows,
    required this.emitir,
  });

  final ClienteHttp http;
  final String pastaTemporaria;
  final bool windows;
  final void Function(EventoServico) emitir;

  bool _cancelado = false;

  Future<InfoAtualizacao?> verificarAtualizacao() => ig.verificarAtualizacao(
    http,
    nomeAsset: nomeAssetDaPlataforma(windows: windows),
  );

  /// Baixa para `<temp>/CalculadoraDARF-<versao>.exe|.apk` (android/main.py:
  /// 2820) e devolve o caminho. O progresso sai no máximo a cada 300 ms e
  /// uma última vez ao fim.
  Future<String> baixarAtualizacao(InfoAtualizacao info) async {
    _cancelado = false;
    final extensao = windows ? 'exe' : 'apk';
    final destino = File(
      '$pastaTemporaria/CalculadoraDARF-${info.versao}.$extensao',
    );
    final relogio = Stopwatch()..start();
    Duration? ultimo;
    var visto = (0, 0);
    var emitido = (-1, -1);
    final arquivo = await ig.baixarAtualizacao(
      http,
      info,
      destino,
      cancelado: () => _cancelado,
      progresso: (baixado, total) {
        visto = (baixado, total);
        final agora = relogio.elapsed;
        if (ultimo != null && agora - ultimo! < _intervaloProgresso) return;
        ultimo = agora;
        emitido = visto;
        emitir(EventoProgresso(baixado, total));
      },
    );
    if (visto != emitido) emitir(EventoProgresso(visto.$1, visto.$2));
    return arquivo.path;
  }

  Future<void> cancelarDownload() async => _cancelado = true;
}
