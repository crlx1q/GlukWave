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
DisableProgramGroupPage=yes
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
VersionInfoVersion=1.0.0.3

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

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"
Name: "startup"; Description: "{cm:Autostart}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#BundleDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\GlukWave"; Filename: "{app}\glukwave.exe"; WorkingDir: "{app}"
Name: "{userdesktop}\GlukWave"; Filename: "{app}\glukwave.exe"; WorkingDir: "{app}"; Tasks: desktopicon

[Registry]
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "GlukWave"; ValueData: """{app}\glukwave.exe"" --start-minimized"; Flags: uninsdeletevalue; Tasks: startup
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueName: "GlukWave"; Flags: deletevalue; Tasks: not startup

[Run]
Filename: "{app}\glukwave.exe"; Description: "{cm:LaunchProgram,GlukWave}"; Flags: nowait postinstall skipifsilent
