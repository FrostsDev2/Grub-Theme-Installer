# Frosts GRUB Theme Installer

This repository contains a comprehensive shell script designed to install GRUB
bootloader themes and manage GRUB configuration settings across various Linux
distributions.

# What is this?

This project is an automated installer and management tool for GRUB themes.
Beyond simply copying files, it acts as a configuration utility that allows
users to modify bootloader behavior (such as timeouts and default entries)
through an interactive terminal interface. It is designed to be
"theme-agnostic," meaning the install.sh script can be placed into any GRUB
theme folder and it will automatically handle the installation process for that
specific theme.

# Features

  - Cross-Distribution Support: Automatically detects and uses package managers
    for Ubuntu/Debian (apt), Fedora/CentOS (dnf/yum), Arch Linux (pacman),
    OpenSUSE (zypper), Void Linux (xbps), and Solus (eopkg).
  - Interactive Customization Menu: A built-in TUI (Terminal User Interface) to
    manage boot settings without manual file editing.
  - Smart Detection: Automatically identifies the correct GRUB paths and handles
    distribution-specific quirks (like Fedora's font paths or Kali Linux's
    configuration overrides).
  - Automatic Backups: Creates backups of your /etc/default/grub file before
    making any modifications.
  - Safety Checks: Verifies the existence of required theme files (like
    theme.txt) before attempting installation.

# How it Works

The script operates in three primary modes:

1.  Installation Mode (Default):

      - Detects the root directory of the theme.
      - Installs necessary dependencies if they are missing.
      - Copies theme assets to /usr/share/grub/themes (or /boot if specified).
      - Modifies /etc/default/grub to point to the new theme and disables
        conflicting settings (like graphical terminal overrides).
      - Regenerates the GRUB configuration file.

2.  Management Mode (--menu):

      - Provides a menu to change the GRUB_TIMEOUT.
      - Changes the GRUB_DEFAULT boot entry.
      - Toggles GRUB_SAVEDEFAULT behavior.
      - Switches between hidden and visible menu styles.

3.  Removal Mode (--remove):

      - Deletes the theme files from the system.
      - Reverts changes in /etc/default/grub by commenting out the theme path.
      - Regenerates the GRUB configuration to restore the default look.

# Installation and Usage

Prerequisites

  - A Linux-based operating system using GRUB2.
  - Bash shell.
  - Root (sudo) privileges.

Basic Installation

To install the theme located in the current directory:

chmod +x install.sh
sudo ./install.sh

Using the Customization Menu

To manage boot settings (timeout, default entry, etc.) interactively:

sudo ./install.sh --menu

Uninstallation

To remove the theme and revert to system defaults:

sudo ./install.sh --remove

Command Line Options

| Option     | Long Flag    | Description                                                                        |
| :--------- | :----------- | :--------------------------------------------------------------------------------- |
| `-b`       | `--boot`     | Install theme into `/boot/grub/themes` instead of `/usr/share/grub/themes`.        |
| `-g [DIR]` | `--generate` | Only copy theme files into the specified directory; do not modify system settings. |
| `-r`       | `--remove`   | Remove the theme and reset GRUB configuration.                                     |
| `-m`       | `--menu`     | Launch the interactive GRUB customization menu.                                    |
| `-h`       | `--help`     | Show the help menu and exit.                                                       |

# Troubleshooting

  - Incorrect Password: The script requires root privileges to modify
    /etc/default/grub and the /boot partition. Ensure you run the script with
    sudo.
  - Theme not appearing: If the theme does not appear after a successful
    installation, ensure that "Secure Boot" is not interfering with GRUB
    customization on certain hardware, or try installing to the boot partition
    using the -b flag.
  - Restore Defaults: If you need to manually restore your GRUB settings, the
    script saves a backup of your configuration at /etc/default/grub.bak.
