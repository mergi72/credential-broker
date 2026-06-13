[Setup]
AppId={{0F8F58A5-08E6-4A95-91B6-6F0D7F85D3F2}
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
Source: "artifacts\broker-installer-payload\start-credential-broker.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "artifacts\broker-installer-payload\stop-credential-broker.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "artifacts\broker-installer-payload\config\broker.json"; DestDir: "{app}\config"; Flags: ignoreversion

[Dirs]
Name: "{app}\config"
Name: "{app}\logs"
Name: "{userappdata}\Credential Broker\config"

[Registry]
Root: HKCU; Subkey: "Environment"; ValueType: string; ValueName: "CREDENTIAL_BROKER_MACHINE_CONFIG_DIR"; ValueData: "{app}\config"; Flags: uninsdeletevalue
Root: HKCU; Subkey: "Environment"; ValueType: string; ValueName: "CREDENTIAL_BROKER_USER_CONFIG_DIR"; ValueData: "{userappdata}\Credential Broker\config"; Flags: uninsdeletevalue

[Icons]
Name: "{userstartup}\Credential Broker"; Filename: "powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""{app}\start-credential-broker.ps1"""; WorkingDir: "{app}"

[Run]
Filename: "powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""{app}\start-credential-broker.ps1"""; Flags: nowait runhidden

[UninstallRun]
Filename: "powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""{app}\stop-credential-broker.ps1"""; Flags: runhidden waituntilterminated; RunOnceId: "CredentialBrokerStop"
