{ delib, lib, pkgs, ... }:

let
  systemName =
    if pkgs.stdenv.isDarwin then "darwin"
    else if pkgs.stdenv.isLinux then "linux"
    else "other";

  resolvePkg = spec:
    let
      selected =
        if systemName == "darwin" then spec.pkgDarwin or spec.pkg or null
        else if systemName == "linux" then spec.pkgLinux or spec.pkg or null
        else spec.pkg or null;
      path =
        if builtins.isList selected then selected
        else if selected == null then null
        else [ selected ];
    in
    if path == null then null else lib.attrByPath path null pkgs;

  mkToolModule = toolName: spec:
    let
      optionPath = [ "tools" spec.group toolName "enable" ];
      supportedSystems = spec.systems or [ "darwin" "linux" ];
      package = resolvePkg spec;
      isSupportedSystem = builtins.elem systemName supportedSystems;
    in
    delib.module {
      name = "tools.${spec.group}.${toolName}";

      options = with delib; moduleOptions {
        enable = boolOption false;
      };

      myconfig = {
        always = { parent, ... }:
          lib.setAttrByPath optionPath (lib.mkDefault parent.enable);
      };

      home.ifEnabled = { ... }: {
        home.packages = lib.optional (isSupportedSystem && package != null) package;
      };
    };

  toolCatalog = {
    # Core
    bat = { group = "core"; pkg = "bat"; };
    coreutils = { group = "core"; pkg = "coreutils"; };
    curl = { group = "core"; pkg = "curl"; };
    eza = { group = "core"; pkg = "eza"; };
    fd = { group = "core"; pkg = "fd"; };
    htop = { group = "core"; pkg = "htop"; };
    httpie = { group = "core"; pkg = "httpie"; };
    jq = { group = "core"; pkg = "jq"; };
    just = { group = "core"; pkg = "just"; };
    nmap = { group = "core"; pkg = "nmap"; };
    python3 = { group = "core"; pkg = "python3"; };
    ripgrep = { group = "core"; pkg = "ripgrep"; };
    tree = { group = "core"; pkg = "tree"; };
    unzip = { group = "core"; pkg = "unzip"; };
    watchexec = { group = "core"; pkg = "watchexec"; };
    wget = { group = "core"; pkg = "wget"; };
    yq = { group = "core"; pkg = "yq"; };
    zip = { group = "core"; pkg = "zip"; };

    # Development
    awscli2 = { group = "dev"; pkg = "awscli2"; };
    gh = { group = "dev"; pkg = "gh"; };
    go = { group = "dev"; pkg = "go"; };
    mercurial = { group = "dev"; pkg = "mercurial"; };
    nodejs = { group = "dev"; pkg = "nodejs"; };
    opentofu = { group = "dev"; pkg = "opentofu"; };
    terraform = { group = "dev"; pkg = "terraform"; };
  };
in
{
  imports = lib.mapAttrsToList mkToolModule toolCatalog;
}
