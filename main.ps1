# Enable long path support
function Enable-LongPaths {
    Write-Host "Enabling long path support..."
    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem" -Name "LongPathsEnabled" -Value 1 -Force
}
Enable-LongPaths

# ASCII Art Banner
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

# Windows API Functions
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

# Helper Functions
function New-SymbolicLink {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Target
    )
    New-Item -Path $Path -ItemType SymbolicLink -Value $Target -Force | Out-Null
}

function Remove-SymbolicLink {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)][string]$Path
    )
    if ((Test-Path -LiteralPath $Path) -and ((Get-Item -LiteralPath $Path).Attributes -band [System.IO.FileAttributes]::ReparsePoint)) {
        $result = [WinAPI]::DeleteFile($Path)
        if (-not $result) {
            $errorMessage = [System.ComponentModel.Win32Exception]::new([System.Runtime.InteropServices.Marshal]::GetLastWin32Error()).Message
            throw "Failed to remove symbolic link: $errorMessage"
        }
    }
}

function Move-File-With-Metadata {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)][string]$SourcePath,
        [Parameter(Mandatory = $true)][string]$DestinationPath
    )
    $result = [WinAPI]::MoveFile($SourcePath, $DestinationPath)
    if (-not $result) {
        $errorMessage = [System.ComponentModel.Win32Exception]::new([System.Runtime.InteropServices.Marshal]::GetLastWin32Error()).Message
        throw "Failed to move file: $errorMessage"
    }
}

function Show-ProgressBar {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)][int]$CurrentStep,
        [Parameter(Mandatory = $true)][int]$TotalSteps,
        [Parameter(Mandatory = $true)][string]$Activity,
        [Parameter()][string]$CurrentFile = ''
    )
    if ($TotalSteps -le 0) {
        $TotalSteps = 1  # Prevent division by zero
    }
    $percentComplete = [math]::Round(($CurrentStep / $TotalSteps) * 100)
    Write-Progress -Activity $Activity -Status "$percentComplete% Complete - Processing $CurrentFile" -PercentComplete $percentComplete
}

# Optimized Function to remove empty directories recursively
function Remove-EmptyDirectories {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)][string]$RootPath
    )

    $totalDirsRemoved = 0

    function Remove-EmptyDirsRecursively($path) {
        $subDirs = [System.IO.Directory]::GetDirectories($path)
        foreach ($dir in $subDirs) {
            Remove-EmptyDirsRecursively $dir
        }

        $entries = [System.IO.Directory]::EnumerateFileSystemEntries($path)
        if ($entries.Count -eq 0) {
            try {
                [System.IO.Directory]::Delete($path)
                $totalDirsRemoved++
            } catch {
                Write-Verbose "Failed to remove directory: $path - $_"
            }
        }
    }

    Remove-EmptyDirsRecursively $RootPath
}

# Function to read the configuration file
function Read-Config {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)][string]$ConfigFilePath
    )
    $config = @{}
    if (Test-Path -LiteralPath $ConfigFilePath) {
        Get-Content -LiteralPath $ConfigFilePath | ForEach-Object {
            $_ = $_.Trim()
            if ($_.Length -gt 0 -and $_.Substring(0, 1) -ne '#') {
                $parts = $_ -split '='
                if ($parts.Length -eq 2) {
                    $key = $parts[0].Trim()
                    $value = $parts[1].Trim()
                    $value = $value -replace "%USERPROFILE%", $env:USERPROFILE
                    $config[$key] = $value
                }
            }
        }
    } else {
        Write-Host "Config file not found: $ConfigFilePath"
    }
    return $config
}

# Function to check if a mod is installed
function Is-Mod-Installed {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)][string]$ModPath,
        [Parameter(Mandatory = $true)][string]$GameDirectory
    )

    $sampleFile = Get-ChildItem -LiteralPath $ModPath -Recurse -File | Select-Object -First 1
    if ($sampleFile) {
        $relativePath = $sampleFile.FullName.Substring($ModPath.Length).TrimStart("\")
        $linkPath = Join-Path -Path $GameDirectory -ChildPath $relativePath
        if (Test-Path -LiteralPath $linkPath) {
            $linkItem = Get-Item -LiteralPath $linkPath
            if ($linkItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
                $targetPath = (Get-Item $linkItem.FullName -Force).Target
                return $targetPath.StartsWith($ModPath)
            }
        }
    }
    return $false
}

