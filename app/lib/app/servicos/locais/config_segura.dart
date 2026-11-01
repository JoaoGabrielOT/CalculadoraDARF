import '../../../nucleo/nucleo.dart';

/// Config para ler e depois gravar; a guarda fica no núcleo
/// (`Repositorio.lerConfigParaGravar`), compartilhada com a sincronização.
Config lerConfigParaGravar(Repositorio repo) => repo.lerConfigParaGravar();
