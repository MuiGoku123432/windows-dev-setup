#Requires -Version 5.1
<#
.SYNOPSIS
    Bootstraps a complete Windows dev environment.
.DESCRIPTION
    Installs and configures WezTerm, Nushell, Neovim/LazyVim, Starship,
    Git, and supporting tools. Safe to re-run (idempotent).
.NOTES
    Run from the repo root: .\setup.ps1
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

$script:failures = @()
$script:ScriptRoot = $PSScriptRoot

# ─── Helper Functions ────────────────────────────────────────────────

function Write-Step {
    param([string]$Message)
    Write-Host ""
    Write-Host ":: $Message" -ForegroundColor Cyan
}

function Write-Success {
    param([string]$Message)
    Write-Host "   [OK] $Message" -ForegroundColor Green
}

function Write-Skip {
    param([string]$Message)
    Write-Host "   [SKIP] $Message" -ForegroundColor Yellow
}

function Write-Fail {
    param([string]$Message)
    Write-Host "   [FAIL] $Message" -ForegroundColor Red
    $script:failures += $Message
}

function Refresh-Path {
    $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $env:Path = "$machinePath;$userPath"
}

function Install-WingetPackage {
    param(
        [string]$PackageId,
        [string]$DisplayName
    )

    # Check if already installed
    $listed = winget list --id $PackageId --accept-source-agreements 2>$null
    if ($LASTEXITCODE -eq 0 -and ($listed | Select-String -Pattern $PackageId -Quiet)) {
        Write-Skip "$DisplayName already installed"
        return
    }

    Write-Host "   Installing $DisplayName..." -ForegroundColor White
    winget install --id $PackageId --exact --accept-source-agreements --accept-package-agreements --silent 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Fail "Failed to install $DisplayName ($PackageId)"
        return
    }

    Refresh-Path
    Write-Success "$DisplayName installed"
}

function Install-ScoopPackage {
    param(
        [string]$PackageName,
        [string]$Bucket
    )

    # Check if already installed
    $scoopList = scoop list 2>$null | Out-String
    if ($scoopList -match $PackageName) {
        Write-Skip "$PackageName already installed (scoop)"
        return
    }

    # Add bucket if specified and not already added
    if ($Bucket) {
        $bucketList = scoop bucket list 2>$null | Out-String
        if (-not ($bucketList -match $Bucket)) {
            Write-Host "   Adding scoop bucket '$Bucket'..." -ForegroundColor White
            scoop bucket add $Bucket 2>$null
        }
    }

    Write-Host "   Installing $PackageName via scoop..." -ForegroundColor White
    scoop install "$PackageName" 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Fail "Failed to install $PackageName via scoop"
        return
    }

    Refresh-Path
    Write-Success "$PackageName installed (scoop)"
}

function Deploy-ConfigFile {
    param(
        [string]$SourceRelativePath,
        [string]$TargetPath
    )

    $sourcePath = Join-Path $script:ScriptRoot $SourceRelativePath

    if (-not (Test-Path $sourcePath)) {
        Write-Fail "Source config not found: $SourceRelativePath"
        return
    }

    # Ensure target directory exists
    $targetDir = Split-Path $TargetPath -Parent
    if (-not (Test-Path $targetDir)) {
        New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
    }

    # If target exists, compare SHA256 hashes
    if (Test-Path $TargetPath) {
        $sourceHash = (Get-FileHash $sourcePath -Algorithm SHA256).Hash
        $targetHash = (Get-FileHash $TargetPath -Algorithm SHA256).Hash

        if ($sourceHash -eq $targetHash) {
            Write-Skip "$TargetPath is up to date"
            return
        }

        # Backup existing file with timestamp
        $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
        $backupPath = "$TargetPath.bak.$timestamp"
        Copy-Item $TargetPath $backupPath
        Write-Host "   Backed up existing file to $backupPath" -ForegroundColor Yellow
    }

    Copy-Item $sourcePath $TargetPath -Force
    Write-Success "Deployed $SourceRelativePath -> $TargetPath"
}

function Set-GitConfigIfMissing {
    param(
        [string]$Key,
        [string]$Value
    )

    $current = git config --global --get $Key 2>$null
    if ($current) {
        Write-Skip "git $Key already set to '$current'"
        return
    }

    git config --global $Key $Value
    Write-Success "git $Key set to '$Value'"
}

# ─── Preflight Checks ───────────────────────────────────────────────

Write-Host ""
Write-Host "========================================" -ForegroundColor Magenta
Write-Host "  Windows Dev Environment Setup" -ForegroundColor Magenta
Write-Host "========================================" -ForegroundColor Magenta

Write-Step "Running preflight checks"

# Check winget
if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Write-Host ""
    Write-Host "ERROR: winget is not available." -ForegroundColor Red
    Write-Host "Install 'App Installer' from the Microsoft Store, then re-run this script." -ForegroundColor Red
    Write-Host "https://apps.microsoft.com/detail/9NBLGGH4NNS1" -ForegroundColor Yellow
    exit 1
}
Write-Success "winget found"

