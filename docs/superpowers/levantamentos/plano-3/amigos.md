# Levantamento: Amigos

Origem Windows: `calculadora_darf.py` (abrir 2922-2932; `DialogoAmigos` 3721-3839). Origem Android: `android/main.py` (`bloco_amigos` 2112-2187; `ver_amigo` e `carregar_amigo` 2200-2248). Código: `app/lib/app/telas/amigos/tela_amigos.dart`; botão "Amigos" do cabeçalho em `app/lib/app/telas/casca.dart`. Teste: `app/test/app/telas/amigos/tela_amigos_test.dart`. Validação do e-mail, compartilhamento e gravação ficam em `ContaLocal` (`adicionarAmigo`, `removerAmigo`); a tela só lê o campo e mostra o resultado.

| Elemento | Windows | Android | Comportamento no app | Coberto por |
|---|---|---|---|---|
| Abrir sem conta | py:2922-2924 | (bloco só na Conta) | aviso "Amigos": "Conecte sua conta Google para adicionar amigos." | `sem conta ...` |
| Abrir sem planilha | py:2925-2928 | android:2142-2145 | aviso "Amigos": "Aguarde a criação da sua planilha no Google Drive e tente novamente." (conta sem `linkPlanilha`) | `sem planilha ...` |
| Janela | py:3721-3726 | bloco na Conta | PC: diálogo de 480 px; celular: tela cheia com barra "Amigos" (o bloco da aba Conta fica para a tarefa da Conta, que pode reutilizar `TelaAmigos`) | `diálogo ...`; `celular ...` |
| Explicação | py:3727-3730 | android:2182-2183 | "Ao adicionar um amigo, sua planilha é compartilhada com ele somente para leitura. Para ver os dados dele, ele também precisa adicionar você." | `adicionar ...` |
| Adicionar | py:3790-3803 | android:2118-2142 | e-mail em minúsculas e sem espaços; "Compartilhando sua planilha…" com o botão desabilitado; sucesso verde "Planilha compartilhada com <e-mail>." e campo limpo; Enter também adiciona. As recusas ("E-mail inválido.", "Esse é o seu próprio e-mail.", "Esse amigo já foi adicionado.") vêm do serviço | `adicionar compartilha e lista` |
| Erro | py:3828-3831 | android:2132-2137 | texto de `textoErro` em vermelho ("Sem conexão com a internet." para Offline); o campo mantém o que foi digitado e o botão volta | `erro mostra o texto` |
| Lista | py:3766-3788 | android:2156-2162 | e-mail em negrito e "Adicionado em dd/mm/aaaa"; sem amigos, "Nenhum amigo adicionado." Relida ao fim de cada operação e quando os dados mudam | `adicionar ...` |
| Remover | py:3805-3822 | android:2164-2187 | confirma "Remover amigo" / "<e-mail> deixará de ter acesso à sua planilha." (botões "Remover" e "Cancelar"); "Removendo acesso…"; sucesso "Acesso de <e-mail> removido."; se era o amigo na tela, volta para "Meus dados" | `remover confirma ...`; `remover o amigo aberto ...` |
| Ver | py:3833-3835, 2929-2932 | android:2200-2204 | fecha a janela e troca a visão para o amigo; no celular fora de Apuração/Caixa/Radar vai antes para a Apuração. Se o carregamento falha, `EstadoApp` avisa | `Ver troca a visão e fecha` |
| Ações ocupadas | py:3812-3814 | - | Adicionar, Ver e Remover ficam desabilitados enquanto compartilha ou remove | cobertos pelo botão habilitado após erro |

Decisões sem equivalente literal: o Windows abria o diálogo de forma modal e esperava o resultado; o app devolve o e-mail por `Navigator.pop`. No Android o aviso de erro era um snackbar; o app usa a linha de status do Windows nas duas plataformas.
