; ClawFactory Secure Setup - Inno Setup 6 script
; Builds a hardened OpenClaw Skills Factory on Windows 11.
; Compile with: "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" ClawFactory-Secure-Setup.iss

#define MyAppName      "ClawFactory Secure Setup"
#define MyAppVersion   "1.0.35"
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
Source: "resources\uninstall.ps1";           DestDir: "{app}\resources";  Flags: ignoreversion
Source: "resources\wsl-keepalive.vbs";       DestDir: "{app}\resources";  Flags: ignoreversion
Source: "smoke-test.ps1";                    DestDir: "{app}\resources";  Flags: ignoreversion
Source: "resources\logo.png";                DestDir: "{app}\resources";  Flags: ignoreversion
Source: "resources\logo.README.txt";         DestDir: "{app}\resources";  Flags: ignoreversion
Source: "resources\lobster.ico";             DestDir: "{app}\resources";  Flags: ignoreversion
; Bundled Ubuntu rootfs for offline `wsl --import` (~341 MB pre-compression;
; sourced separately at build time, gitignored). Extracts to {tmp} so it's
; not duplicated into the install dir; `deleteafterinstall` purges it after
; setup.ps1 finishes. setup.ps1 receives the path via -BundledRootfsDir.
Source: "resources\ubuntu-rootfs.tar.gz";    DestDir: "{tmp}";            Flags: deleteafterinstall
Source: "resources\ClawChat.exe";            DestDir: "{app}";            Flags: ignoreversion
Source: "resources\openclaw-install.sh";     DestDir: "{app}\resources";  Flags: ignoreversion

[Run]
; [R5] No API key on the command line - setup.ps1 reads from Windows Credential Manager.
; {srcexe} is passed so setup.ps1 can register a RunOnce that relaunches this
; same .exe with /SILENT /resume after a WSL2-install reboot. {code:GetResumeFlag}
; appends ' -Resume' iff the wizard was relaunched with /resume.
Filename: "powershell.exe"; \
  Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\setup.ps1"" -AcknowledgedOpenClawUrl -Provider {code:GetProviderLabel} -SourceExe ""{srcexe}"" -BundledRootfsDir ""{tmp}""{code:GetResumeFlag}{code:GetSilentFlag}"; \
  WorkingDir: "{app}"; \
  StatusMsg: "{code:GetStatusMsg}"; \
  Flags: waituntilterminated

; v1.0.34: the uninstaller is invoked from CurUninstallStepChanged(usUninstall)
; in [Code], NOT from [UninstallRun]. Inno expands [UninstallRun] Parameters
; constants at INSTALL time (when writing the uninstall log), so the prior
; {code:GetUninstallFlags} ran during Setup and its UninstallSilent call aborted
; the install ("Cannot call UninstallSilent function during Setup"). See the
; CurUninstallStepChanged procedure at the bottom of [Code].

[Icons]
Name: "{commondesktop}\ClawFactory"; \
  Filename: "{app}\ClawChat.exe"; \
  WorkingDir: "{app}"; \
  IconFilename: "{app}\resources\lobster.ico"; \
  Comment: "Open ClawFactory"
Name: "{group}\ClawChat"; \
  Filename: "{app}\ClawChat.exe"; \
  WorkingDir: "{app}"; \
  IconFilename: "{app}\resources\lobster.ico"; \
  Comment: "Open ClawChat desktop window"
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
const
  LICENSE_API_URL = 'https://api.clawfactory.app/activate';
  LICENSE_REG_KEY = 'SOFTWARE\ClawFactory';
  LICENSE_REG_NAME = 'LicenseKey';

var
  WelcomePage:    TOutputMsgWizardPage;
  LicensePage:    TInputQueryWizardPage;
  ProviderPage:   TInputOptionWizardPage;
  ApiKeyPage:     TInputQueryWizardPage;
  ApiKeyLaterChk: TNewCheckBox;
  GetKeyButton:   TNewButton;
  BuyButton:      TNewButton;
  AckPage:        TInputOptionWizardPage;
  IsResumeRun:    Boolean;
  ResumeProvider: string;
  ValidatedLicenseKey: string;  { populated after successful /activate response }

function ResumeFlagPath: string;
begin
  Result := ExpandConstant('{commonappdata}\ClawFactory\resume-after-restart.flag');
end;

function HasCmdLineSwitch(const SwitchName: string): Boolean;
var
  i: Integer;
begin
  Result := False;
  for i := 1 to ParamCount do
    if CompareText(ParamStr(i), SwitchName) = 0 then
    begin
      Result := True;
      exit;
    end;
