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

    # Create the shortcut
    $WshShell = New-Object -ComObject WScript.Shell
    $Shortcut = $WshShell.CreateShortcut($desktopPath)

    # Set the shortcut properties
    $Shortcut.TargetPath = "powershell.exe"
    $Shortcut.Arguments = "-ExecutionPolicy Bypass -NoExit -Command `"Start-Process PowerShell -ArgumentList '-ExecutionPolicy Bypass -NoExit -File `"`"$mainScript`"`"' -Verb RunAs`""
    $Shortcut.WorkingDirectory = $scriptDir
    $Shortcut.IconLocation = $iconPath

    # Save the shortcut
    $Shortcut.Save()
    Write-Host "Shortcut created on your desktop successfully!"
} catch {
    Write-Host "An error occurred: $_"
}
