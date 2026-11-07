// Estado da tela Radar: a lista do dono (eu ou um amigo), as cotações que
// chegam uma a uma, os mini-gráficos do dia, o filtro e as ações sobre os
// ativos (calculadora_darf.py:2351-2590, 2646-2672; android/main.py:1682-1867,
// 1998-2068).

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../integracoes/integracoes.dart';
import '../../../nucleo/nucleo.dart';
import '../../componentes/dialogos.dart';
import '../../estado/estado_app.dart';
import '../../regras/textos.dart';
import '../../servicos/api.dart';
import '../../tema/layout.dart';
import '../formularios/abrir_formulario.dart';

const textoStatusPadrao = 'Cotações do Yahoo Finance (atraso de até 15 min)';
const textoStatusAtualizando = 'Atualizando cotações…';
const textoAvisoArrastar =
    'Para arrastar, use Ordenar: Minha ordem e o filtro Todos.';

class ControleRadar extends ChangeNotifier {
  ControleRadar(this._servicos, this._estado) {
    _amigo = _estado.amigo;
    _versao = _estado.versaoDados;
    _naAba = _estado.aba == Aba.radar;
    _ordem = ordem;
    _estado.addListener(_aoMudarEstado);
    // só a aba Radar visível atualiza sozinha (py:2578-2581)
    _timer = Timer.periodic(intervaloAtualizacao, (_) {
      if (_estado.aba == Aba.radar && !atualizando) unawaited(atualizar());
    });
    unawaited(recarregar());
  }

  static const intervaloAtualizacao = Duration(seconds: 60);

  final ServicosApp _servicos;
  final EstadoApp _estado;

  late String? _amigo;
  late int _versao;
  late bool _naAba;
  late String _ordem;
  String? _dono; // de quem é a [visao]
  int _geracao = 0;
  bool _descartado = false;
  bool _ocupado = false; // adicionar, comprar e vender: um de cada vez
  Timer? _timer;

  /// Tickers pedidos que ainda não responderam, e os que esperam a rodada em
  /// curso acabar (py:2538-2540).
  final Set<String> _emVoo = {};
  final Set<String> _espera = {};

  /// O radar na tela; null enquanto o primeiro carregamento (ou o de outra
  /// visão) não chega, ou quando ele falhou ([erro]).
  VisaoRadar? visao;
  bool carregando = false;
  String? erro;

  final Map<String, CotacaoRadar> cotacoes = {};
  final Map<String, Grafico> minis = {};
  String filtro = filtrosRadar.first;
  bool atualizando = false;
  String status = textoStatusPadrao;

  /// O [status] é um aviso (cor de aviso), não o texto de rotina.
  bool statusAviso = false;

  /// O e-mail do amigo cujo radar está na tela; null = meu radar.
  String? get amigo => _estado.amigo;

  String get ordem => _estado.preferencias.ordemRadar;

  @override
  void notifyListeners() {
    if (!_descartado) super.notifyListeners();
  }

  @override
  void dispose() {
    _descartado = true;
    _timer?.cancel();
    _estado.removeListener(_aoMudarEstado);
    super.dispose();
  }

  void _aoMudarEstado() {
    final naAba = _estado.aba == Aba.radar;
    final entrou = naAba && !_naAba;
    _naAba = naAba;
    if (_estado.amigo != _amigo || _estado.versaoDados != _versao) {
      _amigo = _estado.amigo;
      _versao = _estado.versaoDados;
      unawaited(recarregar());
    }
    if (entrou) unawaited(atualizar());
    // a ordem escolhida (preferência do estado) muda a lista
    if (ordem != _ordem) {
      _ordem = ordem;
      notifyListeners();
    }
  }

  // --- a lista

  /// Vale o último pedido: uma resposta antiga é descartada. Ao trocar de
  /// visão a lista anterior sai da tela; no mesmo dono ela fica até a nova
  /// chegar (e, se falhar, continua à vista com o erro por cima).
  Future<void> recarregar() async {
    final geracao = ++_geracao;
    final alvo = _estado.amigo;
    if (_dono != alvo) visao = null;
    carregando = true;
    notifyListeners();
    try {
      final nova = await _servicos.radar(amigo: alvo);
      if (geracao != _geracao) return;
      visao = nova;
      _dono = alvo;
      erro = null;
    } catch (e) {
      if (geracao != _geracao) return;
      erro = e is PedidoSuperado && visao != null ? null : textoErro(e);
    }
    carregando = false;
    notifyListeners();
    if (geracao == _geracao && erro == null && _estado.aba == Aba.radar) {
      _cotarFaltantes();
    }
  }

  /// Quem acabou de entrar na lista (outro dono, outro aparelho) busca a
  /// cotação; quem já tem, ou já está a caminho, espera o próximo ciclo.
  void _cotarFaltantes() {
    final faltam = [
      for (final i in visao?.itens ?? const <ItemRadar>[])
        if (!cotacoes.containsKey(i.ticker) &&
            !_emVoo.contains(i.ticker) &&
            !_espera.contains(i.ticker))
          i.ticker,
    ];
    if (faltam.isNotEmpty) unawaited(atualizar(apenas: faltam));
  }

