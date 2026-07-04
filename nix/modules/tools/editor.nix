{ dotmod, config, lib, pkgs, ... }:

# Editor tool group

let
  goneovimPackage =
    let
      version = "0.6.17";
      sources = {
        aarch64-darwin = {
          assetArch = "arm64";
          hash = "sha256-urqfmJF6R00wgSe6YVuJZwBzKmRL+IDwuCkKXPKUdCU=";
        };
        x86_64-darwin = {
          assetArch = "x86_64";
          hash = "sha256-CDXycm27dbvk0qcnisuphlwAb1SJ+hElIaumHd2t0Pg=";
        };
      };
      source = sources.${pkgs.stdenvNoCC.hostPlatform.system}
        or (throw "goneovim is only packaged for Darwin in this repo");
      neovimPath = lib.makeBinPath [ pkgs.neovim ];
    in
    pkgs.stdenvNoCC.mkDerivation {
      pname = "goneovim";
      inherit version;

      src = pkgs.fetchurl {
        url = "https://github.com/akiyosi/goneovim/releases/download/v${version}/goneovim-v${version}-macos-${source.assetArch}.tar.bz2";
        inherit (source) hash;
      };

      nativeBuildInputs = [ pkgs.makeWrapper ];
      sourceRoot = ".";

      installPhase = ''
        runHook preInstall

        app_src="goneovim-v${version}-macos-${source.assetArch}/goneovim.app"
        app_dst="$out/Applications/Goneovim.app"
        app_bin="$app_dst/Contents/MacOS/goneovim"

        mkdir -p "$out/Applications" "$out/bin"
        cp -R "$app_src" "$app_dst"
        chmod -R u+w "$app_dst"

        mv "$app_bin" "$app_bin.unwrapped"
        makeWrapper "$app_bin.unwrapped" "$app_bin" \
          --prefix PATH : "${neovimPath}"
        makeWrapper "$app_bin.unwrapped" "$out/bin/goneovim" \
          --prefix PATH : "${neovimPath}"

        runHook postInstall
      '';

      meta = {
        description = "Neovim GUI written in Go";
        homepage = "https://github.com/akiyosi/goneovim";
        license = lib.licenses.mit;
        mainProgram = "goneovim";
        platforms = [
          "aarch64-darwin"
          "x86_64-darwin"
        ];
        sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
      };
    };
in

(dotmod.mkModule { inherit config; }) {
  path = "tools.editor";

  options = with dotmod; moduleOptions {
    enable = boolOption false;
    goneovim = {
      enable = boolOption false;
    };
  };

  homeAlways = { myconfig, ... }:
    let
      goneovimEnabled = myconfig.tools.editor.goneovim.enable or false;
    in
    lib.mkIf goneovimEnabled {
      assertions = [
        {
          assertion = pkgs.stdenv.isDarwin;
          message = "tools.editor.goneovim is only supported on Darwin.";
        }
      ];

      home.packages = lib.optional pkgs.stdenv.isDarwin goneovimPackage;
    };
}
