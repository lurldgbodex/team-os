#!/usr/bin/env bash
# PreToolUse hook: block dangerous actions with a clear reason.
#
# Claude Code sends the pending tool call as JSON on stdin:
#   { "tool_name": "Bash", "tool_input": { "command": "..." }, ... }
# To block, we print a JSON decision on stdout and exit 0. (Exiting with
# code 2 and writing the reason to stderr is the other supported way.)
#
# The rules here are the *hard* ones. They are deliberately few and simple so
# they are easy to explain, test and audit. Softer "ask first" rules live in
# policy/rules/*.json and are merged into the engineer's Claude settings by
# the installer.

set -u

input="$(cat)"

# jq is a hard requirement of Team OS (checked by the installer). If it is
# missing we fail open rather than block all work.
command -v jq >/dev/null 2>&1 || exit 0

tool="$(printf '%s' "$input" | jq -r '.tool_name // empty')"

deny() {
  # $1 = rule id, $2 = human reason
  jq -n --arg reason "Team OS guard [$1]: $2" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: $reason
    }
  }'
  exit 0
}

# Is this file name a secret? ".env.example" is a committed template without
# secrets, so it is readable. Shared by the Read/Edit/Write and Grep rules.
is_secret_name() {
  case "$1" in
    .env.example) return 1 ;;
    .env|.env.*|*.pem|id_rsa|id_ed25519|credentials) return 0 ;;
  esac
  return 1
}

# Does a Grep glob target a secret file? Globs are checked by their file name
# part. Each "*" is tried as empty and as a letter, and {a,b} is split, so
# ".env*" counts as ".env", "*.pem" as "x.pem", and so on.
glob_targets_secret() {
  local piece base cand
  while IFS= read -r piece; do
    base="${piece##*/}"
    for cand in "${base//[*?]/}" "${base//[*?]/x}"; do
      is_secret_name "$cand" && return 0
    done
  done < <(printf '%s\n' "$1" | tr '{},' '\n\n\n')
  return 1
}

case "$tool" in
  Bash)
    cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty')"

    # 1. Force pushes rewrite shared history.
    if printf '%s' "$cmd" | grep -Eq 'git[[:space:]]+push([^|;&]*)[[:space:]](-f|--force|--force-with-lease)([[:space:]]|$)'; then
      deny "no-force-push" "force pushes are blocked. Open a PR or ask a teammate to help with history rewrites."
    fi

    # 2. Piped installers run unreviewed code.
    if printf '%s' "$cmd" | grep -Eq '(curl|wget)[^|]*\|[[:space:]]*(sudo[[:space:]]+)?(ba|z|da)?sh'; then
      deny "no-piped-installers" "piping a download into a shell is blocked. Download the script, read it, then run it."
    fi

    # 3. Direct production access from an assistant session.
    if printf '%s' "$cmd" | grep -Eiq '(psql|pg_dump|mysql)[^|;&]*(prod|production)'; then
      deny "no-prod-db" "direct production database access is blocked. Use read replicas or the approved data tooling."
    fi

    # 4. Infrastructure deploys go through CI, not a laptop.
    if printf '%s' "$cmd" | grep -Eq '(^|[;&|[:space:]])(cdk|terraform|pulumi)[[:space:]]+(deploy|apply|up)([[:space:]]|$)'; then
      deny "no-local-deploy" "infrastructure deploys run in CI. Open a PR instead."
    fi

    # 5. Reading secrets through the shell.
    #    .env files match by whole file name (".env", ".env.<name>"), the same
    #    as the Read tool rule below, so "config.env" is not caught. A name
    #    starts after whitespace, "/", "=", "," or ":" (so --include=.env and
    #    "a,.env" count).
    #    ".env.example" is a committed template without secrets: it is taken
    #    out of the command first, so it stays readable but a real .env named
    #    alongside it is still blocked.
    scan="$(printf '%s' "$cmd" | sed -E 's#(^|[[:space:]/=,:])\.env\.example([[:space:],:]|$)#\1\2#g')"
    if printf '%s' "$scan" | grep -Eq '(cat|less|more|head|tail|grep|source|\.)[[:space:]]([^|;&]*[[:space:]/=,:])?\.env(\.[A-Za-z]+)?([[:space:],:]|$)' \
      || printf '%s' "$scan" | grep -Eq '(cat|less|more|head|tail|grep|source|\.)[[:space:]]+[^|;&]*(id_rsa|id_ed25519|\.pem|credentials)([[:space:]]|$)'; then
      deny "no-secret-files" "reading .env or key files is blocked. Ask the engineer to share only the non-secret values you need."
    fi
    ;;

  Read|Edit|Write)
    path="$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty')"
    base="$(basename "$path")"
    if is_secret_name "$base"; then
      deny "no-secret-files" "reading or editing $base is blocked. It likely contains secrets."
    fi
    ;;

  Grep)
    # Glob is deliberately not in the hooks.json matcher: it only lists file
    # names and never reads contents. Grep reads contents, so it is covered.
    # A Grep over a whole directory with no glob can still reach .env files
    # unless ripgrep skips them (for example through .gitignore).
    path="$(printf '%s' "$input" | jq -r '.tool_input.path // empty')"
    glob="$(printf '%s' "$input" | jq -r '.tool_input.glob // empty')"
    if [ -n "$path" ] && is_secret_name "$(basename "$path")"; then
      deny "no-secret-files" "searching $(basename "$path") is blocked. It likely contains secrets."
    fi
    if [ -n "$glob" ] && glob_targets_secret "$glob"; then
      deny "no-secret-files" "searching files matching '$glob' is blocked. It would read secrets."
    fi
    ;;
esac

# Anything else: no opinion, normal permission flow continues.
exit 0