  void definirFiltro(String f) {
    if (f == filtro) return;
    filtro = f;
    notifyListeners();
  }

  Future<void> definirOrdem(String chave) async {
    if (chave == ordem) return;
    await _estado.definirOrdemRadar(chave);
  }

  Map<String, DadosAtivo> get _dados => {
    for (final e in cotacoes.entries)
      if (e.value case CotacaoOk(:final dados)) e.key: dados,
  };

  /// Todos os ativos do dono, antes do filtro.
  List<ItemRadar> get itens => visao?.itens ?? const [];

  /// A lista na tela: filtro e ordem aplicados às cotações de agora.
  List<ItemRadar> get lista => filtrarOrdenar(
    itens,
    _dados,
    filtro: filtro,
    ordem: ordem,
    custodia: visao?.custodia ?? const {},
  );

  /// (em alta, em queda, média do dia) de todos os ativos do dono.
  (int, int, double?) get resumo =>
      resumoDia([for (final i in itens) i.ticker], _dados);

  /// A alça só arrasta em "Minha ordem" com o filtro "Todos", nos meus dados.
  bool get reordenavel =>
      amigo == null && ordem == 'manual' && filtro == filtrosRadar.first;

  /// Ativos do amigo que ainda não estão no meu radar.
  List<ItemRadar> get novosDoAmigo => [
    for (final i in itens)
      if (!(visao?.meus.contains(i.ticker) ?? false)) i,
  ];

  // --- cotações

  /// Pede as cotações de [apenas] (ou de todos) ao mesmo tempo; cada linha
  /// atualiza ao chegar. Um pedido durante uma atualização espera a rodada
  /// acabar (py:2530-2577). [forcar] limpa o cache do serviço antes.
  Future<void> atualizar({bool forcar = false, List<String>? apenas}) async {
    final alvo = apenas ?? [for (final i in itens) i.ticker];
    if (alvo.isEmpty) return;
    if (atualizando) {
      _espera.addAll(alvo);
      return;
    }
    atualizando = true;
    status = textoStatusAtualizando;
    statusAviso = false;
    notifyListeners();
    final nomes = {for (final i in itens) i.ticker: i.nome};
    _emVoo.addAll(alvo);
    var falhas = 0;
    try {
      if (forcar) await _servicos.limparCacheCotacoes();
      final rodada = await Future.wait([
        for (final t in alvo) _buscar(t, nomes[t] ?? ''),
      ]);
      falhas = rodada.where((ok) => !ok).length;
    } catch (_) {
      // sem como limpar o cache: a rodada acaba sem atualizar
      falhas = alvo.length;
    } finally {
      _emVoo.removeAll(alvo);
    }
    atualizando = false;
    status =
        'Atualizado às ${horaMinuto(ambiente.agora())} · Yahoo Finance '
        '(atraso de até 15 min)'
        '${falhas > 0 ? ' · $falhas sem atualizar' : ''}';
    statusAviso = false;
    notifyListeners();
    if (_espera.isNotEmpty) {
      final pendentes = _espera.toList();
      _espera.clear();
      unawaited(atualizar(apenas: pendentes));
    }
  }

  /// Devolve se a cotação chegou sem erro.
  Future<bool> _buscar(String ticker, String nome) async {
    CotacaoRadar r;
    try {
      r = await _servicos.cotacao(ticker, nome: nome);
    } catch (e) {
      if (e is PedidoSuperado) return true;
      r = CotacaoErro(ticker, textoErro(e));
    }
    if (_descartado) return true;
    // o preço de antes continua à vista quando a nova tentativa falha
    if (r is! CotacaoErro || cotacoes[ticker] is! CotacaoOk) {
      cotacoes[ticker] = r;
    }
    notifyListeners();
    if (r is CotacaoErro) return false;
    try {
      final g = await _servicos.grafico(ticker, '1D');
      if (_descartado) return true;
      minis[ticker] = g;
      notifyListeners();
    } catch (_) {
      // sem mini-gráfico: o espaço fica vazio até o próximo ciclo
    }
    return true;
  }

  // --- alterações do radar

  /// Mostra o aviso no lugar do status (py:2431-2434).
  void avisarArrastar() {
    status = textoAvisoArrastar;
    statusAviso = true;
    notifyListeners();
  }

  /// Nova posição ([para] já descontada a saída de [de], como no
  /// `onReorderItem`); grava na hora.
  Future<void> reordenar(int de, int para) async {
    final atual = visao;
    if (atual == null || !reordenavel) return;
    if (de == para || de < 0 || de >= atual.itens.length) return;
    final novos = [...atual.itens];
    novos.insert(para, novos.removeAt(de));
    visao = VisaoRadar(
      itens: novos,
      custodia: atual.custodia,
      meus: atual.meus,
      amigo: atual.amigo,
    );
    notifyListeners();
    try {
      await _servicos.reordenarRadar([for (final i in novos) i.ticker]);
    } catch (e) {
      if (e is PedidoSuperado) return;
      _estado.avisar('Radar', textoErro(e));
      await recarregar();
    }
  }

