# Repaginada dos controles — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Aplicar em todas as telas (PC e celular, 3 temas) o padrão de controles aprovado no esboço: hierarquia de ações, um visual por tipo de controle, linhas de 40 px alinhadas, seletor de dados global e legenda de risco alinhada.

**Architecture:** Um kit de controles (`lib/app/componentes/controles.dart`) com estilo vindo do tema (`lib/app/tema/temas.dart`). Um `SeletorDados` global na casca no lugar do `SeletorVisao` das páginas. Cada tela troca seus botões, chips e dropdowns pelas peças do kit, sem mudar comportamento.

**Tech Stack:** Flutter/Dart, provider, flutter_test, goldens.

**Spec:** `docs/superpowers/specs/2026-11-28-repaginada-controles-design.md`. O esboço aprovado é `docs/superpowers/specs/2026-11-28-repaginada-controles-esboco.png` (HTML ao lado).

## Global Constraints
- **Commits:** não fazer commit nem push; o controlador faz o commit de cada task. Não incluir nem alterar `app/lib/nucleo/armazenamento_chave_valor.dart` (mudança alheia).
  - Se `dart format` mexer em arquivos fora da task, desfazer só a formatação desses arquivos.
- **Dependências e escopo:** sem dependência nova, sem cor nova (usar `CoresApp`: `destaque`, `queda`, `alta`, `aviso`, `textoSuave`, `bordaCampo`). Sem mudança de cálculo, regras, navegação ou mensagens de diálogo.
- **Medidas e comportamento:**
  - Tudo que divide uma linha mede 40 px de altura.
  - Nada de overflow em 360 px (celular), em 840 px e em 1366 px (PC).
  - Toda ação continua alcançável. Todo `BotaoIcone` tem tooltip, e a semântica usa o rótulo antigo da ação ('Editar', 'Excluir', 'Remover', 'Atualizar', 'Adicionar', 'Ordenar', 'Tipo').
- **Comandos (em `app/`):**
  - testes: `flutter test <arquivos>`, `flutter test --exclude-tags vivo`, `flutter analyze`;
  - goldens: `flutter test test/app/goldens --update-goldens --plain-name <nome>`, conferidos abrindo os PNGs.

## Review Focus
1. Amigo aberto, carregando, ou lista de amigos falhando: o `SeletorDados` mostra o estado certo (desabilitado ao carregar; "Meus dados" + amigo aberto na falha); a faixa do celular aparece e some — Task 2.
2. E-mail de amigo longo e janela de PC de 840 px: o cabeçalho não estoura (texto ≤ 180 px com reticências; ícones abaixo de 1200 px) — Task 2.
3. Ordenar num botão só: a direção e o campo persistem como hoje; no Radar, arrastar continua exigindo "Minha ordem" + Todos — Tasks 3 e 5.
4. Setas do mês: "próximo" desabilitado no mês atual (máximo); mês fechado e amigo somente leitura mantêm as regras de "Fechar mês" — Task 3.
5. Segmentados de 4 opções em 360 px (Radar; Relatórios 7 | 30 | 90 dias | Todos) no modo compacto, sem overflow — Tasks 5 e 6.

---

