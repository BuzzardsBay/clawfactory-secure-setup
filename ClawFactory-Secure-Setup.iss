; ClawFactory Secure Setup - Inno Setup 6 script
; Builds a hardened OpenClaw Skills Factory on Windows 11.
; Compile with: "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" ClawFactory-Secure-Setup.iss

#define MyAppName      "ClawFactory Secure Setup"
#define MyAppVersion   "1.0.0"
#define MyAppPublisher "Frontier Automation Systems LLC"
#define MyAppURL       "https://openclaw.ai"

[Setup]
; [R1] Fixed AppId for stable upgrade/uninstall identity. Do not regenerate.
AppId={{8D7C4B2A-4F1E-4B5C-9D3E-CF7A6B2E1A90}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
PrivilegesRequired=admin
ArchitecturesInstallIn64BitMode=x64compatible
ArchitecturesAllowed=x64compatible
DefaultDirName={autopf}\ClawFactory
DefaultGroupName=ClawFactory
OutputBaseFilename=ClawFactory-Secure-Setup
OutputDir=Output
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
DisableProgramGroupPage=yes
DisableReadyPage=no
UninstallDisplayIcon={app}\resources\lobster.ico
; [R1] Uncomment after configuring a SignTool via Tools > Configure Sign Tools in the IDE.
; SignTool=signtool

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Files]
Source: "setup.ps1";                         DestDir: "{app}";            Flags: ignoreversion
Source: "README.md";                         DestDir: "{app}";            Flags: ignoreversion
Source: "LICENSE";                           DestDir: "{app}";            Flags: ignoreversion
Source: "resources\safety-rules.md";         DestDir: "{app}\resources";  Flags: ignoreversion
Source: "resources\orchestrator-prompt.md";  DestDir: "{app}\resources";  Flags: ignoreversion
Source: "resources\post-install.ps1";        DestDir: "{app}\resources";  Flags: ignoreversion
Source: "resources\bootstrap.ps1";           DestDir: "{app}\resources";  Flags: ignoreversion
Source: "resources\rename-agent.ps1";        DestDir: "{app}\resources";  Flags: ignoreversion
Source: "resources\launcher.ps1";            DestDir: "{app}\resources";  Flags: ignoreversion
Source: "resources\clawfactory-stop.ps1";    DestDir: "{app}\resources";  Flags: ignoreversion
Source: "resources\switch-provider.ps1";     DestDir: "{app}\resources";  Flags: ignoreversion
Source: "resources\logo.png";                DestDir: "{app}\resources";  Flags: ignoreversion
Source: "resources\logo.README.txt";         DestDir: "{app}\resources";  Flags: ignoreversion
Source: "resources\lobster.ico";             DestDir: "{app}\resources";  Flags: ignoreversion

[Run]
; [R5] No API key on the command line - setup.ps1 reads from Windows Credential Manager.
Filename: "powershell.exe"; \
  Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\setup.ps1"" -AcknowledgedOpenClawUrl -Provider {code:GetProviderLabel}"; \
  WorkingDir: "{app}"; \
  StatusMsg: "Building your hardened OpenClaw Skills Factory (10-20 minutes)..."; \
  Flags: waituntilterminated

[UninstallRun]
Filename: "powershell.exe"; \
  Parameters: "-NoProfile -ExecutionPolicy Bypass -Command ""if ((Read-Host 'Remove Ubuntu WSL distro, skills-factory workspace, and all provider credentials? [y/N]') -eq 'y') {{ wsl --unregister Ubuntu; cmdkey /delete:ClawFactory/GrokApiKey 2>$null; cmdkey /delete:ClawFactory/OpenAIApiKey 2>$null; cmdkey /delete:ClawFactory/AnthropicApiKey 2>$null; cmdkey /delete:ClawFactory/GeminiApiKey 2>$null; Remove-NetFirewallRule -DisplayName 'ClawFactory-Block-Inbound-8787' -ErrorAction SilentlyContinue }}"""; \
  RunOnceId: "ClawFactoryCleanup"; \
  Flags: runhidden

