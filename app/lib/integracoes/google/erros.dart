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
