# Dotfiles-managed bash runtime entrypoint.
# Add installer/app snippets outside this managed block in ~/.bashrc.
if [[ -f "$HOME/.nix/hm-bash/.bashrc" ]]; then
  source "$HOME/.nix/hm-bash/.bashrc"
elif [[ -f "$HOME/.bashrc.local" ]]; then
  source "$HOME/.bashrc.local"
fi
