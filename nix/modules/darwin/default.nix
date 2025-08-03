_:

{
  imports = [
    ./fonts.nix
  ];

  # Generic Darwin system configuration that applies to all Darwin hosts
  # Host-specific settings should go in profiles/

  environment.systemPackages = [ ];
}
