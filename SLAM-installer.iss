[Setup]
AppName=SLAM
AppVersion=1.0
DefaultDirName={pf}\SLAM
DefaultGroupName=SLAM
OutputBaseFilename=SLAM_Installer
Compression=lzma
SolidCompression=yes
PrivilegesRequired=admin
Uninstallable=no
DisableDirPage=no

[Files]
; No static files—content fetched at install time

[Run]
Filename: "explorer.exe"; Parameters: "{app}"; Flags: postinstall nowait; Description: "Open installation folder"
Filename: "{app}\config.txt"; Flags: postinstall shellexec; Description: "Open config.txt"

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

  // Ensure Git and PowerShell 7 are present
  InstallIfMissing('Git.Git', GitExe, 'Git');
  InstallIfMissing('Microsoft.PowerShell', PS7Path, 'PowerShell 7');

  // Clean up any previous clone
  if DirExists(ClonePath) then
    ExecWithWait('cmd.exe', '/c rmdir /S /Q "' + ClonePath + '"');
  CreateDir(ClonePath);

  // Clone repository
  ExecWithWait(GitExe, 'clone https://github.com/halfmanbear/SLAM.git "' + ClonePath + '"');

  // Copy everything—including hidden files—into {app}
  ExecWithWait('cmd.exe', '/c xcopy "' + ClonePath + '\*" "' + InstallPath + '" /E /H /C /I /Y');

  // Run shortcut creation script
  ExecWithWait(PS7Path, '-ExecutionPolicy Bypass -File "' + InstallPath + '\create-shortcut.ps1"');

  // Optional: clean up temp clone
  ExecWithWait('cmd.exe', '/c rmdir /S /Q "' + ClonePath + '"');
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssInstall then
    CloneAndCopySLAM();
end;
