// Compartilhamento da pasta de relatórios com os amigos, feito pela conta
// dona da pasta: leitor, sem e-mail de aviso.

import 'constantes.dart';
import 'erros.dart';
import 'relatorios.dart';
import 'sessao.dart';

/// Limite de páginas da listagem, contra um `nextPageToken` que nunca acaba.
const _maxPaginas = 50;

enum EstadoCompartilhamento {
  /// A conta não pode compartilhar a pasta: nada aparece.
  naoDono,

  /// Dona da pasta, mas o token não tem [escopoDrive]: aviso "Permitir".
  semEscopo,

  /// Dona da pasta com [escopoDrive].
  pronto,
}

class ResultadoCompartilhamento {
  const ResultadoCompartilhamento({
    this.compartilhados = 0,
    this.recusados = const [],
    this.semEscopo = false,
    this.erro,
    this.estado,
  });

  /// O que a conferência concluiu; `null` quando não deu para conferir.
  final EstadoCompartilhamento? estado;

  /// Amigos que ganharam acesso agora.
  final int compartilhados;

  /// E-mails que o Google recusou (400: sem conta Google).
  final List<String> recusados;

  /// Falta [escopoDrive] (antes de tentar ou num 403 do Google).
  final bool semEscopo;

  /// Motivo da falha que interrompeu o compartilhamento.
  final String? erro;
}

abstract interface class FonteCompartilhamento {
  /// `naoDono` só com resposta definitiva (sem `canShare`, fora de `owners`,
  /// 403/404); falha passageira lança o erro.
  Future<EstadoCompartilhamento> estado();

  /// Dá acesso de leitor aos [emails] que ainda não têm nenhum papel na
  /// pasta. Não lança erro do Google: sem conferir o dono volta vazio (sem
  /// `estado`); depois de conferir, a falha volta em `erro`.
  Future<ResultadoCompartilhamento> compartilharCom(List<String> emails);
}

String _normalizado(String email) => email.trim().toLowerCase();

/// `reason` de um 403 que quer dizer "sem acesso à pasta"; os de limite
/// (`rateLimitExceeded` e afins) e o de escopo ficam de fora.
const _motivosSemAcesso = {
  'insufficientFilePermissions',
  'forbidden',
  'notFound',
};

/// 404, ou 403 de permissão (ou sem `reason`): resposta definitiva de que a
/// conta não é dona da pasta.
bool _semAcesso(ErroGoogle e) {
  if (e.status == 404) return true;
  if (e.status != 403 || e is EscopoInsuficiente) return false;
  final motivo = e.motivo;
  return motivo == null || _motivosSemAcesso.contains(motivo);
}

class DriveCompartilhamento implements FonteCompartilhamento {
  DriveCompartilhamento(this.sessao);

  final SessaoGoogle sessao;

  static const _urlPermissoes = '$urlDrive/files/$pastaRelatorios/permissions';

  /// Memória da sessão, da conta [_contaMemoria]: e-mails que o Google
  /// recusou (400) e o e-mail que o Drive gravou para cada amigo (o Gmail
  /// normaliza pontos e `googlemail.com`).
  String? _contaMemoria;
  final _recusados = <String>{};
  final _doDrive = <String, String>{};

  void _conferirMemoria() {
    final conta = sessao.email;
    if (conta == _contaMemoria) return;
    _contaMemoria = conta;
    _recusados.clear();
    _doDrive.clear();
  }

