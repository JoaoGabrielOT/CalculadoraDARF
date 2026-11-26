# Aba "Relatórios" — design

Data: 26/11/2026. Base: app Flutter 2.6.0 (branch `migracao-flutter`). Pedido completo do dono: `prompt.md` na raiz do repositório principal (fonte dos dados, comportamento, renderização, formato do JSON schemaVersion 1, robustez e testes) — este documento só registra as decisões e o recorte de implementação; o `prompt.md` vale por inteiro.

## Intenção
Mostrar no app (Windows, Android e Web) o Relatório de Abertura de Mercado que uma automação externa grava todo dia útil numa pasta do Google Drive, com o mesmo visual do e-mail, sem sair do app.

## Decisões do dono (26/11)
- **Escopo:** trocar `drive.metadata.readonly` por `drive.readonly` (lista e baixa arquivos criados por outro cliente). Todos entram de novo uma vez; escopo continua restrito (modo Teste). O Python 1.12 não muda.
- **Público:** todos os usuários; o dono compartilha a pasta (folderId `1pIy2wYGucMq_1Jitg96yWy8Bxu4ytn5B`) como leitor com os e-mails cadastrados.
- **Navegação:** 6ª aba "Relatórios" entre Notícias e Conta (barra lateral no PC, barra inferior no celular).

## Abordagens consideradas
1. Trocar por `drive.readonly` — escolhida.
2. Acrescentar `drive.readonly` mantendo os atuais — mesmo efeito, escopo redundante.
3. Automação grava numa planilha compartilhada (sem novo escopo) — exigiria mudar a automação externa.

## Desenho (minhas decisões, corrigíveis)
- **Escopos** em `constantes.dart` e em `web_servidor/api/auth/inicio.js` (com testes). Token antigo sem `drive.readonly`: a sincronização continua normal; só a aba Relatórios mostra "Para ver os relatórios, entre de novo com o Google" com o botão de login (não desconecta ninguém). Detecção: escopos gravados no token e, na falta, resposta 403 `insufficientPermissions`.
- **Núcleo puro (`lib/nucleo/relatorios/`)**: modelo tolerante (campo ausente → null/"—", enum desconhecido → neutra, campos extras ignorados, `schemaVersion > 1` → aviso), leitura da data pelo nome `relatorio-abertura-AAAA-MM-DD.json` (fora do padrão é ignorado e vai para o log), escolha do relatório de hoje e ordenação.
- **Fuso:** "hoje" em America/Sao_Paulo calculado como UTC−3 fixo (o Brasil não tem horário de verão desde 2019), sem dependência nova; isolado numa função para trocar se isso mudar.
- **Drive (`lib/integracoes/google/`)**: `files.list` com a consulta e os campos do pedido, paginada; `files.get?alt=media`. Reusa `SessaoGoogle`/`ClienteHttp` (na Web, Drive é chamado direto com Bearer, como Sheets).
- **Cache:** pelo `Armazenamento` já existente — `relatorios/indice.json` (nome → id, modifiedTime) e um arquivo por relatório; baixa de novo só se o modifiedTime mudar. Sem internet: mostra o cache com aviso discreto. Na Web o cache é descartável (pode ser apagado se o navegador encher).
- **Serviços:** novos métodos em `ServicosApp` (listar relatórios, abrir relatório) implementados em `ServicosLocais`, no proxy do isolate e na Web.
- **Tela (`lib/app/telas/relatorios/`)**: controle + tela + componentes por seção (a–k do pedido), com a paleta do pedido fixa (não muda com o tema, como no e-mail) dentro de cartões do tema do app; links por `Plataforma.abrirUrl`. Lista de anteriores com data por extenso e contagem colorida do termômetro.
- **Testes:** os três do pedido (parser com a fixture: todos os campos, 22 ativos, termômetro somando 22; escolha de hoje — existe, não existe, fuso; ordenação e campos faltando) + Drive com cliente falso (paginação, cache por modifiedTime, sem internet) + widget/golden da aba nos 3 temas, PC e celular.
- **Release:** 2.7.0 com notas e o passo de adicionar `drive.readonly` na tela de consentimento do Google Cloud (feito pelo controlador no navegador).

## Fora do escopo
Gerar ou editar relatórios; notificação de relatório novo; outros tipos de relatório além de "abertura".

## Pendências do dono
- Colocar a fixture `tests/fixtures/relatorio-abertura-2026-11-26.json` no repositório.
- Compartilhar a pasta com os usuários.
