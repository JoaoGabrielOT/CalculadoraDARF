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

// Atalho antigo (a 1.12 apontando para o instalador ao lado de dados\): se a
// migração já foi feita e esta versão já está instalada, só abre o app.
function InitializeSetup: Boolean;
var
  Instalada, Pasta, Atual: String;
  VInstalada, VAtual: Int64;
  Codigo: Integer;
begin
  Result := True;
  if WizardSilent then Exit;
  if not DirExists(ExpandConstant('{src}\dados')) then Exit;
  if not FileExists(PastaSuporte + '\dados\.migrado_1_12.json') then Exit;
  if not RegQueryStringValue(HKCU, ChaveDesinstalar, 'DisplayVersion', Instalada) then Exit;
  if not RegQueryStringValue(HKCU, ChaveDesinstalar, 'InstallLocation', Pasta) then Exit;
  Atual := '{#Versao}';
  if not StrToVersion(Instalada, VInstalada) then Exit;
  if not StrToVersion(Atual, VAtual) then Exit;
  if ComparePackedVersion(VInstalada, VAtual) < 0 then Exit;
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
