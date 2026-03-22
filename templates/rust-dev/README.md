# Rust Dev Template (Nix flake)

Quick start:

```bash
nix flake init -t github:atalie2m/dotfiles#rust-dev
nix develop
```

What you get:

- Toolchain: stable via [rust-overlay](https://github.com/oxalica/rust-overlay) with `rust-src` (optional `wasm32-unknown-unknown` is commented in `flake.nix`)
- `rust-analyzer`, `pkg-config`, `llvmPackages.libclang` (with `LIBCLANG_PATH` set for bindgen/clang-sys)
- Cargo helpers: `just`, `cargo-nextest`, `bacon`, `cargo-deny`, `cargo-llvm-cov`, `cargo-expand`, `sccache`
- Native build deps: `cmake`, `ninja`, `protobuf`, `sqlite` (`openssl` commented until needed)
