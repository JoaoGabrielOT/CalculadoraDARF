# Calculadora DARF

App para Windows, Android e Web que registra operações com ações e BDRs e calcula o imposto mensal (DARF, código 6015). Feito em Flutter.

- Day trade (20%) e swing trade (15%, com isenção de R$ 20 mil em vendas de ações no mês)
- Taxas da B3 e IRRF (dedo-duro)
- Caixa: saldo em conta, impacto de cada ordem e agenda de liquidações (D+2 em dias úteis da B3)
- Sincronização com uma planilha no Google Drive, compartilhada entre o computador e o celular
- Compartilhamento com amigos (somente leitura): apuração, caixa e radar, com importação de ativos do radar do amigo
- Radar de ações com logo da empresa, cotação e variação do dia, média de 6 meses, ATR e classificação de risco; gráfico de preço por período (1D a Máx), filtros e ordenação; ordem definida arrastando os ativos
- Notícias dos ativos do radar (Google Notícias), com notificação das relevantes enquanto o app está aberto ou em segundo plano
- Relatórios de abertura com análises de especialistas, filtros e gráficos
- Atualização automática pelas releases deste repositório

## Download

Na [última release](../../releases/latest):

- **Windows:** `CalculadoraDARF.exe`
- **Android:** `CalculadoraDARF.apk` (permita a instalação de apps desta origem quando o Android pedir)
- **Web:** https://calculadora-darf-web.vercel.app

## Estrutura

| Pasta ou arquivo | Conteúdo |
|---|---|
| `app/` | App Flutter (Windows, Android e Web): `lib/nucleo` (cálculo e planilha), `lib/integracoes` (Google, Yahoo, atualizador), `lib/app` (telas e serviços) |
| `web_servidor/` | Funções do servidor da versão Web (login Google) |
| `.github/workflows/release.yml` | Testes, builds e publicação das releases (tag sem "v", como `2.11.0`) |
| `docs/release/` | Notas de cada release |
| `assets/` | Logo e ícones (fonte dos ícones do app) |
| `tests/fixtures/` | Relatórios de exemplo usados nos testes |
| `*.py`, `android/main.py`, `tests/*.py`, `ferramentas/` | Versão Python antiga (até a 1.12.1), mantida só como referência; o `atualizador.py` é usado no CI para conferir que quem ainda tem a versão antiga recebe as atualizações |
