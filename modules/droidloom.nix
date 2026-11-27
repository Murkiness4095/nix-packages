{ self, ... }:
{
  flake.nixosModules.droidloom =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.virtualisation.droidloom;
      kernel = config.lib.kernelConfig;
    in
    {
      options.virtualisation.droidloom = {
        enable = lib.mkEnableOption "Droidloom Android application runtime";
        package = lib.mkOption {
          type = lib.types.package;
          default = self.packages.${pkgs.stdenv.hostPlatform.system}.droidloom;
          description = "Droidloom package with matching Android partitions.";
        };
        user = lib.mkOption {
          type = lib.types.str;
          description = "Desktop account that can start and stop the Droidloom system service.";
        };
      };

      config = lib.mkIf cfg.enable {
        assertions = [
          {
            assertion = cfg.user != "root" && (config.users.users.${cfg.user}.isNormalUser or false);
            message = "Droidloom needs a normal desktop user in virtualisation.droidloom.user.";
          }
        ];

        system.requiredKernelConfig = [
          (kernel.isEnabled "ANDROID_BINDER_IPC")
          (kernel.isEnabled "ANDROID_BINDERFS")
          (kernel.isEnabled "MEMFD_CREATE")
        ];

        environment.systemPackages = [ cfg.package ];
        systemd.packages = [ cfg.package ];
        systemd.services.droidloomd.serviceConfig.IPAccounting = false;

        security.polkit.enable = true;
        security.polkit.extraConfig = ''
          polkit.addRule(function(action, subject) {
            if (action.id === "org.freedesktop.systemd1.manage-units" &&
                subject.user === ${builtins.toJSON cfg.user} &&
                action.lookup("unit") === "droidloomd.service" &&
                ["start", "stop"].includes(action.lookup("verb"))) {
              return polkit.Result.YES;
            }
          });
        '';
      };
    };
}
