# Define symbolic link creation function
function New-SymbolicLink {
    param (
        [string]$Path,
        [string]$Target
    )
    New-Item -Path $Path -ItemType SymbolicLink -Value $Target -Force
}

# Define symbolic link removal function
function Remove-SymbolicLink {
    param (
        [string]$Path
    )
    if ((Test-Path -Path $Path) -and ((Get-Item -Path $Path).Attributes -band [System.IO.FileAttributes]::ReparsePoint)) {
        Remove-Item -Path $Path -Force
    }
}

# Define function to remove empty directories recursively
function Remove-EmptyDirectories {
    param (
        [string]$RootPath
    )

    Get-ChildItem -Path $RootPath -Recurse -Directory | Sort-Object FullName -Descending | ForEach-Object {
        if (-not (Get-ChildItem -Path $_.FullName)) {
            Remove-Item -Path $_.FullName -Recurse -Force
            Write-Host "Removed empty directory: $_.FullName"
        }
    }
}

# Define mod installation function
function Install-Mod {
    param (
        [string]$ModName,
        [string]$ModSourcePath,
        [string]$GameDirectory
    )

    # Extract the last directory name from ModSourcePath to use in backup directory name
    $modSourceDirName = Split-Path -Path $ModSourcePath -Leaf
    $backupDirParent = Split-Path -Path $ModSourcePath -Parent
    $backupDir = Join-Path -Path $backupDirParent -ChildPath "Backup-$modSourceDirName"

    # Create backup directory only if needed
    $backupNeeded = $false

    # Function to copy files and create symbolic links
    function Copy-And-Link {
        param (
            [string]$SourcePath,
            [string]$TargetPath
        )

        Get-ChildItem -Path $SourcePath -Recurse -File | ForEach-Object {
            $relativePath = $_.FullName.Substring($SourcePath.Length).TrimStart("\")
            $targetFilePath = Join-Path -Path $TargetPath -ChildPath $relativePath
            $backupFilePath = Join-Path -Path $backupDir -ChildPath $relativePath

            if (Test-Path -Path $targetFilePath) {
                $backupNeeded = $true

                # Create necessary directories in backup path
                $backupDirPath = Split-Path -Path $backupFilePath -Parent
                if (-not (Test-Path -Path $backupDirPath)) {
                    New-Item -ItemType Directory -Path $backupDirPath -Force
                }

                # If target is a symbolic link, prompt the user for action
                if ((Get-Item -Path $targetFilePath).Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
                    $currentTarget = (Get-Item -Path $targetFilePath).Target
                    Write-Host "Conflict: $targetFilePath is already linked to $currentTarget"
                    $choice = Read-Host "Do you want to replace the existing link? (Enter 'yes' to replace or 'no' to keep the existing link)"
                    if ($choice -ne 'yes') {
                        return
                    }
                }

                # Backup the existing file
                Copy-Item -Path $targetFilePath -Destination $backupFilePath -Force
                # Remove the existing file
                Remove-Item -Path $targetFilePath -Force
            }

            # Create necessary directories in target path
            $targetDir = Split-Path -Path $targetFilePath -Parent
            if (-not (Test-Path -Path $targetDir)) {
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
    if ($backupNeeded -and -not (Test-Path -Path $backupDir)) {
        New-Item -ItemType Directory -Path $backupDir
    }

    Write-Host "Installed mod: $ModName"
}

# Define mod uninstallation function
function Uninstall-Mod {
    param (
        [string]$ModName,
        [string]$ModSourcePath,
        [string]$GameDirectory
    )

    # Extract the last directory name from ModSourcePath to use in backup directory name
    $modSourceDirName = Split-Path -Path $ModSourcePath -Leaf
    $backupDirParent = Split-Path -Path $ModSourcePath -Parent
    $backupDir = Join-Path -Path $backupDirParent -ChildPath "Backup-$modSourceDirName"

    # Restore backup if it exists
    if (Test-Path -Path $backupDir) {
        Get-ChildItem -Path $backupDir -Recurse -File | ForEach-Object {
            $relativePath = $_.FullName.Substring($backupDir.Length).TrimStart("\")
            $targetFilePath = Join-Path -Path $GameDirectory -ChildPath $relativePath

            # Remove the symbolic link if it exists
            Remove-SymbolicLink -Path $targetFilePath

            # Create necessary directories in target path
            $targetDir = Split-Path -Path $targetFilePath -Parent
            if (-not (Test-Path -Path $targetDir)) {
                New-Item -ItemType Directory -Path $targetDir -Force
            }

            # Restore the backup file
            Copy-Item -Path $_.FullName -Destination $targetFilePath -Force
            Write-Host "Restored: $targetFilePath"
        }

        # Remove the backup directory
        Remove-Item -Path $backupDir -Recurse -Force
    } else {
        # No backup found, remove the symbolic links directly
        Write-Host "No backup found for mod: $ModName, removing symbolic links directly."

        Get-ChildItem -Path $ModSourcePath -Recurse -File | ForEach-Object {
            $relativePath = $_.FullName.Substring($ModSourcePath.Length).TrimStart("\")
            $targetFilePath = Join-Path -Path $GameDirectory -ChildPath $relativePath

            # Remove the symbolic link if it exists
            Remove-SymbolicLink -Path $targetFilePath
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
    Get-ChildItem -Path $GameDirectory -Recurse | Where-Object {
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
    if (Test-Path -Path $ConfigFilePath) {
        Get-Content -Path $ConfigFilePath | ForEach-Object {
            $parts = $_ -split '='
            if ($parts.Length -eq 2) {
                $config[$parts[0].Trim()] = $parts[1].Trim() -replace "%USERPROFILE%", $env:USERPROFILE
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
    $gamesPath = Join-Path -Path $BasePath -ChildPath 'Games'
    $games = Get-ChildItem -Path $gamesPath -Directory

    Write-Host "Available games:"
    for ($i = 0; $i -lt $games.Count; $i++) {
        Write-Host "$($i + 1). $($games[$i].Name)"
    }

    $selectedGameIndex = [int](Read-Host "Enter the number corresponding to the game")
    if ($selectedGameIndex -gt 0 -and $selectedGameIndex -le $games.Count) {
        return $games[$selectedGameIndex - 1].FullName
    } else {
        Write-Host "Invalid selection. Exiting."
        exit
    }
}

# Let the user select a mod parent directory (Core Mods or Save Game Mods)
function Select-ModParent {
    param (
        [string]$gamePath
    )
    $modParents = @("Core Mods", "Save Game Mods")

    Write-Host "Available mod parent directories:"
    for ($i = 0; $i -lt $modParents.Count; $i++) {
        Write-Host "$($i + 1). $($modParents[$i])"
    }

    $selectedModParentIndex = [int](Read-Host "Enter the number corresponding to the mod parent directory")
    if ($selectedModParentIndex -gt 0 -and $selectedModParentIndex -le $modParents.Count) {
        return Join-Path -Path $gamePath -ChildPath $modParents[$selectedModParentIndex - 1]
    } else {
        Write-Host "Invalid selection. Exiting."
        exit
    }
}

# Check if mod is installed by looking for a specific symbolic link
function Is-Mod-Installed {
    param (
        [string]$ModPath,
        [string]$GameDirectory
    )

    $sampleFile = Get-ChildItem -Path $ModPath -Recurse -File | Select-Object -First 1
    if ($sampleFile) {
        $relativePath = $sampleFile.FullName.Substring($ModPath.Length).TrimStart("\")
        $linkPath = Join-Path -Path $GameDirectory -ChildPath $relativePath
        return (Test-Path -Path $linkPath) -and ((Get-Item -Path $linkPath).Attributes -band [System.IO.FileAttributes]::ReparsePoint)
    }
    return $false
}

# Let the user select a mod directory with installed mods marked with an asterisk
function Select-Mod {
    param (
        [string]$modParentPath,
        [string]$gameDirectory
    )
    $mods = Get-ChildItem -Path $modParentPath -Directory | Where-Object { $_.Name -notmatch '^Backup-' }
    $modList = @()

    foreach ($mod in $mods) {
        $modName = $mod.Name
        if (Is-Mod-Installed -ModPath $mod.FullName -GameDirectory $gameDirectory) {
            $modName = "* " + $modName
        }
        $modList += $modName
    }

    Write-Host "Available mods:"
    for ($i = 0; $i -lt $modList.Count; $i++) {
        Write-Host "$($i + 1). $($modList[$i])"
    }

    $selectedModIndex = [int](Read-Host "Enter the number corresponding to the mod")
    if ($selectedModIndex -gt 0 -and $selectedModIndex -le $modList.Count) {
        return $mods[$selectedModIndex - 1].FullName
    } else {
        Write-Host "Invalid selection. Exiting."
        exit
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
if (-not $config.ContainsKey('SaveGameDirectory') -or [string]::IsNullOrEmpty($config['SaveGameDirectory'])) {
    Write-Host "SaveGameDirectory not found in config file. Exiting."
    exit
}

while ($true) {
    $gamePath = Select-Game -BasePath $scriptDir
    $modParentPath = Select-ModParent -gamePath $gamePath

    if ($modParentPath -like "*Core Mods*") {
        $gameDirectory = $config['CoreGameDirectory']
    } elseif ($modParentPath -like "*Save Game Mods*") {
        $gameDirectory = $config['SaveGameDirectory']
    } else {
        Write-Host "Invalid mod parent directory. Exiting."
        exit
    }

    $modPath = Select-Mod -modParentPath $modParentPath -gameDirectory $gameDirectory

    # Determine if the mod is currently installed
    $modName = Split-Path -Path $modPath -Leaf
    $modInstalled = Is-Mod-Installed -ModPath $modPath -GameDirectory $gameDirectory

    # Toggle mod installation state
    if ($modInstalled) {
        Uninstall-Mod -ModName $modName -ModSourcePath $modPath -GameDirectory $gameDirectory
    } else {
        Install-Mod -ModName $modName -ModSourcePath $modPath -GameDirectory $gameDirectory
    }
}
