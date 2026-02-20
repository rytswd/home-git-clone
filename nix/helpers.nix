{
  lib,
  config,
  pkgs,
}:

{
  # Retry a command with exponential backoff for transient network failures
  # (e.g., DNS not yet available during nixos-rebuild switch)
  withRetry = { retries ? 3, delay ? 2, failMode ? "error" }: cmd: ''
    _retry_count=0
    _retry_max=${toString retries}
    _retry_delay=${toString delay}
    while true; do
      if ${cmd}; then
        break
      else
        _retry_count=$((_retry_count + 1))
        if [ "$_retry_count" -ge "$_retry_max" ]; then
          echo "Command failed after $_retry_max attempts." >&2
          ${if failMode == "warn" then "break" else "exit 1"}
        fi
        echo "Attempt $_retry_count/$_retry_max failed, retrying in ''${_retry_delay}s..." >&2
        sleep "$_retry_delay"
        _retry_delay=$((_retry_delay * 2))
      fi
    done
  '';

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
