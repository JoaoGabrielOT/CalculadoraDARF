import '../../nucleo/nucleo.dart';
import '../http/cliente.dart';
import 'credenciais.dart';
import 'erros.dart';
import 'login.dart';
import 'planilha.dart';
import 'sessao.dart';
import 'token.dart';

/// Login alternativo ao do navegador com loopback (na Web, pelo servidor).
typedef FazerLogin = Future<String> Function(
  AbrirUrl abrirUrl, {
  Future<void>? cancelar,
  String? mesmaConta,
  List<String> escoposExtras,
});

/// O que o sincronizador precisa da conta Google (a fachada [Google] e os
/// falsos dos testes).
abstract interface class ContaGoogle {
  String? get email;
  bool get temCredencial;
  bool temToken();
  Future<String> carregarToken();

  /// [mesmaConta] ("entrar de novo" com a sessão aberta): outra conta é
  /// recusada com [OutraConta], sem trocar o token nem a sessão.
  /// [escoposExtras] vão ao Google junto de `escoposGoogle`.
  Future<String> login(
    AbrirUrl abrirUrl, {
    Future<void>? cancelar,
    String? mesmaConta,
    List<String> escoposExtras = const [],
  });
  void sair();
  Future<String?> buscarPlanilha([String dono = 'me']);
  Future<bool> planilhaExiste(String sid);
  Future<String> criarPlanilha();
  Future<Map<String, List<Linha>>> ler(String sid);
  Future<void> escrever(String sid, Map<String, List<Linha>> dados);
  Future<void> compartilhar(String sid, String email);
  Future<void> descompartilhar(String sid, String email);
}

/// Sessão, login e planilha juntos (a classe `Google` de google_sync.py).
class Google implements ContaGoogle {
  Google({
    required this.sessao,
    required this.planilha,
    required this.httpLogin,
    this.cliente,
    this.fazerLogin,
    this.aoSair,
  });

  final SessaoGoogle sessao;
  final PlanilhaGoogle planilha;
  final ClienteHttp httpLogin;
  final ClienteOAuth? cliente;
  final FazerLogin? fazerLogin;

  /// Chamado depois de `sair()` com o token que havia (`null` se ilegível).
  final void Function(TokenGoogle? token)? aoSair;

  @override
  String? get email => sessao.email;

  @override
  bool get temCredencial => cliente != null || fazerLogin != null;

  @override
  bool temToken() => sessao.temToken();

  @override
  Future<String> carregarToken() => sessao.carregarToken();

  @override
  Future<String> login(
    AbrirUrl abrirUrl, {
    Future<void>? cancelar,
    String? mesmaConta,
    List<String> escoposExtras = const [],
  }) async {
    final fazerLogin = this.fazerLogin;
    if (fazerLogin != null) {
      return await fazerLogin(
        abrirUrl,
        cancelar: cancelar,
        mesmaConta: mesmaConta,
        escoposExtras: escoposExtras,
      );
    }
    final cliente = this.cliente;
    if (cliente == null) {
      throw SemCredencial('Arquivo credentials.json não encontrado.');
    }
    return await loginNavegador(
      sessao,
      cliente,
      httpLogin,
      abrirUrl,
      cancelar: cancelar,
      mesmaConta: mesmaConta,
      escoposExtras: escoposExtras,
    );
  }

  @override
  void sair() {
    final aoSair = this.aoSair;
    if (aoSair == null) {
      sessao.sair();
      return;
    }
    TokenGoogle? token;
    try {
      token = lerToken(sessao.armazenamento);
    } catch (_) {
      token = null;
    }
    sessao.sair();
    aoSair(token);
  }

  @override
  Future<String?> buscarPlanilha([String dono = 'me']) =>
      planilha.buscarPlanilha(dono);

  @override
  Future<bool> planilhaExiste(String sid) => planilha.planilhaExiste(sid);

  @override
  Future<String> criarPlanilha() => planilha.criarPlanilha();

  @override
  Future<Map<String, List<Linha>>> ler(String sid) => planilha.ler(sid);

  @override
  Future<void> escrever(String sid, Map<String, List<Linha>> dados) =>
      planilha.escrever(sid, dados);

  @override
  Future<void> compartilhar(String sid, String email) =>
      planilha.compartilhar(sid, email);

  @override
  Future<void> descompartilhar(String sid, String email) =>
      planilha.descompartilhar(sid, email);
}
