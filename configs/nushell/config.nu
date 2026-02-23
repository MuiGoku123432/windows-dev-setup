# Nushell configuration

$env.config = {
  show_banner: false

  completions: {
    case_sensitive: false
    algorithm: "fuzzy"
  }

  table: {
    mode: rounded
  }

  history: {
    file_format: "sqlite"
    max_size: 10000
  }
}

# Aliases
alias vim = nvim
alias ll = ls -l
alias la = ls -la