end;

{ Naive scan for `"provider": "<value>"` in the JSON resume flag. We can't
  pull a JSON parser into Inno's [Code]; the flag is written by setup.ps1
  with a known shape so a scan is safe enough. Inno Pascal lacks PosEx so
  we repeatedly slice off the head of the string. }
function ReadResumeProvider: string;
var
  Content: AnsiString;
  Tail: string;
  P, Q: Integer;
begin
  Result := 'grok';
  if not LoadStringFromFile(ResumeFlagPath, Content) then exit;
  Tail := string(Content);
  P := Pos('"provider"', Tail);
  if P = 0 then exit;
  Tail := Copy(Tail, P + Length('"provider"'), MaxInt);
  P := Pos(':', Tail);
  if P = 0 then exit;
  Tail := Copy(Tail, P + 1, MaxInt);
  P := Pos('"', Tail);
  if P = 0 then exit;
  Tail := Copy(Tail, P + 1, MaxInt);
  Q := Pos('"', Tail);
  if Q = 0 then exit;
  Result := Copy(Tail, 1, Q - 1);
end;

function GetProviderLabel(Param: string): string;
begin
  if IsResumeRun then
  begin
    Result := ResumeProvider;
    exit;
  end;
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

function GetResumeFlag(Param: string): string;
begin
  if IsResumeRun then
    Result := ' -Resume'
  else
    Result := '';
end;

