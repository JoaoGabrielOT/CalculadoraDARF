/// Erros do núcleo; `toString()` devolve só a mensagem, como o `str(e)` do
/// Python, porque o texto vai direto para o usuário.
abstract class ErroNucleo implements Exception {
  ErroNucleo(this.mensagem);

  final String mensagem;

  @override
  String toString() => mensagem;
}

/// `ValueError` com mensagem para o usuário.
class ErroValidacao extends ErroNucleo {
  ErroValidacao(super.mensagem);
}

/// `mercado.SemDados`.
class SemDados extends ErroNucleo {
  SemDados(super.mensagem);
}

/// Limite de consultas do Yahoo atingido.
class LimiteConsultas extends ErroNucleo {
  LimiteConsultas(super.mensagem);
}

/// Falha de rede.
class ErroConexao extends ErroNucleo {
  ErroConexao(super.mensagem);
}

/// `sugestoes.SemSugestao`.
class SemSugestao extends ErroNucleo {
  SemSugestao(super.mensagem);
}