### Task 1: Kit de controles e tema
**Files:** Create `app/lib/app/componentes/controles.dart`, `app/test/app/componentes/controles_test.dart`; Modify `app/lib/app/tema/temas.dart` (`segmentedButtonTheme`; campos densos de 40 px via `inputDecorationTheme`, sem mudar os campos de formulário existentes que já têm altura própria, a menos que o teste mostre 40 px).
- **Interfaces (Produces):**
  - **Botões:**
    - `BotaoPrincipal({required IconData icone, required String rotulo, VoidCallback? onPressed})` (FilledButton.icon);
    - `BotaoSecundario({required IconData icone, required String rotulo, VoidCallback? onPressed, bool compacto = false})` (OutlinedButton.icon);
    - `BotaoIcone({required IconData icone, required String tooltip, VoidCallback? onPressed, bool destrutivo = false, bool marcado = false})`: `marcado` desenha um ponto `destaque` no canto, para filtro ativo; destrutivo usa a cor `queda`;
    - `BotaoLeve({required IconData icone, required String rotulo, VoidCallback? onPressed, Color? cor, double larguraMaxRotulo = 180})` (TextButton.icon, com o rótulo com reticências).
  - **Escolha e filtros:**
    - `Segmentado<T>({required List<(T, String)> opcoes, required T valor, required ValueChanged<T> aoMudar, bool compacto = false})`: SegmentedButton de escolha única; `compacto` = sem ✓ e com padding horizontal de 10;
    - `CampoBusca({required TextEditingController controller, required String dica, ValueChanged<String>? aoMudar, double? largura})`: lupa e botão de limpar quando tem texto;
    - `BotaoMenu<T>({required IconData icone, required String rotulo, required List<(T, String)> itens, required ValueChanged<T> aoEscolher, T? marcado, bool soIcone = false})`;
    - `BotaoOrdenar<T>({required List<(T, String)> campos, required T campo, required bool desc, required ValueChanged<T> aoCampo, required VoidCallback aoInverter, bool semDirecao = false, bool soIcone = false})`: rótulo "<campo> ↑" ou "<campo> ↓" (só "<campo>" com `semDirecao`) e tooltip 'Ordenar'. O menu tem os campos (✓ no atual) e, separado, "Crescente ↑" ou "Decrescente ↓" para inverter.
  - **Seletores e selos:**
    - `SeletorCaixa<T>({required String rotulo, required T valor, required List<(T, String)> itens, ValueChanged<T>? aoMudar, double? largura})`: caixa contornada com rótulo flutuante e 40 px; `aoMudar` null = desabilitado;
    - `SeletorMes({required String mes, required String maximo, required ValueChanged<String> aoMudar, required VoidCallback aoAbrir})`: ◂ e ▸ mudam um mês (formato `AAAA-MM`); ▸ é desabilitado quando `mes == maximo`; o centro mostra `fmtMes(mes)` e chama `aoAbrir`. Tooltips 'Mês anterior' e 'Próximo mês';
    - `Selo({required String texto, required Color cor, IconData? icone, bool ponto = false})`: etiqueta chapada (fundo `cor` a 18%, texto `cor`, raio 8, sem borda);
    - `LegendaPonto({required String texto, required Color cor})`: ponto de 8 px + texto `textoSuave`, para legendas não clicáveis.
- [ ] Testes (`controles_test.dart`, nos 3 temas onde fizer diferença):
  - altura renderizada de 40 px para `BotaoPrincipal`, `BotaoSecundario`, `Segmentado`, `CampoBusca`, `BotaoMenu` e `SeletorCaixa`;
  - `BotaoIcone` expõe o tooltip e `find.bySemanticsLabel(tooltip)`; o destrutivo usa a cor `queda`;
  - `Segmentado` chama `aoMudar` com o valor tocado; `compacto` não mostra `Icons.check`;
  - `BotaoOrdenar` mostra 'Cadastro ↑'; escolher outro campo chama `aoCampo`; "Decrescente ↓" chama `aoInverter`; `semDirecao` mostra só 'Minha ordem';
  - `SeletorMes('2026-11', maximo '2026-11')`: ▸ desabilitado; ◂ chama `aoMudar('2026-10')`; '2026-01' + ◂ dá '2025-12'; tocar no centro chama `aoAbrir`;
  - `CampoBusca`: digitar chama `aoMudar` e o botão de limpar zera o texto;
  - `SeletorCaixa` com `aoMudar` null fica desabilitado.
- [ ] Implementar o kit e o tema. As telas ainda não usam o kit.
- [ ] `flutter test test/app/componentes/controles_test.dart` e `flutter analyze` PASS. Escrever o relatório em `task-1-report.md`.

### Task 2: Seletor de dados global e cabeçalho
**Files:**
- Create `app/lib/app/componentes/seletor_dados.dart`.
- Modify:
  - `app/lib/app/telas/casca.dart` (`_Cabecalho` e o AppBar do celular, mais a faixa do amigo);
  - remoção do `SeletorVisao` em `telas/apuracao/tela_apuracao.dart` (linhas ~211 e ~373, mais o "Atualizar" do amigo), `telas/caixa/tela_caixa.dart` (~160 e ~781) e `telas/radar/tela_radar.dart` (~474 e ~689);
  - apagar `telas/apuracao/seletor_visao.dart`, movendo `rotuloMeusDados` para `seletor_dados.dart`.
