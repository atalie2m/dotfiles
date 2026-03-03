# Dotfiles-managed ZDOTDIR zsh wrapper.
# Add installer/app snippets outside this managed block in ~/.nix/.zshrc.
if [[ -f "$HOME/.nix/hm-zsh/.zshrc" ]]; then
  source "$HOME/.nix/hm-zsh/.zshrc"
elif [[ -f "$HOME/.zshrc.local" ]]; then
  source "$HOME/.zshrc.local"
fi
