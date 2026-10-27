# Calculadora DARF

App para Windows e Android que registra operações com ações e BDRs e calcula o imposto mensal (DARF, código 6015).

- Day trade (20%) e swing trade (15%, com isenção de R$ 20 mil em vendas de ações no mês)
- Taxas da B3 e IRRF (dedo-duro)
- Caixa: saldo em conta, impacto de cada ordem e agenda de liquidações (D+2 em dias úteis da B3)
- Sincronização com uma planilha no Google Drive, compartilhada entre o computador e o celular
- Compartilhamento com amigos (somente leitura): apuração, caixa e radar, com importação de ativos do radar do amigo
- Radar de ações com logo da empresa, cotação e variação do dia, média de 6 meses, ATR e classificação de risco; gráfico de preço por período (1D a Máx), filtros e ordenação; ordem definida arrastando os ativos
- Notícias dos ativos do radar (Google Notícias), com notificação das relevantes enquanto o app está aberto ou em segundo plano
- Atualização automática pelas releases deste repositório

## Download

Na [última release](../../releases/latest):

- **Windows:** `CalculadoraDARF.exe`
- **Android:** `CalculadoraDARF.apk` (permita a instalação de apps desta origem quando o Android pedir)

## Estrutura

| Arquivo | Conteúdo |
|---|---|
| `nucleo.py` | Cálculo, armazenamento local, planilha e mesclagem entre aparelhos (compartilhado) |
| `google_sync.py` | Login Google, Sheets e Drive (compartilhado) |
| `mercado.py` | Cotações e indicadores do radar (compartilhado) |
| `noticias.py` | Notícias do radar, relevância e logos (compartilhado) |
| `atualizador.py` | Verificação e download de novas versões (compartilhado) |
| `calculadora_darf.py`, `tema.py`, `componentes.py` | App Windows (CustomTkinter) |
| `android/main.py` | App Android (Flet) |
| `assets/` | Logo e ícones |
