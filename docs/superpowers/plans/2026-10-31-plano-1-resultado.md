# Plano 1 (núcleo Dart): resultado e notas para os planos 2, 3 e 4

Concluído em 31/10/2026 na branch `migracao-flutter` (commits fa37010..31e8891). 23 tarefas, cada uma revisada; revisão final do ramo com correções aplicadas e re-revisadas.

## Estado verificado
- `flutter analyze`: sem problemas. `flutter test`: 27103 testes passando.
- `py -3.12 ferramentas/conferir_portados.py`: 147 de 147 testes Python portados.
- `flutter test --tags ida_e_volta` + `py -3.12 ferramentas/conferir_ida_e_volta.py app/build/ida_e_volta`: IDA E VOLTA OK (20 roteiros).
- `python -m unittest discover -s tests`: 147 OK (Python intacto).
- Ambiente: Flutter 3.47.9 em `C:\src\flutter` (no PATH do usuário); Python 3.12.10 instalado para gerar referências.

## Decisões tomadas durante a execução
- Compensação de prejuízo entre meses fica para a 2.1 (spec §9).
- Serial de data gigante e double fora de int64 lançam FormatException (linha pulada) em vez de data falsa silenciosa; o Python trava nesses casos.
- Posição do radar fora de int64 vira nula (não derruba a reconstrução).
- Venda de compra com quantidade 0 lança `DivisaoPorZero` (paridade com ZeroDivisionError).
- Meta sem `status` não é ativa (como `metas_ativas` do Python); `statusOuAtiva` só na descrição e na planilha.
- Arquivos com NaN/Infinity são relidos (`jsonPythonDecode`), como o json.loads.
- Chaves desconhecidas em Lote/Venda/Mes/Amigo/ItemRadar/Caixa são descartadas (a 1.12 não as grava). **Condição para o plano 4:** validar cada arquivo migrado (`fromJson→toJson` igual ao original, salvo int/double) e avisar se divergir.

## Para o plano 2 (integrações)
- Montar a requisição de cotação como `_dados_api` (mercado.py:7, 344-345: period1 = fim − 180·86400, period2 = fim, interval 1d) e o cache de 60 s por ticker.
- A camada de rede deve converter falhas para `ErroConexao`, `SemDados` e `LimiteConsultas` (ex.: `ClientException`/`SocketException` → `ErroConexao`); senão `mensagemErro` mostra "Exception: ..." ao usuário.
- `somaPython` trata tudo como double; o `sum()` do 3.12 soma inteiros sem compensação. Se o Yahoo mandar fechamentos inteiros, preservar `int` do JSON do chart ou documentar a premissa.
- Verificar `escrever` sem `endRowIndex` (spec §6.1) e montar `updateCells`/formatação a partir de `esquemaAbas`.

## Para o plano 3 (telas)
- `ambiente`, `corretagemPorOrdem` e a trava de verificação são globais por isolate: rodar o núcleo num isolate dedicado e serializar o acesso ao `Repositorio` (um único dono dos arquivos).
- Nunca trocar a configuração pelo padrão e gravar depois de uma exceção de leitura (apagaria metas, radar e planilhas).
- Usar `verificacaoEmAndamento`/`tentarIniciarVerificacao` para distinguir "verificação em andamento" de "sem metas" (bug do Android, spec §9).
- `reservado` recalcula raízes por compra (O(n²)); medir no Android.
- `lerInt` com fração lança: tratar para o mês não ficar inacessível.

## Pendências menores registradas (não bloqueiam)
Divergências só alcançáveis com dados editados à mão ou absurdos: `trim` × `strip` em caracteres raros, dígitos Unicode não ASCII, `-0.0` × `0`, forma textual de números nos arquivos locais, `resumo {}`, exceções de tipo diferente do Python em entradas inválidas, testes com cobertura parcial em alguns ramos (tempo relativo > 7 dias, guarda de 4.000.000 dias). Detalhes no histórico dos commits e nas revisões.
