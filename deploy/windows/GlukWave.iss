#ifndef BundleDir
  #error BundleDir must point to the verified Windows release bundle
#endif
#ifndef OutputDir
  #error OutputDir must point to the project outputs directory
#endif
#ifndef BuildVersion
  #define BuildVersion "1.0.0"
#endif

[Setup]
AppId={{D7E9025D-99B6-4F87-862B-7E2F3D21181B}
AppName=GlukWave
AppVersion={#BuildVersion}
AppPublisher=Gluk.tech
AppPublisherURL=https://wave.gluk.tech
AppSupportURL=https://wave.gluk.tech
AppUpdatesURL=https://wave.gluk.tech
DefaultDirName={localappdata}\Programs\GlukWave
DefaultGroupName=GlukWave
DisableProgramGroupPage=no
DisableWelcomePage=no
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0.17763
SetupIconFile={#BundleDir}\data\flutter_assets\assets\app_icon.ico
UninstallDisplayIcon={app}\glukwave.exe
OutputDir={#OutputDir}
OutputBaseFilename=GlukWave-Setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes
RestartApplications=no
SetupLogging=yes
VersionInfoVersion=1.0.0.8

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "russian"; MessagesFile: "compiler:Languages\Russian.isl"
Name: "ukrainian"; MessagesFile: "compiler:Languages\Ukrainian.isl"
Name: "german"; MessagesFile: "compiler:Languages\German.isl"
Name: "spanish"; MessagesFile: "compiler:Languages\Spanish.isl"

[CustomMessages]
english.Autostart=Start GlukWave with Windows (in the tray)
russian.Autostart=Запускать GlukWave вместе с Windows (в трее)
ukrainian.Autostart=Запускати GlukWave разом із Windows (у треї)
german.Autostart=GlukWave mit Windows starten (im Infobereich)
spanish.Autostart=Iniciar GlukWave con Windows (en la bandeja)
english.WebViewInstall=Installing the system player. An internet connection is required.
russian.WebViewInstall=Устанавливаем системный плеер. Нужно подключение к интернету.
ukrainian.WebViewInstall=Встановлюємо системний програвач. Потрібне підключення до інтернету.
german.WebViewInstall=Systemplayer wird installiert. Eine Internetverbindung ist erforderlich.
spanish.WebViewInstall=Instalando el reproductor del sistema. Se requiere conexión a internet.
english.WebViewFailed=The system player could not be installed. Check your connection and run GlukWave Setup again.
russian.WebViewFailed=Не удалось установить системный плеер. Проверь интернет и повтори установку GlukWave.
ukrainian.WebViewFailed=Не вдалося встановити системний програвач. Перевір інтернет і повтори встановлення GlukWave.
german.WebViewFailed=Der Systemplayer konnte nicht installiert werden. Verbindung prüfen und GlukWave erneut installieren.
spanish.WebViewFailed=No se pudo instalar el reproductor del sistema. Comprueba la conexión y vuelve a ejecutar el instalador.

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"
Name: "startup"; Description: "{cm:Autostart}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#BundleDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "{#WebViewBootstrapper}"; DestName: "MicrosoftEdgeWebview2Setup.exe"; Flags: dontcopy

[Icons]
Name: "{group}\GlukWave"; Filename: "{app}\glukwave.exe"; WorkingDir: "{app}"
Name: "{userdesktop}\GlukWave"; Filename: "{app}\glukwave.exe"; WorkingDir: "{app}"; Tasks: desktopicon

[Registry]
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "GlukWave"; ValueData: """{app}\glukwave.exe"" --start-minimized"; Flags: uninsdeletevalue; Tasks: startup
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueName: "GlukWave"; Flags: deletevalue; Tasks: not startup

[Run]
Filename: "{app}\glukwave.exe"; Description: "{cm:LaunchProgram,GlukWave}"; Flags: nowait postinstall skipifsilent

[Code]
function WebViewInstalled: Boolean;
var
  Version: String;
  Key: String;
begin
  Key := 'Software\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}';
  Result := (RegQueryStringValue(HKCU, Key, 'pv', Version) and (Version <> '') and (Version <> '0.0.0.0'))
    or (RegQueryStringValue(HKLM32, Key, 'pv', Version) and (Version <> '') and (Version <> '0.0.0.0'));
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  ExitCode: Integer;
begin
  Result := '';
  if not WebViewInstalled then begin
    WizardForm.StatusLabel.Caption := CustomMessage('WebViewInstall');
    ExtractTemporaryFile('MicrosoftEdgeWebview2Setup.exe');
    if not Exec(ExpandConstant('{tmp}\MicrosoftEdgeWebview2Setup.exe'), '/silent /install', '', SW_HIDE, ewWaitUntilTerminated, ExitCode) then
      Result := CustomMessage('WebViewFailed')
    else if not WebViewInstalled then
      Result := CustomMessage('WebViewFailed');
  end;
end;
