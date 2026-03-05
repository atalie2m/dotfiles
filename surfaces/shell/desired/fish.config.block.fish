# Dotfiles-managed fish runtime entrypoint.
# Add installer/app snippets outside this managed block in ~/.config/fish/config.fish.
if test -f "$HOME/.config/fish/hm-fish/config.fish"
  source "$HOME/.config/fish/hm-fish/config.fish"
end
