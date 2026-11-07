// Notícias, logos e imagens sobre o repositório local. Roda no isolate de
// serviços: o `ServicoNoticias`, as `Logos` e os clientes são os desse isolate,
// e nada mais grava `noticias.json`/`noticias_detalhes.json`.

import 'dart:typed_data';

import '../../../integracoes/integracoes.dart';
import '../../../nucleo/nucleo.dart';
import '../api.dart';
import '../eventos.dart';
import 'config_segura.dart';

class NoticiasLocal {
  NoticiasLocal({
    required this.repo,
    required this.servico,
    required this.logos,
    required this.cache,
    required this.navegador,
    required this.emitir,
  });

  final Repositorio repo;
  final ServicoNoticias servico;
  final Logos logos;
  final CacheBinario cache;

  /// Cliente das imagens das matérias (`Logos.clienteNavegador`).
  final ClienteHttp navegador;
  final void Function(EventoServico) emitir;

  bool _rodando = false;

  Armazenamento get _disco => repo.armazenamento;

  List<(String, String)> _radar() => [
    for (final r in lerConfigParaGravar(repo).radar) (r.ticker, r.nome),
  ];

  /// O radar na ordem escolhida pelo usuário (opções do filtro de ativo).
  List<(String, String)> _radarOrdenado() => [
    for (final r in ordenarRadar(lerConfigParaGravar(repo).radar))
      (r.ticker, r.nome),
  ];

  VisaoNoticias _visao() {
    final d = lerEstado(_disco);
    return VisaoNoticias(
      itens: d.itens,
      detalhes: lerDetalhes(_disco),
      naoLidas: naoLidas(d),
      hora: d.hora,
      lidasAte: d.lidasAte,
      erros: d.erros,
      rodando: _rodando,
      radar: _radarOrdenado(),
      novas: {
        for (final i in d.itens)
          if (ehNova(d, i)) i.id,
      },
    );
  }

  Future<VisaoNoticias> noticias() async => _visao();

  /// Busca as notícias do radar (calculadora_darf.py:2299-2311). Sem `forcar`,
  /// só busca se passaram 10 min ou se há ativo do radar ainda desconhecido.
  Future<VisaoNoticias> atualizarNoticias({bool forcar = false}) async {
    final radar = _radar();
    if (_rodando || radar.isEmpty) return _visao();
    if (!forcar) {
      final d = lerEstado(_disco);
      final semNoticias = radar.any((r) => !d.conhecidos.contains(r.$1));
      if (!precisaAtualizar(d) && !semNoticias) return _visao();
    }
    _rodando = true;
    final List<Noticia> novas;
    try {
      (_, novas) = await servico.atualizar(radar, detalhes: true);
    } finally {
      _rodando = false;
    }
    final visao = _visao();
    emitir(EventoNoticias(visao, textosNotificacao(novas)));
    return visao;
  }

  /// Passo do timer: o `precisaAtualizar` limita a busca a uma por 10 min. Uma
  /// falha não derruba o timer; a próxima passada tenta de novo.
  Future<void> tick() async {
    try {
      await atualizarNoticias();
    } catch (_) {
      // config ilegível ou disco com problema: o aviso já vem pela casca
    }
  }

  Future<void> marcarNoticiasLidas() async {
    marcarLidas(_disco);
  }

  Future<ImagemBytes?> logo(String ticker) async {
    final png = await logos.logoPng(ticker);
    if (png != null) return ImagemBytes(bytes: png, svg: false);
    final svg = await logos.logoSvg(ticker);
    return svg == null ? null : ImagemBytes(bytes: svg, svg: true);
  }

  Future<Uint8List?> favicon(Noticia item) => logos.favicon(item);

  /// Bytes do JPEG reduzido; falha de rede ou imagem inválida é só "sem
  /// imagem".
  Future<Uint8List?> imagemNoticia(String url) async {
    try {
      final nome = await baixarImagemNoticia(navegador, cache, url);
      return nome == null ? null : await cache.ler(nome);
    } on Exception {
      return null;
    }
  }
}
