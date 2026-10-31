/// Onde ficam os arquivos de dados (`AAAA-MM.json`, `config.json`...), por nome.
/// O núcleo só conhece esta interface; o acesso ao disco fica em
/// `armazenamento_arquivos.dart`.
abstract class Armazenamento {
  /// Conteúdo do arquivo, ou `null` se não existir.
  String? ler(String nome);

  /// Cria ou substitui o arquivo inteiro.
  void gravar(String nome, String conteudo);

  bool existe(String nome);

  /// Nomes de todos os arquivos.
  List<String> listar();

  /// Remove o arquivo; sem efeito se não existir.
  void apagar(String nome);
}

/// Armazenamento em memória (mapa nome -> texto), para testes.
class ArmazenamentoMemoria implements Armazenamento {
  final Map<String, String> _arquivos = {};

  @override
  String? ler(String nome) => _arquivos[nome];

  @override
  void gravar(String nome, String conteudo) => _arquivos[nome] = conteudo;

  @override
  bool existe(String nome) => _arquivos.containsKey(nome);

  @override
  List<String> listar() => _arquivos.keys.toList();

  @override
  void apagar(String nome) => _arquivos.remove(nome);
}
