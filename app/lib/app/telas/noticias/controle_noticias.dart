// Estado da tela Notícias: a visão lida do disco (matérias, prévias e radar), os
// filtros, o status e o que acontece ao entrar e sair da aba
// (calculadora_darf.py:1786-1790, 2129-2336; android/main.py:679-683,
// 1868-1997). A busca em si é do `EstadoApp`: ela acontece com a aba fechada.

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../integracoes/integracoes.dart';
import '../../../nucleo/nucleo.dart';
import '../../estado/estado_app.dart';
import '../../regras/textos.dart';
import '../../servicos/api.dart';
import 'mural.dart';

const todasNoticias = 'Todas';
const relevantesNoticias = 'Relevantes';
const todosAtivos = 'Todos os ativos';
const textoStatusNoticias = 'Google Notícias · ativos do Radar de Ações';
const textoStatusBuscando = 'Buscando notícias…';

class ControleNoticias extends ChangeNotifier {
  ControleNoticias(this._servicos, this._estado) {
    _versao = _estado.versaoNoticias;
    _naAba = _estado.aba == Aba.noticias;
    _aplicarFiltroDoEstado();
    _estado.addListener(_aoMudarEstado);
    unawaited(recarregar());
    // fora do `build` em que o provedor cria o controle
    if (_naAba) scheduleMicrotask(() => unawaited(_estado.atualizarNoticias()));
  }

  final ServicosApp _servicos;
  final EstadoApp _estado;

  late int _versao;
  late bool _naAba;
  int _geracao = 0;
  bool _descartado = false;

  /// O ticker do filtro veio do gráfico do ativo: sai quando o usuário deixa
  /// a aba.
  bool _doGrafico = false;

  final Map<String, Future<Uint8List?>> _imagens = {};
  final Map<String, Future<Uint8List?>> _favicons = {};

  String tema = todasNoticias;
  String ticker = todosAtivos;

  /// As notícias na tela; null enquanto a primeira leitura não chega. Se uma
  /// nova leitura falhar, a anterior continua à vista com o [erro] por cima.
  VisaoNoticias? visao;
  String? erro;

  @override
  void notifyListeners() {
    if (!_descartado) super.notifyListeners();
  }

  @override
  void dispose() {
    _descartado = true;
    _estado.removeListener(_aoMudarEstado);
    super.dispose();
  }

  void _aoMudarEstado() {
    final naAba = _estado.aba == Aba.noticias;
    final mudouAba = naAba != _naAba;
    _naAba = naAba;
    var recarregarAgora = false;
    if (_estado.versaoNoticias != _versao) {
      _versao = _estado.versaoNoticias;
      recarregarAgora = true;
    }
    if (mudouAba) {
      if (!naAba && _doGrafico) _soltarFiltroDoGrafico();
      recarregarAgora = true; // entrar mostra o "Nova"; sair o tira
    }
    _aplicarFiltroDoEstado();
    if (recarregarAgora) unawaited(recarregar());
    if (mudouAba && naAba) unawaited(_estado.atualizarNoticias());
    notifyListeners(); // o status depende da busca do estado
  }

  /// Adota o ticker que o gráfico pediu; devolve se mudou algo.
  bool _aplicarFiltroDoEstado() {
    final filtro = _estado.filtroNoticias;
    if (filtro == null || (filtro == ticker && _doGrafico)) return false;
    ticker = filtro;
    _doGrafico = true;
    return true;
  }

  void _soltarFiltroDoGrafico() {
    _doGrafico = false;
    ticker = todosAtivos;
    _estado.limparFiltroNoticias();
  }

  // --- a visão

  /// Vale a última leitura. Com a aba aberta, marca as notícias como lidas
  /// depois de ler (o "Nova" fica à vista até a próxima leitura).
  Future<void> recarregar() async {
    final geracao = ++_geracao;
    try {
      final nova = await _servicos.noticias();
      if (geracao != _geracao) return;
      visao = nova;
      erro = null;
    } catch (e) {
      if (geracao != _geracao) return;
      erro = e is PedidoSuperado ? null : textoErro(e);
      notifyListeners();
      return;
    }
    _validarTicker(nova: visao!);
    notifyListeners();
    if (_naAba) unawaited(_estado.marcarNoticiasLidas());
  }

  /// Ativo que saiu do radar volta para "Todos os ativos" (py:2146).
  void _validarTicker({required VisaoNoticias nova}) {
    if (ticker == todosAtivos) return;
    if (nova.radar.any((r) => r.$1 == ticker)) return;
    ticker = todosAtivos;
    _doGrafico = false;
    _estado.limparFiltroNoticias();
  }

  Future<void> atualizar({bool forcar = false}) async {
    await _estado.atualizarNoticias(forcar: forcar);
  }

  // --- filtros

