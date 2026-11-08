// Migrações dos dados locais (§11): incrementais, em ordem, idempotentes e
// nunca editadas depois de publicadas. Os ids aplicados ficam em
// `config.json` (`Config.migracoes`, por aparelho).

import 'apuracao_medio.dart';
import 'compat/ordenacao.dart';
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

class ResultadoMigracaoDados {
  const ResultadoMigracaoDados({this.aplicada = false, this.corte, this.erro});

  final bool aplicada;

  /// Primeiro mês marcado para o custo médio.
  final String? corte;

  /// O backup falhou: nada foi migrado.
  final String? erro;
}

/// Migração `2.1-custo-medio`: backup, sincronização (sem rede ou sem login
/// segue com os dados locais), marcador no primeiro mês aberto e nos abertos
/// posteriores que ainda não o têm, e o id em `migracoes`. Nunca reescreve
/// lotes, vendas, `resumo` nem meses fechados. Um mês ilegível deixa tudo
/// como está, sem registrar: tenta de novo na próxima abertura.
Future<ResultadoMigracaoDados> migrarCustoMedio(
  Repositorio repo, {
  required String Function() fazerBackup,
  required Future<void> Function() sincronizar,
}) async {
  if (repo.lerConfigParaGravar().migracoes.contains(idMigracaoCustoMedio)) {
    return const ResultadoMigracaoDados();
  }
  try {
    fazerBackup();
  } catch (e) {
    return ResultadoMigracaoDados(erro: '$e');
  }
  try {
    await sincronizar();
  } catch (_) {
    // sem rede ou sem login: os dados locais bastam
  }

  // lê tudo antes de gravar qualquer coisa
  final String corte;
  final marcar = <Mes>[];
  try {
    corte = repo.mesInicial();
    for (final m in [
      corte,
      for (final m in repo.listarMeses())
        if (compararTexto(m, corte) > 0) m,
    ]) {
      final d = repo.carregar(m);
      if (!d.fechado && d.metodo != metodoCustoMedio) marcar.add(d);
    }
  } on FormatException {
    return const ResultadoMigracaoDados();
  } on TypeError {
    return const ResultadoMigracaoDados();
  } on RangeError {
    return const ResultadoMigracaoDados();
  } on ErroNucleo {
    return const ResultadoMigracaoDados();
  }

  for (final d in marcar) {
    marcarCustoMedio(d);
    repo.salvar(d);
  }
  final cfg = repo.lerConfigParaGravar();
  cfg.migracoes = [...cfg.migracoes, idMigracaoCustoMedio];
  repo.gravarConfig(cfg);
  return ResultadoMigracaoDados(aplicada: true, corte: corte);
}