- Tests: `test/app/telas/casca_test.dart` e os testes de Apuração, Caixa e Radar que usavam o dropdown; goldens de todas as telas PC e celular afetadas.
- **Interfaces:** `SeletorDados({bool soIcone = false})` lê `EstadoApp` (`amigo`, `carregandoAmigo`, `versaoDados`, `conta.email`) e `ServicosApp.amigos()` como o `SeletorVisao` fazia, e chama `estado.trocarVisao(email|null)`. O menu tem 'Meus dados', os e-mails, um divisor e 'Gerenciar amigos…' (chama `abrirAmigos(context)`).
- [ ] Testes:
  - **PC 1366, cabeçalho:** 'Meus dados' (com `Icons.group`), saldo, 'Meta de lucro · 2', avatar com a inicial do e-mail e tooltip com o e-mail; sem o botão 'Amigos'.
  - **Menu do seletor:** escolher o e-mail chama `trocarVisao`; 'Gerenciar amigos…' abre Amigos.
  - **Estados do seletor:**
    - com amigo aberto, o seletor mostra o e-mail na cor `aviso` e aparece `BotaoIcone` 'Atualizar';
    - com `carregandoAmigo`, fica desabilitado;
    - com `amigos()` lançando erro, mostra 'Meus dados' + o amigo aberto.
  - **PC 840:** sem overflow; Meta e seletor só com ícone e tooltip; status de sincronização só com o ponto.
  - **E-mail de 40 caracteres a 1366:** sem overflow.
  - **Sem conta:** 'Conectar Google' (secundário).
  - **Celular 360:**
    - `BotaoIcone` 'Meus dados' no AppBar, com o mesmo menu;
    - com amigo aberto, a faixa 'Dados de X · somente leitura' com 'Voltar aos meus', que chama `trocarVisao(null)`;
    - sem amigo, sem faixa.
  - **Páginas:** Apuração, Caixa e Radar não têm mais `DropdownButton` de dados.
- [ ] Implementar conforme o spec ("Seletor de dados global" e "Cabeçalho do PC"; decisões 4 e 5).
- [ ] Testes, goldens afetados (todas as telas PC e as de celular com AppBar mudado) e `flutter analyze` PASS.

### Task 3: Apuração
**Files:** `telas/apuracao/tela_apuracao.dart` (`_Barra`), `lista_lotes.dart`, `lista_vendas.dart`, `lista_posicoes.dart`, `barra_filtros.dart`; Tests `test/app/telas/apuracao/tela_apuracao_test.dart`, `listas_test.dart`, `posicoes_tela_test.dart`; goldens `apuracao_*`, `vendas_grupo_*`.
- **Interfaces (Consumes):** kit da Task 1. Mês: `SeletorMes(mes: estado.mes, maximo: ambiente.hoje().substring(0,7), aoMudar: estado.trocarMes, aoAbrir: () => controle.escolher(context))`.
- [ ] Testes:
  - **Barra, PC:** `SeletorMes`, o selo e `BotaoPrincipal` 'Fechar mês' (desabilitado quando `!controle.podeFechar`); ◂ troca para o mês anterior; ▸ desabilitado no mês atual.
  - **Barra, celular:** `SeletorMes`, o selo e o menu ⋮ com 'Fechar mês'.
  - **Cartão "Ativos comprados", PC:**
    - `BotaoIcone` 'Editar' e 'Excluir' (destrutivo), `BotaoSecundario` 'Registrar venda' e `BotaoPrincipal` 'Novo ativo', todos com o comportamento de antes, inclusive o aviso 'Selecione…';
    - `Segmentado` 'Posição em dd/mm/aaaa' | 'Carteira atual' e o texto da cotação.
  - **Filtros:**
    - `Segmentado` Todos | Em aberto | Vendidos;
    - `CampoBusca` 'Buscar ticker…' filtrando a tabela;
    - `BotaoMenu` 'Tipo' com as opções de hoje;
    - `BotaoOrdenar` com os campos de hoje ('Cadastro ↑'); inverter dá '↓' e reordena.
  - **Vendas do mês e Posições:** mesmo padrão.
  - **Celular 360:**
    - Situação segmentada compacta;
    - busca expandida e ícones 'Tipo' e 'Ordenar' (`marcado` quando fora do padrão);
    - sem overflow;
    - a lista rolável termina com folga ≥ 88 px, de modo que o FAB '+' não cobre o último cartão.
- [ ] Implementar conforme o spec ("Telas › Apuração").
- [ ] Testes, goldens `apuracao_*` e `vendas_grupo_*` e `flutter analyze` PASS.

### Task 4: Caixa
**Files:** `telas/caixa/tela_caixa.dart`; Test `test/app/telas/caixa/tela_caixa_test.dart`; goldens `caixa_*`.
- [ ] Testes:
  - **Ações:** `BotaoPrincipal` 'Aporte', `BotaoSecundario` 'Retirada' e `BotaoLeve` 'Definir saldo', com o mesmo comportamento.
  - **Lançamentos:** `Segmentado` Todos | A liquidar | Liquidados, filtrando como antes.
  - **Celular:** o 'Editar' do cartão de saldo vira `BotaoIcone` 'Editar'; 360 px sem overflow.
- [ ] Implementar conforme o spec ("Telas › Caixa").
- [ ] Testes, goldens `caixa_*` e analyze PASS.

