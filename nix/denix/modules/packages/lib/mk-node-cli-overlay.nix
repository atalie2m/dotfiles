{ ... }:
{
  # Expose helper constructors via module args so this file can live under
  # nix/denix/modules without being interpreted as a regular config module.
  _module.args = {
    mkNpmTarballNodeCli = {
      prev,
      basePackage,
      source,
      modulePath,
      binaryName,
      entrypoint,
      extraNativeBuildInputs ? [],
      completionCommand ? null,
    }:
      basePackage.overrideAttrs (old: rec {
        version = source.version;
        src = source.src;

        nativeBuildInputs = (old.nativeBuildInputs or []) ++ [
          prev.nodejs_22
          prev.makeBinaryWrapper
        ] ++ extraNativeBuildInputs;

        buildPhase = ''
          runHook preBuild
          runHook postBuild
        '';

        installPhase = ''
          runHook preInstall

          dest=$out/lib/node_modules/${modulePath}
          mkdir -p "$dest"
          shopt -s dotglob
          cp -r ./* "$dest"
          shopt -u dotglob

          mkdir -p $out/bin
          makeBinaryWrapper ${prev.nodejs_22}/bin/node $out/bin/${binaryName} --add-flags "$dest/${entrypoint}"
        '' + prev.lib.optionalString (completionCommand != null && prev.stdenv.buildPlatform.canExecute prev.stdenv.hostPlatform) ''
          ${completionCommand}
        '' + ''
          runHook postInstall
        '';

        doInstallCheck = false;
      });

    mkSingleFileNodeCli = {
      prev,
      pname,
      source,
      binaryName,
      scriptPath,
      description,
      homepage,
      license,
      platforms ? prev.lib.platforms.unix,
    }:
      prev.stdenv.mkDerivation rec {
        inherit pname;
        version = source.version;
        src = source.src;

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

          share=$out/share/${pname}
          mkdir -p "$share"
          install -Dm444 $src "$share/${scriptPath}"

          mkdir -p $out/bin
          makeBinaryWrapper ${prev.nodejs_22}/bin/node $out/bin/${binaryName} \
            --add-flags "$share/${scriptPath}"

          runHook postInstall
        '';

        meta = with prev.lib; {
          inherit description homepage license platforms;
          mainProgram = binaryName;
        };
      };
  };
}
