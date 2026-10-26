# Calculadora DARF

App para Windows e Android que registra operações com ações e BDRs e calcula o imposto mensal (DARF, código 6015).

- Day trade (20%) e swing trade (15%, com isenção de R$ 20 mil em vendas de ações no mês)
- Taxas da B3 e IRRF (dedo-duro)
- Sincronização com uma planilha no Google Drive, compartilhada entre o computador e o celular
- Compartilhamento com amigos (somente leitura)
- Radar de ações com cotação, média de 6 meses, ATR e classificação de risco
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
| `atualizador.py` | Verificação e download de novas versões (compartilhado) |
| `calculadora_darf.py`, `tema.py`, `componentes.py` | App Windows (CustomTkinter) |
| `android/main.py` | App Android (Flet) |
| `assets/` | Logo e ícones |

## Publicar uma nova versão

Crie uma release com uma tag nova (ex.: `v1.2.0`) em **Releases → Draft a new release**, ou:

```
git tag v1.2.0
git push origin v1.2.0
```

O GitHub Actions gera o `.exe` e o `.apk` e os anexa à release. Os apps instalados detectam a nova versão ao abrir.

Segredos usados pelo build (Settings → Secrets and variables → Actions):

- `GOOGLE_CREDENTIALS`: conteúdo do `credentials.json` (cliente OAuth do Google)
- `ANDROID_KEYSTORE_BASE64`: chave de assinatura do APK em base64
- `ANDROID_KEYSTORE_PASSWORD`: senha da chave

O APK precisa ser sempre assinado com a mesma chave; sem ela, o Android não instala as atualizações.

## Gerar localmente (Windows)

Com o Python instalado, rode `gerar_exe.bat` (o `credentials.json` precisa estar na pasta).
