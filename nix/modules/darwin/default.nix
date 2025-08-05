_:

{
  imports = [
    ./fonts.nix
  ];

  # Generic Darwin system configuration that applies to all Darwin hosts
  # Host-specific settings are provided via Denix hosts and rices

  environment.systemPackages = [ ];
}