  /// `canShare` e a conta em `owners` (o `drive.readonly` basta); a pasta que
  /// a conta não enxerga (403/404) é de outro dono.
  @override
  Future<EstadoCompartilhamento> estado() async {
    final Map<String, Object?> r;
    try {
      r = await sessao.req(
        'GET',
        '$urlDrive/files/$pastaRelatorios',
        params: {'fields': 'capabilities(canShare),owners(emailAddress)'},
      );
    } on ErroGoogle catch (e) {
      if (_semAcesso(e)) return EstadoCompartilhamento.naoDono;
      // limite, 5xx, rede: não conferido
      rethrow;
    }
    // lidos depois do pedido: a renovação pode ter trocado o token
    final escopos = sessao.escopos;
    final conta = sessao.email;
    if (escopos == null || conta == null) {
      throw LoginNecessario('Faça login com o Google.');
    }
    final capacidades = r['capabilities'];
    final donos = r['owners'];
    final dona =
        donos is List &&
        donos.any(
          (d) =>
              d is Map &&
              d['emailAddress'] is String &&
              _normalizado(d['emailAddress'] as String) == conta,
        );
    if (capacidades is! Map || capacidades['canShare'] != true || !dona) {
      return EstadoCompartilhamento.naoDono;
    }
    return escopos.contains(escopoDrive)
        ? EstadoCompartilhamento.pronto
        : EstadoCompartilhamento.semEscopo;
  }

  /// E-mails (normalizados) com qualquer papel na pasta, de todas as páginas.
  Future<Set<String>> _comAcesso() async {
    final emails = <String>{};
    final vistas = <String>{};
    String? pagina;
    for (var i = 0; i < _maxPaginas; i++) {
      final r = await sessao.req(
        'GET',
        _urlPermissoes,
        params: {
          'fields': 'nextPageToken,permissions(emailAddress,role,type)',
          'pageToken': ?pagina,
        },
      );
      final permissoes = r['permissions'];
      if (permissoes is List) {
        for (final p in permissoes) {
          final email = p is Map ? p['emailAddress'] : null;
          if (email is String && email.trim().isNotEmpty) {
            emails.add(_normalizado(email));
          }
        }
      }
      final proxima = r['nextPageToken'];
      if (proxima is! String || proxima.isEmpty || !vistas.add(proxima)) break;
      pagina = proxima;
    }
    return emails;
  }

  @override
  Future<ResultadoCompartilhamento> compartilharCom(List<String> emails) async {
    final EstadoCompartilhamento estado;
    try {
      estado = await this.estado();
    } on ErroGoogle {
      // sem conferir o dono, nada a dizer: quem não é dono nunca vê aviso
      return const ResultadoCompartilhamento();
    }
    if (estado != EstadoCompartilhamento.pronto) {
      return ResultadoCompartilhamento(
        estado: estado,
        semEscopo: estado == EstadoCompartilhamento.semEscopo,
      );
    }
    _conferirMemoria();
    var compartilhados = 0;
    final recusados = <String>[];
    ResultadoCompartilhamento resultado({
      bool semEscopo = false,
      String? erro,
    }) => ResultadoCompartilhamento(
      estado: estado,
      compartilhados: compartilhados,
      recusados: List.unmodifiable(recusados),
      semEscopo: semEscopo,
      erro: erro,
    );

    try {
      final faltam = {for (final e in emails) _normalizado(e)}
        ..removeWhere((e) => e.isEmpty || _recusados.contains(e));
      if (faltam.isEmpty) return resultado();
      final comAcesso = await _comAcesso();
      faltam.removeWhere(
        (e) => comAcesso.contains(e) || comAcesso.contains(_doDrive[e]),
      );
      for (final email in faltam) {
        try {
          final r = await sessao.req(
            'POST',
            _urlPermissoes,
            params: {'sendNotificationEmail': false, 'fields': 'emailAddress'},
            json: {'role': 'reader', 'type': 'user', 'emailAddress': email},
          );
          final gravado = r['emailAddress'];
          if (gravado is String && gravado.trim().isNotEmpty) {
            _doDrive[email] = _normalizado(gravado);
          }
          compartilhados++;
        } on ErroGoogle catch (e) {
          // e-mail sem conta Google: os outros seguem e ele não é tentado de
          // novo nesta sessão
          if (e.status != 400) rethrow;
          _recusados.add(email);
          recusados.add(email);
        }
      }
      return resultado();
    } on EscopoInsuficiente catch (e) {
      return resultado(semEscopo: true, erro: e.mensagem);
    } on ErroGoogle catch (e) {
      return resultado(erro: e.mensagem);
    }
  }
}