# Function to remove leftover symbolic links directly
function Remove-Links-Directly {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)][string]$GameDirectory,
        [Parameter(Mandatory = $true)][string]$ModSourcePath
    )

    $symlinkPaths = Get-ChildItem -Recurse -Force -LiteralPath $GameDirectory | Where-Object { $_.Attributes -band [System.IO.FileAttributes]::ReparsePoint } | Select-Object -ExpandProperty FullName

    $totalLinks = $symlinkPaths.Count
    if ($totalLinks -eq 0) { $totalLinks = 1 }  # Prevent division by zero
    $currentStep = 0

    foreach ($symlinkPath in $symlinkPaths) {
        $currentStep++
        Show-ProgressBar -CurrentStep $currentStep -TotalSteps $totalLinks -Activity "Uninstalling Mod - Removing Links" -CurrentFile $symlinkPath

        $relativePath = $symlinkPath.Substring($GameDirectory.Length).TrimStart("\")
        $sourceFilePath = Join-Path -Path $ModSourcePath -ChildPath $relativePath

        if (Test-Path -LiteralPath $sourceFilePath) {
            Remove-SymbolicLink -Path $symlinkPath
            Write-Verbose "Removed leftover symbolic link: $symlinkPath"
        }
    }

    # Ensure progress bar is complete
    Show-ProgressBar -CurrentStep $totalLinks -TotalSteps $totalLinks -Activity "Uninstalling Mod - Removing Links" -CurrentFile $null

    # Clear the progress bar
    Write-Progress -Activity "Uninstalling Mod - Removing Links" -Completed
}

# Function to install a mod
function Install-Mod {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)][string]$ModName,
        [Parameter(Mandatory = $true)][string]$ModSourcePath,
        [Parameter(Mandatory = $true)][string]$GameDirectory,
        [Parameter(Mandatory = $true)][string]$BackupDirectory
    )

    $backupDir = Join-Path -Path $BackupDirectory -ChildPath ("Backup-" + $ModName)
    $files = Get-ChildItem -LiteralPath $ModSourcePath -Recurse -File
    $totalFiles = $files.Count
    if ($totalFiles -eq 0) { $totalFiles = 1 } # Prevent division by zero
    $currentStep = 0

    foreach ($file in $files) {
        $currentStep++
        Show-ProgressBar -CurrentStep $currentStep -TotalSteps $totalFiles -Activity "Installing $ModName" -CurrentFile $file.FullName

        $relativePath = $file.FullName.Substring($ModSourcePath.Length).TrimStart("\")
        $targetFilePath = Join-Path -Path $GameDirectory -ChildPath $relativePath
        $backupFilePath = Join-Path -Path $backupDir -ChildPath $relativePath

        if (Test-Path -LiteralPath $targetFilePath) {
            # Backup existing file
            $backupDirPath = Split-Path -Path $backupFilePath -Parent
            if (-not (Test-Path -LiteralPath $backupDirPath)) {
                New-Item -ItemType Directory -Path $backupDirPath -Force | Out-Null
            }

            # Remove symbolic link if it exists
            Remove-SymbolicLink -Path $targetFilePath

            # Move file to backup
            Move-File-With-Metadata -SourcePath $targetFilePath -DestinationPath $backupFilePath
        }

        # Ensure target directory exists
        $targetDir = Split-Path -Path $targetFilePath -Parent
        if (-not (Test-Path -LiteralPath $targetDir)) {
            New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
        }

        # Create symbolic link
        New-SymbolicLink -Path $targetFilePath -Target $file.FullName
    }

    # Ensure progress bar is complete
    Show-ProgressBar -CurrentStep $totalFiles -TotalSteps $totalFiles -Activity "Installing $ModName" -CurrentFile $null

    # Clear the progress bar
    Write-Progress -Activity "Installing $ModName" -Completed

    Write-Host "Installed mod: $ModName" -ForegroundColor Green
}

