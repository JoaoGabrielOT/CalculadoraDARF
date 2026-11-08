// Contrato entre a interface e os serviços do app. Roda no isolate de
// serviços: sem package:flutter.

import 'dart:typed_data';

import '../../integracoes/integracoes.dart';
import '../../nucleo/nucleo.dart';
import '../tema/tema_visual.dart';
import 'eventos.dart';

abstract interface class ServicosApp {
  Stream<EventoServico> get eventos;

  // ciclo e preferências
  Future<EstadoInicial> iniciar();
  Future<void> encerrar();
  Future<void> salvarPreferencias(Preferencias p);

  // apuração; amigo != null = dados do amigo carregado (somente leitura)
  Future<List<String>> mesesComDados({String? amigo});
  Future<String> mesInicial({String? amigo});
  Future<VisaoMes> carregarMes(String mes, {String? amigo});
  Future<VisaoPosicoes> posicoes(String mes, {String? amigo});
  Future<SugestoesTicker> sugestoesTicker(
    String mes, {
    bool soCustodia = false,
  });
  Future<VisaoMes> registrarCompra(String mes, NovaCompra c);
  Future<VisaoMes> editarCompra(String mes, String loteId, NovaCompra c);
  Future<VisaoMes> excluirCompra(String mes, String loteId);
  Future<VendaRegistrada> registrarVenda(String mes, NovaVenda v);
  Future<VisaoMes> editarVenda(String mes, String vendaId, NovaVenda v);
  Future<VisaoMes> excluirVenda(String mes, String vendaId);
  Future<String> novoGrupoVenda();
  Future<List<Lote>> comprasElegiveis(String mes, String ticker, String data);
  Future<PreviaVenda> previaVenda(String mes, NovaVendaQtd v);
  Future<VendaRegistrada> registrarVendaQtd(String mes, NovaVendaQtd v);
  Future<VisaoMes> editarGrupoVenda(String mes, String grupo, NovaVendaQtd v);
  Future<Set<String>> mesesSemVendaRetroativa(String mesAtual);
  Future<int> reservadoEmMetas(String loteId);
  Future<PreparoFechamento> prepararFechamento(String mes);
  Future<Fechamento> fecharMes(String mes);

  // caixa
  Future<VisaoCaixa> caixa({String? amigo});
  Future<VisaoCaixa> alterarSaldo(ModoSaldo modo, double valor);

  // conta, sincronização e amigos
  Future<EstadoConta> conta();
  Future<void> conectar();
  Future<void> cancelarLogin();
  Future<void> sair();
  Future<void> sincronizarAgora();
  Future<List<Amigo>> amigos();
  Future<void> adicionarAmigo(String email);
  Future<void> removerAmigo(String email);
  Future<ResumoAmigo> carregarAmigo(String email);
  Future<void> esquecerAmigo();

  // mercado, radar e metas
  Future<VisaoRadar> radar({String? amigo});
  Future<ItemRadar> adicionarRadar(String ticker);
  Future<int> importarRadar(List<ItemRadar> itens);
  Future<void> removerRadar(String ticker);
  Future<void> reordenarRadar(List<String> tickers);
  Future<void> limparCacheCotacoes();
  Future<CotacaoRadar> cotacao(String ticker, {String nome = ''});
  Future<Grafico> grafico(String ticker, String periodo);
  Future<Map<String, double?>> precosCarteira(Set<String> tickers);
  Future<Map<String, CotacaoAtual?>> cotacoesAtuais(Set<String> tickers);
  Future<(double, String)> precoVenda(String ticker, String dia);
  Future<VisaoMetas> metas();
  Future<VisaoSugestoes> sugestoesMetas({bool incluirRadar = false});
  Future<PrecoAlvo> calcularPrecoAlvo(String loteId, int qtd, double lucro);
  Future<Projecao> projetarPreco(String loteId, int qtd, double preco);
  Future<Meta?> parceiraOco(String loteId, String gatilho);
  Future<Meta> criarMetaAlvo(
    String loteId,
    int qtd,
    double precoAlvo, {
    double? lucroDesejado,
    String? ocoCom,
  });
  Future<Meta> criarStop(
    String loteId,
    int qtd,
    double precoStop, {
    bool movel = false,
    String? ocoCom,
    double? precoAtual,
    Map<String, Object?>? sugestao,
  });
  Future<void> cancelarMeta(String metaId);
  Future<ResultadoVerificacao> verificarMetas();

