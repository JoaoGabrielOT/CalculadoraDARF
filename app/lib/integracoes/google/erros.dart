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

/// Resposta 200 cujo corpo não é um objeto JSON.
class RespostaInvalida extends ErroGoogle {
  RespostaInvalida([super.mensagem, super.status]);
}
