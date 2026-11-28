# A NixOS system as an unkernel distro image: a read-only file system labelled
# kwroot holding the system's closure, which unkernel's base system mounts
# under an overlay root before it runs /sbin/init.
{
  pkgs,
  toplevel,
}:
let
  closure = pkgs.closureInfo { rootPaths = [ toplevel ]; };
in
pkgs.runCommand "${toplevel.name}.erofs"
  {
    nativeBuildInputs = [
      pkgs.erofs-utils
      pkgs.nix
    ];
  }
  ''
    root=$TMPDIR/root
    # The base system moves its mounts onto these before it changes root.
    mkdir -p $root/{dev,proc,sys,run,tmp,data} $root/{bin,sbin,usr/lib} $root/nix/store
    xargs -a ${closure}/store-paths cp -a -t $root/nix/store

    # The base system refuses a root whose /bin/sh does not run, and
    # activation, which makes NixOS's own, comes after that check.
    ln -s ${toplevel}/sw/bin/sh $root/bin/sh
    ln -s ${toplevel}/init $root/sbin/init
    mkdir -p $root/nix/var/nix/profiles
    ln -s ${toplevel} $root/nix/var/nix/profiles/system

    # Home Manager's activation realises its generation, and nix builds on
    # what the store holds, so the image's database knows the closure.
    nix-store --store "local?root=$root" --load-db < ${closure}/registration

    # Names the overlay's state on a persistent data disk.
    echo nixos > $root/usr/lib/kw-distro
    echo ${toplevel.name} > $root/usr/lib/kw-image

    # zstd is the only compressor the wasm kernel reads reliably.
    mkfs.erofs -zzstd,level=15 -C131072 -Efragments -L kwroot -T0 \
      -U ${
        let
          h = builtins.hashString "sha256" toplevel.outPath;
          part = start: len: builtins.substring start len h;
        in
        "${part 0 8}-${part 8 4}-${part 12 4}-${part 16 4}-${part 20 12}"
      } \
      --force-uid=0 --force-gid=0 $out $root
  ''
