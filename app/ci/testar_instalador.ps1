# Testa o instalador real no runner: instala em silêncio a partir de uma pasta
# acentuada com uma 1.12 falsa ao lado, confere a migração feita pelo app e desinstala.
param([Parameter(Mandatory = $true)][string]$Instalador)

$ErrorActionPreference = 'Stop'

function Falhar($msg) {
  Write-Output "::error title=Instalador::$msg"
  exit 1
}

function Aviso($msg) {
  Write-Output "::notice title=Instalador::$msg"
}

if (-not (Test-Path $Instalador)) { Falhar "instalador não encontrado: $Instalador" }
$Instalador = (Resolve-Path $Instalador).Path

$utf8 = New-Object System.Text.UTF8Encoding($false)
$exeInstalado = Join-Path $env:LOCALAPPDATA 'Programs\Calculadora DARF\calculadoradarf.exe'
$pastaInstalada = Split-Path $exeInstalado
$suporte = Join-Path $env:APPDATA 'JoaoGabrielOT\Calculadora DARF'

# 1. pasta da 1.12 falsa, com acento, e o instalador ao lado (como o atualizador Python faz)
$origemPai = Join-Path $env:RUNNER_TEMP 'Área de Trabalho\Calculadora DARF'
$origem = Join-Path $origemPai 'dados'
New-Item -ItemType Directory -Force -Path (Join-Path $origem 'logos') | Out-Null
[IO.File]::WriteAllText((Join-Path $origem 'config.json'), '{"tema": "Dark", "radar": []}', $utf8)
[IO.File]::WriteAllText((Join-Path $origem '2026-10.json'), '{"mes": "2026-10", "fechado": false, "darf_anterior": 0.0, "lotes": [{"id": "L1", "ticker": "AAPL34", "tipo": "Ação", "data_compra": "2026-10-05", "qtd": 100, "preco": 30.0, "vendas": [], "mod": 0}], "excluidos": {}}', $utf8)
[IO.File]::WriteAllBytes((Join-Path $origem 'logos\X.png'), [byte[]](137, 80, 78, 71, 13, 10, 26, 10))
$hashesOrigem = @{}
Get-ChildItem $origem -Recurse -File | ForEach-Object { $hashesOrigem[$_.FullName] = (Get-FileHash $_.FullName).Hash }
Copy-Item $Instalador (Join-Path $origemPai 'CalculadoraDARF.exe')
Aviso "pasta 1.12 falsa criada em $origemPai"

