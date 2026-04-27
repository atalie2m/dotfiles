{ lib, pkgs }:

{
  api-db = with pkgs; [
    hurl
    bruno-cli
    grpcurl
    websocat
    oha
    vegeta
    jq
    yq
    dasel
    jc
    duckdb
    usql
    harlequin
    pg_activity
    litecli
    pgcli
    mycli
    postgresql
    redis
    sqlite
    mysql84
    mariadb
    minio
    mailpit
    atlas
    goose
    sqlx-cli
    diesel-cli
    prisma
  ];

  docs = with pkgs; [
    pandoc
    quarto
    typst
    tectonic
    mdbook
    mdbook-linkcheck2
    graphviz
    plantuml
    glow
    lychee
    typos
    vale
  ] ++ lib.optionals stdenv.isLinux [
    d2
    mdbook-mermaid
    mermaid-cli
  ];

  release = with pkgs; [
    git-cliff
    goreleaser
    cargo-dist
    cargo-release
    cosign
    slsa-verifier
    syft
    grype
    trivy
    oras
    crane
    regctl
    dive
    gh
  ];

  container-oci = with pkgs; [
    docker
    podman
    buildah
    skopeo
    oras
    crane
    regctl
    dive
    trivy
    syft
    grype
    cosign
    slsa-verifier
    ko
    goreleaser
  ];

  kubernetes = with pkgs; [
    kubectl
    kustomize
    kubernetes-helm
    kubie
    kubecolor
    kubectl-neat
    popeye
    kubeconform
    kube-linter
    kind
    k3d
    tilt
    skaffold
    stern
    k9s
    trivy
    syft
    grype
    cosign
  ];

  infra-iac = with pkgs; [
    opentofu
    terraform
    terragrunt
    tflint
    tfsec
    checkov
    infracost
    sops
    age
    gitleaks
    trufflehog
    check-jsonschema
    yamllint
  ];

  ai-coding = with pkgs; [
    aider-chat
    llm
    goose-cli
    crush
    uv
    nodejs_22
    pnpm
    ripgrep
    ast-grep
    semgrep
  ];

  model-hf = with pkgs; [
    git-lfs
    git-xet
    python3Packages.huggingface-hub
    rclone
    dvc
    datalad
    git-annex
    uv
    pixi
    ruff
    python3Packages.pytest
    trufflehog
    gitleaks
    noseyparker
  ];

  native-debug =
    with pkgs;
    [ hyperfine ]
    ++ lib.optionals stdenv.isDarwin [ samply ]
    ++ lib.optionals stdenv.isLinux [
      linuxPackages.perf
      hotspot
      valgrind
      heaptrack
    ];
}
