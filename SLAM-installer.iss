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
; No files are directly included because we're downloading them from GitHub

[Run]
Filename: "explorer.exe"; Parameters: "{app}"; Flags: postinstall nowait; Description: "Open installation folder"
Filename: "{app}\config.txt"; Flags: postinstall shellexec; Description: "Open config.txt"

[Code]
const
  PS7Path = 'C:\Program Files\PowerShell\7\pwsh.exe';
  GitExe = 'C:\Program Files\Git\cmd\git.exe';
  WingetExe = 'winget';
  TempGitCloneDir = '{tmp}\SLAMTempClone';  // Temporary directory for cloning

procedure ExecWithWait(FilePath: String; Parameters: String);
var
  ResultCode: Integer;
begin
  if Exec(FilePath, Parameters, '', SW_SHOW, ewWaitUntilTerminated, ResultCode) then
  begin
    Log('Executed: ' + FilePath + ' with parameters: ' + Parameters);
    if ResultCode <> 0 then
      MsgBox('Command failed with exit code: ' + IntToStr(ResultCode), mbError, MB_OK);
  end
  else
    MsgBox('Error while executing: ' + FilePath, mbError, MB_OK);
end;

function IsInstalled(FilePath: String): Boolean;
begin
  Result := FileExists(FilePath);
end;

function CheckGitInstalled(): Boolean;
begin
  Result := IsInstalled(GitExe);
end;

function CheckPowerShell7Installed(): Boolean;
begin
  Result := IsInstalled(PS7Path);
end;

function CheckWingetInstalled(): Boolean;
var
  ResultCode: Integer;
begin
  Result := Exec('cmd.exe', '/c winget --version', '', SW_HIDE, ewWaitUntilTerminated, ResultCode) and (ResultCode = 0);
end;

procedure InstallGitWithWinget();
begin
  if CheckWingetInstalled() then
  begin
    Log('Installing Git using winget...');
    ExecWithWait(WingetExe, 'install --id Git.Git -e --source winget');
  end
  else
    MsgBox('Winget is not installed or not available. Please install Git manually.', mbError, MB_OK);
end;

procedure InstallPowerShell7WithWinget();
begin
  if CheckWingetInstalled() then
  begin
    Log('Installing PowerShell 7 using winget...');
    ExecWithWait(WingetExe, 'install --id Microsoft.PowerShell -e --source winget');
  end
  else
    MsgBox('Winget is not installed or not available. Please install PowerShell 7 manually.', mbError, MB_OK);
end;

procedure CloneToTempDirectory();
begin
  if not DirExists(ExpandConstant(TempGitCloneDir)) then
    if not CreateDir(ExpandConstant(TempGitCloneDir)) then
    begin
      MsgBox('Failed to create temporary clone directory. Please check permissions.', mbError, MB_OK);
      Exit;
    end;

  Log('Cloning SLAM repository from GitHub to temporary directory...');
  ExecWithWait(GitExe, 'clone https://github.com/halfmanbear/SLAM.git "' + ExpandConstant(TempGitCloneDir) + '"');
end;

procedure CopyDirTree(SourcePath, DestPath: string);
var
  FindRec: TFindRec;
begin
  if not DirExists(DestPath) then
    CreateDir(DestPath);

  if FindFirst(SourcePath + '*', FindRec) then
  begin
    try
      repeat
        if (FindRec.Name <> '.') and (FindRec.Name <> '..') then
        begin
          if (FindRec.Attributes and FILE_ATTRIBUTE_DIRECTORY) <> 0 then
          begin
            CopyDirTree(SourcePath + FindRec.Name + '\', DestPath + FindRec.Name + '\');
          end
          else
          begin
            if not FileCopy(SourcePath + FindRec.Name, DestPath + FindRec.Name, False) then
              MsgBox('Failed to copy file: ' + SourcePath + FindRec.Name, mbError, MB_OK);
          end;
        end;
      until not FindNext(FindRec);
    finally
      FindClose(FindRec);
    end;
  end;
end;

procedure CopyTempToInstallDir();
var
  InstallDir: String;
begin
  InstallDir := ExpandConstant('{app}');
  Log('Copying files to the installation directory: ' + InstallDir);
  CopyDirTree(ExpandConstant(TempGitCloneDir) + '\', InstallDir + '\');
end;

procedure DownloadAndInstallSLAM();
var
  InstallDir: String;
begin
  InstallDir := ExpandConstant('{app}');

  // Ensure Git is installed
  if not CheckGitInstalled() then
  begin
    InstallGitWithWinget();
    if not CheckGitInstalled() then
    begin
      MsgBox('Git could not be installed automatically. Please install Git.', mbError, MB_OK);
      Exit;
    end;
  end;

  // Proceed to clone and copy files
  CloneToTempDirectory();
  if DirExists(ExpandConstant(TempGitCloneDir)) then
  begin
    CopyTempToInstallDir();
  end
  else
  begin
    MsgBox('No files were cloned. Aborting installation.', mbError, MB_OK);
    Exit;
  end;

  // Ensure PowerShell 7 is installed
  if not CheckPowerShell7Installed() then
  begin
    InstallPowerShell7WithWinget();
    if not CheckPowerShell7Installed() then
    begin
      MsgBox('PowerShell 7 could not be installed automatically. Please install PowerShell 7.', mbError, MB_OK);
      Exit;
    end;
  end;

  // Execute the create-shortcut.ps1 script
  ExecWithWait(PS7Path, '-ExecutionPolicy Bypass -File "' + InstallDir + '\create-shortcut.ps1"');
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssInstall then
  begin
    DownloadAndInstallSLAM();  // Download and install SLAM
  end;
end;