  /// Devolve true se adicionou (a tela limpa o campo).
  Future<bool> adicionar(BuildContext c, String texto) async {
    if (_ocupado || amigo != null) return false;
    _ocupado = true;
    try {
      final ItemRadar item;
      try {
        item = await _servicos.adicionarRadar(texto);
      } catch (e) {
        if (e is! PedidoSuperado && c.mounted) {
          await avisar(c, 'Radar', textoErro(e));
        }
        return false;
      }
      // só o ativo novo busca cotação (py:2518)
      unawaited(atualizar(apenas: [item.ticker]));
      await recarregar();
      return true;
    } finally {
      _ocupado = false;
    }
  }

  Future<void> remover(BuildContext c, String ticker) async {
    final sim = await confirmar(
      c,
      'Remover do radar',
      'Remover $ticker do radar?',
      sim: 'Remover',
      perigo: true,
    );
    if (!sim) return;
    try {
      await _servicos.removerRadar(ticker);
    } catch (e) {
      if (e is! PedidoSuperado && c.mounted) {
        await avisar(c, 'Radar', textoErro(e));
      }
      return;
    }
    cotacoes.remove(ticker);
    minis.remove(ticker);
    await recarregar();
  }

  Future<void> importar(BuildContext c, String ticker) async {
    final item = itens.where((i) => i.ticker == ticker).firstOrNull;
    if (item == null || _ocupado) return;
    _ocupado = true;
    try {
      await _servicos.importarRadar([item]);
      await recarregar();
      if (c.mounted && !expandido(c)) {
        ScaffoldMessenger.maybeOf(c)?.showSnackBar(
          SnackBar(content: Text('$ticker adicionado ao seu radar.')),
        );
      }
    } catch (e) {
      if (e is! PedidoSuperado && c.mounted) {
        await avisar(c, 'Radar', textoErro(e));
      }
    } finally {
      _ocupado = false;
    }
  }

  Future<void> importarTodos(BuildContext c) async {
    if (_ocupado) return;
    final novos = novosDoAmigo;
    if (novos.isEmpty) {
      await avisar(
        c,
        'Radar',
        'Todos os ativos do radar do amigo já estão no seu radar.',
      );
      return;
    }
    final sim = await confirmar(
      c,
      'Importar radar',
      'Adicionar ${novos.length} ativo(s) ao seu radar: '
          '${novos.map((i) => i.ticker).join(', ')}?',
      sim: 'Importar',
    );
    if (!sim || !c.mounted) return;
    _ocupado = true;
    try {
      await _servicos.importarRadar(novos);
      await recarregar();
    } catch (e) {
      if (e is! PedidoSuperado && c.mounted) {
        await avisar(c, 'Radar', textoErro(e));
      }
    } finally {
      _ocupado = false;
    }
  }

  // --- comprar e vender (py:2646-2672)

  /// Preço atual da cotação, no texto do campo de preço do formulário.
  String? _precoTexto(String ticker) {
    final c = cotacoes[ticker];
    final preco = c is CotacaoOk ? c.dados.preco : null;
    return preco != null && preco > 0 ? precoTexto(preco) : null;
  }

  /// Volta aos meus dados, num mês aberto; null se não deu.
  Future<VisaoMes?> _preparar(BuildContext c) async {
    try {
      return await _estado.prepararOperacao();
    } catch (e) {
      if (e is! PedidoSuperado && c.mounted) {
        await avisar(c, 'Radar', textoErro(e));
      }
      return null;
    }
  }

  Future<void> comprar(BuildContext c, String ticker) async {
    if (_ocupado) return;
    _ocupado = true;
    try {
      final v = await _preparar(c);
      if (v == null || !c.mounted) return;
      final preco = _precoTexto(ticker);
      // o formulário infere o tipo (Ação ou BDR) pelo ticker
      final nova = await abrirFormCompra(
        c,
        v,
        iniciais: {'ticker': ticker, 'preco': ?preco},
      );
      if (nova != null) unawaited(recarregar());
    } finally {
      _ocupado = false;
    }
  }

  Future<void> vender(BuildContext c, String ticker) async {
    if (_ocupado) return;
    _ocupado = true;
    try {
      final v = await _preparar(c);
      if (v == null || !c.mounted) return;
      final emCustodia = v.dados.lotes.any(
        (l) => l.ticker == ticker && restante(l) > 0,
      );
      if (!emCustodia) {
        await avisar(
          c,
          'Vender',
          'Não há $ticker em custódia no mês ${fmtMes(v.mes)}.',
        );
        return;
      }
      final r = await abrirFormVenda(c, v, ticker: ticker);
      if (r != null) unawaited(recarregar());
    } finally {
      _ocupado = false;
    }
  }
}
