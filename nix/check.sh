# Probe every repository recorded in a home-git-clone manifest and report
# reachability, without needing the Nix configuration that produced it.
#
# Usage: home-git-clone-check [MANIFEST]
#   MANIFEST defaults to ~/.config/home-git-clone/manifest.json (the live
#   symlink maintained by the Home Manager module).
#
# Exit codes: 0 when all remotes are reachable, 1 otherwise.

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  echo "Usage: home-git-clone-check [MANIFEST]"
  echo "Probe every repository in a home-git-clone manifest and report reachability."
  echo "MANIFEST defaults to \$HOME/.config/home-git-clone/manifest.json."
  echo "Exit codes: 0 all remotes reachable, 1 otherwise."
  exit 0
fi

manifest="${1:-$HOME/.config/home-git-clone/manifest.json}"

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

# Mirror the module's SSH setup so the verdict here predicts what an
# activation on this machine would see.
if [ -S "$HOME/.gnupg/S.gpg-agent.ssh" ]; then
  export SSH_AUTH_SOCK="$HOME/.gnupg/S.gpg-agent.ssh"
fi

names=()
kinds=()
urls=()
bypasses=()
while IFS=$'\t' read -r name kind url bypass _path; do
  names+=("$name")
  kinds+=("$kind")
  urls+=("$url")
  bypasses+=("$bypass")
done < <(jq -r '.repos[] | [.name, .kind, .url, (.bypassGitConfig | tostring), .path] | @tsv' "$manifest")

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
  # Same probe as the module's activation preflight: GIT_TERMINAL_PROMPT=0
  # makes credential prompts fail fast instead of hanging under the timeout,
  # and bypassGitConfig reproduces the environment the clone would use.
  probe_env=(GIT_TERMINAL_PROMPT=0)
  if [ "${bypasses[$i]}" = "true" ]; then
    probe_env+=(GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null)
  fi
  rc=0
  err="$(env "${probe_env[@]}" timeout 10 git ls-remote --exit-code "${urls[$i]}" HEAD 2>&1 >/dev/null)" || rc=$?
  if [ "$rc" -eq 0 ]; then
    statuses+=("OK")
    causes+=("")
  else
    overall=1
    statuses+=("FAIL")
    if [ "$rc" -eq 124 ]; then
      causes+=("timed out after 10s")
    else
      # First non-empty stderr line: the root cause (ssh/curl error) comes
      # first, git's generic advice last.
      cause="$(printf '%s\n' "$err" | grep -v '^[[:space:]]*$' | head -n 1 || true)"
      causes+=("${cause:-probe failed with exit code $rc}")
    fi
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
