{
  description = "Rust dev template: stable toolchain (rust-overlay), rust-analyzer, LLVM libclang, cargo tooling, sccache, build deps";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    { self, nixpkgs, rust-overlay, ... }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
        "x86_64-darwin"
      ];
    in
    {
      devShells = nixpkgs.lib.genAttrs systems (
        system:
        let
          pkgs = import nixpkgs {
            inherit system;
            overlays = [ rust-overlay.overlays.default ];
          };
        in
        {
          default = pkgs.mkShell {
            name = "rust-dev";
            packages = with pkgs; [
              (rust-bin.stable.latest.default.override {
                extensions = [ "rust-src" ];
                # targets = [ "wasm32-unknown-unknown" ];
              })

              rust-analyzer

              pkg-config
              llvmPackages.libclang

              just
              cargo-nextest
              bacon
              cargo-deny

              cargo-llvm-cov
              cargo-expand
              sccache

              cmake
              ninja
              protobuf
              sqlite
            ];

            shellHook = ''
              export LIBCLANG_PATH="${pkgs.llvmPackages.libclang.lib}/lib"
            '';
          };
        }
      );
    };
}
