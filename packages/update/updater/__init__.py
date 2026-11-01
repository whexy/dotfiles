"""Update the upstream pins of this flake's packages.

Each package that pins an upstream declares ``passthru.updater`` (validated by
lib/updater.nix). ``updater.driver`` finds those packages and runs the
matching kind from ``updater.kinds``; a ``script`` kind runs the package's own
update.py, which imports these modules.
"""


class UpdateError(Exception):
    """An update that cannot finish; the driver reverts the package."""
