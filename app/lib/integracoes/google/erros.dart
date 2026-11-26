import '../../nucleo/erros.dart';

/// google_sync.py:48-63.
class ErroGoogle extends ErroNucleo {
  ErroGoogle([super.mensagem = '', this.status = 0]);

  final int status;
}

class SemCredencial extends ErroGoogle {
  SemCredencial([super.mensagem, super.status]);
}

class LoginNecessario extends ErroGoogle {
  LoginNecessario([super.mensagem, super.status]);
}

class Offline extends ErroGoogle {
  Offline([super.mensagem, super.status]);
}

/// 403 porque o token não tem o escopo que o pedido exige.
class EscopoInsuficiente extends ErroGoogle {
  EscopoInsuficiente([super.mensagem, super.status]);
}

/// "Entrar de novo" que voltou com outra conta Google: recusado sem trocar a
/// sessão nem o token.
class OutraConta extends ErroGoogle {
  OutraConta(String email) : super(textoOutraConta(email));
}

String textoOutraConta(String email) =>
    'Entre com a mesma conta ($email). Para trocar de conta, use Sair na aba '
    'Conta.';

/// Resposta 200 cujo corpo não é um objeto JSON.
class RespostaInvalida extends ErroGoogle {
  RespostaInvalida([super.mensagem, super.status]);
}
