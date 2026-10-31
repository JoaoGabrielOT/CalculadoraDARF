// Textos das metas para as telas (metas.py:20-21, 747-781).

import '../datas.dart';
import '../formatacao.dart';
import '../modelos/meta.dart';
import 'preco_alvo.dart';

/// Aviso que acompanha o registro automático (`AVISO_REGISTRO`).
const String avisoRegistro =
    'Registro automático no app; não envia ordem à corretora';

/// Rótulo de cada status (`STATUS_ROTULO`).
const Map<String, String> statusRotulo = {
  'ativa': 'Ativa',
  'executada': 'Executada',
  'cancelada': 'Cancelada',
  'inválida': 'Inválida',
};

/// Título, status, detalhe e cor (accent, danger, aviso ou muted) de uma meta
/// na lista; [erro] marca a meta com `ultimo_erro`.
class DescricaoMeta {
  const DescricaoMeta({
    required this.titulo,
    required this.status,
    required this.detalhe,
    required this.cor,
    required this.erro,
  });

  final String titulo;
  final String status;
  final String detalhe;
  final String cor;
  final bool erro;
}

const Map<String, String> _cores = {
  'ativa': 'aviso',
  'executada': 'accent',
  'cancelada': 'muted',
  'inválida': 'danger',
};

/// `descricao`: textos para a lista de metas. [todas]: a lista de metas, para
/// dizer com qual meta esta forma um OCO.
DescricaoMeta descricao(Meta meta, {List<Meta>? todas}) {
  final String titulo;
  if (gatilho(meta) == 'stop') {
    var t = '${meta.ticker} · ${meta.qtd} un. · stop ${brl(meta.stopAtual!)}';
    if (meta.movel == true) t += ' (móvel)';
    titulo = t;
  } else {
    titulo = '${meta.ticker} · ${meta.qtd} un. a ${brl(meta.precoAlvo!)}';
  }
  final st = meta.status;
  final cor = _cores[st] ?? 'muted';
  final criada = DataHora.parse(meta.criadaEm);
  final partes = <String>[
    'Criada em ${fmtData(criada.data)} ${criada.horaMinuto}',
  ];
  final inicial = meta.stopInicial;
  if (gatilho(meta) == 'stop' &&
      meta.movel == true &&
      inicial != null &&
      (inicial - meta.stopAtual!).abs() > 0.004) {
    partes.add('stop inicial ${brl(inicial)}');
  }
  if (meta.lucroDesejado != null) {
    partes.add('lucro desejado ${brl(meta.lucroDesejado!)}');
  }
  final oco = meta.oco;
  if (oco != null && oco.isNotEmpty) {
    Meta? par;
    for (final m in todas ?? const <Meta>[]) {
      if (!identical(m, meta) && m.oco == oco) {
        par = m;
        break;
      }
    }
    if (par == null) {
      partes.add('OCO');
    } else if (gatilho(par) == 'stop') {
      partes.add('OCO com stop ${brl(par.stopAtual!)}');
    } else {
      partes.add('OCO com alvo ${brl(par.precoAlvo!)}');
    }
  }
  final ex = meta.execucao;
  if (st == 'executada' && ex != null && ex.isNotEmpty) {
    final hora = ex['hora'];
    final quando =
        fmtData(ex['data']! as String) +
        (hora is String && hora.isNotEmpty ? ' $hora' : '');
    final preco = (ex['preco_usado']! as num).toDouble();
    partes.add('executada em $quando a ${brl(preco)} (${ex['motivo'] ?? ''})');
  }
  final detalhe = meta.canceladaDetalhe;
  if (st == 'cancelada' && detalhe != null && detalhe.isNotEmpty) {
    partes.add(detalhe);
  }
  final erro = meta.ultimoErro;
  if (erro != null && erro.isNotEmpty) partes.add(erro);
  return DescricaoMeta(
    titulo: titulo,
    status: statusRotulo[st] ?? st,
    detalhe: partes.join(' · '),
    cor: cor,
    erro: erro != null && erro.isNotEmpty,
  );
}
