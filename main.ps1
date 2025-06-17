# Add necessary assemblies for Windows Forms
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Hide the PowerShell console window
function Hide-ConsoleWindow {
    $consoleHandle = Get-ConsoleWindow
    if ($consoleHandle -ne 0) {
        # 0 = Hide window
        ShowWindowAsync $consoleHandle 0
    }
}

# Get console window handle
function Get-ConsoleWindow {
    Add-Type -Namespace Win32 -Name NativeMethods -MemberDefinition @"
    [DllImport("kernel32.dll")]
    public static extern IntPtr GetConsoleWindow();
"@
    [Win32.NativeMethods]::GetConsoleWindow()
}

# Import ShowWindowAsync function
function ShowWindowAsync {
    param (
        [IntPtr]$hWnd,
        [int]$nCmdShow
    )
    Add-Type -Namespace Win32 -Name NativeMethods2 -MemberDefinition @"
    [DllImport("user32.dll")]
    public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);
"@
    [Win32.NativeMethods2]::ShowWindowAsync($hWnd, $nCmdShow) | Out-Null
}

# Hide the console window
Hide-ConsoleWindow

# Enable long path support
function Enable-LongPaths {
    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem" -Name "LongPathsEnabled" -Value 1 -Force
}
Enable-LongPaths

# Windows API Functions for File Operations
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

# Define the ModItem class
Add-Type -TypeDefinition @"
using System;

public class ModItem {
    public string Name { get; set; }
    public bool IsInstalled { get; set; }

    public override string ToString() {
        return Name;
    }
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
                # Handle exceptions if necessary
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
        Show-CustomMessageBox -Text "Config file not found: $ConfigFilePath"
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

    foreach ($symlinkPath in $symlinkPaths) {
        $relativePath = $symlinkPath.Substring($GameDirectory.Length).TrimStart("\")
        $sourceFilePath = Join-Path -Path $ModSourcePath -ChildPath $relativePath

        if (Test-Path -LiteralPath $sourceFilePath) {
            Remove-SymbolicLink -Path $symlinkPath
        }
    }
}

# Function to install a mod
function Install-Mod {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)][string]$ModName,
        [Parameter(Mandatory = $true)][string]$ModSourcePath,
        [Parameter(Mandatory = $true)][string]$GameDirectory,
        [Parameter(Mandatory = $true)][string]$BackupDirectory,
        [Parameter()][System.Windows.Forms.ProgressBar]$ProgressBar
    )

    $backupDir = Join-Path -Path $BackupDirectory -ChildPath ("Backup-" + $ModName)
    $files = Get-ChildItem -LiteralPath $ModSourcePath -Recurse -File
    $totalFiles = $files.Count
    $currentStep = 0

    if ($ProgressBar) {
        $ProgressBar.Minimum = 0
        $ProgressBar.Maximum = $totalFiles
    }

    foreach ($file in $files) {
        $currentStep++
        if ($ProgressBar) {
            $ProgressBar.Value = $currentStep
            $ProgressBar.Refresh()
        }

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

    if ($ProgressBar) {
        $ProgressBar.Value = 0
    }
}

