param (
    [switch]$elevated
)

if (-not $elevated) {
    # Check if the script is run with administrative privileges
    if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
        $arguments = "-ExecutionPolicy Bypass -File '" + $myInvocation.MyCommand.Definition + "' -ArgumentList '-elevated'"
        Start-Process powershell -Verb runAs -ArgumentList $arguments
        exit
    }
}

Write-Host "Script is running with administrative privileges."

try {
    # Define the path to the current script's directory
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
    Write-Host "Script directory: $scriptDir"

    # Define the path to the main.ps1 script
    $mainScript = Join-Path -Path $scriptDir -ChildPath "main.ps1"
    Write-Host "Main script path: $mainScript"

    # Define the path to the icon file
    $iconPath = Join-Path -Path $scriptDir -ChildPath "icon.ico"
    Write-Host "Icon path: $iconPath"

    # Define the path to the user's desktop
    $desktopPath = [System.IO.Path]::Combine([System.Environment]::GetFolderPath('Desktop'), "SLAM.lnk")
    Write-Host "Shortcut path: $desktopPath"

    # Find PowerShell 7 installation (check common locations)
    $pwshPath = $null
    $pwshPaths = @(
        "C:\Program Files\PowerShell\7\pwsh.exe",
        "C:\Program Files\PowerShell\7-preview\pwsh.exe",
        "$env:LOCALAPPDATA\Microsoft\PowerShell\7\pwsh.exe"
    )

    foreach ($path in $pwshPaths) {
        if (Test-Path $path) {
            $pwshPath = $path
            Write-Host "Found PowerShell 7 at: $pwshPath"
            break
        }
    }

    if (-not $pwshPath) {
        # Try to find pwsh.exe in PATH
        $pwshInPath = Get-Command pwsh.exe -ErrorAction SilentlyContinue
        if ($pwshInPath) {
            $pwshPath = $pwshInPath.Source
            Write-Host "Found PowerShell 7 in PATH: $pwshPath"
        } else {
            throw "PowerShell 7 (pwsh.exe) not found. Please install PowerShell 7."
        }
    }

    # Create the shortcut
    $WshShell = New-Object -ComObject WScript.Shell
    $Shortcut = $WshShell.CreateShortcut($desktopPath)

    # Set the shortcut properties - simplified to run with admin rights
    $Shortcut.TargetPath = $pwshPath
    $Shortcut.Arguments = "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$mainScript`""
    $Shortcut.WorkingDirectory = $scriptDir
    $Shortcut.IconLocation = $iconPath

    # Save the shortcut
    $Shortcut.Save()

    # Set the "Run as administrator" flag on the shortcut.
    $shortcutBytes = [System.IO.File]::ReadAllBytes($desktopPath)
    $shortcutBytes[0x15] = $shortcutBytes[0x15] -bor 0x20
    [System.IO.File]::WriteAllBytes($desktopPath, $shortcutBytes)

    Write-Host "Shortcut created on your desktop successfully!"
    Write-Host "The shortcut has been configured to run as Administrator."
} catch {
    Write-Host "An error occurred: $_"
}
