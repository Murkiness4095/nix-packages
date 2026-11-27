{
  inputs,
  lib,
  self,
  ...
}:
let
  version = "0.6.10";
  assets = {
    x86_64-linux = {
      arch = "x86_64";
      shell = "42d5f2a392df7b3098a4747720424e1ff7b62f54619a154aa25085c5d9fbe5cb";
      engine = "3df874d5e2e6175940f8df91cd1a1d62d11d87cbb9e400cabe3d64686d3a1fee";
    };
    aarch64-linux = {
      arch = "aarch64";
      shell = "2f47690a348c4e0635d891aee335bd18f5185ae1985b34debe71067dd5c0b481";
      engine = "9195c01f0b2706339e522513bbf4145c6f3f825b96b8c56286899687dac3b49c";
    };
  };
in
{
  perSystem =
    { pkgs, system, ... }:
    lib.mkIf (builtins.hasAttr system assets) (
      let
        source = /. + builtins.unsafeDiscardStringContext inputs.denial-source.outPath;
        asset = assets.${system};
        release =
          name: sha256:
          pkgs.fetchurl {
            url = "https://github.com/denialwm/denial/releases/download/v${version}/${name}-1-${asset.arch}.pkg.tar.zst";
            inherit sha256;
          };
        shell = release "denial-${version}" asset.shell;
        engine = release "denial-flutter-engine-1.${version}" asset.engine;
        compositor =
          (pkgs.callPackage (source + "/nix/compositor.nix") {
            src = lib.fileset.toSource {
              root = source;
              fileset = lib.fileset.unions (
                map (name: source + "/${name}") [
                  "compositor"
                  "protocol"
                  "packaging/arch/denial-portals.conf"
                  "packaging/arch/denial.portal"
                  "packages/denial_flutter_sdk/assets/cursors/bibata_modern_ice"
                ]
              );
            };
            inherit version;
            buildIdentity = version;
          }).overrideAttrs
            (old: {
              meta = old.meta // {
                platforms = builtins.attrNames assets;
              };
            });
      in
      {
        packages.denial = pkgs.stdenvNoCC.mkDerivation {
          pname = "denial";
          inherit version;
          srcs = [
            shell
            engine
          ];
          sourceRoot = ".";
          nativeBuildInputs = with pkgs; [
            autoPatchelfHook
            makeWrapper
            zstd
          ];
          buildInputs = with pkgs; [
            fontconfig
            libglvnd
            libxkbcommon
            stdenv.cc.cc.lib
            wayland
          ];

          # Build the compositor and its native helpers with nixpkgs. Reuse
          # the matching upstream application bundles until ARM AOT is packaged.
          installPhase = ''
            runHook preInstall
            mkdir -p "$out"
            cp -a usr/. "$out/"
            cp -a etc "$out/"
            for program in deniald denialctl denial-portal denial-polkit-agent; do
              install -m755 ${compositor}/bin/"$program" "$out/bin/$program"
            done
            substituteInPlace "$out/lib/systemd/system-sleep/denial-suspend-mode" \
              --replace-fail 'command -v loginctl' 'test -x ${pkgs.systemd}/bin/loginctl' \
              --replace-fail 'loginctl list-sessions' '${pkgs.systemd}/bin/loginctl list-sessions' \
              --replace-fail 'loginctl show-session' '${pkgs.systemd}/bin/loginctl show-session' \
              --replace-fail 'loginctl show-user' '${pkgs.systemd}/bin/loginctl show-user' \
              --replace-fail "sed 's/\[//g; s/\]//g'" "${pkgs.gnused}/bin/sed 's/\[//g; s/\]//g'" \
              --replace-fail 'logger -t denial-suspend-mode' '${pkgs.util-linux}/bin/logger -t denial-suspend-mode'
            rm "$out/bin/denial-settings"
            ln -s ../lib/denial-apps/settings "$out/bin/denial-settings"
            for file in \
              "$out/share/wayland-sessions/denial.desktop" \
              "$out/share/dbus-1/services/org.freedesktop.impl.portal.desktop.denial.service" \
              "$out/lib/systemd/user/"*.service \
              "$out/share/applications/"*.desktop; do
              substituteInPlace "$file" --replace-quiet /usr/bin/ "$out/bin/" \
                --replace-quiet /usr/lib/denial-apps/ "$out/lib/denial-apps/"
            done
            wrapProgram "$out/bin/denial-portal" \
              --add-flags "--dialog-bundle $out/lib/denial/polkit"
            wrapProgram "$out/bin/denial-polkit-agent" \
              --add-flags "--runner $out/lib/denial/polkit/denial-app --bundle $out/lib/denial/polkit --engine $out/lib/denial/polkit/lib/libflutter_engine.so"
            wrapProgram "$out/lib/denial-apps/settings" \
              --prefix LD_LIBRARY_PATH : ${
                lib.makeLibraryPath [
                  pkgs.fontconfig
                  pkgs.vulkan-loader
                  pkgs.wayland
                ]
              }
            wrapProgram "$out/bin/denial-session" \
              --prefix PATH : ${
                lib.makeBinPath [
                  pkgs.coreutils
                  pkgs.systemd
                  pkgs.xwayland
                ]
              }
            runHook postInstall
          '';

          dontStrip = true;
          dontPatchELF = true;
          dontAutoPatchelf = true;
          postFixup = ''
            autoPatchelf "$out/lib/denial" "$out/lib/denial-apps"
          '';
          doInstallCheck = true;
          installCheckPhase = ''
            runHook preInstallCheck
            test -x "$out/bin/deniald"
            test -x "$out/bin/denial-settings"
            test -s "$out/lib/denial/flutter/lib/libflutter_engine.so"
            test -s "$out/lib/denial/flutter/lib/libapp.so"
            test -s "$out/lib/denial/flutter/data/icudtl.dat"
            runHook postInstallCheck
          '';
          meta = {
            description = "Flutter-native Wayland compositor";
            homepage = "https://github.com/denialwm/denial";
            license = lib.licenses.gpl3Plus;
            sourceProvenance = with lib.sourceTypes; [
              fromSource
              binaryNativeCode
            ];
            mainProgram = "denial-session";
            platforms = builtins.attrNames assets;
            maintainers = [ ];
          };
        };
      }
    );

  flake.nixosModules.denial =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      imports = [ (inputs.denial-source + "/nix/module.nix") ];
      programs.denial.package = lib.mkDefault self.packages.${pkgs.stdenv.hostPlatform.system}.denial;
      assertions = lib.optionals config.programs.denial.enable [
        {
          assertion = !config.programs.denial.engine.buildFromSource;
          message = "The nix-packages Denial package uses the release Flutter engine.";
        }
        {
          assertion = !config.programs.denial.plugins.enable;
          message = "The nix-packages Denial module does not yet provide the plugin manager.";
        }
      ];
    };
}
