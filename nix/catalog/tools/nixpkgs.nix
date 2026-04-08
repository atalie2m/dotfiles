{
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
  nkf = { group = "core"; pkg = "nkf"; };
  python3 = { group = "core"; pkg = "python3"; };
  ripgrep = { group = "core"; pkg = "ripgrep"; };
  tree = { group = "core"; pkg = "tree"; };
  unzip = { group = "core"; pkg = "unzip"; };
  watchexec = { group = "core"; pkg = "watchexec"; };
  wget = { group = "core"; pkg = "wget"; };
  yq = { group = "core"; pkg = "yq"; };
  zip = { group = "core"; pkg = "zip"; };

  # Development
  ansible = { group = "dev"; pkg = "ansible"; };
  awscli2 = { group = "dev"; pkg = "awscli2"; };
  gh = { group = "dev"; pkg = "gh"; };
  go = { group = "dev"; pkg = "go"; };
  gitAbsorb = { group = "dev"; pkg = "git-absorb"; };
  gnugrep = { group = "dev"; pkg = "gnugrep"; };
  gnused = { group = "dev"; pkg = "gnused"; };
  mercurial = { group = "dev"; pkg = "mercurial"; };
  nodejs = { group = "dev"; pkg = "nodejs"; };
  opentofu = { group = "dev"; pkg = "opentofu"; };
  terraform = {
    group = "dev";
    pkg = "terraform";
    unfree = [ "terraform" ];
  };
}
