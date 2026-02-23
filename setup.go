//go:build windows

package main

import (
	"bufio"
	"crypto/sha256"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"syscall"
	"time"
	"unsafe"
)

// ─── Global State ───────────────────────────────────────────────────

var failures []string
var scriptRoot string

// ─── ANSI Colors ────────────────────────────────────────────────────

const (
	colorReset   = "\033[0m"
	colorRed     = "\033[31m"
	colorGreen   = "\033[32m"
	colorYellow  = "\033[33m"
	colorCyan    = "\033[36m"
	colorMagenta = "\033[35m"
	colorWhite   = "\033[37m"
)

// ─── Windows Console Setup ──────────────────────────────────────────

func enableVirtualTerminal() {
	kernel32 := syscall.NewLazyDLL("kernel32.dll")
	getStdHandle := kernel32.NewProc("GetStdHandle")
	getConsoleMode := kernel32.NewProc("GetConsoleMode")
	setConsoleMode := kernel32.NewProc("SetConsoleMode")

	const stdOutputHandle = ^uintptr(0) - 11 + 1 // STD_OUTPUT_HANDLE = -11
	const enableVirtualTerminalProcessing = 0x0004

	handle, _, _ := getStdHandle.Call(stdOutputHandle)
	var mode uint32
	getConsoleMode.Call(handle, uintptr(unsafe.Pointer(&mode)))
	setConsoleMode.Call(handle, uintptr(mode|enableVirtualTerminalProcessing))
}

// ─── Helper Functions ───────────────────────────────────────────────

func writeStep(msg string) {
	fmt.Printf("\n%s:: %s%s\n", colorCyan, msg, colorReset)
}

func writeSuccess(msg string) {
	fmt.Printf("   %s[OK]%s %s\n", colorGreen, colorReset, msg)
}

func writeSkip(msg string) {
	fmt.Printf("   %s[SKIP]%s %s\n", colorYellow, colorReset, msg)
}

func writeFail(msg string) {
	fmt.Printf("   %s[FAIL]%s %s\n", colorRed, colorReset, msg)
	failures = append(failures, msg)
}

func refreshPath() {
	out, err := exec.Command("powershell", "-NoProfile", "-Command",
		`[Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User')`).Output()
	if err == nil {
		os.Setenv("PATH", strings.TrimSpace(string(out)))
	}
}

func commandExists(name string) bool {
	_, err := exec.LookPath(name)
	return err == nil
}

func runCmd(name string, args ...string) (string, error) {
	cmd := exec.Command(name, args...)
	out, err := cmd.CombinedOutput()
	return strings.TrimSpace(string(out)), err
}

func runCmdPassthrough(name string, args ...string) error {
	cmd := exec.Command(name, args...)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	cmd.Stdin = os.Stdin
	return cmd.Run()
}

func installWingetPackage(packageID, displayName string) {
	out, _ := runCmd("winget", "list", "--id", packageID, "--accept-source-agreements")
	if strings.Contains(out, packageID) {
		writeSkip(displayName + " already installed")
		return
	}

	fmt.Printf("   %sInstalling %s...%s\n", colorWhite, displayName, colorReset)
	err := runCmdPassthrough("winget", "install", "--id", packageID, "--exact",
		"--accept-source-agreements", "--accept-package-agreements", "--silent")
	if err != nil {
		writeFail(fmt.Sprintf("Failed to install %s (%s)", displayName, packageID))
		return
	}

	refreshPath()
	writeSuccess(displayName + " installed")
}

func installScoopPackage(pkg, bucket string) {
	out, _ := runCmd("scoop", "list")
	if strings.Contains(out, pkg) {
		writeSkip(pkg + " already installed (scoop)")
		return
	}

	if bucket != "" {
		bucketOut, _ := runCmd("scoop", "bucket", "list")
		if !strings.Contains(bucketOut, bucket) {
			fmt.Printf("   %sAdding scoop bucket '%s'...%s\n", colorWhite, bucket, colorReset)
			runCmd("scoop", "bucket", "add", bucket)
		}
	}

	fmt.Printf("   %sInstalling %s via scoop...%s\n", colorWhite, pkg, colorReset)
	err := runCmdPassthrough("scoop", "install", pkg)
	if err != nil {
		writeFail("Failed to install " + pkg + " via scoop")
		return
	}

	refreshPath()
	writeSuccess(pkg + " installed (scoop)")
}

func fileHash(path string) (string, error) {
	f, err := os.Open(path)
	if err != nil {
		return "", err
	}
	defer f.Close()

	h := sha256.New()
	if _, err := io.Copy(h, f); err != nil {
		return "", err
	}
	return fmt.Sprintf("%x", h.Sum(nil)), nil
}

