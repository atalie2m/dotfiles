{ delib, ... }:

let
  version = "0.26.0";
  overlay = final: prev: {
    gemini-cli = prev.stdenv.mkDerivation rec {
      pname = "gemini-cli";
      inherit version;

      src = prev.fetchurl {
        url = "https://github.com/google-gemini/gemini-cli/releases/download/v${version}/gemini.js";
        hash = "sha256-IOx+n39JGYmHp42ObLD30H2Lgpju6bDBQ7fHLP1oc60=";
      };

      dontUnpack = true;

      nativeBuildInputs = [
        prev.makeBinaryWrapper
      ];

      buildPhase = ''
        runHook preBuild
        runHook postBuild
      '';

      installPhase = ''
        runHook preInstall

        share=$out/share/gemini-cli
        mkdir -p "$share"
        install -Dm444 $src "$share/gemini.js"

        mkdir -p $out/bin
        makeBinaryWrapper ${prev.nodejs_22}/bin/node $out/bin/gemini \
          --add-flags "$share/gemini.js"

        runHook postInstall
      '';

      meta = with prev.lib; {
        description = "Command-line interface for Google Gemini agents";
        homepage = "https://github.com/google-gemini/gemini-cli";
        license = licenses.asl20;
        mainProgram = "gemini";
        platforms = platforms.unix;
      };
    };
  };

in

# Gemini CLI overlay for Denix
delib.module {
  name = "packages.gemini-cli-overlay";

  options.packages.gemini-cli-overlay = with delib.options; {
    enable = boolOption false;
  };

  home.ifEnabled = _: {
    nixpkgs.overlays = [ overlay ];
  };

  darwin.ifEnabled = _: {
    nixpkgs.overlays = [ overlay ];
  };
}
