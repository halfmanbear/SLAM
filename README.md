# SLAM - SymLink Advanced Modding for DCS

## Overview

SLAM (SymLink Advanced Modding) is a PowerShell-based mod management tool designed for DCS (Digital Combat Simulator) World. It leverages symbolic links to manage mods more efficiently, providing a seamless way to install, uninstall, and toggle mods without the need to move files around. This ensures that your original mod files remain untouched, and any changes made in-game are directly reflected in the linked files.

## Features

- **Space Saving:** Symbolic links create a direct reference to the mod files, reducing disk space usage and improving performance.
- **Minimized SSD Degradation:** Fewer reads/writes are performed, leading to less degradation of SSDs.
- **Efficient Mod Management:** Easily install, uninstall, and toggle mods using symbolic links.
- **Automatic Backup:** Automatically backs up DCS files before creating symbolic links to mods, ensuring you can easily revert to the original game state if needed.
- **Persistent Mod Files:** Uses symbolic links to ensure any edits made in-game are directly reflected and retained in the mod files.
- **Simple Configuration:** Uses a single `config.txt` file to specify the game install location.
- **User-Friendly Interface:** Command-line interface guides you through selecting games and mods.

## Installation

1. **Download the Release ZIP**: Found here [Releases](https://github.com/halfmanbear/SLAM/releases)

2. **Extract the ZIP**: Extract the `SLAM` folder to your desired Mod Files location.

3. **Configure DCS Install Location**:
   - Open `\SLAM\config.txt` and edit `CoreGameDirectory=` and `SavedGamesDirectory=` paths if needed. The default is 'Release'.

4. **Add Mod Folders**:
   - Add mod folders and files to `\SLAM\Games\DCS\Core Mods\` and `\SLAM\Games\DCS\Saved Games Mods\` as needed.

5. **Run the Setup**:
   - **Note**: If a blue SmartScreen warning appears click `More info` then `Run anyway`
   - **For Windows**: Double-click `install.bat` to create the `SLAM` desktop shortcut.
   - Use the desktop shortcut to launch SLAM with the necessary permissions.

## Using SLAM

1. **Run SLAM**: Use the desktop shortcut created during the installation to run `SLAM`.

2. **Select Game**: Choose `DCS`.

3. **Select Mod Destination**: Select either `Core Mods` or `Saved Game Mods`.

4. **View Your Mods**: You will now see all mods located in the respective `Core Mods` or `Saved Game Mods` folders.

5. **Manage Mods**: Select a mod to toggle installation or uninstallation. Enabled mods will be marked with an `*` and displayed in `green`.

6. **Original Game File Backups**: Original game file backups are automatically stored in `\SLAM\Games\DCS\Backup` by default. Note: Some mods may not replace original game files, so no Backup folder will be created.

Thank you for using SLAM! If you encounter any issues or have feedback, please visit our [GitHub Issues page](https://github.com/halfmanbear/SLAM/issues).

## Contributing

We welcome contributions to SLAM. Please feel free to submit issues, fork the repository, and create pull requests.  

If you find SLAM useful, consider supporting its development through [GitHub Sponsors](https://github.com/sponsors/halfmanbear) or [Buy Me a Coffee](https://www.buymeacoffee.com/halfmanbear).

## Acknowledgements

- Inspired by the need for efficient and user-friendly mod management for DCS World.
- Thanks to the DCS community for their continuous support and feedback.

---

Happy Modding!