func deployConfigFile(srcRel, target string) {
	sourcePath := filepath.Join(scriptRoot, srcRel)

	if _, err := os.Stat(sourcePath); os.IsNotExist(err) {
		writeFail("Source config not found: " + srcRel)
		return
	}

	targetDir := filepath.Dir(target)
	if err := os.MkdirAll(targetDir, 0755); err != nil {
		writeFail("Failed to create directory: " + targetDir)
		return
	}

	if _, err := os.Stat(target); err == nil {
		srcHash, err1 := fileHash(sourcePath)
		tgtHash, err2 := fileHash(target)
		if err1 == nil && err2 == nil && srcHash == tgtHash {
			writeSkip(target + " is up to date")
			return
		}

		timestamp := time.Now().Format("20060102-150405")
		backupPath := target + ".bak." + timestamp
		copyFile(target, backupPath)
		fmt.Printf("   %sBacked up existing file to %s%s\n", colorYellow, backupPath, colorReset)
	}

	if err := copyFile(sourcePath, target); err != nil {
		writeFail("Failed to deploy " + srcRel + ": " + err.Error())
		return
	}
	writeSuccess("Deployed " + srcRel + " -> " + target)
}

func copyFile(src, dst string) error {
	in, err := os.Open(src)
	if err != nil {
		return err
	}
	defer in.Close()

	out, err := os.Create(dst)
	if err != nil {
		return err
	}
	defer out.Close()

	_, err = io.Copy(out, in)
	return err
}

func setGitConfigIfMissing(key, value string) {
	current, _ := runCmd("git", "config", "--global", "--get", key)
	if current != "" {
		writeSkip(fmt.Sprintf("git %s already set to '%s'", key, current))
		return
	}

	runCmd("git", "config", "--global", key, value)
	writeSuccess(fmt.Sprintf("git %s set to '%s'", key, value))
}

func promptInput(prompt string) string {
	fmt.Print(prompt)
	reader := bufio.NewReader(os.Stdin)
	input, _ := reader.ReadString('\n')
	return strings.TrimSpace(input)
}

// ─── Main ───────────────────────────────────────────────────────────

