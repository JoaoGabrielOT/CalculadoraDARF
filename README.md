# Calculadora DARF

App para Windows que registra operações com ações e BDRs e calcula o imposto mensal (DARF, código 6015).

- Day trade (20%) e swing trade (15%, com isenção de R$ 20 mil em vendas de ações no mês)
- Taxas da B3 e IRRF (dedo-duro)
- Sincronização com uma planilha no Google Drive e compartilhamento com amigos
- Radar de ações com cotação, média de 6 meses, ATR e classificação de risco
- Atualização automática pelas releases deste repositório

## Download

Baixe o `CalculadoraDARF.exe` na [última release](../../releases/latest).

## Publicar uma nova versão

```
git tag v1.1.0
git push origin v1.1.0
```

O GitHub Actions gera o executável e publica a release. Os apps instalados detectam a nova versão ao abrir.

O arquivo `credentials.json` (cliente OAuth do Google) não fica no repositório: ele é lido do segredo `GOOGLE_CREDENTIALS`.

## Gerar localmente

Com o Python instalado, rode `gerar_exe.bat` (o `credentials.json` precisa estar na pasta).
