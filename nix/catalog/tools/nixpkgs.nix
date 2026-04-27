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

  # Global shell UX
  shellUxFzf = { group = "shellUx"; tool = "fzf"; pkg = "fzf"; };
  shellUxTelevision = { group = "shellUx"; tool = "television"; pkg = "television"; };
  shellUxSkim = { group = "shellUx"; tool = "skim"; pkg = "skim"; };
  shellUxPeco = { group = "shellUx"; tool = "peco"; pkg = "peco"; };
  shellUxNavi = { group = "shellUx"; tool = "navi"; pkg = "navi"; };
  shellUxGum = { group = "shellUx"; tool = "gum"; pkg = "gum"; };
  shellUxComma = { group = "shellUx"; tool = "comma"; pkg = "comma"; };
  shellUxPayRespects = { group = "shellUx"; tool = "payRespects"; pkg = "pay-respects"; };
  shellUxFend = { group = "shellUx"; tool = "fend"; pkg = "fend"; };
  shellUxQalc = { group = "shellUx"; tool = "qalc"; pkg = "libqalculate"; };
  shellUxVivid = { group = "shellUx"; tool = "vivid"; pkg = "vivid"; };
  shellUxEntr = { group = "shellUx"; tool = "entr"; pkg = "entr"; };
  shellUxWatchexec = { group = "shellUx"; tool = "watchexec"; pkg = "watchexec"; };
  shellUxGping = { group = "shellUx"; tool = "gping"; pkg = "gping"; };
  shellUxHyperfine = { group = "shellUx"; tool = "hyperfine"; pkg = "hyperfine"; };
  shellUxChezmoi = { group = "shellUx"; tool = "chezmoi"; pkg = "chezmoi"; };
  shellUxTopgrade = { group = "shellUx"; tool = "topgrade"; pkg = "topgrade"; };

  # Files and navigation
  filesNavigationEza = { group = "filesNavigation"; tool = "eza"; pkg = "eza"; };
  filesNavigationFd = { group = "filesNavigation"; tool = "fd"; pkg = "fd"; };
  filesNavigationZoxide = { group = "filesNavigation"; tool = "zoxide"; pkg = "zoxide"; };
  filesNavigationYazi = { group = "filesNavigation"; tool = "yazi"; pkg = "yazi"; };
  filesNavigationBroot = { group = "filesNavigation"; tool = "broot"; pkg = "broot"; };
  filesNavigationSuperfile = { group = "filesNavigation"; tool = "superfile"; pkg = "superfile"; };
  filesNavigationNcdu = { group = "filesNavigation"; tool = "ncdu"; pkg = "ncdu"; };
  filesNavigationDust = { group = "filesNavigation"; tool = "dust"; pkg = "dust"; };
  filesNavigationDuf = { group = "filesNavigation"; tool = "duf"; pkg = "duf"; };
  filesNavigationDysk = { group = "filesNavigation"; tool = "dysk"; pkg = "dysk"; };
  filesNavigationCroc = { group = "filesNavigation"; tool = "croc"; pkg = "croc"; };
  filesNavigationTrashCli = { group = "filesNavigation"; tool = "trashCli"; pkg = "trash-cli"; };
  filesNavigationRsync = { group = "filesNavigation"; tool = "rsync"; pkg = "rsync"; };
  filesNavigationRclone = { group = "filesNavigation"; tool = "rclone"; pkg = "rclone"; };
  filesNavigationOuch = { group = "filesNavigation"; tool = "ouch"; pkg = "ouch"; };

  # Viewers and previews
  viewersPreviewBat = { group = "viewersPreview"; tool = "bat"; pkg = "bat"; };
  viewersPreviewBatExtras = { group = "viewersPreview"; tool = "batExtras"; pkg = [ "bat-extras" "core" ]; };
  viewersPreviewGlow = { group = "viewersPreview"; tool = "glow"; pkg = "glow"; };
  viewersPreviewTealdeer = { group = "viewersPreview"; tool = "tealdeer"; pkg = "tealdeer"; };
  viewersPreviewChafa = { group = "viewersPreview"; tool = "chafa"; pkg = "chafa"; };
  viewersPreviewHexyl = { group = "viewersPreview"; tool = "hexyl"; pkg = "hexyl"; };
  viewersPreviewLess = { group = "viewersPreview"; tool = "less"; pkg = "less"; };
  viewersPreviewDelta = { group = "viewersPreview"; tool = "delta"; pkg = "delta"; };
  viewersPreviewMdcat = { group = "viewersPreview"; tool = "mdcat"; pkg = "mdcat"; };
  viewersPreviewFq = { group = "viewersPreview"; tool = "fq"; pkg = "fq"; };
  viewersPreviewFx = { group = "viewersPreview"; tool = "fx"; pkg = "fx"; };

  # Search and text transforms
  searchTextRipgrep = { group = "searchText"; tool = "ripgrep"; pkg = "ripgrep"; };
  searchTextRipgrepAll = { group = "searchText"; tool = "ripgrepAll"; pkg = "ripgrep-all"; };
  searchTextFd = { group = "searchText"; tool = "fd"; pkg = "fd"; };
  searchTextFzf = { group = "searchText"; tool = "fzf"; pkg = "fzf"; };
  searchTextGrex = { group = "searchText"; tool = "grex"; pkg = "grex"; };
  searchTextSd = { group = "searchText"; tool = "sd"; pkg = "sd"; };
  searchTextDifftastic = { group = "searchText"; tool = "difftastic"; pkg = "difftastic"; };
  searchTextDiffSoFancy = { group = "searchText"; tool = "diffSoFancy"; pkg = "diff-so-fancy"; };
  searchTextDelta = { group = "searchText"; tool = "delta"; pkg = "delta"; };

  # Personal Git operations
  gitPersonalDelta = { group = "gitPersonal"; tool = "delta"; pkg = "delta"; };
  gitPersonalLazygit = { group = "gitPersonal"; tool = "lazygit"; pkg = "lazygit"; };
  gitPersonalGitui = { group = "gitPersonal"; tool = "gitui"; pkg = "gitui"; };
  gitPersonalGh = { group = "gitPersonal"; tool = "gh"; pkg = "gh"; };
  gitPersonalGhDash = { group = "gitPersonal"; tool = "ghDash"; pkg = "gh-dash"; };
  gitPersonalGitAbsorb = { group = "gitPersonal"; tool = "gitAbsorb"; pkg = "git-absorb"; };
  gitPersonalJujutsu = { group = "gitPersonal"; tool = "jujutsu"; pkg = "jujutsu"; };
  gitPersonalSapling = { group = "gitPersonal"; tool = "sapling"; pkg = "sapling"; };
  gitPersonalGitBranchless = { group = "gitPersonal"; tool = "gitBranchless"; pkg = "git-branchless"; };
  gitPersonalGitoxide = { group = "gitPersonal"; tool = "gitoxide"; pkg = "gitoxide"; };
  gitPersonalMergiraf = { group = "gitPersonal"; tool = "mergiraf"; pkg = "mergiraf"; };
  gitPersonalGitFilterRepo = { group = "gitPersonal"; tool = "gitFilterRepo"; pkg = "git-filter-repo"; };
  gitPersonalOnefetch = { group = "gitPersonal"; tool = "onefetch"; pkg = "onefetch"; };
  gitPersonalTokei = { group = "gitPersonal"; tool = "tokei"; pkg = "tokei"; };

  # Nix operator cockpit
  nixOperatorNh = { group = "nixOperator"; tool = "nh"; pkg = "nh"; };
  nixOperatorNom = { group = "nixOperator"; tool = "nom"; pkg = "nix-output-monitor"; };
  nixOperatorNixIndex = { group = "nixOperator"; tool = "nixIndex"; pkg = "nix-index"; };
  nixOperatorNixSearchTv = { group = "nixOperator"; tool = "nixSearchTv"; pkg = "nix-search-tv"; };
  nixOperatorManix = { group = "nixOperator"; tool = "manix"; pkg = "manix"; };
  nixOperatorNixInspect = { group = "nixOperator"; tool = "nixInspect"; pkg = "nix-inspect"; };
  nixOperatorNixTree = { group = "nixOperator"; tool = "nixTree"; pkg = "nix-tree"; };
  nixOperatorNvd = { group = "nixOperator"; tool = "nvd"; pkg = "nvd"; };
  nixOperatorDirenv = { group = "nixOperator"; tool = "direnv"; pkg = "direnv"; };
  nixOperatorNixDirenv = { group = "nixOperator"; tool = "nixDirenv"; pkg = "nix-direnv"; };
  nixOperatorNixYourShell = { group = "nixOperator"; tool = "nixYourShell"; pkg = "nix-your-shell"; };
  nixOperatorNixd = { group = "nixOperator"; tool = "nixd"; pkg = "nixd"; };
  nixOperatorNil = { group = "nixOperator"; tool = "nil"; pkg = "nil"; };
  nixOperatorNixInit = { group = "nixOperator"; tool = "nixInit"; pkg = "nix-init"; };
  nixOperatorNurl = { group = "nixOperator"; tool = "nurl"; pkg = "nurl"; };
  nixOperatorNixUpdate = { group = "nixOperator"; tool = "nixUpdate"; pkg = "nix-update"; };
  nixOperatorTopgrade = { group = "nixOperator"; tool = "topgrade"; pkg = "topgrade"; };
  nixOperatorAlejandra = { group = "nixOperator"; tool = "alejandra"; pkg = "alejandra"; };

  # Observability
  observabilityBottom = { group = "observability"; tool = "bottom"; pkg = "bottom"; };
  observabilityBtop = { group = "observability"; tool = "btop"; pkg = "btop"; };
  observabilityProcs = { group = "observability"; tool = "procs"; pkg = "procs"; };
  observabilityBandwhich = { group = "observability"; tool = "bandwhich"; pkg = "bandwhich"; };
  observabilityGlances = { group = "observability"; tool = "glances"; pkg = "glances"; };
  observabilityIftop = { group = "observability"; tool = "iftop"; pkg = "iftop"; };
  observabilitySniffnet = { group = "observability"; tool = "sniffnet"; pkg = "sniffnet"; };
  observabilityMacmon = { group = "observability"; tool = "macmon"; pkg = "macmon"; systems = [ "darwin" ]; };
  observabilityMacpm = { group = "observability"; tool = "macpm"; pkg = "macpm"; systems = [ "darwin" ]; };
  observabilityFastfetch = { group = "observability"; tool = "fastfetch"; pkg = "fastfetch"; };
  observabilityHtop = { group = "observability"; tool = "htop"; pkg = "htop"; };
  observabilitySamply = { group = "observability"; tool = "samply"; pkg = "samply"; };
  observabilityPySpy = { group = "observability"; tool = "pySpy"; pkg = "py-spy"; systems = [ "linux" ]; };
  observabilityGoss = { group = "observability"; tool = "goss"; pkg = "goss"; };
  observabilityLnav = { group = "observability"; tool = "lnav"; pkg = "lnav"; };

  # Network and API inspection
  networkTrippy = { group = "network"; tool = "trippy"; pkg = "trippy"; };
  networkMtr = { group = "network"; tool = "mtr"; pkg = "mtr"; };
  networkDoggo = { group = "network"; tool = "doggo"; pkg = "doggo"; };
  networkDig = { group = "network"; tool = "dig"; pkg = "dig"; };
  networkXh = { group = "network"; tool = "xh"; pkg = "xh"; };
  networkCurl = { group = "network"; tool = "curl"; pkg = "curl"; };
  networkWget = { group = "network"; tool = "wget"; pkg = "wget"; };
  networkGping = { group = "network"; tool = "gping"; pkg = "gping"; };
  networkMosh = { group = "network"; tool = "mosh"; pkg = "mosh"; };
  networkKeychain = { group = "network"; tool = "keychain"; pkg = "keychain"; };
  networkTeleport = { group = "network"; tool = "teleport"; pkg = "teleport"; };
  networkTsh = { group = "network"; tool = "tsh"; pkg = "teleport"; };
  networkTermshark = { group = "network"; tool = "termshark"; pkg = "termshark"; };
  networkRustscan = { group = "network"; tool = "rustscan"; pkg = "rustscan"; };
  networkNmap = { group = "network"; tool = "nmap"; pkg = "nmap"; };
  networkBandwhich = { group = "network"; tool = "bandwhich"; pkg = "bandwhich"; };
  networkSniffnet = { group = "network"; tool = "sniffnet"; pkg = "sniffnet"; };
  networkWebsocat = { group = "network"; tool = "websocat"; pkg = "websocat"; };
  networkGrpcurl = { group = "network"; tool = "grpcurl"; pkg = "grpcurl"; };

  httpApiPersonalXh = { group = "httpApiPersonal"; tool = "xh"; pkg = "xh"; };
  httpApiPersonalCurl = { group = "httpApiPersonal"; tool = "curl"; pkg = "curl"; };
  httpApiPersonalHttpie = { group = "httpApiPersonal"; tool = "httpie"; pkg = "httpie"; };
  httpApiPersonalAtac = { group = "httpApiPersonal"; tool = "atac"; pkg = "atac"; };
  httpApiPersonalJq = { group = "httpApiPersonal"; tool = "jq"; pkg = "jq"; };
  httpApiPersonalYq = { group = "httpApiPersonal"; tool = "yq"; pkg = "yq"; };
  httpApiPersonalFx = { group = "httpApiPersonal"; tool = "fx"; pkg = "fx"; };

  # Download and archive
  downloadArchiveOuch = { group = "downloadArchive"; tool = "ouch"; pkg = "ouch"; };
  downloadArchiveTar = { group = "downloadArchive"; tool = "tar"; pkg = "gnutar"; };
  downloadArchiveGzip = { group = "downloadArchive"; tool = "gzip"; pkg = "gzip"; };
  downloadArchivePigz = { group = "downloadArchive"; tool = "pigz"; pkg = "pigz"; };
  downloadArchiveZstd = { group = "downloadArchive"; tool = "zstd"; pkg = "zstd"; };
  downloadArchiveUnzip = { group = "downloadArchive"; tool = "unzip"; pkg = "unzip"; };
  downloadArchiveP7zip = { group = "downloadArchive"; tool = "p7zip"; pkg = "p7zip"; };
  downloadArchiveFfmpeg = { group = "downloadArchive"; tool = "ffmpeg"; pkg = "ffmpeg"; };
  downloadArchiveRclone = { group = "downloadArchive"; tool = "rclone"; pkg = "rclone"; };
  downloadArchiveRsync = { group = "downloadArchive"; tool = "rsync"; pkg = "rsync"; };

  # TUI workspaces
  tuiWorkspaceZellij = { group = "tuiWorkspace"; tool = "zellij"; pkg = "zellij"; };
  tuiWorkspaceTmux = { group = "tuiWorkspace"; tool = "tmux"; pkg = "tmux"; };
  tuiWorkspaceSesh = { group = "tuiWorkspace"; tool = "sesh"; pkg = "sesh"; };
  tuiWorkspaceK9s = { group = "tuiWorkspace"; tool = "k9s"; pkg = "k9s"; };
  tuiWorkspaceLazydocker = { group = "tuiWorkspace"; tool = "lazydocker"; pkg = "lazydocker"; };
  tuiWorkspaceStern = { group = "tuiWorkspace"; tool = "stern"; pkg = "stern"; };
  tuiWorkspaceLnav = { group = "tuiWorkspace"; tool = "lnav"; pkg = "lnav"; };
  tuiWorkspaceToast = { group = "tuiWorkspace"; tool = "toast"; pkg = "toast"; };
  tuiWorkspaceGobang = { group = "tuiWorkspace"; tool = "gobang"; pkg = "gobang"; };
  tuiWorkspaceHarlequin = { group = "tuiWorkspace"; tool = "harlequin"; pkg = "harlequin"; };
  tuiWorkspacePgActivity = { group = "tuiWorkspace"; tool = "pgActivity"; pkg = "pg_activity"; };
  tuiWorkspaceAtuin = { group = "tuiWorkspace"; tool = "atuin"; pkg = "atuin"; };

  # Personal data exploration
  dataPersonalJq = { group = "dataPersonal"; tool = "jq"; pkg = "jq"; };
  dataPersonalYq = { group = "dataPersonal"; tool = "yq"; pkg = "yq"; };
  dataPersonalFx = { group = "dataPersonal"; tool = "fx"; pkg = "fx"; };
  dataPersonalJc = { group = "dataPersonal"; tool = "jc"; pkg = "jc"; };
  dataPersonalMiller = { group = "dataPersonal"; tool = "miller"; pkg = "miller"; };
  dataPersonalVisidata = { group = "dataPersonal"; tool = "visidata"; pkg = "visidata"; };
  dataPersonalDasel = { group = "dataPersonal"; tool = "dasel"; pkg = "dasel"; };
  dataPersonalQsv = { group = "dataPersonal"; tool = "qsv"; pkg = "qsv"; };
  dataPersonalXan = { group = "dataPersonal"; tool = "xan"; pkg = "xan"; };
  dataPersonalCsvlens = { group = "dataPersonal"; tool = "csvlens"; pkg = "csvlens"; };
  dataPersonalSq = { group = "dataPersonal"; tool = "sq"; pkg = "sq"; };
  dataPersonalDuckdb = { group = "dataPersonal"; tool = "duckdb"; pkg = "duckdb"; };
  dataPersonalFq = { group = "dataPersonal"; tool = "fq"; pkg = "fq"; };
  dataPersonalUsql = { group = "dataPersonal"; tool = "usql"; pkg = "usql"; };
  dataPersonalHarlequin = { group = "dataPersonal"; tool = "harlequin"; pkg = "harlequin"; };
  dataPersonalPgActivity = { group = "dataPersonal"; tool = "pgActivity"; pkg = "pg_activity"; };

  # Personal containers and Kubernetes
  containerK8sPersonalDocker = { group = "containerK8sPersonal"; tool = "docker"; pkg = "docker"; };
  containerK8sPersonalPodman = { group = "containerK8sPersonal"; tool = "podman"; pkg = "podman"; };
  containerK8sPersonalLazydocker = { group = "containerK8sPersonal"; tool = "lazydocker"; pkg = "lazydocker"; };
  containerK8sPersonalKubectl = { group = "containerK8sPersonal"; tool = "kubectl"; pkg = "kubectl"; };
  containerK8sPersonalK9s = { group = "containerK8sPersonal"; tool = "k9s"; pkg = "k9s"; };
  containerK8sPersonalStern = { group = "containerK8sPersonal"; tool = "stern"; pkg = "stern"; };
  containerK8sPersonalKubie = { group = "containerK8sPersonal"; tool = "kubie"; pkg = "kubie"; };
  containerK8sPersonalKubecolor = { group = "containerK8sPersonal"; tool = "kubecolor"; pkg = "kubecolor"; };

  # Personal security and secrets
  securityPersonalRustscan = { group = "securityPersonal"; tool = "rustscan"; pkg = "rustscan"; };
  securityPersonalNmap = { group = "securityPersonal"; tool = "nmap"; pkg = "nmap"; };
  securityPersonalSshAudit = { group = "securityPersonal"; tool = "sshAudit"; pkg = "ssh-audit"; };
  securityPersonalMinisign = { group = "securityPersonal"; tool = "minisign"; pkg = "minisign"; };
  securityPersonalSops = { group = "securityPersonal"; tool = "sops"; pkg = "sops"; };
  securityPersonalAge = { group = "securityPersonal"; tool = "age"; pkg = "age"; };
  securityPersonalAgePluginYubikey = { group = "securityPersonal"; tool = "agePluginYubikey"; pkg = "age-plugin-yubikey"; };
  securityPersonalFlawz = { group = "securityPersonal"; tool = "flawz"; pkg = "flawz"; };
  securityPersonalGitleaks = { group = "securityPersonal"; tool = "gitleaks"; pkg = "gitleaks"; };
  securityPersonalTrufflehog = { group = "securityPersonal"; tool = "trufflehog"; pkg = "trufflehog"; };
  securityPersonalNoseyparker = { group = "securityPersonal"; tool = "noseyparker"; pkg = "noseyparker"; };

  passwordSecretsOp = {
    group = "passwordSecrets";
    tool = "op";
    pkg = "_1password-cli";
    unfree = [ "1password-cli" ];
  };
  passwordSecretsSops = { group = "passwordSecrets"; tool = "sops"; pkg = "sops"; };
  passwordSecretsAge = { group = "passwordSecrets"; tool = "age"; pkg = "age"; };
  passwordSecretsAgePluginYubikey = { group = "passwordSecrets"; tool = "agePluginYubikey"; pkg = "age-plugin-yubikey"; };
  passwordSecretsSshToAge = { group = "passwordSecrets"; tool = "sshToAge"; pkg = "ssh-to-age"; };
  passwordSecretsKeychain = { group = "passwordSecrets"; tool = "keychain"; pkg = "keychain"; };

  # AI and model workflows
  aiLlmAider = { group = "aiLlm"; tool = "aider"; pkg = "aider-chat"; };
  aiLlmLlm = { group = "aiLlm"; tool = "llm"; pkg = "llm"; };
  aiLlmOllama = { group = "aiLlm"; tool = "ollama"; pkg = "ollama"; };
  aiLlmLlamaCpp = { group = "aiLlm"; tool = "llamaCpp"; pkg = "llama-cpp"; };
  aiLlmGoose = { group = "aiLlm"; tool = "goose"; pkg = "goose-cli"; };
  aiLlmCrush = { group = "aiLlm"; tool = "crush"; pkg = "crush"; unfree = [ "crush" ]; };
  aiLlmHuggingfaceHub = { group = "aiLlm"; tool = "huggingfaceHub"; pkg = [ "python3Packages" "huggingface-hub" ]; };

  modelHfPersonalGitLfs = { group = "modelHfPersonal"; tool = "gitLfs"; pkg = "git-lfs"; };
  modelHfPersonalHuggingfaceHub = { group = "modelHfPersonal"; tool = "huggingfaceHub"; pkg = [ "python3Packages" "huggingface-hub" ]; };
  modelHfPersonalRclone = { group = "modelHfPersonal"; tool = "rclone"; pkg = "rclone"; };
  modelHfPersonalCroc = { group = "modelHfPersonal"; tool = "croc"; pkg = "croc"; };

  # Backup and terminal visuals
  backupRecoveryRestic = { group = "backupRecovery"; tool = "restic"; pkg = "restic"; };
  backupRecoveryBorgbackup = { group = "backupRecovery"; tool = "borgbackup"; pkg = "borgbackup"; };
  backupRecoveryKopia = { group = "backupRecovery"; tool = "kopia"; pkg = "kopia"; };
  backupRecoveryRclone = { group = "backupRecovery"; tool = "rclone"; pkg = "rclone"; };
  backupRecoveryRsync = { group = "backupRecovery"; tool = "rsync"; pkg = "rsync"; };

  terminalVisualVivid = { group = "terminalVisual"; tool = "vivid"; pkg = "vivid"; };
  terminalVisualChafa = { group = "terminalVisual"; tool = "chafa"; pkg = "chafa"; };
  terminalVisualVhs = { group = "terminalVisual"; tool = "vhs"; pkg = "vhs"; };
}
