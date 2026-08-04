; ClawFactory Secure Setup - Inno Setup 6 script
; Builds a hardened OpenClaw Skills Factory on Windows 11.
; Compile with: "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" ClawFactory-Secure-Setup.iss

#define MyAppName      "ClawFactory Secure Setup"
#define MyAppVersion   "1.1.1"
#define MyAppPublisher "Frontier Automation Systems LLC"
#define MyAppURL       "https://openclaw.ai"
; v1.1.0 (JOB 3B): the combined installer also bundles ClawFactory Studio, whose
; signed per-user NSIS installer is embedded and run de-elevated after the core
; sandbox install (see [Files] + the InstallStudioComponent procedure in [Code]).
; DRY: this filename is referenced by both the [Files] entry and the [Code] launch.
#define StudioInstaller "ClawFactory-Studio-Setup-1.1.0.exe"

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
Source: "resources\clawfactory-grants.ps1";  DestDir: "{app}\resources";  Flags: ignoreversion
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
; --- Security-track resources (SECFIX DNS/SOUL -> gate coverage -> close-doors -> chat proxy).
; setup.ps1 reads each of these from {app}\resources and base64-streams it into
; WSL at install time. They MUST ship: without them Step-InstallTurnGate and
; Step-InstallChatProxy throw FileNotFoundException inside Invoke-WithRollback,
; so the install ABORTS and every security control is absent. (This was a real
; bug: the steps were added across three jobs and the [Files] entries were not --
; caught by the Azure staging preflight, before a VM was ever provisioned.
; Step-Preflight now asserts these exist, so a future omission fails fast and loud.)
Source: "resources\openclaw-shim.sh";          DestDir: "{app}\resources";  Flags: ignoreversion
Source: "resources\clawfactory-turn-gate.sh";  DestDir: "{app}\resources";  Flags: ignoreversion
Source: "resources\clawfactory-spend-check.js"; DestDir: "{app}\resources"; Flags: ignoreversion
Source: "resources\install-turn-gate.sh";      DestDir: "{app}\resources";  Flags: ignoreversion
Source: "resources\freeze-injected-soul.sh";   DestDir: "{app}\resources";  Flags: ignoreversion
Source: "resources\clawfactory-proxy.js";      DestDir: "{app}\resources";  Flags: ignoreversion
Source: "resources\clawfactory-proxy.service"; DestDir: "{app}\resources";  Flags: ignoreversion
Source: "resources\install-chat-proxy.sh";     DestDir: "{app}\resources";  Flags: ignoreversion
Source: "resources\gateway-wait.sh";           DestDir: "{app}\resources";  Flags: ignoreversion
; --- v1 Guard 1: delete quarantine (recoverable deletes). Step-InstallQuarantine
; streams all eight into WSL; Step-Preflight refuses to install without them.
Source: "resources\quarantine-lib.js";                 DestDir: "{app}\resources"; Flags: ignoreversion
Source: "resources\clawfactory-quarantined.js";        DestDir: "{app}\resources"; Flags: ignoreversion
Source: "resources\clawfactory-quarantinectl.js";      DestDir: "{app}\resources"; Flags: ignoreversion
Source: "resources\clawfactory-quarantine-rm.js";      DestDir: "{app}\resources"; Flags: ignoreversion
Source: "resources\clawfactory-quarantine.service";    DestDir: "{app}\resources"; Flags: ignoreversion
Source: "resources\clawfactory-quarantine-gc.service"; DestDir: "{app}\resources"; Flags: ignoreversion
Source: "resources\clawfactory-quarantine-gc.timer";   DestDir: "{app}\resources"; Flags: ignoreversion
Source: "resources\install-quarantine.sh";             DestDir: "{app}\resources"; Flags: ignoreversion
; --- v1 Guard 2: approval-gated send (email leaves only with your approval).
; Step-InstallSend streams all eleven into WSL; Step-Preflight refuses to install
; without them. This pairing is the two halves of the bug that once shipped an
; installer with zero security controls: a step was added, the [Files] entry was
; not, and a fresh install aborted with no guards in place. Add both or neither.
Source: "resources\send-lib.js";                        DestDir: "{app}\resources"; Flags: ignoreversion
Source: "resources\send-smtp.js";                       DestDir: "{app}\resources"; Flags: ignoreversion
Source: "resources\clawfactory-sendd.js";               DestDir: "{app}\resources"; Flags: ignoreversion
Source: "resources\clawfactory-sendctl.js";             DestDir: "{app}\resources"; Flags: ignoreversion
Source: "resources\clawfactory-send.js";                DestDir: "{app}\resources"; Flags: ignoreversion
Source: "resources\clawfactory-send.service";           DestDir: "{app}\resources"; Flags: ignoreversion
Source: "resources\clawfactory-send-gc.service";        DestDir: "{app}\resources"; Flags: ignoreversion
Source: "resources\clawfactory-send-gc.timer";          DestDir: "{app}\resources"; Flags: ignoreversion
Source: "resources\clawfactory-fw-assert.sh";           DestDir: "{app}\resources"; Flags: ignoreversion
Source: "resources\egress-policy.json";                 DestDir: "{app}\resources"; Flags: ignoreversion
Source: "resources\install-send.sh";                    DestDir: "{app}\resources"; Flags: ignoreversion
; --- v1.1.0 (JOB 3B): embedded ClawFactory Studio (the visual workbench) --------
; The SIGNED per-user Studio installer (~100 MB), sourced from the Studio repo's
; release dir at build time (gitignored; scripts\build_release.ps1 fails the build if
; its sha256 does not match the digest pinned there). It is
; staged to {app}\stage rather than {tmp} on purpose: this Setup runs elevated, so
; {tmp} is the elevating admin's temp -- unreadable to a DIFFERENT original user.
; {app} (Program Files) is world Read+Execute, so the de-elevated original user that
; InstallStudioComponent runs it as can read+execute it (the kitchen-table case).
; NOT deleteafterinstall: InstallStudioComponent consumes it in ssPostInstall (whose
; timing vs deleteafterinstall is undocumented) and deletes it itself right after.
Source: "resources\{#StudioInstaller}";        DestDir: "{app}\stage";      Flags: ignoreversion

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
  Comment: "Emergency stop: stops the OpenClaw gateway and agent processes"
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
  KeyGuidePage:   TWizardPage;      { v1.0.46: how-to-get-your-key guidance }
  KeyGuideSteps:  TNewStaticText;   { numbered steps, per provider }
  KeyGuideFormat: TNewStaticText;   { "a valid key starts with ..." }
  KeyGuideSafety: TNewStaticText;   { key-is-yours + spend-cap note }
  OpenConsoleBtn: TNewButton;       { opens the provider console }
  ApiKeyPage:     TInputQueryWizardPage;
  ApiKeyLaterChk: TNewCheckBox;
  ApiKeyShowChk:  TNewCheckBox;     { v1.0.46: show/hide the masked key }
  GetKeyButton:   TNewButton;
  BuyButton:      TNewButton;
  AckPage:        TInputOptionWizardPage;
  IsResumeRun:    Boolean;
  ResumeProvider: string;
  KeyChangeGuard: Boolean;          { re-entrancy guard for the trim-on-change }
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