# 2. instalação silenciosa (só o processo do instalador; o app aberto pelo [Run] segue vivo)
$p = Start-Process -FilePath (Join-Path $origemPai 'CalculadoraDARF.exe') `
  -ArgumentList '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART' -PassThru
if (-not $p.WaitForExit(180000)) { Falhar 'instalador não terminou em 180 s' }
if ($p.ExitCode -ne 0) { Falhar "instalador saiu com código $($p.ExitCode)" }
Aviso 'instalação silenciosa terminou com código 0'

# 3. arquivos instalados
if (-not (Test-Path $exeInstalado)) { Falhar "$exeInstalado ausente" }
foreach ($dll in 'msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll') {
  if (-not (Test-Path (Join-Path $pastaInstalada $dll))) { Falhar "$dll ausente ao lado do exe instalado" }
}
Aviso 'exe e as DLLs msvcp140, vcruntime140 e vcruntime140_1 instalados'
$atalho = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Calculadora DARF.lnk'
if (-not (Test-Path $atalho)) { Falhar "atalho ausente: $atalho" }
Aviso 'atalho do menu Iniciar criado'
$arqOrigem = Join-Path $suporte 'migracao_origem.txt'
if (-not (Test-Path $arqOrigem)) { Falhar 'migracao_origem.txt ausente' }
$texto = [IO.File]::ReadAllText($arqOrigem, [Text.Encoding]::UTF8).TrimStart([char]0xFEFF).Trim()
if ($texto -ne $origem) { Falhar "migracao_origem.txt tem '$texto', esperado '$origem'" }
Aviso "migracao_origem.txt com o caminho acentuado: $texto"

# 4. o app aberto pelo [Run] migra e grava o marcador
$marcador = Join-Path $suporte 'dados\.migrado_1_12.json'
$limite = (Get-Date).AddSeconds(60)
while (-not (Test-Path $marcador) -and (Get-Date) -lt $limite) { Start-Sleep -Milliseconds 500 }
if (-not (Test-Path $marcador)) {
  if (-not (Get-Process calculadoradarf -ErrorAction SilentlyContinue)) { Falhar 'o app não está rodando e o marcador não foi gravado' }
  Falhar 'marcador .migrado_1_12.json não apareceu em 60 s'
}
Aviso 'app abriu no runner e gravou o marcador da migração'
foreach ($rel in '2026-10.json', 'logos\X.png') {
  if (-not (Test-Path (Join-Path $suporte "dados\$rel"))) { Falhar "$rel não copiado para o destino" }
}
$m = Get-Content $marcador -Raw -Encoding UTF8 | ConvertFrom-Json
if (@($m.divergentes).Count -ne 0) { Falhar "marcador com divergências: $(@($m.divergentes) -join ', ')" }
Aviso "arquivos copiados (copiados=$($m.copiados)) e marcador sem divergências"
foreach ($f in $hashesOrigem.Keys) {
  if (-not (Test-Path $f) -or (Get-FileHash $f).Hash -ne $hashesOrigem[$f]) { Falhar "origem alterada: $f" }
}
if (@(Get-ChildItem $origem -Recurse -File).Count -ne $hashesOrigem.Count) { Falhar 'origem ganhou ou perdeu arquivos' }
Aviso 'pasta dados\ antiga intacta'
# 4a. migração 2.1-custo-medio: backup pre-2.4.0-* com os mesmos arquivos e id no config.json
$cfgDestino = Join-Path $suporte 'dados\config.json'
$limite = (Get-Date).AddSeconds(90)
$migrou = $false
do {
  if (Test-Path $cfgDestino) {
    try { $migrou = @((Get-Content $cfgDestino -Raw -Encoding UTF8 | ConvertFrom-Json).migracoes) -contains '2.1-custo-medio' } catch { $migrou = $false }
  }
  if (-not $migrou) { Start-Sleep -Milliseconds 500 }
} while (-not $migrou -and (Get-Date) -lt $limite)
if (-not $migrou) { Falhar 'config.json do destino sem 2.1-custo-medio em migracoes (90 s)' }
$backups = @(Get-ChildItem (Join-Path $suporte 'dados\backup') -Directory -Filter 'pre-2.4.0-*' -ErrorAction SilentlyContinue)
if ($backups.Count -ne 1) { Falhar "esperada 1 pasta backup\pre-2.4.0-*, achadas $($backups.Count)" }
$jsonOrigem = @(Get-ChildItem $origem -File -Filter '*.json')
$jsonBackup = @(Get-ChildItem $backups[0].FullName -File)
if ($jsonBackup.Count -ne $jsonOrigem.Count) { Falhar "backup tem $($jsonBackup.Count) arquivos, esperado $($jsonOrigem.Count)" }
foreach ($f in $jsonOrigem) {
  $b = Join-Path $backups[0].FullName $f.Name
  if (-not (Test-Path $b) -or (Get-FileHash $b).Hash -ne $hashesOrigem[$f.FullName]) { Falhar "backup diferente da origem: $($f.Name)" }
}
Aviso "migração 2.1-custo-medio registrada e backup $($backups[0].Name) com os mesmos arquivos"
# 4b. atualização silenciosa com o app aberto: CloseApplications fecha, o [Run] reabre
$antes = @(Get-Process calculadoradarf -ErrorAction SilentlyContinue)
if ($antes.Count -eq 0) { Falhar 'app não está rodando antes da atualização' }
$idsAntes = @($antes | ForEach-Object Id)
$hashConfig = (Get-FileHash (Join-Path $suporte 'dados\config.json')).Hash
$p = Start-Process -FilePath (Join-Path $origemPai 'CalculadoraDARF.exe') `
  -ArgumentList '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART' -PassThru
