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

  # Run a clone command against a module-owned sibling dir ($HGC_PARTIAL)
  # and rename into place on success: a clone killed mid-transfer
  # (SIGTERM/SIGKILL, e.g. systemd stop or logout) must never leave a torn
  # repository that the existence check would treat as complete forever --
  # jj in particular does not clean up its destination. The rename is
  # atomic on the same filesystem, and a stale partial dir from a killed
  # run is safe to remove because only this module writes there. Expects
  # $REPO_PATH to be set; cloneCmd must clone into "$HGC_PARTIAL".
  atomicClone = cloneCmd: ''
    HGC_PARTIAL="$REPO_PATH.hgc-partial"
    $DRY_RUN_CMD ${pkgs.coreutils}/bin/rm -rf "$HGC_PARTIAL"
    ${cloneCmd}
    $DRY_RUN_CMD ${pkgs.coreutils}/bin/mv "$HGC_PARTIAL" "$REPO_PATH"
  '';

  # Effective target path, git-config bypass and VCS marker directory for a
  # configured repository. Shared by the clone scripts, the preflight and the
  # manifest so their views of a repository cannot drift apart.
  repoFacts = kind: path: repo:
    let
      useSubdir = if kind == "git" then repo.useWorktree else repo.useWorkspace;
      finalPath = if useSubdir then "${path}/${repo.rev}" else path;
    in
    {
      repoPath = "${config.home.homeDirectory}/${finalPath}";
      # Auto-bypass git config for HTTPS URLs to prevent SSH rewrites
      shouldBypass =
        if repo.bypassGitConfig != null then repo.bypassGitConfig else lib.hasPrefix "https://" repo.url;
      vcsDir = if kind == "git" then ".git" else ".jj";
    };

  # Setup GPG agent SSH socket if available
  setupGpgAgent = ''
    if [ -S "${config.home.homeDirectory}/.gnupg/S.gpg-agent.ssh" ]; then
      export SSH_AUTH_SOCK="${config.home.homeDirectory}/.gnupg/S.gpg-agent.ssh"
    fi
  '';
}
