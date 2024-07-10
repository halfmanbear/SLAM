# SLAM (SymLink Advanced Modding for DCS)



## Overview



SLAM (SymLink Advanced Modding) is a PowerShell-based mod management tool designed for DCS (Digital Combat Simulator) World. It leverages symbolic links to manage mods more efficiently, providing a seamless way to install, uninstall, and toggle mods without the need to move files around. This ensures that your original mod files remain untouched, and any changes made in-game are directly reflected in the linked files.



## Features

- **Space Saving:** Symbolic links enable SLAM to utilize half the disk space compared to other mod managers.

- **Efficient Mod Management:** Easily install, uninstall, and toggle mods using symbolic links.

- **Preserve Original Files:** Changes made in-game are directly reflected in the original mod files.

- **Automatic Backup:** Creates backups of original files before linking, ensuring safety and reversibility.

- **Simple Configuration:** Uses a single `config.txt` file to specify game directories for Core Mods and Save Game Mods.

- **User-Friendly Interface:** Command-line interface guides you through selecting games and mods.



## Benefits 



**SLAM:**

- Uses symbolic links, ensuring that any changes made in the game directory are directly applied to the original mod files.

- Symbolic links create a direct reference to the original files, reducing disk space usage and improving performance.

- As fewer reads/writes are performed, there is less degradation to SSDs.

- Provides a straightforward PowerShell script for managing mods.

- Automatically backs up original files before creating symbolic links, ensuring you can easily revert to the original game state if needed.

  

**Other Mod Managers:**

- Requires copying mod files to the game directory, leading to double the storage space used and potential synchronization issues.

- Involves copying and moving files, which can be time-consuming and inefficient, especially for large mods.

- Can be more complex to configure and manage, especially for users unfamiliar with their interfaces.


## Installation

1. **Clone the Repository:**
   ```sh
   git clone https://github.com/yourusername/SLAM.git
   ```

2. **Navigate to the Directory:**
   ```sh
   cd SLAM
   ```

3. **Configure `config.txt`:**
   - Create a `config.txt` file in the root directory of the project with the following contents:
     ```plaintext
     CoreGameDirectory=C:\Program Files\Eagle Dynamics\DCS World
     SaveGameDirectory=%USERPROFILE%\Saved Games\DCS
     ```

4. **Run the Script:**
   - Open PowerShell and run the script:
     ```sh
     .\SLAM.ps1
     ```

## Usage

1. **Select a Game:**
   - Follow the prompts to select the game directory.

2. **Select a Mod Parent Directory:**
   - Choose either "Core Mods" or "Save Game Mods".

3. **Select a Mod:**
   - Pick the mod you wish to install, uninstall, or toggle.

4. **Manage Mods:**
   - The script will automatically handle the installation, uninstallation, or toggling of the selected mod.

## Contributing

We welcome contributions to SLAM. Please feel free to submit issues, fork the repository, and create pull requests.

## License

SLAM is released under the MIT License. See [LICENSE](LICENSE) for more details.

## Acknowledgements

- Inspired by the need for efficient and user-friendly mod management for DCS World.
- Thanks to the DCS community for their continuous support and feedback.

---

Happy Modding!
