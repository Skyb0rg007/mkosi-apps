{
  description = "mkosi-apps flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    skyenet = {
      url = "github:Skyb0rg007/packages?dir=NixOS";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      skyenet,
    }:
    let
      inherit (nixpkgs) lib;
      systems = [ "x86_64-linux" ];
      forEachSystem = lib.genAttrs systems;
    in
    {
      devShells = forEachSystem (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          # mkosi runs directly, not in a buildFHSEnv: bubblewrap's user
          # namespace makes systemd-nsresourced refuse mkosi's range request
          # (DynamicRangeUnavailable). The host tools below only bootstrap the
          # default tools tree; everything else runs inside it. That bootstrap
          # also needs /usr/share/keyrings/debian-archive-keyring.gpg on the
          # host, see the README.
          default = pkgs.mkShellNoCC {
            packages = [
              skyenet.legacyPackages.${system}.mkosi-HEAD
              pkgs.apt
              pkgs.gnupg
              pkgs.sequoia-sqv
              pkgs.zstd
              pkgs.nixfmt
              pkgs.treefmt
              pkgs.debian-devscripts
              pkgs.dpkg
              pkgs.sequoia-sqop
              # Regenerates the Python lockfiles of apps that have none upstream.
              pkgs.uv
            ];
            # Nix exports SOURCE_DATE_EPOCH=315532800, which makes mkosi clamp
            # every mtime in the images to 1980, /usr's included. Then no new
            # version's /usr is newer than a machine's /etc/.updated, and
            # ConditionNeedsUpdate= never reruns ldconfig.service and friends
            # after an upgrade. As in ParticleOS, builds keep their own time.
            shellHook = ''
              unset SOURCE_DATE_EPOCH
            '';
            # Since systemd 262, systemd-nsresourced refuses a writable overlayfs
            # whose upper layer outlives the user namespace, which is every
            # build overlay mkosi mounts for BuildPackages= and build scripts
            # (systemd/mkosi#4438). So mkosi builds in a plain unprivileged
            # user namespace instead; bin/install-app shifts the output to the
            # foreign UID range. Needs a mkosi newer than 27.1.
            MKOSI_FORCE_USERNS_FALLBACK = "1";
          };
        }
      );

    };
}
