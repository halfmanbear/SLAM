[Setup]
AppName=SLAM
AppVersion=1.0
DefaultDirName={pf}\SLAM
DefaultGroupName=SLAM
OutputBaseFilename=SLAM_Installer
Compression=lzma
SolidCompression=yes
PrivilegesRequired=admin
Uninstallable=yes
DisableDirPage=no
UninstallDisplayName=SLAM - SymLink Advanced Modding
UninstallDisplayIcon={app}\icon.ico

[Files]
; No static files—content fetched at install time

[Run]
Filename: "explorer.exe"; Parameters: "{app}"; Flags: postinstall nowait; Description: "Open installation folder"
; Filename: "{app}\config.txt"; Flags: postinstall shellexec; Description: "Open config.txt"

[Code]
const
  PS7Path = 'C:\Program Files\PowerShell\7\pwsh.exe';
  GitExe  = 'C:\Program Files\Git\cmd\git.exe';
  WingetExe = 'winget';
  TempDir = '{tmp}\SLAMTempClone';

function ExecWithWait(const FilePath, Params, ErrorMsg: String): Boolean;
var
  ResultCode: Integer;
begin
  Result := Exec(FilePath, Params, '', SW_SHOW, ewWaitUntilTerminated, ResultCode);
  if not Result or (ResultCode <> 0) then
  begin
    MsgBox(Format('%s'#13#10'Command: %s %s'#13#10'Exit code: %d', [ErrorMsg, FilePath, Params, ResultCode]), mbError, MB_OK);
    Result := False;
  end
  else
    Result := True;
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

function InstallIfMissing(const Id, ExePath, FriendlyName: String): Boolean;
begin
  Result := True;
  if not IsInstalled(ExePath) then
  begin
    if CheckWingetInstalled() then
    begin
      if not ExecWithWait('cmd.exe', '/c ' + WingetExe + ' install --id ' + Id + ' -e --source winget',
                          'Failed to install ' + FriendlyName) then
      begin
        MsgBox(FriendlyName + ' installation failed. Please install it manually and try again.', mbError, MB_OK);
        Result := False;
      end;
    end
    else
    begin
      MsgBox(FriendlyName + ' is missing and winget is unavailable. Please install it manually.', mbError, MB_OK);
      Result := False;
    end;
  end;
end;

function CloneAndCopySLAM(): Boolean;
var
  InstallPath, ClonePath: String;
begin
  Result := False;
  InstallPath := ExpandConstant('{app}');
  ClonePath   := ExpandConstant(TempDir);

  // Ensure Git and PowerShell 7 are present
  if not InstallIfMissing('Git.Git', GitExe, 'Git') then
    Exit;

  if not InstallIfMissing('Microsoft.PowerShell', PS7Path, 'PowerShell 7') then
    Exit;

  // Clean up any previous clone
  if DirExists(ClonePath) then
    ExecWithWait('cmd.exe', '/c rmdir /S /Q "' + ClonePath + '"', 'Failed to clean previous clone directory');

  if not ForceDirectories(ClonePath) then
  begin
    MsgBox('Failed to create temporary directory: ' + ClonePath, mbError, MB_OK);
    Exit;
  end;

  // Clone repository
  if not ExecWithWait(GitExe, 'clone https://github.com/halfmanbear/SLAM.git "' + ClonePath + '"',
                      'Failed to clone SLAM repository. Please check your internet connection.') then
    Exit;

  // Verify clone was successful
  if not FileExists(ClonePath + '\main.ps1') then
  begin
    MsgBox('Repository cloned but main.ps1 not found. Installation cannot continue.', mbError, MB_OK);
    Exit;
  end;

  // Copy everything—including hidden files—into {app}
  if not ExecWithWait('cmd.exe', '/c xcopy "' + ClonePath + '\*" "' + InstallPath + '" /E /H /C /I /Y',
                      'Failed to copy files to installation directory') then
    Exit;

  // Run shortcut creation script
  ExecWithWait(PS7Path, '-ExecutionPolicy Bypass -File "' + InstallPath + '\create-shortcut.ps1"',
               'Failed to create desktop shortcut (you can create it manually later)');

  // Clean up temp clone
  ExecWithWait('cmd.exe', '/c rmdir /S /Q "' + ClonePath + '"', 'Failed to clean up temporary files');

  Result := True;
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssInstall then
  begin
    if not CloneAndCopySLAM() then
    begin
      MsgBox('SLAM installation failed. Please check the error messages above and try again.', mbError, MB_OK);
      WizardForm.Close;
    end;
  end;
end;