if (-not $p.WaitForExit(180000)) { Falhar 'atualização não terminou em 180 s' }
if ($p.ExitCode -ne 0) { Falhar "atualização saiu com código $($p.ExitCode)" }
$limite = (Get-Date).AddSeconds(60)
do {
  Start-Sleep -Milliseconds 500
  $novos = @(Get-Process calculadoradarf -ErrorAction SilentlyContinue | Where-Object { $idsAntes -notcontains $_.Id })
} while ($novos.Count -eq 0 -and (Get-Date) -lt $limite)
if ($novos.Count -eq 0) { Falhar 'o app não foi reaberto pelo [Run] depois da atualização' }
if (@(Get-Process calculadoradarf -ErrorAction SilentlyContinue | Where-Object { $idsAntes -contains $_.Id }).Count -ne 0) { Falhar 'o app antigo não foi fechado pela atualização' }
if (-not (Test-Path $marcador) -or (Get-FileHash (Join-Path $suporte 'dados\config.json')).Hash -ne $hashConfig) { Falhar 'dados alterados pela atualização' }
Aviso 'atualização silenciosa: código 0, app fechado e reaberto, dados intactos'
Get-Process calculadoradarf -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 2

# 4c. instalador mais antigo que o instalado não rebaixa
$chave = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\{ABE8CE4E-E03F-4D9C-8B54-DA1CA348A2DD}_is1'
$versaoReal = (Get-ItemProperty $chave).DisplayVersion
$hashExe = (Get-FileHash $exeInstalado).Hash
Set-ItemProperty $chave -Name DisplayVersion -Value '99.0.0'
try {
  $p = Start-Process -FilePath (Join-Path $origemPai 'CalculadoraDARF.exe') `
    -ArgumentList '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART' -PassThru
  if (-not $p.WaitForExit(180000)) { Falhar 'instalador (rebaixamento) não terminou em 180 s' }
  Aviso "instalador com versão menor que a instalada saiu com código $($p.ExitCode)"
  if (-not (Test-Path $exeInstalado) -or (Get-FileHash $exeInstalado).Hash -ne $hashExe) { Falhar 'o exe instalado mudou no rebaixamento' }
  if ((Get-ItemProperty $chave).DisplayVersion -ne '99.0.0') { Falhar 'o instalador regravou a versão no rebaixamento' }
} finally {
  Set-ItemProperty $chave -Name DisplayVersion -Value $versaoReal
}
Aviso 'rebaixamento recusado: exe instalado inalterado'
Start-Sleep -Seconds 2
Get-Process calculadoradarf -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 2

# 5. desinstalação (o desinstalador se copia e o processo original sai logo: espera pelo exe sumir)
$unins = Join-Path $pastaInstalada 'unins000.exe'
if (-not (Test-Path $unins)) { Falhar 'unins000.exe ausente' }
Start-Process -FilePath $unins -ArgumentList '/VERYSILENT' | Out-Null
$limite = (Get-Date).AddSeconds(60)
while ((Test-Path $exeInstalado) -and (Get-Date) -lt $limite) { Start-Sleep -Milliseconds 500 }
if (Test-Path $exeInstalado) { Falhar 'exe ainda existe depois da desinstalação' }
if (-not (Test-Path $marcador)) { Falhar 'a desinstalação apagou a pasta de dados nova' }
foreach ($f in $hashesOrigem.Keys) {
  if (-not (Test-Path $f)) { Falhar "a desinstalação mexeu na origem: $f" }
}
Aviso 'desinstalação removeu o exe e manteve os dados (nova e antiga)'
