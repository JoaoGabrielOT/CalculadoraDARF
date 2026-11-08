// Migrações dos dados locais (§11): incrementais, em ordem, idempotentes e
// nunca editadas depois de publicadas. Os ids aplicados ficam em
// `config.json` (`Config.migracoes`, por aparelho).

import 'apuracao_medio.dart';
import 'compat/ordenacao.dart';
import 'datas.dart';
import 'erros.dart';
import 'modelos/mes.dart';
import 'repositorio.dart';

/// Entrega 2.1: o custo médio vale a partir do primeiro mês aberto.
const idMigracaoCustoMedio = '2.1-custo-medio';

const tituloBackupFalhou = 'Backup dos dados';

const textoBackupFalhou =
    'Não foi possível fazer o backup dos dados; o cálculo por custo médio '
    'não foi ativado. Feche outros programas que usem a pasta de dados e abra '
    'o app de novo.';

const tituloMesesIlegiveis = 'Cálculo por custo médio';

/// Meses que a migração não conseguiu ler (ficaram como estavam).
String textoMesesIlegiveis(List<String> meses) =>
    'Estes meses não puderam ser lidos e ficaram fora da ativação do cálculo '
    'por custo médio: ${meses.map(fmtMes).join(', ')}. Confira esses '
    'arquivos.';

/// Meses ilegíveis anteriores ao corte: a migração espera a correção.
String textoMigracaoAdiada(List<String> meses) =>
    'O cálculo por custo médio não foi ativado porque estes meses não '
    'puderam ser lidos: ${meses.map(fmtMes).join(', ')}. Confira esses '
    'arquivos; o app tenta de novo na próxima abertura.';

class ResultadoMigracaoDados {
  const ResultadoMigracaoDados({
    this.aplicada = false,
    this.corte,
    this.erro,
    this.pulados = const [],
    this.sincronizou = false,
  });

  final bool aplicada;

  /// Primeiro mês aberto, a partir do qual vale o custo médio.
  final String? corte;

  /// O backup falhou: nada foi migrado.
  final String? erro;

  /// Meses ilegíveis, deixados como estavam.
  final List<String> pulados;

  /// Uma sincronização completa terminou antes da marcação.
  final bool sincronizou;
}

/// A migração ainda não foi registrada e há meses gravados. Sem nenhum mês
/// (instalação nova) ela espera: roda numa abertura depois que a
/// sincronização trouxer os dados.
bool migracaoCustoMedioPendente(Repositorio repo) =>
    !repo.lerConfig().migracoes.contains(idMigracaoCustoMedio) &&
    repo.listarMeses().isNotEmpty;

bool _erroDeLeitura(Object e) =>
    e is FormatException ||
    e is TypeError ||
    e is RangeError ||
    e is ErroNucleo;

/// Migração `2.1-custo-medio`:
/// 1. backup (se falhar, nada é feito e volta o `erro`);
/// 2. sincronização completa, limitada por quem chama (sem rede, sem login
///    ou demorada, segue com os dados locais);
/// 3. corte = primeiro mês aberto legível; marca ele e os abertos
///    posteriores sem marcador, **sem carimbar** o `mod` (o marcador não pode
///    vencer, na mesclagem, um mês que outro aparelho já fechou);
/// 4. registra o id em `migracoes`.
///
/// Meses ilegíveis voltam em `pulados`. Depois do corte eles só ficam como
/// estão; antes dele (poderiam ser o mês aberto do corte) nada é marcado nem
/// registrado. Sem mês aberto com arquivo também não: tenta de novo na
/// próxima abertura.
/// Nunca reescreve lotes, vendas, `resumo` nem meses fechados.
Future<ResultadoMigracaoDados> migrarCustoMedio(
  Repositorio repo, {
  required String Function() fazerBackup,
  required Future<bool> Function() sincronizar,
}) async {
  if (!migracaoCustoMedioPendente(repo)) return const ResultadoMigracaoDados();
  try {
    fazerBackup();
  } catch (e) {
    return ResultadoMigracaoDados(erro: '$e');
  }
  var sincronizou = false;
  try {
    sincronizou = await sincronizar();
  } catch (_) {
    // os dados locais bastam
  }

  String? corte;
  final pulados = <String>[];
  final marcar = <Mes>[];
  for (final m in repo.listarMeses()) {
    final Mes d;
    try {
      d = repo.carregar(m);
    } catch (e) {
      if (!_erroDeLeitura(e)) rethrow;
      pulados.add(m);
      continue;
    }
    if (d.fechado) continue;
    corte ??= m;
    if (d.metodo != metodoCustoMedio) marcar.add(d);
  }
  final c = corte;
  if (c == null || pulados.any((m) => compararTexto(m, c) < 0)) {
    return ResultadoMigracaoDados(pulados: pulados, sincronizou: sincronizou);
  }

  for (final d in marcar) {
    marcarCustoMedio(d);
    repo.salvar(d, carimbar: false);
  }
  final cfg = repo.lerConfigParaGravar();
  cfg.migracoes = [...cfg.migracoes, idMigracaoCustoMedio];
  repo.gravarConfig(cfg);
  return ResultadoMigracaoDados(
    aplicada: true,
    corte: corte,
    pulados: pulados,
    sincronizou: sincronizou,
  );
}

/// Corte reaplicado (§11): com a migração registrada neste aparelho e nenhum
/// mês marcado (o mês do corte voltou fechado, sem marcador, de um aparelho
/// antigo pela sincronização), marca o primeiro mês aberto, sem carimbo, e
/// devolve qual. Um mês ilegível pode ser o marcado: nesse caso nada muda.
String? reaplicarCorteCustoMedio(Repositorio repo) {
  Mes? primeiro;
  try {
    if (!repo.lerConfig().migracoes.contains(idMigracaoCustoMedio)) {
      return null;
    }
    for (final m in repo.listarMeses()) {
      final d = repo.carregar(m);
      if (d.metodo == metodoCustoMedio) return null;
      if (!d.fechado) primeiro ??= d;
    }
  } catch (e) {
    if (!_erroDeLeitura(e)) rethrow;
    return null;
  }
  if (primeiro == null) return null;
  marcarCustoMedio(primeiro);
  repo.salvar(primeiro, carimbar: false);
  return primeiro.mes;
}
