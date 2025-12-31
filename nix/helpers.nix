{
  lib,
  config,
  pkgs,
}:

{
  # Auto-detect default branch from remote repository
  autoDetectBranch = url: bypassWrapper: ''
    echo "Auto-detecting default branch for ${url}..."
    DEFAULT_BRANCH=$(${bypassWrapper ''${pkgs.git}/bin/git ls-remote --symref "${url}" HEAD''} | \
                     ${pkgs.gawk}/bin/awk '/^ref:/ {sub(/refs\/heads\//, "", $2); print $2}')
    if [ -z "$DEFAULT_BRANCH" ]; then
      echo "Warning: Could not detect default branch, falling back to 'main'" >&2
      DEFAULT_BRANCH="main"
    fi
    echo "Detected default branch: $DEFAULT_BRANCH"
  '';

  # Setup GPG agent SSH socket if available
  setupGpgAgent = ''
    if [ -S "${config.home.homeDirectory}/.gnupg/S.gpg-agent.ssh" ]; then
      export SSH_AUTH_SOCK="${config.home.homeDirectory}/.gnupg/S.gpg-agent.ssh"
    fi
  '';
}
