import '../../../nucleo/nucleo.dart';

/// Config para ler e depois gravar. Um `config.json` ilegível seria lido como
/// o padrão e a gravação o apagaria: nesse caso nada é alterado (mesma regra
/// de `DadosSincronizacaoLocal._config`).
Config lerConfigParaGravar(Repositorio repo) {
  final texto = repo.armazenamento.ler('config.json');
  if (texto != null) {
    try {
      jsonPythonDecode(texto);
    } on FormatException {
      throw ErroValidacao(mensagemConfigIlegivel);
    }
  }
  return repo.lerConfig();
}

const mensagemConfigIlegivel =
    'O arquivo config.json está ilegível; nada foi alterado.';
