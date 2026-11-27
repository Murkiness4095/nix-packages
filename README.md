# nix-packages

Import the same flake revision on both NixOS hosts:

```nix
inputs.nix-packages.url = "github:Murkiness4095/nix-packages";
```

Add the public Cachix cache to each host's NixOS configuration:

```nix
nix.settings = {
  extra-substituters = [ "https://nix-packages.cachix.org" ];
  extra-trusted-public-keys = [
    "nix-packages.cachix.org-1:Mx8MBa+WI8CVVfbGr2MArBvR6ZYkiuoRjmuwMR5nkAk="
  ];
};
```

Use `inputs.nix-packages.packages.${pkgs.stdenv.hostPlatform.system}.<package>`
to select the exact derivation built by CI. Keep the package flake's nixpkgs
lock in use. Overriding its nixpkgs input can change the store paths and cause
local builds. Activate the cache settings before relying on it for a rebuild.

GitHub Actions builds packages on native x86-64 Linux, ARM64 Linux and ARM64
macOS runners. Successful builds from main are uploaded even if another package
on the same runner fails. Pull requests can read the cache.

Create a write token for the cache in Cachix and store it as the
`CACHIX_AUTH_TOKEN` repository Actions secret. For example, run
`gh secret set CACHIX_AUTH_TOKEN` and paste the token at the prompt. Hosts
downloading from the public cache only need the URL and public key above.

## Tern

Tern's upstream artifact requires an authenticated Stencil session. The public
workflow excludes it. For a local build, download the exact artifact listed in
`pkgs/tern.nix` through your authenticated session and seed the fixed-output
store path with `nix store add --mode flat ./<artifact-name>` before building.

## Denial

Import the same module on x86-64 and ARM64 NixOS:

```nix
{
  imports = [ inputs.nix-packages.nixosModules.denial ];
  programs.denial.enable = true;
}
```

CI builds the Rust compositor and its native helpers from the pinned source.
The package uses the matching upstream Flutter shell, engine, and Settings
bundles. Device-specific kernel, graphics and input settings belong in the
host configuration.