func main() {
	enableVirtualTerminal()

	// Determine script root from executable location
	exePath, err := os.Executable()
	if err != nil {
		fmt.Println("ERROR: Cannot determine executable path:", err)
		os.Exit(1)
	}
	scriptRoot = filepath.Dir(exePath)

	// ─── Banner ─────────────────────────────────────────────────────
	fmt.Println()
	fmt.Printf("%s========================================%s\n", colorMagenta, colorReset)
	fmt.Printf("%s  Windows Dev Environment Setup%s\n", colorMagenta, colorReset)
	fmt.Printf("%s========================================%s\n", colorMagenta, colorReset)

	// ─── Preflight Checks ───────────────────────────────────────────
	writeStep("Running preflight checks")

	if !commandExists("winget") {
		fmt.Println()
		fmt.Printf("%sERROR: winget is not available.%s\n", colorRed, colorReset)
		fmt.Printf("%sInstall 'App Installer' from the Microsoft Store, then re-run this program.%s\n", colorRed, colorReset)
		fmt.Printf("%shttps://apps.microsoft.com/detail/9NBLGGH4NNS1%s\n", colorYellow, colorReset)
		os.Exit(1)
	}
	writeSuccess("winget found")

	client := &http.Client{Timeout: 10 * time.Second}
	resp, err := client.Get("https://www.github.com")
	if err != nil {
		fmt.Println()
		fmt.Printf("%sERROR: Cannot reach github.com. Check your internet connection.%s\n", colorRed, colorReset)
		os.Exit(1)
	}
	resp.Body.Close()
	writeSuccess("Internet connectivity OK")

	// ─── Step 1: Scoop ──────────────────────────────────────────────
	writeStep("Step 1/13: Scoop (package manager)")

	if commandExists("scoop") {
		writeSkip("Scoop already installed")
	} else {
		fmt.Printf("   %sInstalling Scoop...%s\n", colorWhite, colorReset)
		err := runCmdPassthrough("powershell", "-NoProfile", "-Command",
			"Invoke-RestMethod get.scoop.sh | Invoke-Expression")
		if err != nil {
			writeFail("Failed to install Scoop: " + err.Error())
		} else {
			refreshPath()
			writeSuccess("Scoop installed")
		}
	}

	// ─── Step 2: Git ────────────────────────────────────────────────
	writeStep("Step 2/13: Git")
	installWingetPackage("Git.Git", "Git")

	// ─── Git Identity Prompt ────────────────────────────────────────
	if commandExists("git") {
		gitName, _ := runCmd("git", "config", "--global", "--get", "user.name")
		gitEmail, _ := runCmd("git", "config", "--global", "--get", "user.email")

		if gitName == "" {
			fmt.Println()
			fmt.Printf("   %sGit user.name not configured.%s\n", colorYellow, colorReset)
			inputName := promptInput("   Enter your name (e.g. John Doe): ")
			if inputName != "" {
				runCmd("git", "config", "--global", "user.name", inputName)
				writeSuccess(fmt.Sprintf("git user.name set to '%s'", inputName))
			}
		} else {
			writeSkip(fmt.Sprintf("git user.name already set to '%s'", gitName))
		}

		if gitEmail == "" {
			fmt.Printf("   %sGit user.email not configured.%s\n", colorYellow, colorReset)
			inputEmail := promptInput("   Enter your email (e.g. john@example.com): ")
			if inputEmail != "" {
				runCmd("git", "config", "--global", "user.email", inputEmail)
				writeSuccess(fmt.Sprintf("git user.email set to '%s'", inputEmail))
			}
		} else {
			writeSkip(fmt.Sprintf("git user.email already set to '%s'", gitEmail))
		}
	}

	// ─── Step 3: JetBrainsMono Nerd Font ────────────────────────────
	writeStep("Step 3/13: JetBrainsMono Nerd Font")
	installScoopPackage("JetBrainsMono-NF", "nerd-fonts")

	// ─── Step 4: Zig ────────────────────────────────────────────────
	writeStep("Step 4/13: Zig (C compiler for Treesitter)")
	installWingetPackage("zig.zig", "Zig")

	// ─── Step 5: ripgrep ────────────────────────────────────────────
	writeStep("Step 5/13: ripgrep")
	installWingetPackage("BurntSushi.ripgrep.MSVC", "ripgrep")

	// ─── Step 6: fd ─────────────────────────────────────────────────
	writeStep("Step 6/13: fd")
	installWingetPackage("sharkdp.fd", "fd")

	// ─── Step 7: Volta ──────────────────────────────────────────────
	writeStep("Step 7/13: Volta (JS toolchain manager)")
	installWingetPackage("Volta.Volta", "Volta")

	// ─── Step 8: Node.js via Volta ──────────────────────────────────
	writeStep("Step 8/13: Node.js LTS (via Volta)")

	if commandExists("node") {
		nodeVersion, _ := runCmd("node", "--version")
		writeSkip("Node.js already installed (" + nodeVersion + ")")
	} else {
		if commandExists("volta") {
			fmt.Printf("   %sInstalling Node.js LTS via Volta...%s\n", colorWhite, colorReset)
			err := runCmdPassthrough("volta", "install", "node")
			if err != nil {
				writeFail("Failed to install Node.js via Volta")
			} else {
				refreshPath()
				writeSuccess("Node.js LTS installed via Volta")
			}
		} else {
			writeFail("Volta not found - cannot install Node.js")
		}
	}

	// ─── Step 9: Nushell ────────────────────────────────────────────
	writeStep("Step 9/13: Nushell")
	installWingetPackage("Nushell.Nushell", "Nushell")

	// ─── Step 10: Starship ──────────────────────────────────────────
	writeStep("Step 10/13: Starship (prompt)")
	installWingetPackage("Starship.Starship", "Starship")

	// ─── Step 11: WezTerm ───────────────────────────────────────────
	writeStep("Step 11/13: WezTerm")
	installWingetPackage("wez.wezterm", "WezTerm")

	// ─── Step 12: Neovim ────────────────────────────────────────────
	writeStep("Step 12/13: Neovim")
	installWingetPackage("Neovim.Neovim", "Neovim")

	// ─── Step 13: LazyVim ───────────────────────────────────────────
	writeStep("Step 13/13: LazyVim (Neovim distribution)")

	localAppData := os.Getenv("LOCALAPPDATA")
	nvimConfigDir := filepath.Join(localAppData, "nvim")
	lazyVimMarker := filepath.Join(nvimConfigDir, "lua", "config", "lazy.lua")

	if _, err := os.Stat(lazyVimMarker); err == nil {
		writeSkip("LazyVim already configured")
	} else {
		if commandExists("git") {
			// Backup existing nvim config if present
			if _, err := os.Stat(nvimConfigDir); err == nil {
				timestamp := time.Now().Format("20060102-150405")
				backupDir := nvimConfigDir + ".bak." + timestamp
				fmt.Printf("   %sBacking up existing nvim config to %s%s\n", colorYellow, backupDir, colorReset)
				os.Rename(nvimConfigDir, backupDir)
			}

			fmt.Printf("   %sCloning LazyVim starter...%s\n", colorWhite, colorReset)
			err := runCmdPassthrough("git", "clone", "https://github.com/LazyVim/starter", nvimConfigDir)
			if err != nil {
				writeFail("Failed to clone LazyVim starter")
			} else {
				gitDir := filepath.Join(nvimConfigDir, ".git")
				os.RemoveAll(gitDir)
				writeSuccess("LazyVim starter cloned to " + nvimConfigDir)
			}
		} else {
			writeFail("Git not found - cannot clone LazyVim starter")
		}
	}

	// ─── Deploy Config Files ────────────────────────────────────────
	writeStep("Deploying configuration files")

	userProfile := os.Getenv("USERPROFILE")
	appData := os.Getenv("APPDATA")

	deployConfigFile(
		filepath.Join("configs", "wezterm", ".wezterm.lua"),
		filepath.Join(userProfile, ".wezterm.lua"),
	)
	deployConfigFile(
		filepath.Join("configs", "nushell", "config.nu"),
		filepath.Join(appData, "nushell", "config.nu"),
	)
	deployConfigFile(
		filepath.Join("configs", "nushell", "env.nu"),
		filepath.Join(appData, "nushell", "env.nu"),
	)
	deployConfigFile(
		filepath.Join("configs", "starship", "starship.toml"),
		filepath.Join(userProfile, ".config", "starship.toml"),
	)

	// ─── Git Config ─────────────────────────────────────────────────
	writeStep("Configuring Git defaults")

	if commandExists("git") {
		setGitConfigIfMissing("core.editor", "nvim")
		setGitConfigIfMissing("core.autocrlf", "true")
		setGitConfigIfMissing("init.defaultBranch", "main")
		setGitConfigIfMissing("pull.rebase", "true")
		setGitConfigIfMissing("diff.colorMoved", "default")
		setGitConfigIfMissing("merge.conflictstyle", "diff3")
	} else {
		writeFail("Git not found - skipping git config")
	}

	// ─── Post-Install Verification ──────────────────────────────────
	writeStep("Verifying installations")

	refreshPath()

	type tool struct {
		name string
		cmd  string
		args string
	}

	tools := []tool{
		{"git", "git", "--version"},
		{"scoop", "scoop", "--version"},
		{"zig", "zig", "version"},
		{"rg", "rg", "--version"},
		{"fd", "fd", "--version"},
		{"volta", "volta", "--version"},
		{"node", "node", "--version"},
		{"nu", "nu", "--version"},
		{"starship", "starship", "--version"},
		{"wezterm", "wezterm", "--version"},
		{"nvim", "nvim", "--version"},
	}

	fmt.Println()
	fmt.Printf("   %sTool            Version%s\n", colorWhite, colorReset)
	fmt.Printf("   %s────            ───────%s\n", colorWhite, colorReset)

	for _, t := range tools {
		if commandExists(t.cmd) {
			out, _ := runCmd(t.cmd, t.args)
			// Take first line only
			version := out
			if idx := strings.IndexByte(version, '\n'); idx != -1 {
				version = version[:idx]
			}
			// Extract version number
			version = extractVersion(version)
			fmt.Printf("   %s%-16s%s%s\n", colorGreen, t.name, version, colorReset)
		} else {
			fmt.Printf("   %s%-16s%s%s\n", colorRed, t.name, "NOT FOUND", colorReset)
		}
	}

	// ─── Summary ────────────────────────────────────────────────────
	fmt.Println()

	if len(failures) > 0 {
		fmt.Printf("%s========================================%s\n", colorRed, colorReset)
		fmt.Printf("%s  Completed with %d failure(s):%s\n", colorRed, len(failures), colorReset)
		fmt.Printf("%s========================================%s\n", colorRed, colorReset)
		for _, fail := range failures {
			fmt.Printf("  %s- %s%s\n", colorRed, fail, colorReset)
		}
		fmt.Println()
	} else {
		fmt.Printf("%s========================================%s\n", colorGreen, colorReset)
		fmt.Printf("%s  All done! No failures.%s\n", colorGreen, colorReset)
		fmt.Printf("%s========================================%s\n", colorGreen, colorReset)
	}

	fmt.Println()
	fmt.Printf("%sNext steps:%s\n", colorCyan, colorReset)
	fmt.Println("  1. Open WezTerm - it launches Nushell automatically")
	fmt.Println("  2. Run 'nvim' to trigger first-time LazyVim plugin install (~1-2 min)")
	fmt.Println("  3. Customize configs in this repo's configs/ directory, re-run setup to apply")
	fmt.Println()
}

// extractVersion pulls the first version-like string (digits and dots) from text.
func extractVersion(s string) string {
	start := -1
	for i, c := range s {
		if c >= '0' && c <= '9' {
			if start == -1 {
				start = i
			}
		} else if c == '.' && start != -1 {
			continue
		} else if start != -1 {
			return s[start:i]
		}
	}
	if start != -1 {
		return s[start:]
	}
	return s
}
