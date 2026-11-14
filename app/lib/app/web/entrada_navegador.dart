import '../../integracoes/integracoes.dart';
import '../../nucleo/armazenamento_chave_valor.dart';
import '../plataforma/plataforma_web.dart';
import 'chave_valor_navegador.dart';
import 'entrada_web.dart';

/// Partida no navegador. O endereço e o nonce do login são lidos uma vez por
/// carga; cada tentativa de subir os serviços refaz o aviso inicial.
EntradaWeb? entradaWeb() {
  final plataforma = PlataformaWeb()..usarMenuDoApp();
  final endereco = Uri.base;
  final nonce = guardaNonceDoNavegador().consumir();
  final kv = chaveValorDoNavegador();
  late final EntradaWeb entrada;
  entrada = EntradaWeb(
    plataforma: plataforma,
    criarServicos: (_) {
      entrada.avisoInicial = null;
      return prepararServicosWeb(
        endereco: endereco,
        nonceEsperado: nonce,
        armazenamentoNavegador: kv == null ? null : ArmazenamentoChaveValor(kv),
        travarAba: plataforma.travarAbaUnica,
        limparEndereco: plataforma.limparEndereco,
        irPara: plataforma.navegar,
        abrirUrl: plataforma.abrirUrl,
        avisar: (titulo, texto) => entrada.avisoInicial = (titulo, texto),
      );
    },
  );
  return entrada;
}
