{
  description = "Nix packages repository";

  nixConfig = {
    extra-substituters = [ "https://nix-packages.cachix.org" ];
    extra-trusted-public-keys = [
      "nix-packages.cachix.org-1:Mx8MBa+WI8CVVfbGr2MArBvR6ZYkiuoRjmuwMR5nkAk="
    ];
  };

  inputs = {
    denial-source = {
      url = "github:denialwm/denial/v0.6.10";
      flake = false;
    };
    flake-compat.url = "https://git.lix.systems/lix-project/flake-compat/archive/main.tar.gz";
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };
    nix-github-actions = {
      url = "github:nix-community/nix-github-actions";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixpkgs.url = "https://channels.nixos.org/nixos-unstable/nixexprs.tar.zst";
    nvfetcher = {
      url = "github:berberman/nvfetcher/0.8.1";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-compat.follows = "";
    };
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];

      imports = [
        inputs.treefmt-nix.flakeModule
        ./modules/denial.nix
        ./pkgs/denial.nix
        ./pkgs/onekey-wallet.nix
        ./pkgs/omp-gui.nix
        ./pkgs/tern.nix
      ];

      perSystem = {
        treefmt = {
          projectRootFile = "flake.nix";
          programs.nixfmt.enable = true;
          flakeCheck = true;
          flakeFormatter = true;
        };
      };
    };
}
