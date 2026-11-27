{ inputs, self, ... }:
{
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
