# Environment variables
$env.EDITOR = "nvim"
$env.VISUAL = "nvim"

# Starship prompt - initialize via vendor autoload
mkdir ($nu.default-config-dir | path join "vendor" "autoload")
starship init nu | save -f ($nu.default-config-dir | path join "vendor" "autoload" "starship.nu")
