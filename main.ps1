# ASCII Art
$asciiArt = @"
############################################################
#   ________  ___            __       ___      ___         #
#  /"       )|"  |          /""\     |"  \    /"  |        #
# (:   \___/ ||  |         /    \     \   \  //   |        #
#  \___  \   |:  |        /' /\  \    /\\  \/.    |        #
#   __/  \\   \  |___    //  __'  \  |: \.        |        #
#  /" \   :) ( \_|:  \  /   /  \\  \ |.  \    /:  |        #
# (_______/   \_______)(___/    \___)|___|\__/|___|        #
#                                                          #
#       - SymLink Advanced Modding for DCS -               #
############################################################

"@

# Enable long path support
function Enable-LongPaths {
    Write-Host "Enabling long path support..."
    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem" -Name "LongPathsEnabled" -Value 1
}

Enable-LongPaths

# Add Windows API DeleteFile and MoveFile functions
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class WinAPI {
    [DllImport("kernel32.dll", SetLastError=true, CharSet=CharSet.Auto)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool DeleteFile(string path);

    [DllImport("kernel32.dll", SetLastError=true, CharSet=CharSet.Auto)]
    public static extern bool MoveFile(string lpExistingFileName, string lpNewFileName);
}
"@

# Define symbolic link creation function
function New-SymbolicLink {
    param (
        [string]$Path,
        [string]$Target
    )
    New-Item -Path $Path -ItemType SymbolicLink -Value $Target -Force
}

# Define symbolic link removal function using Windows API
function Remove-SymbolicLink {
    param (
        [string]$Path
    )
    if ((Test-Path -Path $Path) -and ((Get-Item -Path $Path).Attributes -band [System.IO.FileAttributes]::ReparsePoint)) {
        $result = [WinAPI]::DeleteFile($Path)
        if ($result) {
            Write-Host "Successfully removed symbolic link: $Path"
        } else {
            $errorMessage = [System.ComponentModel.Win32Exception]::new([System.Runtime.InteropServices.Marshal]::GetLastWin32Error()).Message
            Write-Host "Failed to remove symbolic link: $errorMessage"
        }
    }
}

# Define function to remove empty directories recursively
function Remove-EmptyDirectories {
    param (
        [string]$RootPath
    )

    Get-ChildItem -Path $RootPath -Recurse -Directory | Sort-Object FullName -Descending | ForEach-Object {
        if (-not (Get-ChildItem -LiteralPath $_.FullName)) {
            Remove-Item -LiteralPath $_.FullName -Recurse -Force
            Write-Host "Removed empty directory: $_.FullName"
        }
    }
}

# Define a function to move files using the Windows API
function Move-File-With-Metadata {
    param (
        [string]$SourcePath,
        [string]$DestinationPath
    )

    if ([WinAPI]::MoveFile($SourcePath, $DestinationPath)) {
        Write-Host "Successfully moved $SourcePath to $DestinationPath with metadata updates."
        return $true
    } else {
        $errorMessage = [System.ComponentModel.Win32Exception]::new([System.Runtime.InteropServices.Marshal]::GetLastWin32Error()).Message
        Write-Host "Failed to move file: $errorMessage"
        return $false
    }
}

# Define mod installation function
function Install-Mod {
    param (
        [string]$ModName,
        [string]$ModSourcePath,
        [string]$GameDirectory,
        [string]$BackupDirectory
    )

    # Define the backup directory using the user-configurable path
    $backupDir = Join-Path -Path $BackupDirectory -ChildPath ("Backup-" + $ModName)

    # Create backup directory only if needed
    $backupNeeded = $false

    # Function to copy files and create symbolic links
    function Copy-And-Link {
        param (
            [string]$SourcePath,
            [string]$TargetPath
        )

        Get-ChildItem -LiteralPath $SourcePath -Recurse -File | ForEach-Object {
            $relativePath = $_.FullName.Substring($SourcePath.Length).TrimStart("\")
            $targetFilePath = Join-Path -Path $TargetPath -ChildPath $relativePath
            $backupFilePath = Join-Path -Path $backupDir -ChildPath $relativePath

            if (Test-Path -LiteralPath $targetFilePath) {
                $backupNeeded = $true

                # Create necessary directories in backup path
                $backupDirPath = [System.IO.Path]::GetDirectoryName($backupFilePath)
                if (-not (Test-Path -LiteralPath $backupDirPath)) {
                    New-Item -ItemType Directory -Path $backupDirPath -Force
                }

                # If target is a symbolic link, prompt the user for action
                if ((Get-Item -LiteralPath $targetFilePath).Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
                    $currentTarget = (Get-Item -LiteralPath $targetFilePath).Target
                    Write-Host "Conflict: $targetFilePath is already linked to $currentTarget"
                    $choice = Read-Host "Do you want to replace the existing link? (Enter 'yes' to replace or 'no' to keep the existing link) [default: yes]"
                    if ($choice -eq 'no' -or $choice -eq 'n') {
                        return
                    }
                }

                # Backup the existing file
                $moveSuccess = Move-File-With-Metadata -SourcePath $targetFilePath -DestinationPath $backupFilePath
                if ($moveSuccess) {
                    Write-Host "File moved successfully: $targetFilePath"
                } else {
                    Write-Host "Failed to move file: $targetFilePath"
                }

                # Remove the existing file if it was successfully moved
                if (Test-Path -LiteralPath $targetFilePath) {
                    Remove-Item -LiteralPath $targetFilePath -Force
                }
            }

            # Create necessary directories in target path
            $targetDir = [System.IO.Path]::GetDirectoryName($targetFilePath)
            if (-not (Test-Path -LiteralPath $targetDir)) {
                New-Item -ItemType Directory -Path $targetDir -Force
            }

            # Create the symbolic link
            New-SymbolicLink -Path $targetFilePath -Target $_.FullName
            Write-Host "Linked: $($_.FullName) to $targetFilePath"
        }
    }

    # Copy and link files from ModSourcePath to GameDirectory
    Copy-And-Link -SourcePath $ModSourcePath -TargetPath $GameDirectory

    # Create the backup directory if needed
    if ($backupNeeded -and -not (Test-Path -LiteralPath $backupDir)) {
        New-Item -ItemType Directory -Path $backupDir
    }

    Write-Host "Installed mod: $ModName"
}

# Define mod uninstallation function
function Uninstall-Mod {
    param (
        [string]$ModName,
        [string]$ModSourcePath,
        [string]$GameDirectory,
        [string]$BackupDirectory
    )

    # Define the backup directory using the user-configurable path
    $backupDir = Join-Path -Path $BackupDirectory -ChildPath ("Backup-" + $ModName)

    # Function to restore backup if it exists
    function Restore-Backup {
        if (Test-Path -LiteralPath $backupDir) {
            $files = Get-ChildItem -LiteralPath $backupDir -Recurse -File
            foreach ($file in $files) {
                $relativePath = $file.FullName.Substring($backupDir.Length).TrimStart("\")
                $targetFilePath = Join-Path -Path $GameDirectory -ChildPath $relativePath

                # Remove the symbolic link if it exists
                Remove-SymbolicLink -Path $targetFilePath

                # Create necessary directories in target path
                $targetDir = [System.IO.Path]::GetDirectoryName($targetFilePath)
                if (-not (Test-Path -LiteralPath $targetDir)) {
                    New-Item -ItemType Directory -Path $targetDir -Force
                }

                # Restore the backup file
                Move-File-With-Metadata -SourcePath $file.FullName -DestinationPath $targetFilePath
                Write-Host "Restored: $targetFilePath"
            }

            # Remove the backup directory
            Remove-Item -LiteralPath $backupDir -Recurse -Force
        } else {
            Write-Host "No backup found for mod: $ModName, removing symbolic links directly."
            Remove-Links-Directly
        }
    }

    # Function to remove links directly when no backup is found
    function Remove-Links-Directly {
        $symlinkPaths = Get-ChildItem -Recurse -Force -LiteralPath $GameDirectory | Where-Object { $_.Attributes -band [System.IO.FileAttributes]::ReparsePoint } | Select-Object -ExpandProperty FullName

        foreach ($symlinkPath in $symlinkPaths) {
            $relativePath = $symlinkPath.Substring($GameDirectory.Length).TrimStart("\")
            $sourceFilePath = Join-Path -Path $ModSourcePath -ChildPath $relativePath

            if (Test-Path -LiteralPath $sourceFilePath) {
                # Remove the symbolic link if it exists
                Remove-SymbolicLink -Path $symlinkPath
            }
        }
    }

    # Attempt to restore backup
    Restore-Backup

    # Verify and re-remove any remaining symlinks
    $remainingSymlinks = Get-ChildItem -Recurse -Force -LiteralPath $GameDirectory | Where-Object { $_.Attributes -band [System.IO.FileAttributes]::ReparsePoint } | Select-Object -ExpandProperty FullName
    foreach ($symlink in $remainingSymlinks) {
        $relativePath = $symlink.Substring($GameDirectory.Length).TrimStart("\")
        $sourceFilePath = Join-Path -Path $ModSourcePath -ChildPath $relativePath

        if (Test-Path -LiteralPath $sourceFilePath) {
            # Remove the symbolic link if it exists
            Remove-SymbolicLink -Path $symlink
        }
    }

    # Remove empty directories in the game directory
    Remove-EmptyDirectories -RootPath $GameDirectory

    Write-Host "Uninstalled mod: $ModName"
}

# Define mod listing function
function List-Mods {
    param (
        [string]$GameDirectory
    )
    Get-ChildItem -LiteralPath $GameDirectory -Recurse | Where-Object {
        $_.Attributes -band [System.IO.FileAttributes]::ReparsePoint
    } | ForEach-Object {
        Write-Host $_.Name
    }
}

# Read configuration file
function Read-Config {
    param (
        [string]$ConfigFilePath
    )
    $config = @{}
    if (Test-Path -LiteralPath $ConfigFilePath) {
        Get-Content -LiteralPath $ConfigFilePath | ForEach-Object {
            $_ = $_.Trim()
            if ($_.Length -gt 0 -and $_.Substring(0, 1) -ne '#') {
                $parts = $_ -split '='
                if ($parts.Length -eq 2) {
                    $config[$parts[0].Trim()] = $parts[1].Trim() -replace "%USERPROFILE%", $env:USERPROFILE
                }
            }
        }
    } else {
        Write-Host "Config file not found: $ConfigFilePath"
    }
    return $config
}

# Let the user select a game directory
function Select-Game {
    param (
        [string]$BasePath
    )
    Clear-Host
    Write-Host $asciiArt -ForegroundColor Blue
    $gamesPath = Join-Path -Path $BasePath -ChildPath 'Games'
    $games = Get-ChildItem -LiteralPath $gamesPath -Directory

    Write-Host "Available games:" -ForegroundColor Cyan
    for ($i = 0; $i -lt $games.Count; $i++) {
        Write-Host "$($i + 1). $($games[$i].Name)"
    }
    Write-Host ""
    Write-Host "q. Quit" -ForegroundColor Red

    $selectedGameIndex = Read-Host "Enter the number corresponding to the game or 'q' to quit"
    if ($selectedGameIndex -eq 'q') {
        exit
    }
    $selectedGameIndex = [int]$selectedGameIndex
    if ($selectedGameIndex -gt 0 -and $selectedGameIndex -le $games.Count) {
        return $games[$selectedGameIndex - 1].FullName
    } else {
        Write-Host "Invalid selection. Try Again." -ForegroundColor Red
        return Select-Game -BasePath $BasePath
    }
}

# Let the user select a mod parent directory (Core Mods or Saved Games Mods)
function Select-ModParent {
    param (
        [string]$gamePath
    )
    Clear-Host
    Write-Host $asciiArt -ForegroundColor Blue
    $modParents = @("Core Mods", "Saved Games Mods")

    Write-Host "Available mod parent directories:" -ForegroundColor Cyan
    for ($i = 0; $i -lt $modParents.Count; $i++) {
        Write-Host "$($i + 1). $($modParents[$i])"
    }
    Write-Host ""
    Write-Host "b. Back" -ForegroundColor Yellow

    $selectedModParentIndex = Read-Host "Enter the number corresponding to the mod parent directory or 'b' to go back"
    if ($selectedModParentIndex -eq 'b') {
        return 'back'
    }
    $selectedModParentIndex = [int]$selectedModParentIndex
    if ($selectedModParentIndex -gt 0 -and $selectedModParentIndex -le $modParents.Count) {
        return Join-Path -Path $gamePath -ChildPath $modParents[$selectedModParentIndex - 1]
    } else {
        Write-Host "Invalid selection. Try Again." -ForegroundColor Red
        return Select-ModParent -gamePath $gamePath
    }
}

# Check if mod is installed by looking for a specific symbolic link
function Is-Mod-Installed {
    param (
        [string]$ModPath,
        [string]$GameDirectory
    )

    $sampleFile = Get-ChildItem -LiteralPath $ModPath -Recurse -File | Select-Object -First 1
    if ($sampleFile) {
        $relativePath = $sampleFile.FullName.Substring($ModPath.Length).TrimStart("\")
        $linkPath = Join-Path -Path $GameDirectory -ChildPath $relativePath
        return (Test-Path -LiteralPath $linkPath) -and ((Get-Item -LiteralPath $linkPath).Attributes -band [System.IO.FileAttributes]::ReparsePoint)
    }
    return $false
}

# Let the user select a mod directory with installed mods marked with an asterisk
function Select-Mod {
    param (
        [string]$modParentPath,
        [string]$gameDirectory
    )
    Clear-Host
    Write-Host $asciiArt -ForegroundColor Blue
    $mods = Get-ChildItem -LiteralPath $modParentPath -Directory | Where-Object { $_.Name -notmatch '^Backup-' }
    $modList = @()

    foreach ($mod in $mods) {
        $modName = $mod.Name
        if (Is-Mod-Installed -ModPath $mod.FullName -GameDirectory $gameDirectory) {
            $modName = "* " + $modName
            Write-Host "$($modList.Count + 1). $modName" -ForegroundColor Green
        } else {
            Write-Host "$($modList.Count + 1). $modName"
        }
        $modList += $modName
    }

    Write-Host ""
    Write-Host "b. Back" -ForegroundColor Yellow

    $selectedModIndex = Read-Host "Enter the number corresponding to the mod or 'b' to go back"
    if ($selectedModIndex -eq 'b') {
        return 'back'
    }
    $selectedModIndex = [int]$selectedModIndex
    if ($selectedModIndex -gt 0 -and $selectedModIndex -le $modList.Count) {
        return $mods[$selectedModIndex - 1].FullName
    } else {
        Write-Host "Invalid selection. Try Again." -ForegroundColor Red
        return Select-Mod -modParentPath $modParentPath -gameDirectory $gameDirectory
    }
}

# Main script
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
if (-not $scriptDir) {
    $scriptDir = Get-Location
}

# Read configuration
$configFilePath = Join-Path -Path $scriptDir -ChildPath 'config.txt'
$config = Read-Config -ConfigFilePath $configFilePath

if (-not $config.ContainsKey('CoreGameDirectory') -or [string]::IsNullOrEmpty($config['CoreGameDirectory'])) {
    Write-Host "CoreGameDirectory not found in config file. Exiting."
    exit
}
if (-not $config.ContainsKey('SavedGamesDirectory') -or [string]::IsNullOrEmpty($config['SavedGamesDirectory'])) {
    Write-Host "SavedGamesDirectory not found in config file. Exiting."
    exit
}

while ($true) {
    $gamePath = Select-Game -BasePath $scriptDir
    $selectedGameName = Split-Path -Path $gamePath -Leaf
    $modParentPath = Select-ModParent -gamePath $gamePath

    if ($modParentPath -eq 'back') {
        continue
    }

    if ($modParentPath -like "*Core Mods*") {
        $gameDirectory = $config['CoreGameDirectory']
    } elseif ($modParentPath -like "*Saved Games Mods*") {
        $gameDirectory = $config['SavedGamesDirectory']
    } else {
        Write-Host "Invalid mod parent directory. Try Again." -ForegroundColor Red
        continue
    }

    while ($true) {
        $modPath = Select-Mod -modParentPath $modParentPath -gameDirectory $gameDirectory

        if ($modPath -eq 'back') {
            break
        }

        # Determine if the mod is currently installed
        $modName = Split-Path -Path $modPath -Leaf
        $backupDirectory = Join-Path -Path $gamePath -ChildPath "Backup"
        $modInstalled = Is-Mod-Installed -ModPath $modPath -GameDirectory $gameDirectory

        # Toggle mod installation state
        if ($modInstalled) {
            Uninstall-Mod -ModName $modName -ModSourcePath $modPath -GameDirectory $gameDirectory -BackupDirectory $backupDirectory
        } else {
            Install-Mod -ModName $modName -ModSourcePath $modPath -GameDirectory $gameDirectory -BackupDirectory $backupDirectory
        }

        Write-Host "Press any key to return to the mod selection menu..."
        [void][System.Console]::ReadKey($true)
    }
}