# Check internet connectivity
try {
    $null = Invoke-WebRequest -Uri "https://www.github.com" -UseBasicParsing -TimeoutSec 10
    Write-Success "Internet connectivity OK"
} catch {
    Write-Host ""
    Write-Host "ERROR: Cannot reach github.com. Check your internet connection." -ForegroundColor Red
    exit 1
}

# Set execution policy for current user if needed
$currentPolicy = Get-ExecutionPolicy -Scope CurrentUser
if ($currentPolicy -eq "Restricted" -or $currentPolicy -eq "Undefined") {
    Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force
    Write-Success "Execution policy set to RemoteSigned for current user"
} else {
    Write-Skip "Execution policy already set to $currentPolicy"
}

# ─── Step 1: Install Scoop ──────────────────────────────────────────

Write-Step "Step 1/13: Scoop (package manager)"

if (Get-Command scoop -ErrorAction SilentlyContinue) {
    Write-Skip "Scoop already installed"
} else {
    Write-Host "   Installing Scoop..." -ForegroundColor White
    try {
        Invoke-RestMethod get.scoop.sh | Invoke-Expression
        Refresh-Path
        Write-Success "Scoop installed"
    } catch {
        Write-Fail "Failed to install Scoop: $_"
    }
}

# ─── Step 2: Install Git ────────────────────────────────────────────

Write-Step "Step 2/13: Git"
Install-WingetPackage "Git.Git" "Git"

# ─── Git Identity Prompt ────────────────────────────────────────────

if (Get-Command git -ErrorAction SilentlyContinue) {
    $gitName = git config --global --get user.name 2>$null
    $gitEmail = git config --global --get user.email 2>$null

    if (-not $gitName) {
        Write-Host ""
        Write-Host "   Git user.name not configured." -ForegroundColor Yellow
        $inputName = Read-Host "   Enter your name (e.g. John Doe)"
        if ($inputName) {
            git config --global user.name $inputName
            Write-Success "git user.name set to '$inputName'"
        }
    } else {
        Write-Skip "git user.name already set to '$gitName'"
    }

    if (-not $gitEmail) {
        Write-Host "   Git user.email not configured." -ForegroundColor Yellow
        $inputEmail = Read-Host "   Enter your email (e.g. john@example.com)"
        if ($inputEmail) {
            git config --global user.email $inputEmail
            Write-Success "git user.email set to '$inputEmail'"
        }
    } else {
        Write-Skip "git user.email already set to '$gitEmail'"
    }
}

# ─── Step 3: JetBrainsMono Nerd Font ────────────────────────────────

Write-Step "Step 3/13: JetBrainsMono Nerd Font"
Install-ScoopPackage "JetBrainsMono-NF" "nerd-fonts"

# ─── Step 4: Zig ────────────────────────────────────────────────────

Write-Step "Step 4/13: Zig (C compiler for Treesitter)"
Install-WingetPackage "zig.zig" "Zig"

# ─── Step 5: ripgrep ────────────────────────────────────────────────

Write-Step "Step 5/13: ripgrep"
Install-WingetPackage "BurntSushi.ripgrep.MSVC" "ripgrep"

# ─── Step 6: fd ─────────────────────────────────────────────────────

Write-Step "Step 6/13: fd"
Install-WingetPackage "sharkdp.fd" "fd"

# ─── Step 7: Volta ──────────────────────────────────────────────────

Write-Step "Step 7/13: Volta (JS toolchain manager)"
Install-WingetPackage "Volta.Volta" "Volta"

# ─── Step 8: Node.js via Volta ───────────────────────────────────────

Write-Step "Step 8/13: Node.js LTS (via Volta)"

if (Get-Command node -ErrorAction SilentlyContinue) {
    $nodeVersion = node --version 2>$null
    Write-Skip "Node.js already installed ($nodeVersion)"
} else {
    if (Get-Command volta -ErrorAction SilentlyContinue) {
        Write-Host "   Installing Node.js LTS via Volta..." -ForegroundColor White
        volta install node 2>$null
        if ($LASTEXITCODE -ne 0) {
            Write-Fail "Failed to install Node.js via Volta"
        } else {
            Refresh-Path
            Write-Success "Node.js LTS installed via Volta"
        }
    } else {
        Write-Fail "Volta not found - cannot install Node.js"
    }
}

# ─── Step 9: Nushell ────────────────────────────────────────────────

Write-Step "Step 9/13: Nushell"
Install-WingetPackage "Nushell.Nushell" "Nushell"

# ─── Step 10: Starship ──────────────────────────────────────────────

Write-Step "Step 10/13: Starship (prompt)"
Install-WingetPackage "Starship.Starship" "Starship"

# ─── Step 11: WezTerm ───────────────────────────────────────────────

Write-Step "Step 11/13: WezTerm"
Install-WingetPackage "wez.wezterm" "WezTerm"

# ─── Step 12: Neovim ────────────────────────────────────────────────

Write-Step "Step 12/13: Neovim"
Install-WingetPackage "Neovim.Neovim" "Neovim"

# ─── Step 13: LazyVim ───────────────────────────────────────────────

Write-Step "Step 13/13: LazyVim (Neovim distribution)"

