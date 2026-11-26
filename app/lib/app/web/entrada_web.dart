// Partida da versão Web, sem package:web: a trava de aba única, o
// armazenamento do navegador, a volta do login e os serviços.

import 'package:http/http.dart' as http;

import '../../integracoes/integracoes.dart';
import '../../nucleo/nucleo.dart';
import '../plataforma/plataforma.dart';
import '../servicos/api.dart';
import '../servicos/servicos_web.dart';
import 'endereco_api.dart';

const _tituloLogin = 'Login não concluído';

/// A trava de aba única já está com outra aba ou janela.
class ErroOutraAba implements Exception {
  const ErroOutraAba();

  @override
  String toString() =>
      'A Calculadora DARF já está aberta em outra aba ou janela deste '
      'navegador. Feche a outra e toque em "Tentar de novo".';
}

/// O que `iniciarApp` usa na Web. [avisosIniciais] é preenchida por
/// [criarServicos] (armazenamento bloqueado, volta do login com erro) e vira,
/// em ordem, os primeiros avisos do estado.
class EntradaWeb {
  EntradaWeb({required this.plataforma, required this.criarServicos});

  final Plataforma plataforma;
  final Future<ServicosApp> Function(Plataforma plataforma) criarServicos;
  final List<(String, String)> avisosIniciais = [];
}

/// Sobe os serviços da Web. [endereco] é o da página na carga e
/// [nonceEsperado] o nonce guardado na ida ao login (lido uma vez por carga).
/// O endereço com a volta do login é limpo antes de tudo, mesmo se a trava
/// falhar; sem a trava, nada do armazenamento é tocado.
Future<ServicosApp> prepararServicosWeb({
  required Uri endereco,
  required String? nonceEsperado,
  required Armazenamento? armazenamentoNavegador,
  required Future<bool> Function() travarAba,
  required void Function() limparEndereco,
  required Future<void> Function(Uri url) irPara,
  required Future<bool> Function(Uri url) abrirUrl,
  required void Function(String titulo, String texto) avisar,
  http.Client? cliente,
  bool timers = true,
}) async {
  final retorno = lerRetornoLogin(endereco, nonceEsperado: nonceEsperado);
  if (retorno != null) limparEndereco();
  if (!await travarAba()) throw const ErroOutraAba();
  final c = cliente ?? http.Client();
  var armazenamento = armazenamentoNavegador;
  if (armazenamento == null) {
    armazenamento = ArmazenamentoMemoria();
    avisar(
      'Dados do navegador bloqueados',
      'O navegador não permite que o app guarde dados neste site. O app '
          'funciona, mas será preciso entrar de novo a cada visita.',
    );
  }
  final mesmaConta = retorno == null
      ? null
      : consumirMesmaContaWeb(armazenamento);
  switch (retorno) {
    case RetornoPacote(:final pacote)
        when mesmaConta != null && armazenamento.existe(arquivoToken):
      // "entrar de novo": outra conta não substitui a sessão que havia
      final recusa = await gravarPacoteDaMesmaConta(
        armazenamento,
        pacote,
        mesmaConta: mesmaConta,
        http: ClienteHttp(c, tempoLimite: const Duration(seconds: 30)),
        api: enderecoApi(endereco),
      );
      if (recusa != null) avisar(_tituloLogin, recusa);
    case RetornoPacote(:final pacote):
      gravarPacoteWeb(armazenamento, pacote);
    case final RetornoErro e:
      // o código vem do endereço: só o texto fixo de avisoRetorno é mostrado
      final aviso = avisoRetorno(e);
      avisar(aviso.$1, aviso.$2);
    case null:
      break;
  }
  return criarServicosWeb(
    api: enderecoApi(endereco),
    origem: endereco,
    armazenamento: armazenamento,
    irPara: irPara,
    abrirUrl: abrirUrl,
    cliente: c,
    timers: timers,
  );
}
