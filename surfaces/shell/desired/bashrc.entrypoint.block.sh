# Dotfiles-managed bash runtime entrypoint.
# Add installer/app snippets outside this managed block in ~/.bashrc.
if [[ -f "$HOME/.nix/hm-bash/.bashrc" ]]; then
  source "$HOME/.nix/hm-bash/.bashrc"
fi
if [[ -f "$HOME/.config/shell/bash.local.sh" ]]; then
  source "$HOME/.config/shell/bash.local.sh"
fi
