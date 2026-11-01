import '../../nucleo/nucleo.dart';
import 'api.dart';

/// Avisos que os serviços mandam para a interface sem ela pedir.
sealed class EventoServico {
  const EventoServico();
}

/// A conta Google ou o estado da sincronização mudou.
class EventoConta extends EventoServico {
  const EventoConta(this.conta);

  final EstadoConta conta;
}

/// Meses, config, radar ou caixa mudaram (edição local ou sincronização).
class EventoDadosMudaram extends EventoServico {
  const EventoDadosMudaram();
}

class EventoAviso extends EventoServico {
  const EventoAviso(this.titulo, this.texto);

  final String titulo;
  final String texto;
}

/// Resultado de uma verificação de metas feita em segundo plano.
class EventoMetas extends EventoServico {
  const EventoMetas(this.relatorio);

  final RelatorioMetas relatorio;
}

/// [notificar]: (título, texto, id) das notícias para avisar o usuário.
class EventoNoticias extends EventoServico {
  const EventoNoticias(this.visao, this.notificar);

  final VisaoNoticias visao;
  final List<(String, String, String)> notificar;
}

class EventoProgresso extends EventoServico {
  const EventoProgresso(this.baixado, this.total);

  final int baixado;
  final int total;
}

/// O `config.json` está ilegível: o app abre, mas recusa gravar a config.
class EventoConfigIlegivel extends EventoServico {
  const EventoConfigIlegivel(this.mensagem);

  final String mensagem;
}