### Task 5: Radar
**Files:** `telas/radar/tela_radar.dart`, `linha_radar.dart`; Test `test/app/telas/radar/tela_radar_test.dart`; goldens `radar_*`.
- [ ] Testes:
  - **Topo, PC:** campo de ticker de 40 px, `BotaoPrincipal` 'Adicionar' e `BotaoIcone` 'Atualizar'.
  - **Topo, celular:** campo + '+' roxo (`destaque`) de 40 px na mesma linha.
  - **Filtros:** `Segmentado` Todos | Em alta | Em queda | Em carteira (compacto no celular, 360 px sem overflow) e `BotaoOrdenar` com `semDirecao` para 'Minha ordem'. Arrastar continua bloqueado fora de 'Minha ordem' + Todos, com a mesma mensagem.
  - **Linhas, PC:** 'Comprar' (tonal compacto), 'Vender' (secundário compacto) e `BotaoIcone` 'Remover' (destrutivo), com o mesmo comportamento.
  - **Legenda:**
    - o título 'RISCO PELO ATR%' fica numa linha própria;
    - as 4 faixas são `LegendaPonto`, com os mesmos textos;
    - no celular 360, ficam numa grade de 2 colunas: os itens 0 e 1 na mesma linha (mesmo `dy`), o item 0 alinhado à esquerda com o item 2 (mesmo `dx`), e nenhum item na linha do título;
    - no PC, as 4 faixas ficam na mesma linha.
- [ ] Implementar conforme o spec ("Telas › Radar").
- [ ] Testes, goldens `radar_*` e analyze PASS.

### Task 6: Notícias e Relatórios
**Files:** `telas/noticias/tela_noticias.dart`, `mural.dart`, `cartao_noticia.dart`; `telas/relatorios/tela_relatorios.dart`, `barra_filtros_relatorio.dart`, `vista_relatorio.dart` (selos de leitura); Tests `tela_noticias_test.dart`, `tela_relatorios_test.dart`, `vista_relatorio_test.dart`; goldens `noticias_*`, `relatorios_*`.
- [ ] Testes:
  - **Notícias:**
    - `Segmentado` Todas | Relevantes, `SeletorCaixa` 'Ativo' e `BotaoIcone` 'Atualizar', no PC e no celular;
    - o selo 'Nova' fica logo após o título;
    - 360 px sem overflow.
  - **Relatórios:**
    - o painel de anteriores tem o título com `BotaoIcone` 'Atualizar' e o `Segmentado` 7 dias | 30 dias | 90 dias | Todos numa linha (compacto no celular, 360 px sem overflow);
    - no celular, 'Anteriores' é `BotaoSecundario`;
    - os selos de leitura são `Selo` (chapado);
    - os filtros múltiplos continuam `FilterChip`.
- [ ] Implementar conforme o spec ("Telas › Notícias, Relatórios").
- [ ] Testes, goldens `noticias_*` e `relatorios_*` e analyze PASS.

### Task 7: Conta, Amigos, Metas e formulários
**Files:** `telas/conta/tela_conta.dart`, `telas/amigos/tela_amigos.dart`, `telas/metas/tela_metas.dart`, `aba_sugestoes.dart`, `aba_calculadora.dart`, `lista_metas.dart`, `telas/formularios/*.dart` (rodapés e seleções); Tests correspondentes; goldens `conta_*`, `metas_sugestoes*`, `form_venda_*`.
- [ ] Testes:
  - **Conta, Tema:** `Segmentado` no PC e `SeletorCaixa` 'Tema' no celular, trocando o tema como antes.
  - **Conta, prejuízo:** 'Salvar prejuízo' é `BotaoPrincipal`, alinhado aos campos de 40 px; 'Abrir amigos' é secundário.
  - **Amigos (lista na Conta e tela Amigos):** 'Ver' é `BotaoSecundario(compacto)` e 'Remover' é `BotaoIcone` destrutivo, com a mesma confirmação.
  - **Metas:**
    - Sugestões | Calculadora | Metas viram `Segmentado`, no PC e no celular, com 'Verificar agora' secundário na mesma linha;
    - 'Dados' e 'Ordenar por' viram `SeletorCaixa`, com as chaves `filtro-dados` e `ordem-sugestoes` mantidas;
    - Atualizar vira `BotaoIcone`.
  - **Formulários:** o rodapé tem Cancelar como texto e a ação principal cheia.
  - **Geral:** 360 px sem overflow.
- [ ] Implementar conforme o spec ("Telas › Conta, Amigos, Metas, Formulários").
- [ ] Suíte inteira `flutter test --exclude-tags vivo` e analyze PASS.

### Task 8: Conferência visual final
**Files:** goldens de todas as telas.
- [ ] Regenerar todos os goldens (`flutter test test/app/goldens --update-goldens`) e conferir com o agente `conferidor-visual` contra as Regras 1–4 do spec, nos 3 temas, PC e celular.
- [ ] Corrigir o que ele apontar e regenerar.
- [ ] Rodar a suíte inteira e analyze PASS.