  // notícias, imagens e atualizador
  Future<VisaoNoticias> noticias();
  Future<VisaoNoticias> atualizarNoticias({bool forcar = false});
  Future<void> marcarNoticiasLidas();
  Future<ImagemBytes?> logo(String ticker);
  Future<Uint8List?> favicon(Noticia item);
  Future<Uint8List?> imagemNoticia(String url);
  Future<InfoAtualizacao?> verificarAtualizacao();
  Future<String> baixarAtualizacao(InfoAtualizacao info);
  Future<void> cancelarDownload();
}

/// Preferências por aparelho (`Config.extras`, nunca vão para a planilha).
class Preferencias {
  const Preferencias({
    this.tema = TemaVisual.automatico,
    this.notificarNoticias = true,
    this.ordemRadar = 'manual',
  });

  final TemaVisual tema;
  final bool notificarNoticias;

  /// Chave de `ordensRadar`.
  final String ordemRadar;
}

class EstadoInicial {
  const EstadoInicial({
    required this.mesInicial,
    required this.mesesComDados,
    required this.preferencias,
    this.erroConfig,
    this.temCredencial = false,
  });

  final String mesInicial;
  final List<String> mesesComDados;
  final Preferencias preferencias;

  /// Preenchido quando o `config.json` está ilegível.
  final String? erroConfig;
  final bool temCredencial;
}

class VisaoMes {
  const VisaoMes({
    required this.mes,
    required this.dados,
    required this.apuracao,
    this.amigo,
    this.erroLeitura,
  });

  final String mes;
  final Mes dados;
  final Apuracao apuracao;

  /// E-mail do amigo cujos dados estão na tela.
  final String? amigo;

  /// Mês que não pôde ser lido (arquivo com valor inválido); `dados` vem vazio.
  final String? erroLeitura;

  bool get somenteLeitura => amigo != null;
  bool get editavel => amigo == null && !dados.fechado && erroLeitura == null;
}

/// Posições em aberto numa data de corte. Só leitura: não grava nada.
class VisaoPosicoes {
  const VisaoPosicoes({
    required this.dataCorte,
    required this.corrente,
    required this.posicoes,
    this.indicadores = const [],
  });

  /// `AAAA-MM-DD`: o último dia do mês, ou hoje no mês de hoje.
  final String dataCorte;

  /// O corte é hoje: só então vale mostrar a cotação atual.
  final bool corrente;
  final List<PosicaoAtivo> posicoes;

  /// Indicadores por ativo (saldo em [dataCorte] ou vendido no mês), sem
  /// cotação: o mercado entra com `comCotacoes` quando a cotação chega.
  final List<IndicadoresAtivo> indicadores;
}

class NovaCompra {
  const NovaCompra({
    required this.ticker,
    required this.dataCompra,
    required this.qtd,
    required this.preco,
  });

  final String ticker;
  final String dataCompra;
  final int qtd;
  final double preco;
}

class NovaVenda {
  const NovaVenda({
    required this.loteId,
    required this.data,
    required this.qtd,
    required this.preco,
  });

  final String loteId;
  final String data;
  final int qtd;
  final double preco;
}

class VendaRegistrada {
  const VendaRegistrada({required this.visao, this.mesGravado, this.aviso});

  final VisaoMes visao;

  /// Mês onde a venda retroativa foi gravada.
  final String? mesGravado;

  /// Texto "A venda foi gravada em …" (só em venda retroativa).
  final String? aviso;
}

class SugestoesTicker {
  const SugestoesTicker({required this.tickers, required this.tipos});

  final List<String> tickers;
  final Map<String, String> tipos;
}

class Fechamento {
  const Fechamento({required this.visao, required this.mensagem});

  final VisaoMes visao;
  final String mensagem;
}

enum ModoSaldo { definir, aporte, retirada }

class VisaoCaixa {
  const VisaoCaixa({
    required this.resumo,
    required this.projecao,
    required this.agenda,
    required this.hoje,
    this.amigo,
  });

  final ResumoCaixa resumo;
  final List<DiaProjecao> projecao;
  final List<GrupoAgenda> agenda;
  final String hoje;
  final String? amigo;
}

class EstadoConta {
  const EstadoConta({
    this.email,
    this.temCredencial = false,
    this.temToken = false,
    this.status = StatusSync.off,
    this.ultimaSync,
    this.ultimoErro = '',
    this.linkPlanilha,
    this.ocupado = false,
  });