  void definirTema(String novo) {
    if (novo == tema) return;
    tema = novo;
    notifyListeners();
  }

  /// Escolha do usuário: vale no lugar do filtro que veio do gráfico.
  void definirTicker(String novo) {
    _doGrafico = false;
    _estado.limparFiltroNoticias();
    if (novo == ticker) {
      notifyListeners();
      return;
    }
    ticker = novo;
    notifyListeners();
  }

  /// Tickers do filtro de ativo, na ordem do radar.
  List<String> get ativos => [
    for (final r in visao?.radar ?? const <(String, String)>[]) r.$1,
  ];

  bool get filtrandoAtivo => ticker != todosAtivos;

  /// As matérias do radar com os filtros, até [maxMural] (py:2150-2153).
  List<Noticia> get itens {
    final v = visao;
    if (v == null) return const [];
    final radar = ativos.toSet();
    return [
      for (final i in v.itens)
        if (i.tickers.any(radar.contains) &&
            (tema == todasNoticias || i.temas.isNotEmpty) &&
            (ticker == todosAtivos || i.tickers.contains(ticker)))
          i,
    ].take(maxMural).toList();
  }

  DetalheNoticia? detalhe(Noticia item) => visao?.detalhes[item.id];

  bool ehNova(Noticia item) => visao?.novas.contains(item.id) ?? false;

  /// Matérias lidas, antes dos filtros: decide entre "Buscando…" e "sem
  /// busca feita".
  bool get semBusca => (visao?.hora ?? 0) == 0;

  // --- status

  bool get buscando => _estado.buscandoNoticias;

  /// O status é um erro (cor de erro).
  bool get statusErro {
    if (buscando) return false;
    if (_estado.erroNoticias != null) return true;
    return (visao?.erros ?? const {}).isNotEmpty && !semBusca;
  }

  String get status {
    if (buscando) return textoStatusBuscando;
    final e = _estado.erroNoticias;
    if (e != null) return e;
    final v = visao;
    if (v == null || v.hora == 0) return textoStatusNoticias;
    var texto =
        'Atualizado às ${horaMinuto(v.hora)} · Google Notícias, últimos 7 dias';
    if (v.erros.isNotEmpty) {
      final falhas = ordenadoPor(v.erros.keys, (k) => [k]);
      texto += ' · falha em ${falhas.join(', ')}';
    }
    return texto;
  }

  /// Texto do vazio da lista, ou null quando há matérias (py:2157-2162).
  String? textoVazio({required bool expandido}) {
    if (visao == null || itens.isNotEmpty) return null;
    if (ativos.isEmpty) {
      return expandido
          ? 'Adicione ativos no Radar de Ações para ver as notícias deles aqui.'
          : 'Adicione ativos no Radar para ver as notícias deles aqui.';
    }
    if (semBusca) {
      if (buscando) return textoStatusBuscando;
      return expandido
          ? 'Nenhuma busca feita ainda. Clique em Atualizar.'
          : 'Nenhuma busca feita ainda.';
    }
    return 'Nenhuma notícia nos últimos 7 dias com esse filtro.';
  }

  // --- preferência e links

  bool get notificar => _estado.preferencias.notificarNoticias;

  Future<void> definirNotificar(bool v) => _estado.definirNotificar(v);

  /// O link que o Python abre: a matéria original no PC (a prévia, quando já
  /// chegou) e o link do Google Notícias no celular.
  Future<void> abrir(Noticia item, {required bool expandido}) {
    final direto = expandido ? detalhe(item)?.url ?? '' : '';
    final link = direto.isNotEmpty ? direto : item.link;
    final uri = Uri.tryParse(link);
    if (uri == null || link.isEmpty) return Future.value();
    return _estado.abrirLink(uri);
  }

  // --- imagens (só dos cartões que a lista constrói)

  /// Bytes da imagem da matéria; o pedido de uma URL é feito uma vez.
  Future<Uint8List?> imagem(String url) => _imagens.putIfAbsent(
    url,
    () => _pedir(_imagens, url, () => _servicos.imagemNoticia(url)),
  );

  Future<Uint8List?> favicon(Noticia item) {
    final chave = dominio(item.fonteUrl);
    if (chave.isEmpty) return Future.value();
    return _favicons.putIfAbsent(
      chave,
      () => _pedir(_favicons, chave, () => _servicos.favicon(item)),
    );
  }

  /// Falha ou ausência não ficam no cache: o próximo cartão tenta de novo.
  Future<Uint8List?> _pedir(
    Map<String, Future<Uint8List?>> cache,
    String chave,
    Future<Uint8List?> Function() pedir,
  ) async {
    try {
      final r = await pedir();
      if (r == null) unawaited(Future.microtask(() => cache.remove(chave)));
      return r;
    } catch (_) {
      unawaited(Future.microtask(() => cache.remove(chave)));
      return null;
    }
  }
}
