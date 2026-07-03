# Probe every repository recorded in a home-git-clone manifest and report
# reachability, without needing the Nix configuration that produced it.
# Unlike the activation preflight, this probes every configured repository,
# whether or not it is already cloned locally -- the question answered here
# is "could this manifest be provisioned from scratch on this machine?".
#
# Usage: home-git-clone-check [MANIFEST]
#   MANIFEST defaults to $XDG_CONFIG_HOME/home-git-clone/manifest.json (the
#   live symlink maintained by the Home Manager module).
#
# Exit codes: 0 when all remotes are reachable, 1 otherwise.
#
# The hgc_probe_url function is prepended from nix/probe.sh at build time,
# keeping the probe behaviour identical to the activation preflight.

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  echo "Usage: home-git-clone-check [MANIFEST]"
  echo "Probe every repository in a home-git-clone manifest and report reachability."
  echo "MANIFEST defaults to \$XDG_CONFIG_HOME/home-git-clone/manifest.json."
  echo "Exit codes: 0 all remotes reachable, 1 otherwise."
  exit 0
fi

manifest="${1:-${XDG_CONFIG_HOME:-$HOME/.config}/home-git-clone/manifest.json}"

if [ ! -r "$manifest" ]; then
  echo "error: cannot read manifest: $manifest" >&2
  echo "hint: the home-git-clone module writes it on activation when repositories are configured" >&2
  exit 1
fi

version="$(jq -r '.version // empty' "$manifest")"
if [ "$version" != "1" ]; then
  echo "error: unsupported manifest version: ${version:-<none>} (expected 1)" >&2
  exit 1
fi

# Mirror the module's SSH setup so probes authenticate the same way the
# clones would on this machine.
if [ -S "$HOME/.gnupg/S.gpg-agent.ssh" ]; then
  export SSH_AUTH_SOCK="$HOME/.gnupg/S.gpg-agent.ssh"
fi

names=()
kinds=()
urls=()
bypasses=()
refs=()
# Bypass and ref are resolved inside jq, straight into the probe's own
# vocabulary, so no field is ever empty: bash collapses adjacent tabs for
# whitespace IFS, which would shift the remaining columns. A null/absent
# rev (auto-detected default branch, or an older version-1 manifest without
# the field) degrades to probing HEAD, exactly like the clone's own
# detection.
while IFS=$'\t' read -r name kind url bypass ref _path; do
  names+=("$name")
  kinds+=("$kind")
  urls+=("$url")
  bypasses+=("$bypass")
  refs+=("$ref")
done < <(jq -r '.repos[] | [.name, .kind, .url, (if .bypassGitConfig then "1" else "0" end), (if (.rev // "") == "" then "HEAD" else "refs/heads/" + .rev end), .path] | @tsv' "$manifest")

if [ "${#names[@]}" -eq 0 ]; then
  echo "manifest contains no repositories: $manifest"
  exit 0
fi

# Column widths from actual content, so the table stays aligned regardless
# of repository naming conventions.
labels=()
name_w=4
url_w=3
for i in "${!names[@]}"; do
  label="${names[$i]} (${kinds[$i]})"
  labels+=("$label")
  if [ "${#label}" -gt "$name_w" ]; then
    name_w="${#label}"
  fi
  if [ "${#urls[$i]}" -gt "$url_w" ]; then
    url_w="${#urls[$i]}"
  fi
done

statuses=()
causes=()
overall=0
for i in "${!names[@]}"; do
  hgc_probe_url "${urls[$i]}" "${bypasses[$i]}" "${refs[$i]}"
  if [ "$hgc_probe_rc" -eq 0 ]; then
    statuses+=("OK")
    causes+=("")
  else
    overall=1
    statuses+=("FAIL")
    causes+=("$hgc_probe_cause")
  fi
done

printf '%-*s | %-*s | %s\n' "$name_w" "REPO" "$url_w" "URL" "STATUS"
printf '%s\n' "$(printf '%*s' "$((name_w + url_w + 12))" '' | tr ' ' '-')"
for i in "${!names[@]}"; do
  printf '%-*s | %-*s | %s\n' "$name_w" "${labels[$i]}" "$url_w" "${urls[$i]}" "${statuses[$i]}"
done

if [ "$overall" -ne 0 ]; then
  echo
  echo "unreachable repositories:"
  for i in "${!names[@]}"; do
    if [ "${statuses[$i]}" = "FAIL" ]; then
      echo "  - ${labels[$i]}"
      echo "      url:   ${urls[$i]}"
      echo "      cause: ${causes[$i]}"
    fi
  done
fi

exit "$overall"
