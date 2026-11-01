import '../../nucleo/nucleo.dart';

/// O que o sincronizador usa dos dados locais. O plano 3 implementa a mesma
/// interface sobre o isolate do núcleo.
abstract interface class DadosSincronizacao {
  Future<String?> planilhaDe(String email);
  Future<void> definirPlanilha(String email, String? sid);
  Future<bool> pendente();
  Future<void> definirPendente(bool valor);
  Future<ResultadoSincronizacao> mesclar(Map<String, List<Linha>> abasLidas);
}

/// Dados no [Repositorio] local. O núcleo usa globais por isolate: chamar
/// sempre em série sobre um único repositório.
class DadosSincronizacaoLocal implements DadosSincronizacao {
  DadosSincronizacaoLocal(this._repo);

  final Repositorio _repo;

  /// Config para ler e depois gravar. Um `config.json` ilegível seria lido
  /// como o padrão e a gravação o apagaria: nesse caso nada é alterado.
  Config _config() {
    final texto = _repo.armazenamento.ler('config.json');
    if (texto != null) {
      try {
        jsonPythonDecode(texto);
      } on FormatException {
        throw ErroValidacao(
          'O arquivo config.json está ilegível; nada foi alterado.',
        );
      }
    }
    return _repo.lerConfig();
  }

  @override
  Future<String?> planilhaDe(String email) async =>
      _repo.lerConfig().planilhas[email];

  @override
  Future<void> definirPlanilha(String email, String? sid) async {
    final cfg = _config();
    if (sid == null) {
      cfg.planilhas.remove(email);
    } else {
      cfg.planilhas[email] = sid;
    }
    _repo.gravarConfig(cfg);
  }

  @override
  Future<bool> pendente() async => _repo.lerConfig().pendente;

  @override
  Future<void> definirPendente(bool valor) async {
    final cfg = _config();
    cfg.pendente = valor;
    _repo.gravarConfig(cfg);
  }

  @override
  Future<ResultadoSincronizacao> mesclar(
    Map<String, List<Linha>> abasLidas,
  ) async => sincronizarLinhas(_repo, _config(), abasLidas);
}
