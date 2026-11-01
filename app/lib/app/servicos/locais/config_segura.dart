import '../../../nucleo/nucleo.dart';

/// Config para ler e depois gravar. Um `config.json` ilegível (JSON inválido,
/// raiz que não é objeto ou campo com valor inválido) seria lido como o padrão
/// e a gravação o apagaria: nesse caso nada é alterado (mesma regra de
/// `DadosSincronizacaoLocal._config`).
Config lerConfigParaGravar(Repositorio repo) {
  final texto = repo.armazenamento.ler('config.json');
  try {
    if (texto != null && jsonPythonDecode(texto) is! Map) {
      throw ErroValidacao(mensagemConfigIlegivel);
    }
    return repo.lerConfig();
  } on FormatException {
    throw ErroValidacao(mensagemConfigIlegivel);
  } on TypeError {
    throw ErroValidacao(mensagemConfigIlegivel);
  } on RangeError {
    throw ErroValidacao(mensagemConfigIlegivel);
  }
}

const mensagemConfigIlegivel =
    'O arquivo config.json está ilegível; nada foi alterado.';
