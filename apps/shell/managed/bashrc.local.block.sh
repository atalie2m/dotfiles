# Dotfiles-managed local bash hooks.
# Add personal/app snippets outside the managed block in ~/.bashrc.local.
if [[ -f "$HOME/.config/shell/bash.local.sh" ]]; then
  source "$HOME/.config/shell/bash.local.sh"
fi