$nvimConfigDir = Join-Path $env:LOCALAPPDATA "nvim"
$lazyVimMarker = Join-Path $nvimConfigDir "lua" "config" "lazy.lua"

if (Test-Path $lazyVimMarker) {
    Write-Skip "LazyVim already configured"
} else {
    if (Get-Command git -ErrorAction SilentlyContinue) {
        # Backup existing nvim config if present
        if (Test-Path $nvimConfigDir) {
            $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
            $backupDir = "$nvimConfigDir.bak.$timestamp"
            Write-Host "   Backing up existing nvim config to $backupDir" -ForegroundColor Yellow
            Rename-Item $nvimConfigDir $backupDir
        }

        Write-Host "   Cloning LazyVim starter..." -ForegroundColor White
        git clone https://github.com/LazyVim/starter $nvimConfigDir 2>$null
        if ($LASTEXITCODE -ne 0) {
            Write-Fail "Failed to clone LazyVim starter"
        } else {
            # Remove .git so user can version-control separately
            $gitDir = Join-Path $nvimConfigDir ".git"
            if (Test-Path $gitDir) {
                Remove-Item $gitDir -Recurse -Force
            }
            Write-Success "LazyVim starter cloned to $nvimConfigDir"
        }
    } else {
        Write-Fail "Git not found - cannot clone LazyVim starter"
    }
}

# ─── Deploy Config Files ────────────────────────────────────────────

Write-Step "Deploying configuration files"

Deploy-ConfigFile "configs\wezterm\.wezterm.lua" (Join-Path $HOME ".wezterm.lua")
Deploy-ConfigFile "configs\nushell\config.nu" (Join-Path $env:APPDATA "nushell\config.nu")
Deploy-ConfigFile "configs\nushell\env.nu" (Join-Path $env:APPDATA "nushell\env.nu")
Deploy-ConfigFile "configs\starship\starship.toml" (Join-Path $HOME ".config\starship.toml")

# ─── Git Config ──────────────────────────────────────────────────────

Write-Step "Configuring Git defaults"

if (Get-Command git -ErrorAction SilentlyContinue) {
    Set-GitConfigIfMissing "core.editor" "nvim"
    Set-GitConfigIfMissing "core.autocrlf" "true"
    Set-GitConfigIfMissing "init.defaultBranch" "main"
    Set-GitConfigIfMissing "pull.rebase" "true"
    Set-GitConfigIfMissing "diff.colorMoved" "default"
    Set-GitConfigIfMissing "merge.conflictstyle" "diff3"
} else {
    Write-Fail "Git not found - skipping git config"
}

# ─── Post-Install Verification ──────────────────────────────────────

Write-Step "Verifying installations"

Refresh-Path

$tools = @(
    @{ Name = "git";      Cmd = "git";      Args = "--version" },
    @{ Name = "scoop";    Cmd = "scoop";    Args = "--version" },
    @{ Name = "zig";      Cmd = "zig";      Args = "version" },
    @{ Name = "rg";       Cmd = "rg";       Args = "--version" },
    @{ Name = "fd";       Cmd = "fd";       Args = "--version" },
    @{ Name = "volta";    Cmd = "volta";    Args = "--version" },
    @{ Name = "node";     Cmd = "node";     Args = "--version" },
    @{ Name = "nu";       Cmd = "nu";       Args = "--version" },
    @{ Name = "starship"; Cmd = "starship"; Args = "--version" },
    @{ Name = "wezterm";  Cmd = "wezterm";  Args = "--version" },
    @{ Name = "nvim";     Cmd = "nvim";     Args = "--version" }
)

Write-Host ""
Write-Host "   Tool            Version" -ForegroundColor White
Write-Host "   ────            ───────" -ForegroundColor White

foreach ($tool in $tools) {
    if (Get-Command $tool.Cmd -ErrorAction SilentlyContinue) {
        $version = & $tool.Cmd $tool.Args 2>$null | Select-Object -First 1
        $version = ($version -replace ".*?(\d+\.\d+[\.\d]*).*", '$1').Trim()
        Write-Host ("   {0,-16}{1}" -f $tool.Name, $version) -ForegroundColor Green
    } else {
        Write-Host ("   {0,-16}{1}" -f $tool.Name, "NOT FOUND") -ForegroundColor Red
    }
}

# ─── Summary ─────────────────────────────────────────────────────────

Write-Host ""

if ($script:failures.Count -gt 0) {
    Write-Host "========================================" -ForegroundColor Red
    Write-Host "  Completed with $($script:failures.Count) failure(s):" -ForegroundColor Red
    Write-Host "========================================" -ForegroundColor Red
    foreach ($fail in $script:failures) {
        Write-Host "  - $fail" -ForegroundColor Red
    }
    Write-Host ""
} else {
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "  All done! No failures." -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
}

Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "  1. Open WezTerm - it launches Nushell automatically"
Write-Host "  2. Run 'nvim' to trigger first-time LazyVim plugin install (~1-2 min)"
Write-Host "  3. Customize configs in this repo's configs/ directory, re-run setup.ps1 to apply"
Write-Host ""
