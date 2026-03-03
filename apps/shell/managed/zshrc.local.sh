# Dotfiles-managed local zsh hooks (whole-file managed by shell sync).
# Add personal/app snippets to ~/.config/shell/zsh.local.sh.
if [[ -f "$HOME/.config/shell/zsh.local.sh" ]]; then
  source "$HOME/.config/shell/zsh.local.sh"
fi