  final String? email;
  final bool temCredencial;
  final bool temToken;
  final StatusSync status;
  final double? ultimaSync;
  final String ultimoErro;
  final String? linkPlanilha;
  final bool ocupado;
}

class ResumoAmigo {
  const ResumoAmigo({
    required this.email,
    required this.meses,
    required this.mesInicial,
  });

  final String email;
  final List<String> meses;
  final String mesInicial;
}

class VisaoRadar {
  const VisaoRadar({
    required this.itens,
    required this.custodia,
    required this.meus,
    this.amigo,
  });

  final List<ItemRadar> itens;
  final Set<String> custodia;
  final Set<String> meus;
  final String? amigo;
}

/// Cotação de agora, com a fonte e a hora da consulta: nunca é histórica.
class CotacaoAtual {
  const CotacaoAtual({
    required this.preco,
    required this.hora,
    required this.fonte,
  });

  final double preco;

  /// Hora em que o app consultou a fonte (não a hora do pregão), no fuso de
  /// Brasília.
  final DataHora hora;

  /// `'Yahoo'`.
  final String fonte;
}

sealed class CotacaoRadar {
  const CotacaoRadar();

  String get ticker;
}

class CotacaoOk extends CotacaoRadar {
  const CotacaoOk(this.dados);

  final DadosAtivo dados;

  @override
  String get ticker => dados.ticker;
}

class CotacaoErro extends CotacaoRadar {
  const CotacaoErro(this.ticker, this.mensagem);

  @override
  final String ticker;
  final String mensagem;
}

class VisaoMetas {
  const VisaoMetas({
    required this.metas,
    required this.descricoes,
    required this.lotes,
    required this.ativas,
  });

  final List<Meta> metas;
  final Map<String, DescricaoMeta> descricoes;
  final List<LoteLivre> lotes;
  final int ativas;
}

/// Situação dos dados de um ativo nas sugestões.
enum EstadoDados { ok, semDados, desatualizado, falha }

/// Dados de mercado de um ticker (barras diárias e cotação) e a posição de
/// hoje; o cenário e o consolidado saem daqui por funções puras, sem nova
/// requisição. [posicao] é nula para um ticker só do radar.
class SugestaoAtivo {
  const SugestaoAtivo({
    required this.ticker,
    required this.estado,
    this.mensagem,
    this.cotacao,
    this.barras = const [],
    this.posicao,
  });

  final String ticker;
  final EstadoDados estado;

  /// Texto da falha ou do "sem dados".
  final String? mensagem;
  final CotacaoInfo? cotacao;
  final List<BarraDiaria> barras;
  final PosicaoAtivo? posicao;
}

class VisaoSugestoes {
  const VisaoSugestoes({required this.ativos, required this.rodape});

  final List<SugestaoAtivo> ativos;
  final List<LinhaCard> rodape;
}

sealed class ResultadoVerificacao {
  const ResultadoVerificacao();
}

class VerificacaoEmAndamento extends ResultadoVerificacao {
  const VerificacaoEmAndamento();
}

class SemMetasAtivas extends ResultadoVerificacao {
  const SemMetasAtivas();
}

class VerificacaoFalhou extends ResultadoVerificacao {
  const VerificacaoFalhou(this.mensagem);

  final String mensagem;
}

class VerificacaoConcluida extends ResultadoVerificacao {
  const VerificacaoConcluida(this.relatorio);

  final RelatorioMetas relatorio;
}

class VisaoNoticias {
  const VisaoNoticias({
    required this.itens,
    required this.detalhes,
    required this.naoLidas,
    required this.hora,
    required this.lidasAte,
    required this.erros,
    required this.rodando,
    required this.radar,
    this.novas = const {},
  });

  final List<Noticia> itens;
  final Map<String, DetalheNoticia> detalhes;
  final int naoLidas;
  final double hora;
  final double lidasAte;
  final Map<String, String> erros;
  final bool rodando;

  /// (ticker, nome) na ordem escolhida pelo usuário.
  final List<(String, String)> radar;

  /// Ids das matérias que chegaram depois da última abertura da aba
  /// (`ehNova`): ganham o selo "Nova".
  final Set<String> novas;
}

class ImagemBytes {
  const ImagemBytes({required this.bytes, required this.svg});

  final Uint8List bytes;
  final bool svg;
}

/// Pedido que perdeu para outro mais novo, ou para sair da conta; a interface
/// o descarta sem avisar. Atravessa o isolate com o tipo preservado.
class PedidoSuperado extends ErroGoogle {
  PedidoSuperado(super.mensagem);
}