# Function to uninstall a mod
function Uninstall-Mod {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)][string]$ModName,
        [Parameter(Mandatory = $true)][string]$ModSourcePath,
        [Parameter(Mandatory = $true)][string]$GameDirectory,
        [Parameter(Mandatory = $true)][string]$BackupDirectory
    )

    $backupDir = Join-Path -Path $BackupDirectory -ChildPath ("Backup-" + $ModName)

    # Restore backup files
    if (Test-Path -LiteralPath $backupDir) {
        $files = Get-ChildItem -LiteralPath $backupDir -Recurse -File
        $totalFiles = $files.Count
        $currentStep = 0

        if ($totalFiles -gt 0) {
            foreach ($file in $files) {
                $currentStep++
                Show-ProgressBar -CurrentStep $currentStep -TotalSteps $totalFiles -Activity "Uninstalling $ModName" -CurrentFile $file.FullName

                $relativePath = $file.FullName.Substring($backupDir.Length).TrimStart("\")
                $targetFilePath = Join-Path -Path $GameDirectory -ChildPath $relativePath

                Remove-SymbolicLink -Path $targetFilePath

                # Ensure target directory exists
                $targetDir = Split-Path -Path $targetFilePath -Parent
                if (-not (Test-Path -LiteralPath $targetDir)) {
                    New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
                }

                # Move backup file back to original location
                Move-File-With-Metadata -SourcePath $file.FullName -DestinationPath $targetFilePath
            }

            # Ensure progress bar is complete
            Show-ProgressBar -CurrentStep $totalFiles -TotalSteps $totalFiles -Activity "Uninstalling $ModName" -CurrentFile $null

            # Clear the progress bar
            Write-Progress -Activity "Uninstalling $ModName" -Completed
        }

        # Remove backup directory
        Remove-Item -LiteralPath $backupDir -Recurse -Force
    }

    # Remove any remaining symbolic links
    Remove-Links-Directly -GameDirectory $GameDirectory -ModSourcePath $ModSourcePath

    # Clean up empty directories
    Remove-EmptyDirectories -RootPath $GameDirectory

    # Clear any progress bar if it wasn't already
    Write-Progress -Activity "Uninstalling $ModName" -Completed

    Write-Host "Uninstalled mod: $ModName" -ForegroundColor Green
}

# Function to find mod conflicts at the mod level
function Find-Mod-Conflicts {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)][array]$Mods
    )

    $fileMappings = @{}
    $modConflicts = @{}

    foreach ($mod in $Mods) {
        $modName = $mod.Name
        $files = Get-ChildItem -LiteralPath $mod.FullName -Recurse -File

        foreach ($file in $files) {
            $relativePath = $file.FullName.Substring($mod.FullName.Length).TrimStart("\").ToLower()

            if ($fileMappings.ContainsKey($relativePath)) {
                $existingModName = $fileMappings[$relativePath]
                if ($existingModName -ne $modName) {
                    if (-not $modConflicts.ContainsKey($modName)) {
                        $modConflicts[$modName] = @()
                    }
                    if (-not $modConflicts[$modName].Contains($existingModName)) {
                        $modConflicts[$modName] += $existingModName
                    }

                    if (-not $modConflicts.ContainsKey($existingModName)) {
                        $modConflicts[$existingModName] = @()
                    }
                    if (-not $modConflicts[$existingModName].Contains($modName)) {
                        $modConflicts[$existingModName] += $modName
                    }
                }
            } else {
                $fileMappings[$relativePath] = $modName
            }
        }
    }

    return $modConflicts
}

# Function to get a list of installed mods
function Get-Installed-Mods {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)][string]$GameDirectory,
        [Parameter(Mandatory = $true)][string]$ModParentPath
    )

    $installedMods = @()
    $modDirs = Get-ChildItem -LiteralPath $ModParentPath -Directory | Where-Object { $_.Name -notmatch '^Backup-' }

    foreach ($modDir in $modDirs) {
        $modPath = $modDir.FullName
        $modName = $modDir.Name
        if (Is-Mod-Installed -ModPath $modPath -GameDirectory $GameDirectory) {
            $installedMods += $modName
        }
    }
    return $installedMods
}

