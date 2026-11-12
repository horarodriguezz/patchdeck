; Inno Setup script for Patchdeck (per-user install, no admin rights needed).
; Built by CI:  iscc /DAppVersion=0.2.0 /DSourceDir=..\..\build\windows\x64\runner\Release windows\installer\patchdeck.iss

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#ifndef SourceDir
  #define SourceDir "..\..\build\windows\x64\runner\Release"
#endif

[Setup]
AppId={{6C1C3A52-8E0B-4E4B-9F61-5B1F8A2D7C90}
AppName=Patchdeck
AppVersion={#AppVersion}
AppPublisher=Patchdeck
AppPublisherURL=https://github.com/horarodriguezz/patchdeck
DefaultDirName={localappdata}\Programs\Patchdeck
DefaultGroupName=Patchdeck
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
OutputDir=..\..\build\installer
OutputBaseFilename=PatchdeckSetup-{#AppVersion}
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\patchdeck.exe
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

[Languages]
Name: "spanish"; MessagesFile: "compiler:Languages\Spanish.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Patchdeck"; Filename: "{app}\patchdeck.exe"
Name: "{autodesktop}\Patchdeck"; Filename: "{app}\patchdeck.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\patchdeck.exe"; Description: "{cm:LaunchProgram,Patchdeck}"; Flags: nowait postinstall skipifsilent
