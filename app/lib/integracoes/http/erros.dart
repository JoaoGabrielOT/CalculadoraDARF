import '../../nucleo/erros.dart';

/// `requests.HTTPError`: status de erro (4xx/5xx) com o texto do `raise_for_status`.
class ErroHttp extends ErroNucleo {
  ErroHttp(this.status, super.mensagem);

  final int status;
}

/// `response.raise_for_status()`: 429 vira [LimiteConsultas]; outro status
/// ≥ 400 vira [ErroHttp] com o texto do requests; o resto passa.
void conferirStatus(int status, Uri url, {String? motivo}) {
  if (status == 429) throw LimiteConsultas('Too Many Requests');
  if (status < 400) return;
  final tipo = status < 500 ? 'Client' : 'Server';
  throw ErroHttp(status, '$status $tipo Error: ${motivo ?? ''} for url: $url');
}