[Icons]
Name: "{commondesktop}\ClawFactory"; \
  Filename: "powershell.exe"; \
  Parameters: "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""{app}\resources\launcher.ps1"""; \
  WorkingDir: "{app}"; \
  IconFilename: "{app}\resources\lobster.ico"; \
  Comment: "Open ClawFactory"
Name: "{group}\ClawFactory Kill Switch"; \
  Filename: "powershell.exe"; \
  Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\resources\clawfactory-stop.ps1"""; \
  WorkingDir: "{app}"; \
  Comment: "Emergency stop: kills all ClawFactory agent containers"
Name: "{group}\ClawFactory Dashboard"; \
  Filename: "{sys}\cmd.exe"; \
  Parameters: "/c start http://127.0.0.1:8787"; \
  WorkingDir: "{app}"; \
  Comment: "Open ClawFactory dashboard in browser (gateway must be running)"
Name: "{group}\Rename Your Assistant"; \
  Filename: "powershell.exe"; \
  Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\resources\rename-agent.ps1"""; \
  WorkingDir: "{app}"; \
  Comment: "Rename your assistant (factory mode shows an explanation; full rename ships in the single-agent variant)"
Name: "{group}\Switch AI Provider"; \
  Filename: "powershell.exe"; \
  Parameters: "-NoProfile -ExecutionPolicy Bypass -NoExit -File ""{app}\resources\switch-provider.ps1"""; \
  WorkingDir: "{app}"; \
  Comment: "Change provider (Grok / OpenAI / Claude / Gemini / Ollama) after install"
Name: "{group}\ClawFactory README"; Filename: "{app}\README.md"
Name: "{group}\Uninstall ClawFactory"; Filename: "{uninstallexe}"

[Code]
var
  WelcomePage:    TOutputMsgWizardPage;
  ProviderPage:   TInputOptionWizardPage;
  ApiKeyPage:     TInputQueryWizardPage;
  ApiKeyLaterChk: TNewCheckBox;
  AckPage:        TInputOptionWizardPage;

function GetProviderLabel(Param: string): string;
begin
  case ProviderPage.SelectedValueIndex of
    0: Result := 'grok';
    1: Result := 'openai';
    2: Result := 'claude';
    3: Result := 'gemini';
    4: Result := 'ollama';
    5: Result := 'later';
  else
    Result := 'grok';
  end;
end;

function ProviderNeedsApiKey: Boolean;
begin
  { Grok=0, OpenAI=1, Claude=2, Gemini=3 require a key. Ollama=4 and Later=5 do not. }
  Result := (ProviderPage.SelectedValueIndex <= 3);
end;

function ProviderCredentialTarget: string;
begin
  case ProviderPage.SelectedValueIndex of
    0: Result := 'ClawFactory/GrokApiKey';
    1: Result := 'ClawFactory/OpenAIApiKey';
    2: Result := 'ClawFactory/AnthropicApiKey';
    3: Result := 'ClawFactory/GeminiApiKey';
  else
    Result := 'ClawFactory/GrokApiKey';
  end;
end;

