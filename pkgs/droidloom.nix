{ inputs, lib, ... }:
let
  version = "0.1.0";
  release = "51";
  baseRelease = "49";
  assets = {
    x86_64-linux = {
      arch = "x86_64";
      runtime = "1f72314333772715a4bce0639992ac26b6bc0e8d2ae541373210edf7b6d9848a";
      image = "d274d142e6d3bf1decbef025157350953e61a63d5f82e013bb655fc1af71d7da";
      base = "aa313d072f8935c6c56732a7440a2d7bab8eb797540e30e07411ca91b95f726e";
    };
    aarch64-linux = {
      arch = "aarch64";
      runtime = "5e9f188fad43b77fea447cd73c50692438d138710a18b36a845d7f2d6dbd0bf2";
      image = "7f260d3863c798f893146e2f4ae2fecf6c4df23c5ad300b1b833027f72959656";
      base = "40712a6eb1bcc451c8c4bdd2ca5b2951f845d041c4746a4bb2a07b3259b49473";
    };
  };
in
{
  perSystem =
    { pkgs, system, ... }:
    lib.mkIf (builtins.hasAttr system assets) (
      let
        source = inputs.droidloom-source;
        asset = assets.${system};
        fetchAsset =
          name: revision:
          pkgs.fetchurl {
            url = "https://github.com/denialwm/droidloom/releases/download/packages/droidloom-${name}-${version}-${revision}-${asset.arch}.pkg.tar.zst";
            sha256 = asset.${name};
          };
        runtime = fetchAsset "runtime" release;
        image = fetchAsset "image" release;
        base = fetchAsset "base" baseRelease;
        hostCrates = [
          "droidloom-supervisor"
          "droidloom-wayland"
          "droidloom-applications"
          "droidloom-audio"
          "droidloom-gpu-server"
          "droidloom-devices"
          "droidloom-doctor"
          "droidloom-package-support"
        ];
        hostTools = with pkgs; [
          android-tools
          coreutils
          e2fsprogs
          glibc.bin
          iproute2
          iptables
          nftables
          rsync
          shadow
          systemd
          gnutar
          util-linux
          zstd
        ];
        rewritePaths = ''
          sed -i \
            -e "s|/usr/lib/droidloom/current|$out/lib/droidloom/runtime|g" \
            -e "s|/usr/lib/droidloom|$out/lib/droidloom|g" \
            -e "s|/usr/share/droidloom|$out/share/droidloom|g" \
            -e "s|/usr/bin/droidloom|$out/bin/droidloom|g" \
            -e 's|/usr/bin/pkexec|/run/wrappers/bin/pkexec|g' \
            -e 's|/usr/bin/adb|${pkgs.android-tools}/bin/adb|g' \
            -e 's|/usr/bin/getent|${pkgs.glibc.bin}/bin/getent|g' \
            -e 's|/usr/bin/runuser|${pkgs.util-linux}/bin/runuser|g' \
            -e 's|/usr/bin/nsenter|${pkgs.util-linux}/bin/nsenter|g' \
            -e 's|/usr/bin/systemctl|${pkgs.systemd}/bin/systemctl|g' \
            -e 's|/usr/bin/systemd-run|${pkgs.systemd}/bin/systemd-run|g' \
            -e 's|/usr/bin/\(cat\|env\|id\|sleep\|timeout\)|${pkgs.coreutils}/bin/\1|g' \
            "$@"
        '';
      in
      {
        packages.droidloom = pkgs.rustPlatform.buildRustPackage {
          pname = "droidloom";
          version = "${version}-${release}";
          src = source;
          cargoLock.lockFile = source + "/Cargo.lock";
          cargoBuildFlags = [
            "--bins"
          ]
          ++ lib.concatMap (name: [
            "-p"
            name
          ]) hostCrates;
          cargoTestFlags = lib.concatMap (name: [
            "-p"
            name
          ]) hostCrates;

          nativeBuildInputs = with pkgs; [
            jq
            makeWrapper
            pkg-config
            zstd
          ];
          buildInputs = with pkgs; [
            libdrm
            libgbm
            libxkbcommon
            pipewire
            wayland
            vulkan-loader
          ];

          postPatch = ''
            rewritePaths() {
              ${rewritePaths}
            }
            while IFS= read -r -d "" source; do
              rewritePaths "$source"
            done < <(find runtime graphics -path '*/tests' -prune -o -name '*.rs' -print0)
            substituteInPlace runtime/droidloom-package-support/src/main.rs \
              --replace-fail /etc/polkit-1/rules.d/49-droidloom.rules /etc/droidloom/49-droidloom.rules
          '';

          # The Android partitions contain their own binaries and libraries.
          # Keep the normal fixup for host binaries but leave the guest files intact.
          postFixup = ''
            mkdir -p "$out/lib/droidloom"
            mv "$out/bin/droidloom-package-helper" "$out/lib/droidloom/"
            mkdir "$TMPDIR/droidloom-payload"
            pushd "$TMPDIR/droidloom-payload"
            tar --zstd -xf ${base} usr
            tar --zstd -xf ${image} usr
            tar --zstd -xf ${runtime} usr/lib/systemd usr/share
            rm -rf usr/share/libalpm
            cp -a usr/. "$out/"
            popd
            rewritePaths() {
              ${rewritePaths}
            }
            rewritePaths "$out/share/droidloom/cell-template.json" \
              "$out/share/polkit-1/actions/org.droidloom.setup.policy" \
              "$out/lib/systemd/system/"*.service "$out/lib/systemd/user/"*.service
            jq --arg output "$out" '. + {nixStorePath: $output}' \
              "$out/share/droidloom/package.json" > "$TMPDIR/droidloom-package.json"
            mv "$TMPDIR/droidloom-package.json" "$out/share/droidloom/package.json"
            for program in "$out/bin/"*; do
              wrapProgram "$program" --prefix PATH : ${lib.makeBinPath hostTools}
            done
            wrapProgram "$out/lib/droidloom/droidloom-package-helper" \
              --prefix PATH : ${lib.makeBinPath hostTools}
          '';

          doInstallCheck = true;
          installCheckPhase = ''
            runHook preInstallCheck
            "$out/bin/droidloomctl" --help
            test -s "$out/lib/droidloom/images/images/system.img"
            test -s "$out/lib/droidloom/images/images/vendor.raw.img"
            test -x "$out/lib/droidloom/runtime/bin/droidloom-android-init"
            test -x "$out/lib/droidloom/droidloom-package-helper"
            runHook postInstallCheck
          '';

          meta = {
            description = "Run Android apps in native Wayland windows";
            homepage = "https://github.com/denialwm/droidloom";
            license = [
              lib.licenses.gpl3Plus
              lib.licenses.asl20
              lib.licenses.mit
            ];
            sourceProvenance = with lib.sourceTypes; [
              fromSource
              binaryNativeCode
            ];
            mainProgram = "droidloomctl";
            platforms = builtins.attrNames assets;
            maintainers = [ ];
          };
        };
      }
    );
}
