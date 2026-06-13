[Setup]
AppId={{7F7C8B5A-11A4-40F2-88F4-0EF88F1DF83B}
AppName=Credential Broker
AppVersion=0.2.12
AppPublisher=mergi72
DefaultDirName={localappdata}\Credential Broker
DefaultGroupName=Credential Broker
DisableDirPage=yes
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=artifacts\installer
OutputBaseFilename=CredentialBrokerSetup-v0.2.12
Compression=lzma
SolidCompression=yes
WizardStyle=modern

[Files]
Source: "artifacts\broker-installer-payload\credential-broker.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "artifacts\broker-installer-payload\install-broker.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "artifacts\broker-installer-payload\uninstall-broker.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "artifacts\broker-installer-payload\start-credential-broker.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "artifacts\broker-installer-payload\stop-credential-broker.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "artifacts\broker-installer-payload\config\broker.json"; DestDir: "{app}\config"; Flags: ignoreversion

[Dirs]
Name: "{app}\config"
Name: "{app}\logs"
Name: "{userappdata}\Credential Broker\config"

[Run]
Filename: "powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\install-broker.ps1"" -InstallRoot ""{app}"""; Flags: waituntilterminated logoutput

[UninstallRun]
Filename: "powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\uninstall-broker.ps1"" -InstallRoot ""{app}"""; Flags: waituntilterminated runhidden; RunOnceId: "CredentialBrokerUninstall"