# Function to find conflicts between a mod to install and installed mods
function Find-Mod-Conflicts-With-Installed {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$ModToInstall,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [array]$InstalledMods,

        [Parameter(Mandatory = $true)]
        [string]$ModParentPath
    )

    $modToInstallName = Split-Path -Path $ModToInstall -Leaf
    $modToInstallFiles = Get-ChildItem -LiteralPath $ModToInstall -Recurse -File | ForEach-Object {
        $_.FullName.Substring($ModToInstall.Length).TrimStart("\").ToLower()
    }

    $conflictingMods = @()

    foreach ($installedModName in $InstalledMods) {
        if ($installedModName -eq $modToInstallName) {
            continue
        }

        $installedModPath = Join-Path -Path $ModParentPath -ChildPath $installedModName

        $installedModFiles = Get-ChildItem -LiteralPath $installedModPath -Recurse -File | ForEach-Object {
            $_.FullName.Substring($installedModPath.Length).TrimStart("\").ToLower()
        }

        $conflicts = $modToInstallFiles | Where-Object { $installedModFiles -contains $_ }
        if ($conflicts.Count -gt 0) {
            $conflictingMods += $installedModName
        }
    }
    return $conflictingMods | Select-Object -Unique
}


# User Interface Functions
function Select-Game {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)][string]$BasePath
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

    while ($true) {
        $selection = Read-Host "Enter the number corresponding to the game or 'q' to quit"
        if ($selection -eq 'q') {
            exit
        } elseif ([int]::TryParse($selection, [ref]$null)) {
            $selectedGameIndex = [int]$selection
            if ($selectedGameIndex -gt 0 -and $selectedGameIndex -le $games.Count) {
                return $games[$selectedGameIndex - 1].FullName
            } else {
                Write-Host "Invalid selection. Try Again." -ForegroundColor Red
            }
        } else {
            Write-Host "Invalid input. Try Again." -ForegroundColor Red
        }
    }
}

function Select-ModParent {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)][string]$GamePath
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

    while ($true) {
        $selection = Read-Host "Enter the number corresponding to the mod parent directory or 'b' to go back"
        if ($selection -eq 'b') {
            return 'back'
        } elseif ([int]::TryParse($selection, [ref]$null)) {
            $selectedIndex = [int]$selection
            if ($selectedIndex -gt 0 -and $selectedIndex -le $modParents.Count) {
                return Join-Path -Path $GamePath -ChildPath $modParents[$selectedIndex - 1]
            } else {
                Write-Host "Invalid selection. Try Again." -ForegroundColor Red
            }
        } else {
            Write-Host "Invalid input. Try Again." -ForegroundColor Red
        }
    }
}

function Select-Mod {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)][string]$ModParentPath,
        [Parameter(Mandatory = $true)][string]$GameDirectory
    )

    Clear-Host
    Write-Host $asciiArt -ForegroundColor Blue
    $mods = Get-ChildItem -LiteralPath $ModParentPath -Directory | Where-Object { $_.Name -notmatch '^Backup-' }
    $modList = @()

    Write-Host "Available mods:" -ForegroundColor Cyan
    for ($i = 0; $i -lt $mods.Count; $i++) {
        $mod = $mods[$i]
        $modName = $mod.Name
        if (Is-Mod-Installed -ModPath $mod.FullName -GameDirectory $GameDirectory) {
            $modName = "* " + $modName
            Write-Host "$($i + 1). $modName" -ForegroundColor Green
        } else {
            Write-Host "$($i + 1). $modName"
        }
        $modList += $modName
    }

    # Add options for Install All and Uninstall All
    Write-Host ""
    Write-Host "a. Install All Mods" -ForegroundColor Yellow
    Write-Host "u. Uninstall All Mods" -ForegroundColor Yellow
    Write-Host "b. Back" -ForegroundColor Yellow

    while ($true) {
        $selection = Read-Host "Enter the number of a mod, 'a' to install all, 'u' to uninstall all, or 'b' to go back"
        if ($selection -eq 'b') {
            return 'back'
        } elseif ($selection -eq 'a') {
            return 'install_all'
        } elseif ($selection -eq 'u') {
            return 'uninstall_all'
        } elseif ([int]::TryParse($selection, [ref]$null)) {
            $selectedIndex = [int]$selection
            if ($selectedIndex -gt 0 -and $selectedIndex -le $mods.Count) {
                return $mods[$selectedIndex - 1].FullName
            } else {
                Write-Host "Invalid selection. Try again." -ForegroundColor Red
            }
        } else {
            Write-Host "Invalid input. Try again." -ForegroundColor Red
        }
    }
}

