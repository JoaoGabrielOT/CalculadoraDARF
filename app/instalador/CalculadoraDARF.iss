; Instalador do Calculadora DARF (Inno Setup 6). O AppId não muda nunca.
#ifndef Versao
  #define Versao "0.0.0"
#endif
[Setup]
AppId={{ABE8CE4E-E03F-4D9C-8B54-DA1CA348A2DD}
AppName=Calculadora DARF
AppVersion={#Versao}
VersionInfoVersion={#Versao}
AppPublisher=JoaoGabrielOT
DefaultDirName={localappdata}\Programs\Calculadora DARF
DefaultGroupName=Calculadora DARF
DisableProgramGroupPage=yes
DisableDirPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=..\build\instalador
OutputBaseFilename=CalculadoraDARF
SetupIconFile=..\..\assets\icone.ico
UninstallDisplayIcon={app}\calculadoradarf.exe
UninstallDisplayName=Calculadora DARF
CloseApplications=force
RestartApplications=no
WizardStyle=modern
Compression=lzma2/max
SolidCompression=yes
ShowLanguageDialog=no

[Languages]
Name: "pt"; MessagesFile: "compiler:Languages\BrazilianPortuguese.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; Flags: unchecked

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{userprograms}\Calculadora DARF"; Filename: "{app}\calculadoradarf.exe"; AppUserModelID: "JoaoGabrielOT.CalculadoraDARF"
Name: "{userdesktop}\Calculadora DARF"; Filename: "{app}\calculadoradarf.exe"; Tasks: desktopicon

[Run]
; sem skipifsilent: no modo silencioso (atualização pelo app) o app reabre sozinho
Filename: "{app}\calculadoradarf.exe"; Description: "{cm:LaunchProgram,Calculadora DARF}"; Flags: nowait postinstall

; Desinstalar não apaga %APPDATA%\JoaoGabrielOT\Calculadora DARF (sem [UninstallDelete]).

[Code]
const
  ChaveDesinstalar = 'Software\Microsoft\Windows\CurrentVersion\Uninstall\{ABE8CE4E-E03F-4D9C-8B54-DA1CA348A2DD}_is1';

function PastaSuporte: String;
begin
  Result := ExpandConstant('{userappdata}\JoaoGabrielOT\Calculadora DARF');
end;

// Nunca rebaixa: se a versão instalada é MAIOR que a deste instalador (instalador
// velho baixado de novo, migração que falhou na primeira vez), só abre o app
// instalado e sai sem instalar, silencioso ou não, com ou sem {src}\dados.
// Versão IGUAL, só no modo interativo (atalho antigo da 1.12 apontando para o
// instalador ao lado de dados\): se a migração já foi feita, também só abre o app.
// Atualização silenciosa pelo app (versão menor ou igual) segue instalando.
function InitializeSetup: Boolean;
var
  Instalada, Pasta, Atual: String;
  VInstalada, VAtual: Int64;
  Comparacao, Codigo: Integer;
  AtalhoAntigo: Boolean;
begin
  Result := True;
  if not RegQueryStringValue(HKCU, ChaveDesinstalar, 'DisplayVersion', Instalada) then Exit;
  if not RegQueryStringValue(HKCU, ChaveDesinstalar, 'InstallLocation', Pasta) then Exit;
  Atual := '{#Versao}';
  if not StrToVersion(Instalada, VInstalada) then Exit;
  if not StrToVersion(Atual, VAtual) then Exit;
  Comparacao := ComparePackedVersion(VInstalada, VAtual);
  if Comparacao < 0 then Exit;
  AtalhoAntigo := (not WizardSilent)
    and DirExists(ExpandConstant('{src}\dados'))
    and FileExists(PastaSuporte + '\dados\.migrado_1_12.json');
  if (Comparacao = 0) and (not AtalhoAntigo) then Exit;
  Pasta := AddBackslash(Pasta) + 'calculadoradarf.exe';
  if not FileExists(Pasta) then Exit;
  ShellExec('open', Pasta, '', '', SW_SHOWNORMAL, ewNoWait, Codigo);
  Result := False;
end;

// O app faz a cópia na primeira partida; aqui só se aponta a pasta de origem.
procedure CurStepChanged(CurStep: TSetupStep);
var
  Linhas: TArrayOfString;
begin
  if CurStep <> ssPostInstall then Exit;
  if not DirExists(ExpandConstant('{src}\dados')) then Exit;
  ForceDirectories(PastaSuporte);
  SetArrayLength(Linhas, 1);
  Linhas[0] := ExpandConstant('{src}\dados');
  SaveStringsToUTF8File(PastaSuporte + '\migracao_origem.txt', Linhas, False);
end;