{ v1.0.12: propagate /SILENT to setup.ps1 so its Confirm-Or-Default
  helper can refuse interactive primitives instead of hanging. Without
  this, /SILENT only suppresses the Inno wizard - setup.ps1 has no idea
  it's running unattended and Read-Host calls block forever. }
function GetSilentFlag(Param: string): string;
begin
  if WizardSilent() then
    Result := ' -Silent'
  else
    Result := '';
end;

function GetStatusMsg(Param: string): string;
begin
  if IsResumeRun then
    Result := 'Resuming installation after restart...'
  else
    Result := 'Building your hardened OpenClaw Skills Factory (10-20 minutes)...';
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

function ProviderApiKeyUrl: string;
begin
  case ProviderPage.SelectedValueIndex of
    0: Result := 'https://console.x.ai/';
    1: Result := 'https://platform.openai.com/api-keys';
    2: Result := 'https://console.anthropic.com/settings/keys';
    3: Result := 'https://aistudio.google.com/app/apikey';
  else
    Result := '';
  end;
end;

function ProviderShortName: string;
begin
  case ProviderPage.SelectedValueIndex of
    0: Result := 'Grok';
    1: Result := 'OpenAI';
    2: Result := 'Anthropic';
    3: Result := 'Gemini';
  else
    Result := '';
  end;
end;

procedure GetKeyButtonClick(Sender: TObject);
var
  URL: string;
  ResultCode: Integer;
begin
  URL := ProviderApiKeyUrl;
  if URL = '' then exit;
  ShellExec('open', URL, '', '', SW_SHOWNORMAL, ewNoWait, ResultCode);
end;

procedure BuyButtonClick(Sender: TObject);
var
  ResultCode: Integer;
begin
  ShellExec('open', 'https://clawfactory.app', '', '', SW_SHOWNORMAL, ewNoWait, ResultCode);
end;

{ v1.0.30: aggressively strip everything except A-Z, 0-9, and dashes from a
  user-typed license key. Prevents JSON injection in the WinHTTP POST body
  (Pascal has no native JSON escaper) and catches transcription typos. }
function SanitizeLicenseKey(Raw: string): string;
var
  i: Integer;
  c: Char;
begin
  Result := '';
  Raw := Uppercase(Trim(Raw));
  for i := 1 to Length(Raw) do
  begin
    c := Raw[i];
    if ((c >= 'A') and (c <= 'Z')) or
       ((c >= '0') and (c <= '9')) or
       (c = '-') then
      Result := Result + c;
  end;
end;

{ v1.0.30: machine identifier for license activation. Uses Windows'
  per-install MachineGuid (stable, unique, persists across reboots). This is
  the same UUID that Win32 generates at OS install. SYSTEM has read access
  on every Win10/11. Falls back to empty string if the key is missing - the
  server rejects empty machine IDs and the activation fails cleanly. }
function GetStableMachineId: string;
var
  Guid: string;
begin
  Result := '';
  if RegQueryStringValue(HKEY_LOCAL_MACHINE,
                          'SOFTWARE\Microsoft\Cryptography',
                          'MachineGuid', Guid) then
    Result := Guid;
end;

{ v1.0.30: POST (key, machine_id, product) to the license API and return
  True iff the response indicates a valid activation.

  The key is sanitized to [A-Z0-9-] before being inlined into JSON. The
  machine_id comes from MachineGuid (always a UUID, no escaping needed).
  Network errors / timeouts / non-200 responses all fail closed.

  10-second timeout (connect + send + receive). Don't want to make a user
  wait through a full TCP retry on a flaky network. }
function ValidateLicenseKey(Key: string): Boolean;
var
  WinHTTP: Variant;
  Body, Response, SafeKey, MachineId: string;
begin
  Result := False;
  SafeKey := SanitizeLicenseKey(Key);
  if Length(SafeKey) < 5 then exit;

  MachineId := GetStableMachineId;
  if MachineId = '' then exit;

  Body := '{"key":"' + SafeKey + '","machine_id":"' + MachineId +
          '","product":"clawfactory"}';

  try
    WinHTTP := CreateOleObject('WinHttp.WinHttpRequest.5.1');
    WinHTTP.Open('POST', LICENSE_API_URL, False);
    WinHTTP.SetRequestHeader('Content-Type', 'application/json');
    { Timeouts: resolve, connect, send, receive - all 10s }
    WinHTTP.SetTimeouts(10000, 10000, 10000, 10000);
    WinHTTP.Send(Body);

    if WinHTTP.Status = 200 then
    begin
      Response := WinHTTP.ResponseText;
      Result := (Pos('"valid":true', Response) > 0) or
                (Pos('"valid": true', Response) > 0);
      if Result then ValidatedLicenseKey := SafeKey;
    end;
  except
    Result := False;
  end;
end;

{ v1.0.30: read previously-validated license key from HKLM. Used by /resume
  reruns and by post-install for re-verify on launch. Empty string if not
  present. }
function ReadStoredLicenseKey: string;
var
  Stored: string;
begin
  Result := '';
  if RegQueryStringValue(HKEY_LOCAL_MACHINE, LICENSE_REG_KEY,
                          LICENSE_REG_NAME, Stored) then
    Result := Stored;
end;

{ v1.0.26: read a `/SWITCH=value` command-line argument for headless validation.
  Used only inside a WizardSilent() gate, so interactive installs are unaffected. }
function GetCmdLineValue(const SwitchName: string): string;
var
  i: Integer;
  s: string;
begin
  Result := '';
  for i := 1 to ParamCount do
  begin
    s := ParamStr(i);
    if (Length(s) > Length(SwitchName)) and
       (CompareText(Copy(s, 1, Length(SwitchName)), SwitchName) = 0) then
    begin
      Result := Copy(s, Length(SwitchName) + 1, MaxInt);
      Exit;
    end;
  end;
end;

procedure InitializeWizard;
begin
  { Detect /resume early so wizard pages know whether to skip. The
    RunOnce key registered by setup.ps1 relaunches this .exe with
    /SILENT /resume after a WSL-install reboot. }
  IsResumeRun := HasCmdLineSwitch('/resume');
  if IsResumeRun then
    ResumeProvider := ReadResumeProvider;

  { --- Page 1: Welcome + warning --- }
  WelcomePage := CreateOutputMsgPage(wpWelcome,
    'Hardened OpenClaw Skills Factory',
    'This installer builds a sandboxed environment for AI agents.',
    'ClawFactory Secure Setup configures WSL2, Docker, and OpenClaw with strict' + #13#10 +
    'security guardrails:' + #13#10 + #13#10 +
    '  - Four agents run in Docker sandbox (network=none, sandbox=all).' + #13#10 +
    '  - OpenClaw gateway binds to 127.0.0.1 only.' + #13#10 +
    '  - Tool allowlist blocks shell/sudo/rm/system.run/browser.' + #13#10 +
    '  - WSL automount is disabled (no access to your Windows files).' + #13#10 +
    '  - All agents require explicit human "GO" for any risky action.' + #13#10 + #13#10 +
    'WARNING: AI agents will execute code inside these containers.' + #13#10 +
    'You must personally review every skill before publishing.' + #13#10 +
    'Install takes 10-20 minutes and needs admin rights + internet.');

  { --- Page 2: License key --- }
  { v1.0.30: License gate. ValidateLicenseKey runs on Next click and calls
    the activation API. Skipped under /resume (key already in HKLM) and
    /SILENT (validated against /LICENSE=<key> command-line arg in this
    same procedure below, before any wizard pages are shown to the user). }
  LicensePage := CreateInputQueryPage(WelcomePage.ID,
    'License Key',
    'Enter your ClawFactory license key.',
    'Find your key in the purchase email from licenses@clawfactory.app.' + #13#10 +
    'Format: CF-XXXX-XXXX-XXXX-XXXX. Don''t have a key yet?' + #13#10 +
    'Purchase at clawfactory.app.');
  LicensePage.Add('License key:', False);

  BuyButton := TNewButton.Create(LicensePage);
  BuyButton.Parent := LicensePage.Surface;
  BuyButton.Top    := LicensePage.Edits[0].Top + LicensePage.Edits[0].Height + ScaleY(12);
  BuyButton.Left   := LicensePage.Edits[0].Left;
  BuyButton.Width  := ScaleX(220);
  BuyButton.Height := ScaleY(24);
  BuyButton.Caption := 'Buy a license at clawfactory.app';
  BuyButton.OnClick := @BuyButtonClick;

  { --- Page 3: Provider selection (radio) --- }
  ProviderPage := CreateInputOptionPage(LicensePage.ID,
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

  { v1.0.26: silent-mode /PROVIDER=<name> override. Lets `az vm run-command` headless
    validation pick a non-default provider. ShouldSkipPage already hides the radio
    page on silent runs, so SelectedValueIndex is the only state the rest of the
    install reads. Interactive runs ignore this entirely.

    v1.0.30: also validate /LICENSE=<key> here. Silent installs must pass a
    valid license up front - any failure Aborts the wizard with a clear log
    line. /resume reruns trust the HKLM-stored key from the first cycle. }
  if WizardSilent() then
  begin
    case LowerCase(GetCmdLineValue('/PROVIDER=')) of
      'grok':   ProviderPage.SelectedValueIndex := 0;
      'openai': ProviderPage.SelectedValueIndex := 1;
      'claude': ProviderPage.SelectedValueIndex := 2;
      'gemini': ProviderPage.SelectedValueIndex := 3;
      'ollama': ProviderPage.SelectedValueIndex := 4;
      'later':  ProviderPage.SelectedValueIndex := 5;
    end;

    if not IsResumeRun then
    begin
      if not ValidateLicenseKey(GetCmdLineValue('/LICENSE=')) then
      begin
        Log('License activation failed under /SILENT - missing or invalid /LICENSE= argument.');
        Abort;
      end;
      RegWriteStringValue(HKEY_LOCAL_MACHINE, LICENSE_REG_KEY,
                          LICENSE_REG_NAME, ValidatedLicenseKey);
    end;
  end;

  { --- Page 3: API key (skipped for Ollama / Later via ShouldSkipPage) [R5] --- }
  ApiKeyPage := CreateInputQueryPage(ProviderPage.ID,
    'API Key',
    'Paste the API key for your selected provider.',
    'The key is stored in Windows Credential Manager (DPAPI-protected, tied to your' + #13#10 +
    'Windows user). It is NEVER written to a file inside WSL.' + #13#10 + #13#10 +
    'Rotate later from a terminal with cmdkey (see README).');
  ApiKeyPage.Add('API key:', True);

  { "Get your <Provider> API key" button - opens the provider's key page in
    the default browser. Caption + visibility are updated in CurPageChanged
    based on the provider selected on the previous page. Hidden for Ollama
    (no key needed) and "configure later". }
  GetKeyButton := TNewButton.Create(ApiKeyPage);
  GetKeyButton.Parent := ApiKeyPage.Surface;
  GetKeyButton.Top    := ApiKeyPage.Edits[0].Top + ApiKeyPage.Edits[0].Height + ScaleY(12);
  GetKeyButton.Left   := ApiKeyPage.Edits[0].Left;
  GetKeyButton.Width  := ScaleX(220);
  GetKeyButton.Height := ScaleY(24);
  GetKeyButton.Caption := 'Get your API key →';
  GetKeyButton.OnClick := @GetKeyButtonClick;

  ApiKeyLaterChk := TNewCheckBox.Create(ApiKeyPage);
  ApiKeyLaterChk.Parent  := ApiKeyPage.Surface;
  ApiKeyLaterChk.Top     := GetKeyButton.Top + GetKeyButton.Height + ScaleY(12);
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

procedure CurPageChanged(CurPageID: Integer);
var
  ShortName: string;
begin
  { When the API key page becomes active, set the "Get your API key" button
    label and visibility based on the provider chosen on the previous page. }
  if CurPageID = ApiKeyPage.ID then
  begin
    ShortName := ProviderShortName;
    if ShortName = '' then
    begin
      GetKeyButton.Visible := False;
    end
    else
    begin
      GetKeyButton.Caption := 'Get your ' + ShortName + ' API key →';
      GetKeyButton.Visible := True;
    end;
  end;
end;

function ShouldSkipPage(PageID: Integer): Boolean;
begin
  Result := False;
  { On a /resume relaunch the user has already chosen a provider, supplied
    the API key (DPAPI-stored, survives reboot), entered + validated their
    license key (stored in HKLM), and acknowledged the security notice.
    Skip all those pages so the wizard goes straight to the install step. }
  if IsResumeRun then
  begin
    if (PageID = WelcomePage.ID) or (PageID = LicensePage.ID) or
       (PageID = ProviderPage.ID) or (PageID = ApiKeyPage.ID) or
       (PageID = AckPage.ID) then
    begin
      Result := True;
      exit;
    end;
  end;
  if WizardSilent() then
  begin
    { LicensePage is also skipped under /SILENT - the /LICENSE=<key> CLI
      arg was validated up front in InitializeWizard. If validation failed
      InitializeWizard called Abort, so reaching here means license is OK. }
    if (PageID = LicensePage.ID) or (PageID = ProviderPage.ID) or
       (PageID = ApiKeyPage.ID) or (PageID = AckPage.ID) then
    begin
      Result := True;
      exit;
    end;
  end;
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

  { v1.0.30: license gate. Interactive validation calls the activation API
    and persists the validated key to HKLM on success. /resume and /SILENT
    paths skip this page (see ShouldSkipPage). }
  if CurPageID = LicensePage.ID then
  begin
    Key := Trim(LicensePage.Values[0]);
    if Key = '' then
    begin
      MsgBox('Please enter your license key. Purchase one at clawfactory.app if you don''t have a key yet.',
             mbError, MB_OK);
      Result := False;
      exit;
    end;
    if not ValidateLicenseKey(Key) then
    begin
      MsgBox('License activation failed.' + #13#10 + #13#10 +
             'This usually means:' + #13#10 +
             '  - The key was mistyped (check for 0/O, 1/I)' + #13#10 +
             '  - The key is already activated on 2 other machines' + #13#10 +
             '  - The license server is unreachable (check internet)' + #13#10 + #13#10 +
             'Visit clawfactory.app/deactivate to free a machine slot,' + #13#10 +
             'or contact support@clawfactory.app for help.',
             mbError, MB_OK);
      Result := False;
      exit;
    end;
    RegWriteStringValue(HKEY_LOCAL_MACHINE, LICENSE_REG_KEY,
                        LICENSE_REG_NAME, ValidatedLicenseKey);
    exit;
  end;

  if CurPageID = ApiKeyPage.ID then
  begin
    Key := Trim(ApiKeyPage.Values[0]);
    if (not WizardSilent()) and (Key = '') and (not ApiKeyLaterChk.Checked) then
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
    if (not WizardSilent()) and (not AckPage.Values[0]) then
    begin
      MsgBox('You must acknowledge the security notice before installation can continue.',
             mbError, MB_OK);
      Result := False;
    end;
  end;
end;

// v1.0.34: invoke uninstall.ps1 at UNINSTALL time. The v1.0.33 approach used an
// UninstallRun entry whose Parameters constant Inno expands at INSTALL time (when
// it records the uninstall log) - so the flag-builder ran during Setup and its
// UninstallSilent call raised "Internal error: Cannot call UninstallSilent function
// during Setup", aborting the install with a rollback. usUninstall is the only place
// where BOTH UninstallSilent AND the uninstaller's own REMOVEALL ParamStr are valid,
// and it fires BEFORE Inno removes files, so the app's uninstall.ps1 still exists.
// (Comment uses // lines on purpose: Inno brace-comments do not nest, and code/brace
//  tokens in the prose would otherwise close the comment early.)
procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  Flags, AppDir: string;
  i, ResultCode: Integer;
begin
  if CurUninstallStep = usUninstall then
  begin
    Flags := '';
    if UninstallSilent then
      Flags := Flags + ' -Silent';
    for i := 1 to ParamCount do
    begin
      if CompareText(ParamStr(i), '/REMOVEALL=1') = 0 then
        Flags := Flags + ' -RemoveAll'
      else if CompareText(ParamStr(i), '/REMOVEALL=0') = 0 then
        Flags := Flags + ' -KeepLinuxEnvironment';
    end;
    AppDir := ExpandConstant('{app}');
    Exec('powershell.exe',
      '-NoProfile -ExecutionPolicy Bypass -File "' + AppDir + '\resources\uninstall.ps1"' + Flags,
      '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  end;
end;