# Main Script
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
if (-not $scriptDir) {
    $scriptDir = Get-Location
}

# Read Configuration (using config.txt)
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

# Main Loop
while ($true) {
    $gamePath = Select-Game -BasePath $scriptDir
    $selectedGameName = Split-Path -Path $gamePath -Leaf

    while ($true) {
        $modParentPath = Select-ModParent -GamePath $gamePath
        if ($modParentPath -eq 'back') {
            break  # Go back to game selection
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
            $modSelection = Select-Mod -ModParentPath $modParentPath -GameDirectory $gameDirectory
            if ($modSelection -eq 'back') {
                break  # Go back to mod parent selection
            } elseif ($modSelection -eq 'install_all') {
                $mods = Get-ChildItem -LiteralPath $modParentPath -Directory | Where-Object { $_.Name -notmatch '^Backup-' }
                $modsToInstall = @()
                foreach ($mod in $mods) {
                    if (-not (Is-Mod-Installed -ModPath $mod.FullName -GameDirectory $gameDirectory)) {
                        $modsToInstall += $mod
                    } else {
                        Write-Host "$($mod.Name) is already installed." -ForegroundColor Yellow
                    }
                }

                # Check for conflicts at mod level
                $modConflicts = Find-Mod-Conflicts -Mods $modsToInstall

                if ($modConflicts.Count -gt 0) {
                    Write-Host "Conflicts detected among mods. Please resolve them." -ForegroundColor Red
                    $modsToInstallFinal = @()
                    $modsToSkip = @()

                    $processedMods = @{}

                    foreach ($modName in $modConflicts.Keys) {
                        if ($processedMods.ContainsKey($modName)) {
                            continue
                        }

                        # Get all conflicting mods for this mod
                        $conflictingMods = @($modName) + $modConflicts[$modName]

                        # Remove any mods already processed
                        $conflictingMods = $conflictingMods | Where-Object { -not $processedMods.ContainsKey($_) }

                        if ($conflictingMods.Count -le 1) {
                            continue
                        }

                        Write-Host "The following mods conflict with each other:" -ForegroundColor Cyan
                        for ($i = 0; $i -lt $conflictingMods.Count; $i++) {
                            Write-Host "$($i + 1). $($conflictingMods[$i])"
                        }

                        while ($true) {
                            $selection = Read-Host "Select the mod number to install, or 's' to skip all these mods"
                            if ($selection -eq 's') {
                                foreach ($modToSkip in $conflictingMods) {
                                    $modsToSkip += $modToSkip
                                    $processedMods[$modToSkip] = $true
                                }
                                break
                            } elseif ([int]::TryParse($selection, [ref]$null)) {
                                $selectedIndex = [int]$selection
                                if ($selectedIndex -gt 0 -and $selectedIndex -le $conflictingMods.Count) {
                                    $selectedMod = $conflictingMods[$selectedIndex - 1]
                                    $modsToInstallFinal += $selectedMod
                                    $processedMods[$selectedMod] = $true

                                    # Skip the other mods
                                    foreach ($modToSkip in $conflictingMods) {
                                        if ($modToSkip -ne $selectedMod) {
                                            $modsToSkip += $modToSkip
                                            $processedMods[$modToSkip] = $true
                                        }
                                    }
                                    break
                                } else {
                                    Write-Host "Invalid selection. Try again." -ForegroundColor Red
                                }
                            } else {
                                Write-Host "Invalid input. Try again." -ForegroundColor Red
                            }
                        }
                    }

                    # Add any mods that don't have conflicts
                    foreach ($mod in $modsToInstall) {
                        $modName = $mod.Name
                        if (-not $processedMods.ContainsKey($modName) -and -not $modsToSkip.Contains($modName)) {
                            $modsToInstallFinal += $modName
                        }
                    }

                    # Update modsToInstall to only include selected mods
                    $modsToInstall = $mods | Where-Object { $modsToInstallFinal -contains $_.Name }
                }

                # Proceed with installation
                if ($modsToInstall.Count -gt 0) {
                    try {
                        foreach ($mod in $modsToInstall) {
                            $modPath = $mod.FullName
                            $modName = $mod.Name
                            $backupDirectory = Join-Path -Path $gamePath -ChildPath "Backup"
                            Install-Mod -ModName $modName -ModSourcePath $modPath -GameDirectory $gameDirectory -BackupDirectory $backupDirectory
                        }
                    } catch {
                        Write-Error "An error occurred installing ${modName}: $_"
                    }
                } else {
                    Write-Host "No mods to install." -ForegroundColor Cyan
                }
                Write-Host "All mods have been processed. Press any key to continue..."
                [void][System.Console]::ReadKey($true)
            } elseif ($modSelection -eq 'uninstall_all') {
                $modsToUninstall = Get-ChildItem -LiteralPath $modParentPath -Directory | Where-Object { $_.Name -notmatch '^Backup-' }
                foreach ($mod in $modsToUninstall) {
                    $modPath = $mod.FullName
                    $modName = $mod.Name
                    $backupDirectory = Join-Path -Path $gamePath -ChildPath "Backup"
                    $modInstalled = Is-Mod-Installed -ModPath $modPath -GameDirectory $gameDirectory

                    if ($modInstalled) {
                        try {
                            Uninstall-Mod -ModName $modName -ModSourcePath $modPath -GameDirectory $gameDirectory -BackupDirectory $backupDirectory
                        } catch {
                            Write-Error "An error occurred uninstalling ${modName}: $_"
                        }
                    } else {
                        Write-Host "$modName is not installed." -ForegroundColor Yellow
                    }
                }

                Write-Host "All mods have been uninstalled. Press any key to continue..."
                [void][System.Console]::ReadKey($true)
            } else {
                # The user selected a single mod
                $modPath = $modSelection
                $modName = Split-Path -Path $modPath -Leaf
                $backupDirectory = Join-Path -Path $gamePath -ChildPath "Backup"
                $modInstalled = Is-Mod-Installed -ModPath $modPath -GameDirectory $gameDirectory

                try {
                    if ($modInstalled) {
                        Uninstall-Mod -ModName $modName -ModSourcePath $modPath -GameDirectory $gameDirectory -BackupDirectory $backupDirectory
                    } else {
                        # Get list of installed mods
                        $installedMods = @(Get-Installed-Mods -GameDirectory $gameDirectory -ModParentPath $modParentPath)


                        # Check for conflicts with installed mods
                        $conflictingMods = Find-Mod-Conflicts-With-Installed -ModToInstall $modPath -InstalledMods $installedMods -ModParentPath $modParentPath

                        if ($conflictingMods.Count -gt 0) {
                            Write-Host "Conflicts detected with installed mods. Please resolve them." -ForegroundColor Red

                            foreach ($conflict in $conflictingMods) {
                                Write-Host "The mod '$modName' conflicts with the installed mod '$($conflict)'."
                                $choice = Read-Host "Do you want to (1) Uninstall '$($conflict)' and install '$modName', (2) Cancel installation"
                                if ($choice -eq '1') {
                                    # Uninstall conflicting mod
                                    $conflictingModPath = Join-Path -Path $modParentPath -ChildPath $conflict
                                    Uninstall-Mod -ModName $conflict -ModSourcePath $conflictingModPath -GameDirectory $gameDirectory -BackupDirectory $backupDirectory
                                    # Install selected mod
                                    Install-Mod -ModName $modName -ModSourcePath $modPath -GameDirectory $gameDirectory -BackupDirectory $backupDirectory
                                } else {
                                    Write-Host "Installation of '$modName' canceled." -ForegroundColor Yellow
                                }
                            }
                        } else {
                            # No conflicts, proceed with installation
                            Install-Mod -ModName $modName -ModSourcePath $modPath -GameDirectory $gameDirectory -BackupDirectory $backupDirectory
                        }
                    }
                } catch {
                    Write-Error "An error occurred: $_"
                }

                # Clear any remaining progress bars
                Write-Progress -Activity "Operation" -Completed

                Write-Host "Press any key to return to the mod selection menu..."
                [void][System.Console]::ReadKey($true)
            }
        }
    }
}
