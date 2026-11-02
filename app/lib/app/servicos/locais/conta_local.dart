// Conta Google, sincronização e amigos no isolate dos serviços
// (calculadora_darf.py:2736-2929, 2970-3000; 3784-3830).

import 'dart:async';

import '../../../integracoes/integracoes.dart';
import '../../../nucleo/nucleo.dart';
import '../api.dart';
import '../eventos.dart';
import 'apuracao_local.dart' show AmigoCarregado;
import 'config_segura.dart';

final _emailValido = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

/// Traduz os avisos em texto do [Sincronizador] para os diálogos do Windows
/// (calculadora_darf.py:2764-2767, 2850-2851, 2899).
EventoAviso avisoDe(String texto) {
  const ajuste = 'Ajuste manual necessário: ';
  const sessao = 'Sessão expirada. ';
  if (texto.startsWith(ajuste)) {
    return EventoAviso(
      'Ajuste manual necessário',
      texto.substring(ajuste.length),
    );
  }
  if (texto.startsWith(sessao)) {
    return EventoAviso('Sessão expirada', texto.substring(sessao.length));
  }
  if (texto.startsWith('Conectado como ')) {
    return EventoAviso('Conectado', texto);
  }
  return EventoAviso('Login não concluído', texto);
}

class ContaLocal {
  ContaLocal({
    required this._repo,
    required this._conta,
    required this._abrirUrl,
    required this._emitir,
    Duration atrasoAgendamento = const Duration(milliseconds: 1500),
  }) {
    _sync = Sincronizador(
      conta: _conta,
      dados: DadosSincronizacaoLocal(_repo),
      aoMudarStatus: (_) => _emitirConta(),
      aoMudarDados: () => _emitir(const EventoDadosMudaram()),
      aoAvisar: (texto) => _emitir(avisoDe(texto)),
      atrasoAgendamento: atrasoAgendamento,
    );
  }

  final Repositorio _repo;
  final ContaGoogle _conta;
  final AbrirUrl _abrirUrl;
  final void Function(EventoServico) _emitir;
  late final Sincronizador _sync;

  AmigoCarregado? _amigo;

  /// Aumenta a cada pedido de amigo e a cada limpeza: só o último vale.
  int _geracaoAmigo = 0;

  /// Amigo cuja carga está em voo (ainda não há `_amigo`) e a geração dela.
  String? _emVoo;
  int _geracaoEmVoo = 0;
  bool _ocupadoEmitido = false;

  /// Dados do amigo carregado (somente leitura).
  DadosPlanilha? get amigo => _amigo?.dados;

  AmigoCarregado? get amigoCarregado => _amigo;

  void usarAmigo(String email, DadosPlanilha dados) {
    _amigo = (email: email, dados: dados);
  }

  void limparAmigo() {
    _geracaoAmigo++;
    _amigo = null;
  }

  // --- estado

  EstadoConta estado() {
    final email = _conta.email;
    String? sid;
    try {
      sid = email == null ? null : _repo.lerConfig().planilhas[email];
    } on FormatException {
      // config ilegível: o aviso já foi dado; aqui só falta o link
    } on TypeError {
      // idem
    } on RangeError {
      // idem
    }
    return EstadoConta(
      email: email,
      temCredencial: _conta.temCredencial,
      temToken: _conta.temToken(),
      status: _sync.status,
      ultimaSync: _sync.ultimaSync,
      ultimoErro: _sync.ultimoErro,
      linkPlanilha: sid == null || sid.isEmpty ? null : linkPlanilha(sid),
      ocupado: _sync.ocupado,
    );
  }

  void _emitirConta() {
    final e = estado();
    _ocupadoEmitido = e.ocupado;
    _emitir(EventoConta(e));
  }

  /// `ocupado` muda sem mudança de status quando o login ou a reconexão
  /// terminam; a interface precisa saber para reabilitar o botão.
  void _reconciliar() {
    if (_sync.ocupado != _ocupadoEmitido) _emitirConta();
  }

  // --- conta

  Future<void> conectar() async {
    if (_conta.email != null || _sync.ocupado) return;
    if (!_conta.temCredencial) {
      _emitir(
        const EventoAviso(
          'Credencial não encontrada',
          'Coloque o arquivo credentials.json na mesma pasta do programa '
              'ou gere o .exe com ele na pasta.',
        ),
      );
      return;
    }
    try {
      await _sync.conectar(_abrirUrl);
    } finally {
      _reconciliar();
    }
  }

  /// Fim do isolate: o timer de `agendar` não pode sincronizar depois.
  void encerrar() => _sync.encerrar();

  Future<void> cancelarLogin() async {
    await _sync.cancelarLogin();
  }

  /// Sair da conta limpa a visão do amigo (calculadora_darf.py:2816-2826).
  Future<void> sair() async {
    final tinhaAmigo = _amigo != null;
    limparAmigo();
    _sync.sair();
    if (tinhaAmigo) _emitir(const EventoDadosMudaram());
    _reconciliar();
  }