# Function to uninstall a mod
function Uninstall-Mod {
    [CmdletBinding()]
    param (
        [string]$ModName,
        [string]$ModSourcePath,
        [string]$GameDirectory,
        [string]$BackupDirectory,
        [System.Windows.Forms.ProgressBar]$ProgressBar,
        [ref]$FilesProcessed
    )

    $backupDir = Join-Path -Path $BackupDirectory -ChildPath ("Backup-" + $ModName)

    # Restore backup files
    if (Test-Path -LiteralPath $backupDir) {
        $files = Get-ChildItem -LiteralPath $backupDir -Recurse -File
        $totalFiles = $files.Count

        foreach ($file in $files) {
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

            # Increment files processed and update progress bar
            $FilesProcessed.Value++
            if ($ProgressBar) {
                $ProgressBar.Value = [Math]::Min($FilesProcessed.Value, $ProgressBar.Maximum)
                $ProgressBar.Refresh()
            }
        }

        # Remove backup directory
        Remove-Item -LiteralPath $backupDir -Recurse -Force
    }

    # Remove any remaining symbolic links
    Remove-Links-Directly -GameDirectory $GameDirectory -ModSourcePath $ModSourcePath

    # Clean up empty directories
    Remove-EmptyDirectories -RootPath $GameDirectory
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

# Function to show a custom message box with dark theme
function Show-CustomMessageBox {
    param (
        [string]$Text,
        [string]$Title = "Message",
        [string]$Buttons = "OKCancel"
    )

    $form = New-Object System.Windows.Forms.Form
    $form.Text = $Title
    $form.Size = New-Object System.Drawing.Size(400, 200)
    $form.StartPosition = "CenterParent"
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.BackColor = [System.Drawing.Color]::FromArgb(30, 30, 30)
    $form.ForeColor = [System.Drawing.Color]::White
    $form.ShowInTaskbar = $false

    # Label
    $label = New-Object System.Windows.Forms.Label
    $label.Text = $Text
    $label.Size = New-Object System.Drawing.Size(360, 80)
    $label.Location = New-Object System.Drawing.Point(20, 20)
    $label.BackColor = $form.BackColor
    $label.ForeColor = $form.ForeColor
    $label.AutoSize = $false
    $label.TextAlign = 'MiddleCenter'
    $form.Controls.Add($label)

    # Buttons
    switch ($Buttons) {
        "OK" {
            $buttonOK = New-Object System.Windows.Forms.Button
            $buttonOK.Text = "OK"
            $buttonOK.DialogResult = [System.Windows.Forms.DialogResult]::OK
            $buttonOK.Location = New-Object System.Drawing.Point(160, 120)
            $buttonOK.Size = New-Object System.Drawing.Size(75, 30)
            $buttonOK.BackColor = [System.Drawing.Color]::FromArgb(70, 70, 70)
            $buttonOK.ForeColor = [System.Drawing.Color]::White
            $form.Controls.Add($buttonOK)
            $form.AcceptButton = $buttonOK
        }
        "YesNo" {
            $buttonYes = New-Object System.Windows.Forms.Button
            $buttonYes.Text = "Yes"
            $buttonYes.DialogResult = [System.Windows.Forms.DialogResult]::Yes
            $buttonYes.Location = New-Object System.Drawing.Point(110, 120)
            $buttonYes.Size = New-Object System.Drawing.Size(75, 30)
            $buttonYes.BackColor = [System.Drawing.Color]::FromArgb(70, 70, 70)
            $buttonYes.ForeColor = [System.Drawing.Color]::White
            $form.Controls.Add($buttonYes)

            $buttonNo = New-Object System.Windows.Forms.Button
            $buttonNo.Text = "No"
            $buttonNo.DialogResult = [System.Windows.Forms.DialogResult]::No
            $buttonNo.Location = New-Object System.Drawing.Point(210, 120)
            $buttonNo.Size = New-Object System.Drawing.Size(75, 30)
            $buttonNo.BackColor = [System.Drawing.Color]::FromArgb(70, 70, 70)
            $buttonNo.ForeColor = [System.Drawing.Color]::White
            $form.Controls.Add($buttonNo)

            $form.AcceptButton = $buttonYes
            $form.CancelButton = $buttonNo
        }
        default {
            # OKCancel
            $buttonOK = New-Object System.Windows.Forms.Button
            $buttonOK.Text = "OK"
            $buttonOK.DialogResult = [System.Windows.Forms.DialogResult]::OK
            $buttonOK.Location = New-Object System.Drawing.Point(110, 120)
            $buttonOK.Size = New-Object System.Drawing.Size(75, 30)
            $buttonOK.BackColor = [System.Drawing.Color]::FromArgb(70, 70, 70)
            $buttonOK.ForeColor = [System.Drawing.Color]::White
            $form.Controls.Add($buttonOK)

            $buttonCancel = New-Object System.Windows.Forms.Button
            $buttonCancel.Text = "Cancel"
            $buttonCancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
            $buttonCancel.Location = New-Object System.Drawing.Point(210, 120)
            $buttonCancel.Size = New-Object System.Drawing.Size(75, 30)
            $buttonCancel.BackColor = [System.Drawing.Color]::FromArgb(70, 70, 70)
            $buttonCancel.ForeColor = [System.Drawing.Color]::White
            $form.Controls.Add($buttonCancel)

            $form.AcceptButton = $buttonOK
            $form.CancelButton = $buttonCancel
        }
    }

    return $form.ShowDialog()
}

# Function to get the script directory
function Get-ScriptDirectory {
    if ($MyInvocation.PSCommandPath) {
        $scriptDir = Split-Path -Parent $MyInvocation.PSCommandPath
    } elseif ($PSScriptRoot) {
        $scriptDir = $PSScriptRoot
    } else {
        $scriptDir = Get-Location
    }
    return $scriptDir
}

function Initialize-GUI {
    # Add required assemblies
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    # Create the form
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "SymLink Advanced Modding for DCS"
    $form.Size = New-Object System.Drawing.Size(800, 850)  # Increased form height
    $form.StartPosition = "CenterScreen"
    $form.MaximizeBox = $false
    $form.BackColor = [System.Drawing.Color]::FromArgb(30, 30, 30)
    $form.ForeColor = [System.Drawing.Color]::White

    $form.Add_FormClosed({
        Stop-Process -Id $PID -Force
    })

    # Define fonts
    $headingFont = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)

    # Label for games
    $labelGames = New-Object System.Windows.Forms.Label
    $labelGames.Text = "Available Games:"
    $labelGames.Location = New-Object System.Drawing.Point(10, 10)
    $labelGames.Size = New-Object System.Drawing.Size(120, 20)
    $labelGames.Font = $headingFont
    $labelGames.BackColor = $form.BackColor
    $labelGames.ForeColor = $form.ForeColor
    $form.Controls.Add($labelGames)

    # ListBox for games
    $listboxGames = New-Object System.Windows.Forms.ListBox
    $listboxGames.Location = New-Object System.Drawing.Point(10, 40)
    $listboxGames.Width = 100  # Adjusted width
    $listboxGames.Height = 200  # Set default height
    $listboxGames.BackColor = [System.Drawing.Color]::FromArgb(50, 50, 50)
    $listboxGames.ForeColor = [System.Drawing.Color]::White
    $form.Controls.Add($listboxGames)

    # Label for mod parents
    $labelModParents = New-Object System.Windows.Forms.Label
    $labelModParents.Text = "Mod Parent Directories:"
    $labelModParents.Location = New-Object System.Drawing.Point(130, 10)  # Moved to the right
    $labelModParents.Size = New-Object System.Drawing.Size(160, 20)
    $labelModParents.Font = $headingFont
    $labelModParents.BackColor = $form.BackColor
    $labelModParents.ForeColor = $form.ForeColor
    $form.Controls.Add($labelModParents)

    # ListBox for mod parents
    $listboxModParents = New-Object System.Windows.Forms.ListBox
    $listboxModParents.Location = New-Object System.Drawing.Point(130, 40)  # Moved to the right
    $listboxModParents.Width = 150  # Increased width
    $listboxModParents.Height = 200  # Set default height
    $listboxModParents.BackColor = [System.Drawing.Color]::FromArgb(50, 50, 50)
    $listboxModParents.ForeColor = [System.Drawing.Color]::White
    $form.Controls.Add($listboxModParents)

    # Label for mods
    $labelMods = New-Object System.Windows.Forms.Label
    $labelMods.Text = "Available Mods:"
    $labelMods.Location = New-Object System.Drawing.Point(290, 10)  # Adjusted position
    $labelMods.Size = New-Object System.Drawing.Size(150, 20)
    $labelMods.Font = $headingFont
    $labelMods.BackColor = $form.BackColor
    $labelMods.ForeColor = $form.ForeColor
    $form.Controls.Add($labelMods)

    # ListBox for mods
    $listboxMods = New-Object System.Windows.Forms.ListBox
    $listboxMods.Location = New-Object System.Drawing.Point(290, 40)  # Adjusted position
    $listboxMods.Width = 300  # Adjusted width
    $listboxMods.Height = 200  # Set default height same as mod parents
    $listboxMods.SelectionMode = "MultiSimple"
    $listboxMods.BackColor = [System.Drawing.Color]::FromArgb(50, 50, 50)
    $listboxMods.ForeColor = [System.Drawing.Color]::White
    $listboxMods.DrawMode = [System.Windows.Forms.DrawMode]::OwnerDrawFixed
    $listboxMods.ItemHeight = 20
    $form.Controls.Add($listboxMods)

    # Function to dynamically adjust ListBox height based on item count
    function Adjust-ListBoxHeight($listBox, $maxHeight) {
        $itemCount = $listBox.Items.Count
        $desiredHeight = $itemCount * $listBox.ItemHeight + 4  # +4 for borders
        if ($desiredHeight -gt $maxHeight) {
            $desiredHeight = $maxHeight
        }
        if ($desiredHeight -lt 200) {
            $desiredHeight = 200  # Set minimum/default height
        }
        $listBox.Height = $desiredHeight
    }

    # Set maximum heights for list boxes
    $maxModsListHeight = 320  # Capped at 20% less than previous height

    # Checkbox for Select All
    $checkboxSelectAll = New-Object System.Windows.Forms.CheckBox
    $checkboxSelectAll.Text = "Select All"
    $checkboxSelectAll.Location = New-Object System.Drawing.Point(600, 10)  # Adjusted position
    $checkboxSelectAll.Size = New-Object System.Drawing.Size(150, 20)
    $checkboxSelectAll.BackColor = $form.BackColor
    $checkboxSelectAll.ForeColor = $form.ForeColor
    $form.Controls.Add($checkboxSelectAll)

    # Checkbox for sorting by installed status
    $checkboxSortByInstalled = New-Object System.Windows.Forms.CheckBox
    $checkboxSortByInstalled.Text = "Sort by Installed Status"
    $checkboxSortByInstalled.Location = New-Object System.Drawing.Point(600, 40)  # Adjusted position
    $checkboxSortByInstalled.Size = New-Object System.Drawing.Size(180, 20)
    $checkboxSortByInstalled.BackColor = $form.BackColor
    $checkboxSortByInstalled.ForeColor = $form.ForeColor
    $form.Controls.Add($checkboxSortByInstalled)

    # Open Mod Directory button (adjusted width)
    $buttonOpenModFolder = New-Object System.Windows.Forms.Button
    $buttonOpenModFolder.Text = "Open Mod Directory"
    $buttonOpenModFolder.Location = New-Object System.Drawing.Point(600, 70)  # Adjusted position
    $buttonOpenModFolder.Size = New-Object System.Drawing.Size(200, 30)
    $buttonOpenModFolder.BackColor = [System.Drawing.Color]::FromArgb(70, 70, 70)
    $buttonOpenModFolder.ForeColor = [System.Drawing.Color]::White
    $buttonOpenModFolder.FlatStyle = 'Flat'
    $form.Controls.Add($buttonOpenModFolder)

    # Install button (moved to right side and increased width)
    $buttonInstall = New-Object System.Windows.Forms.Button
    $buttonInstall.Text = "Install Selected Mods"
    $buttonInstall.Location = New-Object System.Drawing.Point(600, 110)  # Adjusted position
    $buttonInstall.Size = New-Object System.Drawing.Size(200, 30)
    $buttonInstall.BackColor = [System.Drawing.Color]::FromArgb(70, 70, 70)
    $buttonInstall.ForeColor = [System.Drawing.Color]::White
    $buttonInstall.FlatStyle = 'Flat'
    $form.Controls.Add($buttonInstall)

    # Uninstall button (moved to right side and increased width)
    $buttonUninstall = New-Object System.Windows.Forms.Button
    $buttonUninstall.Text = "Uninstall Selected Mods"
    $buttonUninstall.Location = New-Object System.Drawing.Point(600, 150)  # Adjusted position
    $buttonUninstall.Size = New-Object System.Drawing.Size(200, 30)
    $buttonUninstall.BackColor = [System.Drawing.Color]::FromArgb(70, 70, 70)
    $buttonUninstall.ForeColor = [System.Drawing.Color]::White
    $buttonUninstall.FlatStyle = 'Flat'
    $form.Controls.Add($buttonUninstall)

    # Add "Check for Updates" button (adjusted width)
    $buttonCheckForUpdates = New-Object System.Windows.Forms.Button
    $buttonCheckForUpdates.Text = "Check for Updates"
    $buttonCheckForUpdates.Location = New-Object System.Drawing.Point(600, 190)  # Adjusted position
    $buttonCheckForUpdates.Size = New-Object System.Drawing.Size(200, 30)
    $buttonCheckForUpdates.BackColor = [System.Drawing.Color]::FromArgb(70, 70, 70)
    $buttonCheckForUpdates.ForeColor = [System.Drawing.Color]::White
    $buttonCheckForUpdates.FlatStyle = 'Flat'
    $form.Controls.Add($buttonCheckForUpdates)

    # Progress Bar
    $progressBar = New-Object System.Windows.Forms.ProgressBar
    $progressBar.Location = New-Object System.Drawing.Point(10, 360)
    $progressBar.Size = New-Object System.Drawing.Size(780, 20)  # Adjusted width
    $progressBar.Minimum = 0
    $form.Controls.Add($progressBar)

    # Logo Image
    $scriptDir = Get-ScriptDirectory
    $logoPath = Join-Path -Path $scriptDir -ChildPath 'icon.ico'
    if (Test-Path -LiteralPath $logoPath) {
        $logoImage = [System.Drawing.Image]::FromFile($logoPath)

        $pictureBox = New-Object System.Windows.Forms.PictureBox
        $pictureBox.Image = $logoImage
        $pictureBox.SizeMode = 'Zoom'
        $pictureBox.Location = New-Object System.Drawing.Point(275, 390)  # Adjusted position
        $pictureBox.Size = New-Object System.Drawing.Size(250, 250)
        $pictureBox.BackColor = $form.BackColor
        $form.Controls.Add($pictureBox)
    }

    # Status Label
    $labelStatus = New-Object System.Windows.Forms.Label
    $labelStatus.Text = "Status: Ready"
    $labelStatus.Location = New-Object System.Drawing.Point(10, 660)  # Adjusted position
    $labelStatus.Size = New-Object System.Drawing.Size(780, 20)  # Adjusted width
    $labelStatus.BackColor = $form.BackColor
    $labelStatus.ForeColor = $form.ForeColor
    $form.Controls.Add($labelStatus)

    # Donation Link Label (adjusted position)
    $linkLabelDonate = New-Object System.Windows.Forms.LinkLabel
    $linkLabelDonate.Text = "Donate/support the developer"
    $linkLabelDonate.Location = New-Object System.Drawing.Point(300, 690)  # Adjusted position
    $linkLabelDonate.Size = New-Object System.Drawing.Size(200, 20)
    $linkLabelDonate.BackColor = $form.BackColor
    $linkLabelDonate.LinkColor = [System.Drawing.Color]::LightBlue
    $linkLabelDonate.ActiveLinkColor = [System.Drawing.Color]::Orange
    $linkLabelDonate.VisitedLinkColor = [System.Drawing.Color]::Purple
    $linkLabelDonate.LinkBehavior = 'HoverUnderline'
    $linkLabelDonate.Add_LinkClicked({
        Start-Process "https://buymeacoffee.com/halfmanbear"
    })
    $form.Controls.Add($linkLabelDonate)

    # Global variables
    $script:GamesPath = $null
    $script:Config = $null
    $script:scriptDir = $scriptDir

    # Load configuration
    Load-Configuration

    # Populate games
    Populate-GamesList -ListBox $listboxGames

    # Populate mod parents
    Populate-ModParentsList -ListBox $listboxModParents

    # Event handlers
    $listboxGames.Add_SelectedIndexChanged({
        UpdateModsList $listboxGames $listboxModParents $listboxMods
        Adjust-ListBoxHeight $listboxMods $maxModsListHeight
    })

    $listboxModParents.Add_SelectedIndexChanged({
        UpdateModsList $listboxGames $listboxModParents $listboxMods
        Adjust-ListBoxHeight $listboxMods $maxModsListHeight
    })

    $buttonInstall.Add_Click({
        InstallSelectedMods $listboxGames $listboxModParents $listboxMods $progressBar $labelStatus
    })

    $buttonUninstall.Add_Click({
        UninstallSelectedMods $listboxGames $listboxModParents $listboxMods $progressBar $labelStatus
    })

    # Event handler for Select All checkbox
    $checkboxSelectAll.Add_CheckedChanged({
        if ($checkboxSelectAll.Checked) {
            # Select all mods
            for ($i = 0; $i -lt $listboxMods.Items.Count; $i++) {
                $listboxMods.SetSelected($i, $true)
            }
        } else {
            # Deselect all mods
            $listboxMods.ClearSelected()
        }
    })

    # Event handler for Sort by Installed Status checkbox
    $checkboxSortByInstalled.Add_CheckedChanged({
        UpdateModsList $listboxGames $listboxModParents $listboxMods
        Adjust-ListBoxHeight $listboxMods $maxModsListHeight
    })

    # Event handler for Open Mod Directory button
    $buttonOpenModFolder.Add_Click({
        $modFolderPath = Join-Path -Path $scriptDir -ChildPath "Games\DCS"
        if (Test-Path -LiteralPath $modFolderPath) {
            Start-Process "explorer.exe" -ArgumentList "`"$modFolderPath`""
        } else {
            Show-CustomMessageBox -Text "Mod folder does not exist: $modFolderPath" -Title "Error" -Buttons "OK"
        }
    })

    # Event handler for "Check for Updates" button
    $buttonCheckForUpdates.Add_Click({
        $labelStatus.Text = "Checking for updates…"

        # Run git in the script folder
        $gitResult = git -C $PSScriptRoot pull origin main 2>&1

        if ($gitResult -match "Already up to date.") {
            $labelStatus.Text = "Already up to date."
        }
        elseif ($gitResult -match "Updating") {
            $labelStatus.Text = "Update applied. Exiting…"
            Stop-Process -Id $PID -Force
        }
        else {
            $labelStatus.Text = "Update failed: $($gitResult -join ' ')"
        }
    })

    # DrawItem event handler for mods
    $listboxMods.Add_DrawItem({
        param($sender, $e)
        try {
            if ($e.Index -ge 0) {
                $listBox = $sender
                $graphics = $e.Graphics
                $modItem = $listBox.Items[$e.Index]

                # Set default colors
                $backColor = $listBox.BackColor
                $foreColor = $listBox.ForeColor

                if ($e.State -band [System.Windows.Forms.DrawItemState]::Selected) {
                    # Selected item
                    $backColor = [System.Drawing.Color]::Blue
                    $foreColor = [System.Drawing.Color]::White
                } elseif ($modItem.IsInstalled) {
                    # Installed mod
                    $foreColor = [System.Drawing.Color]::Green
                }

                $e.Graphics.FillRectangle((New-Object System.Drawing.SolidBrush $backColor), $e.Bounds)
                $textFont = $e.Font

                # Create RectangleF for DrawString
                $textBounds = New-Object System.Drawing.RectangleF(
                    [float]($e.Bounds.X + 2),
                    [float]$e.Bounds.Y,
                    [float]($e.Bounds.Width - 4),
                    [float]$e.Bounds.Height
                )

                $textBrush = New-Object System.Drawing.SolidBrush $foreColor
                $graphics.DrawString($modItem.Name, $textFont, $textBrush, $textBounds)

                $e.DrawFocusRectangle()
            }
        } catch {
            Show-CustomMessageBox -Text "Error in drawing mod item: $_" -Title "Error" -Buttons "OK"
        }
    })

    # Initial adjustment of list box heights
    Adjust-ListBoxHeight $listboxMods $maxModsListHeight

    # Show the form
    $form.ShowDialog() | Out-Null
}

function Load-Configuration {
    $scriptDir = Get-ScriptDirectory
    $script:scriptDir = $scriptDir

    # Read Configuration (using config.txt)
    $configFilePath = Join-Path -Path $scriptDir -ChildPath 'config.txt'
    $script:Config = Read-Config -ConfigFilePath $configFilePath

    $configUpdated = $false

    if (-not $Config.ContainsKey('CoreGameDirectory') -or [string]::IsNullOrEmpty($Config['CoreGameDirectory'])) {
        # Show custom message
        Show-CustomMessageBox -Text "Please locate your [Eagle Dynamics / DCS World] install folder. The default path is usually 'C:\Program Files\Eagle Dynamics\DCS World'." -Title "Select Core Game Directory" -Buttons "OK"

        $folderBrowser = New-Object System.Windows.Forms.FolderBrowserDialog
        $folderBrowser.Description = "Select Core Game Directory"
        $folderBrowser.SelectedPath = "C:\Program Files\"
        if ($folderBrowser.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $Config['CoreGameDirectory'] = $folderBrowser.SelectedPath
            $configUpdated = $true
        } else {
            Show-CustomMessageBox -Text "CoreGameDirectory is required. Exiting." -Title "Error" -Buttons "OK"
            exit
        }
    }

    if (-not $Config.ContainsKey('SavedGamesDirectory') -or [string]::IsNullOrEmpty($Config['SavedGamesDirectory'])) {
        # Show custom message
        Show-CustomMessageBox -Text "Please locate your [Saved Games / DCS] directory. The default path is 'User\Saved Games\DCS'." -Title "Select Saved Games Directory" -Buttons "OK"

        $folderBrowser = New-Object System.Windows.Forms.FolderBrowserDialog
        $folderBrowser.Description = "Select Saved Games Directory"
        $folderBrowser.SelectedPath = Join-Path -Path $env:USERPROFILE -ChildPath "Saved Games\"
        if ($folderBrowser.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $Config['SavedGamesDirectory'] = $folderBrowser.SelectedPath
            $configUpdated = $true
        } else {
            Show-CustomMessageBox -Text "SavedGamesDirectory is required. Exiting." -Title "Error" -Buttons "OK"
            exit
        }
    }

    if ($configUpdated) {
        # Save the updated configuration back to config.txt
        $configLines = @()
        foreach ($key in $Config.Keys) {
            $configLines += "$key=$($Config[$key])"
        }
        Set-Content -Path $configFilePath -Value $configLines

        # Restart the script to load new configuration
        Stop-Process -Id $PID -Force
        exit
    }

    $script:GamesPath = Join-Path -Path $scriptDir -ChildPath 'Games'
}

function Populate-GamesList {
    param (
        [System.Windows.Forms.ListBox]$ListBox
    )
    $games = Get-ChildItem -LiteralPath $GamesPath -Directory
    $ListBox.Items.Clear()
    foreach ($game in $games) {
        $ListBox.Items.Add($game.Name)
    }
}

function Populate-ModParentsList {
    param (
        [System.Windows.Forms.ListBox]$ListBox
    )
    $modParents = @("Core Mods", "Saved Games Mods")
    $ListBox.Items.Clear()
    foreach ($modParent in $modParents) {
        $ListBox.Items.Add($modParent)
    }
}

function UpdateModsList {
    param (
        [System.Windows.Forms.ListBox]$GamesListBox,
        [System.Windows.Forms.ListBox]$ModParentsListBox,
        [System.Windows.Forms.ListBox]$ModsListBox
    )
    $ModsListBox.Items.Clear()
    $selectedGame = $GamesListBox.SelectedItem
    $selectedModParent = $ModParentsListBox.SelectedItem

    if ($selectedGame -and $selectedModParent) {
        $gamePath = Join-Path -Path $GamesPath -ChildPath $selectedGame
        $modParentPath = Join-Path -Path $gamePath -ChildPath $selectedModParent

        if (Test-Path -LiteralPath $modParentPath) {
            $mods = Get-ChildItem -LiteralPath $modParentPath -Directory | Where-Object { $_.Name -notmatch '^Backup-' }

            # Determine game directory
            if ($selectedModParent -eq "Core Mods") {
                $gameDirectory = $Config['CoreGameDirectory']
            } elseif ($selectedModParent -eq "Saved Games Mods") {
                $gameDirectory = $Config['SavedGamesDirectory']
            } else {
                Show-CustomMessageBox -Text "Invalid mod parent directory." -Title "Error" -Buttons "OK"
                return
            }

            # Collect mod items
            $modItems = @()
            foreach ($mod in $mods) {
                $modName = $mod.Name
                $isInstalled = Is-Mod-Installed -ModPath $mod.FullName -GameDirectory $gameDirectory
                $modItem = New-Object ModItem
                $modItem.Name = $modName
                $modItem.IsInstalled = $isInstalled
                $modItems += $modItem
            }

            # Check if sorting by installed status is enabled
            if ($checkboxSortByInstalled.Checked) {
                # Sort by installed status, installed mods come first
                $modItems = $modItems | Sort-Object -Property { -not $_.IsInstalled }, Name
            } else {
                # Default sorting by name
                $modItems = $modItems | Sort-Object Name
            }

            # Add sorted mod items to the listbox
            foreach ($modItem in $modItems) {
                $ModsListBox.Items.Add($modItem)
            }
        }
    }
}

function InstallSelectedMods {
    param (
        [System.Windows.Forms.ListBox]$GamesListBox,
        [System.Windows.Forms.ListBox]$ModParentsListBox,
        [System.Windows.Forms.ListBox]$ModsListBox,
        [System.Windows.Forms.ProgressBar]$ProgressBar,
        [System.Windows.Forms.Label]$StatusLabel
    )

    $selectedMods = $ModsListBox.SelectedItems
    if ($selectedMods.Count -gt 0) {
        foreach ($modItem in $selectedMods) {
            $modName = $modItem.Name
            InstallModFromGUI -ModName $modName -GamesListBox $GamesListBox -ModParentsListBox $ModParentsListBox -ProgressBar $ProgressBar -StatusLabel $StatusLabel
        }
        UpdateModsList $GamesListBox $ModParentsListBox $ModsListBox
    } else {
        Show-CustomMessageBox -Text "Please select at least one mod to install." -Title "Information" -Buttons "OK"
    }
}

function UninstallSelectedMods {
    param (
        [System.Windows.Forms.ListBox]$GamesListBox,
        [System.Windows.Forms.ListBox]$ModParentsListBox,
        [System.Windows.Forms.ListBox]$ModsListBox,
        [System.Windows.Forms.ProgressBar]$ProgressBar,
        [System.Windows.Forms.Label]$StatusLabel
    )

    $selectedMods = $ModsListBox.SelectedItems
    if ($selectedMods.Count -gt 0) {
        $totalFiles = 0

        # Calculate the total number of files across all selected mods
        foreach ($modItem in $selectedMods) {
            $modName = $modItem.Name
            $selectedGame = $GamesListBox.SelectedItem
            $selectedModParent = $ModParentsListBox.SelectedItem

            if ($selectedGame -and $selectedModParent) {
                $gamePath = Join-Path -Path $GamesPath -ChildPath $selectedGame
                $modParentPath = Join-Path -Path $gamePath -ChildPath $selectedModParent
                $modPath = Join-Path -Path $modParentPath -ChildPath $modName

                # Count files in this mod
                if (Test-Path -LiteralPath $modPath) {
                    $totalFiles += (Get-ChildItem -LiteralPath $modPath -Recurse -File).Count
                }
            }
        }

        # Initialize progress bar
        if ($totalFiles -gt 0) {
            $ProgressBar.Minimum = 0
            $ProgressBar.Maximum = $totalFiles
            $ProgressBar.Value = 0
        }

        # Uninstall each mod and update progress bar incrementally
        $filesProcessed = 0
        foreach ($modItem in $selectedMods) {
            $modName = $modItem.Name
            UninstallModFromGUI -ModName $modName -GamesListBox $GamesListBox -ModParentsListBox $ModParentsListBox -ProgressBar $ProgressBar -StatusLabel $StatusLabel -FilesProcessed ([ref]$filesProcessed)
        }

        # Ensure the progress bar is set to 100% when done
        $ProgressBar.Value = $ProgressBar.Maximum
        $ProgressBar.Refresh()

        # Wait a bit for user feedback and then reset the progress bar
        Start-Sleep -Milliseconds 500
        $ProgressBar.Value = 0
        $ProgressBar.Refresh()

        UpdateModsList $GamesListBox $ModParentsListBox $ModsListBox
    } else {
        Show-CustomMessageBox -Text "Please select at least one mod to uninstall." -Title "Information" -Buttons "OK"
    }
}

function InstallModFromGUI {
    param (
        [string]$ModName,
        [System.Windows.Forms.ListBox]$GamesListBox,
        [System.Windows.Forms.ListBox]$ModParentsListBox,
        [System.Windows.Forms.ProgressBar]$ProgressBar,
        [System.Windows.Forms.Label]$StatusLabel
    )

    $selectedGame = $GamesListBox.SelectedItem
    $selectedModParent = $ModParentsListBox.SelectedItem

    if (-not $selectedGame -or -not $selectedModParent) {
        Show-CustomMessageBox -Text "Please select a game and mod parent directory." -Title "Information" -Buttons "OK"
        return
    }

    $gamePath = Join-Path -Path $GamesPath -ChildPath $selectedGame
    $modParentPath = Join-Path -Path $gamePath -ChildPath $selectedModParent
    $modPath = Join-Path -Path $modParentPath -ChildPath $ModName

    if (-not (Test-Path -LiteralPath $modPath)) {
        Show-CustomMessageBox -Text "Mod path does not exist: $modPath" -Title "Error" -Buttons "OK"
        return
    }

    # Determine game directory
    if ($selectedModParent -eq "Core Mods") {
        $gameDirectory = $Config['CoreGameDirectory']
    } elseif ($selectedModParent -eq "Saved Games Mods") {
        $gameDirectory = $Config['SavedGamesDirectory']
    } else {
        Show-CustomMessageBox -Text "Invalid mod parent directory." -Title "Error" -Buttons "OK"
        return
    }

    $backupDirectory = Join-Path -Path $gamePath -ChildPath "Backup"
    $modInstalled = Is-Mod-Installed -ModPath $modPath -GameDirectory $gameDirectory

    if ($modInstalled) {
        Show-CustomMessageBox -Text "Mod '$ModName' is already installed." -Title "Information" -Buttons "OK"
        return
    }

    # Check for conflicts with installed mods
    $installedMods = @(Get-Installed-Mods -GameDirectory $gameDirectory -ModParentPath $modParentPath)

    $conflictingMods = Find-Mod-Conflicts-With-Installed -ModToInstall $modPath -InstalledMods $installedMods -ModParentPath $modParentPath

    if ($conflictingMods.Count -gt 0) {
        $conflictMessage = "The mod '$ModName' conflicts with the following installed mods:`n"
        $conflictMessage += ($conflictingMods -join "`n")
        $conflictMessage += "`nDo you want to uninstall them and proceed?"

        $result = Show-CustomMessageBox -Text $conflictMessage -Title "Conflict Detected" -Buttons "YesNo"
        if ($result -ne [System.Windows.Forms.DialogResult]::Yes) {
            return
        }

        # Uninstall conflicting mods
        foreach ($conflict in $conflictingMods) {
            $conflictingModPath = Join-Path -Path $modParentPath -ChildPath $conflict
            Uninstall-Mod -ModName $conflict -ModSourcePath $conflictingModPath -GameDirectory $gameDirectory -BackupDirectory $backupDirectory -ProgressBar $ProgressBar
        }
    }

    # Install the mod
    $StatusLabel.Text = "Installing mod: $ModName"
    Install-Mod -ModName $ModName -ModSourcePath $modPath -GameDirectory $gameDirectory -BackupDirectory $backupDirectory -ProgressBar $ProgressBar
    $StatusLabel.Text = "Installed mod: $ModName"
}

function UninstallModFromGUI {
    param (
        [string]$ModName,
        [System.Windows.Forms.ListBox]$GamesListBox,
        [System.Windows.Forms.ListBox]$ModParentsListBox,
        [System.Windows.Forms.ProgressBar]$ProgressBar,
        [System.Windows.Forms.Label]$StatusLabel,
        [ref]$FilesProcessed
    )

    $selectedGame = $GamesListBox.SelectedItem
    $selectedModParent = $ModParentsListBox.SelectedItem

    if (-not $selectedGame -or -not $selectedModParent) {
        Show-CustomMessageBox -Text "Please select a game and mod parent directory." -Title "Information" -Buttons "OK"
        return
    }

    $gamePath = Join-Path -Path $GamesPath -ChildPath $selectedGame
    $modParentPath = Join-Path -Path $gamePath -ChildPath $selectedModParent
    $modPath = Join-Path -Path $modParentPath -ChildPath $ModName

    if (-not (Test-Path -LiteralPath $modPath)) {
        return  # Silently skip if mod path doesn't exist
    }

    # Determine game directory
    if ($selectedModParent -eq "Core Mods") {
        $gameDirectory = $Config['CoreGameDirectory']
    } elseif ($selectedModParent -eq "Saved Games Mods") {
        $gameDirectory = $Config['SavedGamesDirectory']
    } else {
        Show-CustomMessageBox -Text "Invalid mod parent directory." -Title "Error" -Buttons "OK"
        return
    }

    $backupDirectory = Join-Path -Path $gamePath -ChildPath "Backup"
    $modInstalled = Is-Mod-Installed -ModPath $modPath -GameDirectory $gameDirectory

    # Silently skip if the mod is not installed
    if (-not $modInstalled) {
        return  # Just return, silently skipping the mod
    }

    # Uninstall the mod and update the progress bar
    $StatusLabel.Text = "Uninstalling mod: $ModName"
    Uninstall-Mod -ModName $ModName -ModSourcePath $modPath -GameDirectory $gameDirectory -BackupDirectory $backupDirectory -ProgressBar $ProgressBar -FilesProcessed $FilesProcessed
    $StatusLabel.Text = "Uninstalled mod: $ModName"
}

# Start the GUI
Initialize-GUI
