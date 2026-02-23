# Windows Dev Environment Setup

A single script that bootstraps a complete Windows development environment. Available as PowerShell or a standalone Go binary.

## What Gets Installed

| Tool | Purpose |
|------|---------|
| **Git** | Version control |
| **Scoop** | Package manager (for Nerd Fonts) |
| **JetBrainsMono Nerd Font** | Terminal/editor font with icon support |
| **WezTerm** | GPU-accelerated terminal emulator |
| **Nushell** | Modern shell (default in WezTerm) |
| **Starship** | Cross-shell prompt |
| **Neovim + LazyVim** | Editor with batteries-included config |
| **Zig** | C compiler for Treesitter parsers |
| **ripgrep** | Fast text search (used by Telescope) |
| **fd** | Fast file finder (used by Telescope) |
| **Volta** | JavaScript toolchain manager |
| **Node.js** | JS runtime (for LSP servers via Mason) |

## Quick Start

### Option A: PowerShell

```powershell
git clone <this-repo-url> windos-setup
cd windos-setup
.\setup.ps1
```

### Option B: Go binary

Download `setup.exe` from the [latest GitHub Release](../../releases/latest) and place it in the repo root, or build from source:

```powershell
go build -o setup.exe setup.go
.\setup.exe
```

Both options are **idempotent** - safe to re-run at any time. They skip already-installed tools and only update config files that have changed (with timestamped backups).

## Building from Source

With Go installed:

```bash
# On Windows
go build -o setup.exe setup.go

# Cross-compile from macOS/Linux
GOOS=windows GOARCH=amd64 go build -o setup.exe setup.go
```

No external dependencies - the Go version uses only the standard library.

## Requirements

- Windows 10/11
- [winget](https://apps.microsoft.com/detail/9NBLGGH4NNS1) (App Installer from Microsoft Store)
- Internet connection
- No admin rights required

## What Gets Configured

### WezTerm (`configs/wezterm/.wezterm.lua`)
- Catppuccin Mocha color scheme
- JetBrainsMono Nerd Font
- Nushell as default shell
- Clean tab bar (hidden when single tab)

### Nushell (`configs/nushell/`)
- Starship prompt integration
- Fuzzy case-insensitive completions
- SQLite history (10k entries)
- Aliases: `vim`=nvim, `ll`=ls -l, `la`=ls -la

### Starship (`configs/starship/starship.toml`)
- Catppuccin Mocha themed prompt
- Git branch/status, language detection, command duration

### Git (applied via `git config --global`)
- Editor: nvim
- Default branch: main
- Pull rebase: true
- Diff3 merge conflict style

### LazyVim
- Cloned from the [official starter](https://github.com/LazyVim/starter)
- `.git` removed so you can version-control separately
- First launch of `nvim` installs all plugins automatically

## Customizing

Edit config files in the `configs/` directory, then re-run `.\setup.ps1` (or `.\setup.exe`) to deploy them. Changed files are deployed with automatic backups of the previous version.

## Repo Structure

```
windos-setup/
  setup.ps1                           # Main setup script (PowerShell)
  setup.go                            # Main setup script (Go)
  go.mod                              # Go module (no external deps)
  configs/
    wezterm/.wezterm.lua              # WezTerm config
    nushell/config.nu                 # Nushell settings
    nushell/env.nu                    # Nushell environment
    starship/starship.toml            # Starship prompt theme
  README.md
```