  /// Marca pendente e sincroniza; sem planilha o sincronizador prepara antes
  /// (calculadora_darf.py:2808-2814).
  Future<void> sincronizarAgora() async {
    final cfg = lerConfigParaGravar(_repo);
    cfg.pendente = true;
    _repo.gravarConfig(cfg);
    await _sync.sincronizar();
  }

  /// `agendar_sync`: marca pendente (mesmo sem conta) e sincroniza depois do
  /// atraso. Usado pelas mutações das outras partes.
  void agendar() => unawaited(_sync.agendar());

  /// Chamado pelo timer da fachada.
  Future<void> tick() async {
    try {
      await _sync.tick();
    } finally {
      _reconciliar();
    }
  }

  // --- amigos

  Future<List<Amigo>> amigos() async => [...lerConfigParaGravar(_repo).amigos];

  /// Sid da planilha da própria conta; recusa sem conta ou sem planilha
  /// (calculadora_darf.py:2923-2928).
  String _planilhaPropria() {
    final minha = _conta.email;
    if (minha == null) {
      throw ErroValidacao('Conecte sua conta Google para adicionar amigos.');
    }
    final sid = _repo.lerConfig().planilhas[minha];
    if (sid == null || sid.isEmpty) {
      throw ErroValidacao(
        'Aguarde a criação da sua planilha no Google Drive e tente novamente.',
      );
    }
    return sid;
  }

  Future<void> adicionarAmigo(String email) async {
    // recusa antes de qualquer chamada remota quando a config está ilegível
    final antes = lerConfigParaGravar(_repo);
    final sid = _planilhaPropria();
    final e = email.trim().toLowerCase();
    if (!_emailValido.hasMatch(e)) throw ErroValidacao('E-mail inválido.');
    if (e == _conta.email!.toLowerCase()) {
      throw ErroValidacao('Esse é o seu próprio e-mail.');
    }
    if (antes.amigos.any((a) => a.email == e)) {
      throw ErroValidacao('Esse amigo já foi adicionado.');
    }
    await _conta.compartilhar(sid, e);
    // sem `await` entre ler e gravar; a config pode ter mudado durante a rede
    final cfg = lerConfigParaGravar(_repo);
    if (!cfg.amigos.any((a) => a.email == e)) {
      cfg.amigos.add(Amigo(email: e, desde: ambiente.hoje()));
    }
    _repo.gravarConfig(cfg);
    agendar();
  }

  Future<void> removerAmigo(String email) async {
    lerConfigParaGravar(_repo);
    // como no Android (main.py:2165-2177): sem conta ou planilha só sai da
    // config, nada a descompartilhar
    final minha = _conta.email;
    final sid = minha == null ? null : _repo.lerConfig().planilhas[minha];
    if (sid != null && sid.isNotEmpty) {
      await _conta.descompartilhar(sid, email);
    }
    final cfg = lerConfigParaGravar(_repo);
    cfg.amigos = [
      for (final a in cfg.amigos)
        if (a.email != email) a,
    ];
    _repo.gravarConfig(cfg);
    agendar();
    final carregando = _emVoo == email;
    final aberto = _amigo?.email == email;
    // a carga em voo desse amigo termina como pedido superado, sem tocar no
    // amigo que já estava carregado (outro e-mail)
    if (carregando) {
      _geracaoAmigo++;
      _emVoo = null;
    }
    if (aberto) limparAmigo();
    if (carregando || aberto) _emitir(const EventoDadosMudaram());
  }

  Future<ResumoAmigo> carregarAmigo(String email) async {
    final minha = _conta.email;
    if (minha == null) {
      throw ErroValidacao(
        'Conecte sua conta Google para ver os dados dos amigos.',
      );
    }
    final geracao = ++_geracaoAmigo;
    _emVoo = email;
    _geracaoEmVoo = geracao;
    final DadosPlanilha dados;
    try {
      dados = await _sync.lerAmigo(email);
    } finally {
      if (_geracaoEmVoo == geracao) _emVoo = null;
    }
    if (geracao != _geracaoAmigo || _conta.email != minha) {
      // vale o último pedido; sair ou novo login durante a rede descarta
      throw PedidoSuperado('O carregamento dos dados do amigo foi cancelado.');
    }
    usarAmigo(email, dados);
    return ResumoAmigo(
      email: email,
      meses: ordenadoPor(dados.meses.keys, (m) => [m]),
      mesInicial: _mesInicial(dados.meses),
    );
  }

  /// Primeiro mês aberto; sem aberto, o maior; sem meses, o de hoje
  /// (calculadora_darf.py:2993-2995).
  String _mesInicial(Map<String, Mes> meses) {
    final abertos = ordenadoPor([
      for (final e in meses.entries)
        if (!e.value.fechado) e.key,
    ], (m) => [m]);
    if (abertos.isNotEmpty) return abertos.first;
    if (meses.isEmpty) return ambiente.hoje().substring(0, 7);
    return ordenadoPor(meses.keys, (m) => [m]).last;
  }

  Future<void> esquecerAmigo() async => limparAmigo();
}
