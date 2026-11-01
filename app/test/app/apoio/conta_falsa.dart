import 'dart:async';

import 'package:calculadoradarf/integracoes/integracoes.dart';
import 'package:calculadoradarf/nucleo/nucleo.dart';

/// Conta Google falsa: chamadas gravadas em [chamadas], sem rede.
class ContaFalsa implements ContaGoogle {
  ContaFalsa({this.email});

  @override
  String? email;
  bool credencial = true;
  bool token = false;
  final chamadas = <String>[];
  Future<void>? segurarLogin;
  Object? falhaLer;
  Future<void> Function()? aoLer;
  Object? falhaCompartilhar;
  String? achada;
  String? planilhaAmigo;
  Map<String, List<Linha>> abasAmigo = normalizarLeitura({});

  @override
  bool get temCredencial => credencial;

  @override
  bool temToken() => token;

  @override
  Future<String> carregarToken() async => email = 'ana@gmail.com';

  @override
  Future<String> login(AbrirUrl abrirUrl, {Future<void>? cancelar}) async {
    chamadas.add('login');
    final segurar = segurarLogin;
    if (segurar != null) {
      await Future.any<void>([
        segurar,
        if (cancelar != null)
          cancelar.then<void>(
            (_) => throw ErroGoogle('O login foi cancelado.'),
          ),
      ]);
    }
    return email = 'ana@gmail.com';
  }

  @override
  void sair() {
    chamadas.add('sair');
    email = null;
  }

  @override
  Future<String?> buscarPlanilha([String dono = 'me']) async {
    chamadas.add('buscar:$dono');
    return dono == 'me' ? achada : planilhaAmigo;
  }

  @override
  Future<bool> planilhaExiste(String sid) async => true;

  @override
  Future<String> criarPlanilha() async {
    chamadas.add('criar');
    return 'sid-criada';
  }

  @override
  Future<Map<String, List<Linha>>> ler(String sid) async {
    chamadas.add('ler:$sid');
    await aoLer?.call();
    if (falhaLer != null) throw falhaLer!;
    return sid == 'sid-bia' ? abasAmigo : normalizarLeitura({});
  }

  @override
  Future<void> escrever(String sid, Map<String, List<Linha>> dados) async {
    chamadas.add('escrever:$sid');
  }

  @override
  Future<void> compartilhar(String sid, String email) async {
    chamadas.add('compartilhar:$sid:$email');
    if (falhaCompartilhar != null) throw falhaCompartilhar!;
  }

  @override
  Future<void> descompartilhar(String sid, String email) async {
    chamadas.add('descompartilhar:$sid:$email');
    if (falhaCompartilhar != null) throw falhaCompartilhar!;
  }
}
