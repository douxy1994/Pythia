#define AppName "Pythia"
#ifndef AppVersion
  #define AppVersion "1.2.2"
#endif
#define AppPublisher "douxy1994"
#define AppExeName "Pythia.exe"
#ifndef ChineseLanguageFile
  #define ChineseLanguageFile "compiler:Languages\ChineseSimplified.isl"
#endif

[Setup]
; Authenticode signing is performed by tool/build-installer.ps1 via signtool, gated on the
; PYTHIA_WIN_CERT_FILE / PYTHIA_WIN_CERT_SHA1 environment variables (no cert material in the
; repo). An equivalent ISCC SignTool directive is intentionally NOT enabled here to avoid
; double-signing: the installer + bundled Pythia.exe are both signed in the PowerShell script.
AppId={{6F96CE7A-6729-4F43-9878-FF171728A2D4}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#AppPublisher}
AppPublisherURL=https://github.com/douxy1994/Pythia
AppSupportURL=https://github.com/douxy1994/Pythia/issues
DefaultDirName={localappdata}\Programs\{#AppName}
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=..\dist
OutputBaseFilename=Pythia-{#AppVersion}-windows-x64
SetupIconFile=..\Assets\AppIcon.ico
UninstallDisplayIcon={app}\{#AppExeName}
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes
RestartApplications=no
VersionInfoVersion={#AppVersion}.0
VersionInfoCompany={#AppPublisher}
VersionInfoDescription=Pythia Windows 原生安装程序
VersionInfoProductName={#AppName}
VersionInfoProductVersion={#AppVersion}

[Languages]
Name: "chinesesimplified"; MessagesFile: "{#ChineseLanguageFile}"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "..\publish\win-x64\*"; DestDir: "{app}"; Excludes: "*.pdb,*.dbg,*.xml"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{userprograms}\Pythia"; Filename: "{app}\{#AppExeName}"; IconFilename: "{app}\{#AppExeName}"
Name: "{autodesktop}\Pythia"; Filename: "{app}\{#AppExeName}"; IconFilename: "{app}\{#AppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(AppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent

[UninstallRun]
Filename: "{sys}\reg.exe"; Parameters: "delete ""HKCU\Software\Microsoft\Windows\CurrentVersion\Run"" /v ""Pythia"" /f"; Flags: runhidden; RunOnceId: "RemoveStartup"