procedure InitializeWizard;
begin
  { --- Page 1: Welcome + warning --- }
  WelcomePage := CreateOutputMsgPage(wpWelcome,
    'Hardened OpenClaw Skills Factory',
    'This installer builds a sandboxed environment for AI agents.',
    'ClawFactory Secure Setup configures WSL2, Docker, and OpenClaw with strict' + #13#10 +
    'security guardrails:' + #13#10 + #13#10 +
    '  - Five agents run in Docker sandbox (network=none, sandbox=all).' + #13#10 +
    '  - OpenClaw gateway binds to 127.0.0.1 only.' + #13#10 +
    '  - Tool allowlist blocks shell/sudo/rm/system.run/browser.' + #13#10 +
    '  - WSL automount is disabled (no access to your Windows files).' + #13#10 +
    '  - All agents require explicit human "GO" for any risky action.' + #13#10 + #13#10 +
    'WARNING: AI agents will execute code inside these containers.' + #13#10 +
    'You must personally review every skill before publishing.' + #13#10 +
    'Install takes 10-20 minutes and needs admin rights + internet.');

  { --- Page 2: Provider selection (radio) --- }
  ProviderPage := CreateInputOptionPage(WelcomePage.ID,
    'Choose your AI provider',
    'Which LLM should power your agents?',
    'You can switch providers later by re-running the installer or using the included' + #13#10 +
    'switch-provider.ps1 helper script. Ollama runs entirely on this machine - no' + #13#10 +
    'account, no API key, no cloud calls (needs ~8 GB RAM).',
    True  { radio buttons (exclusive) }, False);
  ProviderPage.Add('Grok (xAI) - default model: grok-4-1-fast');
  ProviderPage.Add('OpenAI (ChatGPT) - default model: gpt-5');
  ProviderPage.Add('Anthropic Claude - default model: claude-sonnet-4-6');
  ProviderPage.Add('Google Gemini - default model: gemini-2.5-pro');
  ProviderPage.Add('Ollama (local, free, offline-capable) - default model: llama3.1:8b');
  ProviderPage.Add('I''ll configure a provider later');
  ProviderPage.SelectedValueIndex := 0;

  { --- Page 3: API key (skipped for Ollama / Later via ShouldSkipPage) [R5] --- }
  ApiKeyPage := CreateInputQueryPage(ProviderPage.ID,
    'API Key',
    'Paste the API key for your selected provider.',
    'The key is stored in Windows Credential Manager (DPAPI-protected, tied to your' + #13#10 +
    'Windows user). It is NEVER written to a file inside WSL.' + #13#10 + #13#10 +
    'Rotate later from a terminal with cmdkey (see README).');
  ApiKeyPage.Add('API key:', True);

  ApiKeyLaterChk := TNewCheckBox.Create(ApiKeyPage);
  ApiKeyLaterChk.Parent  := ApiKeyPage.Surface;
  ApiKeyLaterChk.Top     := ApiKeyPage.Edits[0].Top + ApiKeyPage.Edits[0].Height + ScaleY(16);
  ApiKeyLaterChk.Left    := ApiKeyPage.Edits[0].Left;
  ApiKeyLaterChk.Width   := ApiKeyPage.SurfaceWidth - ApiKeyLaterChk.Left;
  ApiKeyLaterChk.Height  := ScaleY(20);
  ApiKeyLaterChk.Caption := 'I''ll add my API key later (agents will not run until I do)';

  { --- Page 4: Security acknowledgement (mandatory) --- }
  AckPage := CreateInputOptionPage(ApiKeyPage.ID,
    'Security Acknowledgement',
    'Please confirm you understand what you are about to install.',
    'Tick the box below to continue. Installation is blocked until you do.',
    False, False);
  AckPage.Add('I understand agents execute code in isolated containers and I will ' +
              'personally review every skill before publishing.');
end;

function ShouldSkipPage(PageID: Integer): Boolean;
begin
  Result := False;
  if PageID = ApiKeyPage.ID then
    Result := not ProviderNeedsApiKey;
end;

function NextButtonClick(CurPageID: Integer): Boolean;
var
  Key:        string;
  ResultCode: Integer;
  CredTarget: string;
begin
  Result := True;

  if CurPageID = ApiKeyPage.ID then
  begin
    Key := Trim(ApiKeyPage.Values[0]);
    if (Key = '') and (not ApiKeyLaterChk.Checked) then
    begin
      MsgBox('Enter your API key, or tick "I''ll add my API key later".',
             mbError, MB_OK);
      Result := False;
      exit;
    end;
    if Key <> '' then
    begin
      CredTarget := ProviderCredentialTarget;
      Exec('cmdkey.exe',
           '/generic:' + CredTarget + ' /user:clawuser /pass:' + Key,
           '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
      ApiKeyPage.Values[0] := '';
    end;
  end
  else if CurPageID = AckPage.ID then
  begin
    if not AckPage.Values[0] then
    begin
      MsgBox('You must acknowledge the security notice before installation can continue.',
             mbError, MB_OK);
      Result := False;
    end;
  end;
end;