{ v1.0.46: expected key prefix per provider, for format validation before we
  bother the provider with a live call. Verified against each provider's live
  console/docs (2026-07): Anthropic sk-ant-, OpenAI sk- (modern sk-proj-,
  legacy sk-), xAI xai-, Google AI Studio AIza. }
function ProviderKeyPrefix: string;
begin
  case ProviderPage.SelectedValueIndex of
    0: Result := 'xai-';
    1: Result := 'sk-';
    2: Result := 'sk-ant-';
    3: Result := 'AIza';
  else
    Result := '';
  end;
end;

{ A masked, illustrative example so a first-time buyer recognises a well-formed
  key. Not a real key - the X's stand in for the secret part. }
function ProviderKeyExample: string;
begin
  case ProviderPage.SelectedValueIndex of
    0: Result := 'xai-XXXXXXXXXXXXXXXXXXXXXXXX';
    1: Result := 'sk-proj-XXXXXXXXXXXXXXXXXXXX';
    2: Result := 'sk-ant-api03-XXXXXXXXXXXXXX';
    3: Result := 'AIzaXXXXXXXXXXXXXXXXXXXXXXXX';
  else
    Result := '';
  end;
end;

{ Provider "list models" endpoint - a free, no-token GET used to confirm a key
  actually authenticates. Never a completions call, which would cost tokens. }
function ProviderModelsUrl: string;
begin
  case ProviderPage.SelectedValueIndex of
    0: Result := 'https://api.x.ai/v1/models';
    1: Result := 'https://api.openai.com/v1/models';
    2: Result := 'https://api.anthropic.com/v1/models';
    3: Result := 'https://generativelanguage.googleapis.com/v1beta/models';
  else
    Result := '';
  end;
end;

{ Plain, numbered steps for obtaining a key. Short and calm for a non-developer.
  Console URLs match the button target (ProviderApiKeyUrl) and were verified
  live 2026-07. }
function ProviderStepsText: string;
begin
  case ProviderPage.SelectedValueIndex of
    0: Result :=
      '1.  Click the button below to open the xAI console (console.x.ai).' + #13#10 +
      '2.  Sign in, or create an account if this is your first time.' + #13#10 +
      '3.  Add a payment method under Billing - xAI needs one to issue a key.' + #13#10 +
      '4.  Open "API Keys", click "Create API Key", and give it any name.' + #13#10 +
      '5.  Copy the key it shows you (shown only once), then click Next below.';
    1: Result :=
      '1.  Click the button below to open the OpenAI platform (platform.openai.com).' + #13#10 +
      '2.  Sign in, or create an account if this is your first time.' + #13#10 +
      '3.  Add a little credit under Billing - a few dollars is plenty to start.' + #13#10 +
      '4.  On the API keys page, click "Create new secret key" and name it.' + #13#10 +
      '5.  Copy the key it shows you (shown only once), then click Next below.';
    2: Result :=
      '1.  Click the button below to open the Anthropic console (console.anthropic.com).' + #13#10 +
      '2.  Sign in, or create an account if this is your first time.' + #13#10 +
      '3.  Add a payment method and a little credit under Plans & Billing.' + #13#10 +
      '4.  Go to Settings then API keys, click "Create Key", and name it.' + #13#10 +
      '5.  Copy the key it shows you (shown only once), then click Next below.';
    3: Result :=
      '1.  Click the button below to open Google AI Studio (aistudio.google.com).' + #13#10 +
      '2.  Sign in with a Google account and accept the terms.' + #13#10 +
      '3.  Click "Create API key" - a free tier is available to start.' + #13#10 +
      '4.  Copy the key it shows you, then click Next below.';
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

{ v1.0.46: show/hide toggle for the masked key field. TPasswordEdit.Password
  True = masked, False = revealed. }
procedure ApiKeyShowChkClick(Sender: TObject);
begin
  ApiKeyPage.Edits[0].Password := not ApiKeyShowChk.Checked;
end;

{ v1.0.46: strip stray CR/LF/TAB and surrounding spaces as the key is typed or
  pasted. A trailing newline from a copy is the single most common failure, so
  we clean it the moment it lands rather than only at submit. Guarded against
  the re-entrant OnChange that setting .Text triggers. }
procedure ApiKeyEditChange(Sender: TObject);
var
  Cur, Clean: string;
  i: Integer;
begin
  if KeyChangeGuard then exit;
  Cur := ApiKeyPage.Edits[0].Text;
  Clean := '';
  for i := 1 to Length(Cur) do
    if (Cur[i] <> #13) and (Cur[i] <> #10) and (Cur[i] <> #9) then
      Clean := Clean + Cur[i];
  Clean := Trim(Clean);
  if Clean <> Cur then
  begin
    KeyChangeGuard := True;
    ApiKeyPage.Edits[0].Text := Clean;
    KeyChangeGuard := False;
  end;
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

{ v1.0.46: minimal, no-cost authentication probe. GETs the provider's model
  list with the supplied key and classifies the HTTP status. Model listing
  spends zero tokens. The key is sent ONLY to the provider the user chose, over
  HTTPS, and is never logged or written to disk here. 8s timeouts so a slow
  network cannot stall the install; the caller treats anything but a clean
  200/401/403/429 as "could not verify" and lets the user continue.

  Returns: 0 = valid, 1 = rejected (401/403), 2 = rate-limited (429),
           3 = could not determine (network, timeout, or any other status). }
function LiveCheckKey(Key: string): Integer;
var
  WinHTTP: Variant;
  Url: string;
  Status: Integer;
begin
  Result := 3;
  Url := ProviderModelsUrl;
  if Url = '' then exit;
  try
    WinHTTP := CreateOleObject('WinHttp.WinHttpRequest.5.1');
    WinHTTP.Open('GET', Url, False);
    { Auth header per provider. Gemini takes the key in x-goog-api-key (a header,
      never the URL); Anthropic uses x-api-key + a version header; the OpenAI-
      compatible providers (OpenAI, xAI) use a Bearer token. }
    case ProviderPage.SelectedValueIndex of
      2:
        begin
          WinHTTP.SetRequestHeader('x-api-key', Key);
          WinHTTP.SetRequestHeader('anthropic-version', '2023-06-01');
        end;
      3:
        WinHTTP.SetRequestHeader('x-goog-api-key', Key);
    else
      WinHTTP.SetRequestHeader('Authorization', 'Bearer ' + Key);
    end;
    WinHTTP.SetTimeouts(8000, 8000, 8000, 8000);
    WinHTTP.Send('');
    Status := WinHTTP.Status;
    if Status = 200 then
      Result := 0
    else if (Status = 401) or (Status = 403) then
      Result := 1
    else if Status = 429 then
      Result := 2
    else
      Result := 3;
  except
    Result := 3;
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
    'ClawFactory Secure Setup configures WSL2 and OpenClaw with strict' + #13#10 +
    'security guardrails:' + #13#10 + #13#10 +
    '  - The agent runs as a non-root user (no sudo) inside a WSL2 VM.' + #13#10 +
    '  - Outbound network is an allowlist: HTTPS to approved hosts only.' + #13#10 +
    '  - OpenClaw gateway binds to 127.0.0.1 only.' + #13#10 +
    '  - WSL automount is disabled (no access to your Windows files).' + #13#10 +
    '  - Safety rules are immutable; turns through the gateway are spend- and integrity-gated.' + #13#10 + #13#10 +
    'WARNING: AI agents will execute code inside this WSL2 environment.' + #13#10 +
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

  { --- Page 4: How to get your API key (guidance) [v1.0.46] ------------------
    The point of the wizard: walk a non-developer from "I bought this" to a
    working key without ever touching a terminal. Content is provider-specific
    and filled in / laid out by CurPageChanged (label heights aren't known until
    their captions are set). Skipped for Ollama / "later" / silent / resume via
    ShouldSkipPage. }
  KeyGuidePage := CreateCustomPage(ProviderPage.ID,
    'Get your API key',
    'A one-time setup step. It usually takes only a few minutes.');

  KeyGuideSteps := TNewStaticText.Create(KeyGuidePage);
  KeyGuideSteps.Parent   := KeyGuidePage.Surface;
  KeyGuideSteps.Left     := 0;
  KeyGuideSteps.Width    := KeyGuidePage.SurfaceWidth;
  KeyGuideSteps.WordWrap := True;
  KeyGuideSteps.AutoSize := True;
  KeyGuideSteps.Caption  := '';

  OpenConsoleBtn := TNewButton.Create(KeyGuidePage);
  OpenConsoleBtn.Parent  := KeyGuidePage.Surface;
  OpenConsoleBtn.Left    := 0;
  OpenConsoleBtn.Width   := ScaleX(260);
  OpenConsoleBtn.Height  := ScaleY(26);
  OpenConsoleBtn.Caption := 'Open the provider console';
  OpenConsoleBtn.OnClick := @GetKeyButtonClick;

  KeyGuideFormat := TNewStaticText.Create(KeyGuidePage);
  KeyGuideFormat.Parent   := KeyGuidePage.Surface;
  KeyGuideFormat.Left     := 0;
  KeyGuideFormat.Width    := KeyGuidePage.SurfaceWidth;
  KeyGuideFormat.WordWrap := True;
  KeyGuideFormat.AutoSize := True;
  KeyGuideFormat.Caption  := '';

  KeyGuideSafety := TNewStaticText.Create(KeyGuidePage);
  KeyGuideSafety.Parent   := KeyGuidePage.Surface;
  KeyGuideSafety.Left     := 0;
  KeyGuideSafety.Width    := KeyGuidePage.SurfaceWidth;
  KeyGuideSafety.WordWrap := True;
  KeyGuideSafety.AutoSize := True;
  KeyGuideSafety.Caption  :=
    'Your key is yours. It bills to your own provider account, and ClawFactory ' +
    'never sends it anywhere except to the provider you chose. On this PC it is ' +
    'kept in Windows Credential Manager (DPAPI-protected); in the sandbox it lives ' +
    'only in a locked-down file (mode 600), never on a command line or in .env.' + #13#10 + #13#10 +
    'A configurable spend cap stops turns once you reach your limit - a strong ' +
    'guardrail on the gateway path, not an absolute ceiling (see SECURITY.md). ' +
    'You can also set a hard spending limit in your provider account.';

  { --- Page 5: API key entry (skipped for Ollama / Later via ShouldSkipPage) [R5] --- }
  ApiKeyPage := CreateInputQueryPage(KeyGuidePage.ID,
    'Enter your API key',
    'Paste the key you just copied.',
    'It is stored in Windows Credential Manager (DPAPI-protected) and is never ' + #13#10 +
    'written to a log, a temp file, a command line, or .env. In the sandbox it is ' + #13#10 +
    'kept in a locked-down file (mode 600), readable only by the agent user.' + #13#10 + #13#10 +
    'Not ready yet? Tick the box below - you can add your key later from the Start ' + #13#10 +
    'Menu (ClawFactory > Switch AI Provider), which walks you through it.');
  ApiKeyPage.Add('API key:', True);
  ApiKeyPage.Edits[0].OnChange := @ApiKeyEditChange;

  { Show/hide toggle for the masked field, directly under it. }
  ApiKeyShowChk := TNewCheckBox.Create(ApiKeyPage);
  ApiKeyShowChk.Parent  := ApiKeyPage.Surface;
  ApiKeyShowChk.Left    := ApiKeyPage.Edits[0].Left;
  ApiKeyShowChk.Top     := ApiKeyPage.Edits[0].Top + ApiKeyPage.Edits[0].Height + ScaleY(6);
  ApiKeyShowChk.Width   := ScaleX(160);
  ApiKeyShowChk.Height  := ScaleY(18);
  ApiKeyShowChk.Caption := 'Show key';
  ApiKeyShowChk.OnClick := @ApiKeyShowChkClick;

  { "Get your <Provider> API key" button - a second chance to open the console
    from the entry page. Caption + visibility are set in CurPageChanged. }
  GetKeyButton := TNewButton.Create(ApiKeyPage);
  GetKeyButton.Parent := ApiKeyPage.Surface;
  GetKeyButton.Top    := ApiKeyShowChk.Top + ApiKeyShowChk.Height + ScaleY(12);
  GetKeyButton.Left   := ApiKeyPage.Edits[0].Left;
  GetKeyButton.Width  := ScaleX(240);
  GetKeyButton.Height := ScaleY(24);
  GetKeyButton.Caption := 'Get your API key';
  GetKeyButton.OnClick := @GetKeyButtonClick;

  ApiKeyLaterChk := TNewCheckBox.Create(ApiKeyPage);
  ApiKeyLaterChk.Parent  := ApiKeyPage.Surface;
  ApiKeyLaterChk.Top     := GetKeyButton.Top + GetKeyButton.Height + ScaleY(12);
  ApiKeyLaterChk.Left    := ApiKeyPage.Edits[0].Left;
  ApiKeyLaterChk.Width   := ApiKeyPage.SurfaceWidth - ApiKeyLaterChk.Left;
  ApiKeyLaterChk.Height  := ScaleY(20);
  ApiKeyLaterChk.Caption := 'I''ll add my API key later (agents will not run until I do)';

  { --- Page 6: Security acknowledgement (mandatory) --- }
  AckPage := CreateInputOptionPage(ApiKeyPage.ID,
    'Security Acknowledgement',
    'Please confirm you understand what you are about to install.',
    'Tick the box below to continue. Installation is blocked until you do.',
    False, False);
  AckPage.Add('I understand agents execute code inside a hardened WSL2 environment ' +
              '(non-root, network-restricted) and I will personally review every ' +
              'skill before publishing.');
end;

procedure CurPageChanged(CurPageID: Integer);
var
  ShortName: string;
begin
  ShortName := ProviderShortName;

  { Guidance page: fill in provider-specific copy and stack the controls. Label
    heights are only known once their captions are set, so both the text and the
    vertical layout happen here rather than in InitializeWizard. }
  if CurPageID = KeyGuidePage.ID then
  begin
    KeyGuidePage.Caption := 'Get your ' + ShortName + ' API key';

    KeyGuideSteps.Top     := ScaleY(4);
    KeyGuideSteps.Caption := ProviderStepsText;

    OpenConsoleBtn.Top     := KeyGuideSteps.Top + KeyGuideSteps.Height + ScaleY(14);
    OpenConsoleBtn.Caption := 'Open the ' + ShortName + ' console';

    KeyGuideFormat.Top     := OpenConsoleBtn.Top + OpenConsoleBtn.Height + ScaleY(16);
    KeyGuideFormat.Caption := 'A valid ' + ShortName + ' key starts with "' +
      ProviderKeyPrefix + '" (for example ' + ProviderKeyExample + '). ' +
      'If what you copied does not start that way, you have the wrong value.';

    KeyGuideSafety.Top := KeyGuideFormat.Top + KeyGuideFormat.Height + ScaleY(16);
  end;

  { Entry page: label + visibility of the "Get your key" button, and reset the
    show toggle so a re-entry never leaves the key revealed. }
  if CurPageID = ApiKeyPage.ID then
  begin
    ApiKeyShowChk.Checked := False;
    ApiKeyPage.Edits[0].Password := True;
    if ShortName = '' then
    begin
      GetKeyButton.Visible := False;
    end
    else
    begin
      GetKeyButton.Caption := 'Get your ' + ShortName + ' API key';
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
       (PageID = ProviderPage.ID) or (PageID = KeyGuidePage.ID) or
       (PageID = ApiKeyPage.ID) or (PageID = AckPage.ID) then
    begin
      Result := True;
      exit;
    end;
  end;
  if WizardSilent() then
  begin
    { LicensePage is also skipped under /SILENT - the /LICENSE=<key> CLI
      arg was validated up front in InitializeWizard. If validation failed
      InitializeWizard called Abort, so reaching here means license is OK.
      KeyGuidePage / ApiKeyPage never show under /SILENT: the key is seeded
      into Credential Manager machine-to-machine before setup runs. }
    if (PageID = LicensePage.ID) or (PageID = ProviderPage.ID) or
       (PageID = KeyGuidePage.ID) or (PageID = ApiKeyPage.ID) or
       (PageID = AckPage.ID) then
    begin
      Result := True;
      exit;
    end;
  end;
  { Ollama / "configure later" need no key, so skip both key pages. }
  if (PageID = KeyGuidePage.ID) or (PageID = ApiKeyPage.ID) then
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

    { Deferral: an empty key with "add later" ticked is allowed - the install
      finishes with the agent unconfigured. An empty key without it is a stop. }
    if Key = '' then
    begin
      if (not WizardSilent()) and (not ApiKeyLaterChk.Checked) then
      begin
        MsgBox('Enter your API key, or tick "I''ll add my API key later".',
               mbError, MB_OK);
        Result := False;
      end;
      exit;   { nothing to store }
    end;

    { Format check (interactive only): catch a wrong-value paste with a specific,
      named message before we bother the provider. }
    if (not WizardSilent()) and (ProviderKeyPrefix <> '') and
       (Pos(ProviderKeyPrefix, Key) <> 1) then
    begin
      MsgBox('That does not look like a valid ' + ProviderShortName + ' API key.' + #13#10 + #13#10 +
             ProviderShortName + ' keys start with "' + ProviderKeyPrefix + '" ' +
             '(for example ' + ProviderKeyExample + ').' + #13#10 + #13#10 +
             'Double-check you copied the whole key from the ' + ProviderShortName +
             ' console, with no extra characters.',
             mbError, MB_OK);
      Result := False;
      exit;
    end;

    { Live check (interactive only): confirm the key actually authenticates.
      This NEVER blocks the install by itself - a rejected key can still be
      forced through, and any network problem or timeout just offers to
      continue. See LiveCheckKey for the return codes. }
    if not WizardSilent() then
    begin
      case LiveCheckKey(Key) of
        1:
          begin
            if MsgBox(ProviderShortName + ' rejected this key.' + #13#10 + #13#10 +
                 'It may be mistyped, revoked, or not active yet - a brand-new key ' +
                 'can need a payment method on file and a minute to start working.' + #13#10 + #13#10 +
                 'Fix the key now?  (Choose No to use it as-is anyway.)',
                 mbError, MB_YESNO) = IDYES then
            begin
              Result := False;
              exit;
            end;
          end;
        2:
          MsgBox('Could not verify the key right now - ' + ProviderShortName +
                 ' is rate-limiting requests.' + #13#10 + #13#10 +
                 'Your key was not rejected. The install will continue and you can ' +
                 'test it once things settle.',
                 mbInformation, MB_OK);
        3:
          begin
            if MsgBox('Could not reach ' + ProviderShortName + ' to verify the key ' +
                 '(no network, a firewall, or the provider is briefly down).' + #13#10 + #13#10 +
                 'Continue without verifying?  (Choose No to try again.)',
                 mbConfirmation, MB_YESNO) = IDNO then
            begin
              Result := False;
              exit;
            end;
          end;
      end;
    end;

    { Store via the existing mechanism: Windows Credential Manager. setup.ps1's
      Step-WireProviderKey reads it back from here. Not written to any log, temp
      file, or the Inno log (the scripting Exec does not log its parameters). }
    CredTarget := ProviderCredentialTarget;
    Exec('cmdkey.exe',
         '/generic:' + CredTarget + ' /user:clawuser /pass:' + Key,
         '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
    ApiKeyPage.Values[0] := '';
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

// v1.1.0 (JOB 3B): install the embedded ClawFactory Studio component.
//
// (Comment uses // lines on purpose: Inno brace-comments do not nest and end at the
//  FIRST '}', so a {app}/{tmp}/{commonappdata} token in the prose would close the
//  comment early -- the same reason CurUninstallStepChanged below uses // lines.)
//
// ORDER -- core first, Studio last. Inno processes the [Run] section (where
// setup.ps1 does the whole sandbox/gateway/firewall/SOUL build) BEFORE it fires
// CurStepChanged(ssPostInstall) (verified against the Inno docs, not assumed). So
// by the time this runs, the core install has already finished -- exactly the
// required ordering, with no change to setup.ps1 or its reboot/resume [Run] entry.
//
// ELEVATION RULE -- the bug that passes on a dev box and fails at a kitchen table.
// This Setup runs elevated (PrivilegesRequired=admin). Studio's NSIS installer is
// PER-USER (installs into %LOCALAPPDATA%\Programs). If we launched it in the
// inherited elevated token it would land in the ADMIN's profile, invisible to the
// customer who logs in as a standard user. ExecAsOriginalUser runs it as the
// (normally non-elevated) user who started Setup, so Studio lands in the customer's
// own profile. The staged .exe lives under the app dir\stage (Program Files, world
// Read+Execute) so that de-elevated user can actually read+execute it.
//
// FAILURE HONESTY -- a nonzero Studio exit, or a failure to even launch it,
// RaiseException's. Inno then shows the message and rolls back: the customer gets a
// clean, reportable failure, never a silent "finished with warnings" half-product.
//
// REBOOT SAFETY -- on a fresh box the core install reboots once for WSL2 and
// resumes via RunOnce (/resume). We gate on install-result.txt = 'success' (the
// honest verdict setup.ps1 writes only when the whole core build completes), so on
// a pre-reboot pass we simply skip and let the resumed final pass install Studio.
// If the core did not succeed, its own failure reporting stands -- we do not stack a
// second Studio error on top of it.
procedure InstallStudioComponent;
var
  StudioSetup, StageDir, ResultFile: string;
  CoreResult: AnsiString;
  ResultCode: Integer;
begin
  ResultFile := ExpandConstant('{commonappdata}\ClawFactory\install-result.txt');
  if not LoadStringFromFile(ResultFile, CoreResult) then
  begin
    Log('Studio: core install-result.txt not present yet (mid-install / pre-resume pass); skipping Studio install this pass.');
    exit;
  end;
  if Pos('success', Lowercase(string(CoreResult))) = 0 then
  begin
    Log('Studio: core install did not report success ("' + Trim(string(CoreResult)) + '"); NOT installing Studio -- core failure reporting stands.');
    exit;
  end;

  StageDir    := ExpandConstant('{app}\stage');
  StudioSetup := StageDir + '\{#StudioInstaller}';
  if not FileExists(StudioSetup) then
    RaiseException('The ClawFactory Studio installer is missing from the package (' +
      StudioSetup + '). The combined installer is incomplete -- stopping rather than ' +
      'delivering only half of ClawFactory. Please re-download and run the installer again.');

  // Plain-language progress for the customer.
  if Assigned(WizardForm) then
  begin
    WizardForm.StatusLabel.Caption := 'Installing ClawFactory Studio (your visual workbench)...';
    WizardForm.StatusLabel.Update;
  end;

  Log('Studio: launching per-user installer as the ORIGINAL (de-elevated) user: "' + StudioSetup + '" /S');
  if not ExecAsOriginalUser(StudioSetup, '/S', StageDir, SW_HIDE, ewWaitUntilTerminated, ResultCode) then
    RaiseException('Could not start the ClawFactory Studio installer. ClawFactory''s core ' +
      'is installed but Studio is not -- stopping so you get a clean failure to report ' +
      'rather than a half-installed product. Re-running the installer will try again.');

  if ResultCode <> 0 then
    RaiseException('ClawFactory Studio did not install successfully (installer exit code ' +
      IntToStr(ResultCode) + '). ClawFactory''s core is installed but Studio is not -- ' +
      'stopping so you can re-run the installer for a clean result.');

  Log('Studio: per-user install completed (exit 0). Landed in the original user''s profile.');

  // We consumed the staged installer; remove it (and the now-empty stage dir) so the
  // 100 MB payload does not linger in Program Files. Best-effort -- a leftover here is
  // cosmetic, and Inno's uninstaller would remove the stage dir anyway.
  if not DeleteFile(StudioSetup) then
    Log('Studio: could not delete staged installer ' + StudioSetup + ' (will be removed at uninstall).')
  else
    RemoveDir(StageDir);
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then
    InstallStudioComponent;
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
