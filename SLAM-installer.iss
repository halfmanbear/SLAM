[Setup]
AppName=SLAM
AppVersion=
AppVerName=SLAM
AppPublisher=HalfManBear
UninstallDisplayName=SLAM
UninstallDisplayIcon={app}\icon.ico
DefaultDirName={commonpf}\SLAM
DefaultGroupName=SLAM
OutputBaseFilename=SLAM_Installer
Compression=lzma
SolidCompression=yes
PrivilegesRequired=admin
CreateUninstallRegKey=yes
DisableDirPage=no
DirExistsWarning=no

[Files]
; No static files—content fetched at install time

[UninstallDelete]
Type: filesandordirs; Name: "{app}\*"

[Run]
Filename: "explorer.exe"; Parameters: "{app}"; Flags: postinstall nowait unchecked; Description: "Open installation folder"

[Code]
const
  PS7Path = 'C:\Program Files\PowerShell\7\pwsh.exe';
  GitExe  = 'C:\Program Files\Git\cmd\git.exe';
  WingetExe = 'winget';
  TempDir = '{tmp}\SLAMTempClone';

procedure ExecWithWait(const FilePath, Params: String);
var
  ResultCode: Integer;
begin
  if not Exec(FilePath, Params, '', SW_SHOW, ewWaitUntilTerminated, ResultCode) or (ResultCode <> 0) then
    MsgBox(Format('Command failed: %s %s (Exit code: %d)', [FilePath, Params, ResultCode]), mbError, MB_OK);
end;

function IsInstalled(const Path: String): Boolean;
begin
  Result := FileExists(Path);
end;

function CheckWingetInstalled(): Boolean;
var
  Res: Integer;
begin
  Result := Exec('cmd.exe', '/c ' + WingetExe + ' --version', '', SW_HIDE, ewWaitUntilTerminated, Res) and (Res = 0);
end;

procedure InstallIfMissing(const Id, ExePath, FriendlyName: String);
begin
  if not IsInstalled(ExePath) then
  begin
    if CheckWingetInstalled() then
      ExecWithWait('cmd.exe', '/c ' + WingetExe + ' install --id ' + Id + ' -e --source winget')
    else
      MsgBox(FriendlyName + ' is missing and winget is unavailable. Please install it manually.', mbError, MB_OK);
  end;
end;

procedure CloneAndCopySLAM();
var
  InstallPath, ClonePath: String;
begin
  InstallPath := ExpandConstant('{app}');
  ClonePath   := ExpandConstant(TempDir);

  InstallIfMissing('Git.Git', GitExe, 'Git');
  InstallIfMissing('Microsoft.PowerShell', PS7Path, 'PowerShell 7');

  if DirExists(ClonePath) then
    ExecWithWait('cmd.exe', '/c rmdir /S /Q "' + ClonePath + '"');
  CreateDir(ClonePath);

  ExecWithWait(GitExe, 'clone https://github.com/halfmanbear/SLAM.git "' + ClonePath + '"');

  ExecWithWait('cmd.exe', '/c xcopy "' + ClonePath + '\*" "' + InstallPath + '" /E /H /C /I /Y');

  ExecWithWait(PS7Path, '-ExecutionPolicy Bypass -File "' + InstallPath + '\create-shortcut.ps1"');

  ExecWithWait('cmd.exe', '/c rmdir /S /Q "' + ClonePath + '"');
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssInstall then
    CloneAndCopySLAM();
end;

function InitializeUninstall(): Boolean;
var
  WarningMsg: String;
begin
  WarningMsg := 'WARNING: Before proceeding, ensure that:' + #13#10 + #13#10 +
    '- No mods are currently Installed within SLAM' + #13#10 +
    '- All mods are BACKED UP' + #13#10 + #13#10 +
    'This will DELETE the SLAM directory contents. ' +
    'Mods that have not been backed up will be permanently lost.' + #13#10 + #13#10 +
    'Do you want to continue?';
  
  Result := MsgBox(WarningMsg, mbConfirmation, MB_YESNO or MB_DEFBUTTON2) = IDYES;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  ShortcutPath: String;
  AppPath: String;
begin
  if CurUninstallStep = usUninstall then
  begin
    ShortcutPath := ExpandConstant('{userdesktop}\SLAM.lnk');
    if FileExists(ShortcutPath) then
      DeleteFile(ShortcutPath);
    
    ShortcutPath := ExpandConstant('{commondesktop}\SLAM.lnk');
    if FileExists(ShortcutPath) then
      DeleteFile(ShortcutPath);
    
    ShortcutPath := ExpandConstant('{userprograms}\SLAM.lnk');
    if FileExists(ShortcutPath) then
      DeleteFile(ShortcutPath);
    
    ShortcutPath := ExpandConstant('{commonprograms}\SLAM.lnk');
    if FileExists(ShortcutPath) then
      DeleteFile(ShortcutPath);
  end;
  
  if CurUninstallStep = usPostUninstall then
  begin
    AppPath := ExpandConstant('{app}');
    if DirExists(AppPath) then
      RemoveDir(AppPath);
  end;
end;
