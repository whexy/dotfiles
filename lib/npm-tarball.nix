# The build attributes shared by packages of an npm registry tarball. The
# tarball already ships its compiled `dist/`, so nothing is built.
# packages/update generates `lockfile` from the tarball's package.json after
# `lockfileFilter` (the `npm` updater kind's field), and postPatch applies the
# same filter so the two match. A shrinkwrap the tarball ships is removed,
# since npm would read it in place of `lockfile`. A package's own postPatch
# appends to this one.
{
  pkgs,
  lockfile,
  lockfileFilter,
}:
{
  postPatch = ''
    rm -f npm-shrinkwrap.json
    cp ${lockfile} package-lock.json
    ${pkgs.lib.getExe pkgs.jq} ${pkgs.lib.escapeShellArg lockfileFilter} package.json > package.json.new
    mv package.json.new package.json
  '';
  dontNpmBuild = true;
}
