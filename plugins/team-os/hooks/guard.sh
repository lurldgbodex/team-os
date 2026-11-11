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

# A PR, issue or commit body often mentions a blocked pattern as prose (a
# force push, a piped installer). That text is data, not a command. This
# accepts ONE fixed command shape and, only then, prints its first line so the
# syntax rules can skip the heredoc body. The shape:
#   HEAD <<'WORD'
#   ...body...
#   WORD
# where HEAD is gh pr|issue create|comment|edit, git commit, or cat > PATH,
# with plain arguments (no expansions, no backslashes), WORD is the last line
# and no body line equals WORD. Anything that does not match exactly returns 1
# and the caller checks the raw command. This narrow shape replaced a general
# parser on purpose: the shell grammar is too big to mirror safely.
heredoc_head() {
  local sq="'" dq='"' bs='\' bt='`' bad tok args re head word line last i
  local -a lines=()
  bad="$dq$sq$bs\$$bt"
  tok="([A-Za-z0-9_./:=,@+%-]|${dq}[^$bad]*$dq|${sq}[^$bad]*$sq)+"
  args="( +$tok)*"
  re="^(gh (pr|issue) (create|comment|edit)$args|git commit$args|cat >>? ?[A-Za-z0-9_./-]+) <<'[A-Za-z_][A-Za-z0-9_]*'$"
  while IFS= read -r line || [ -n "$line" ]; do lines+=("$line"); done <<< "${1%$'\n'}"
  [ "${#lines[@]}" -ge 2 ] || return 1
  head="${lines[0]}"
  [[ "$head" =~ $re ]] || return 1
  # In bash, cat > /dev/tcp/host/port sends the body over the network.
  case "$head" in
    "cat >/dev/"*|"cat > /dev/"*|"cat >>/dev/"*|"cat >> /dev/"*) return 1 ;;
  esac
  word="${head##*<<$sq}"; word="${word%$sq}"
  last=$(( ${#lines[@]} - 1 ))
  [ "${lines[$last]}" = "$word" ] || return 1
  for (( i = 1; i < last; i++ )); do
    [ "${lines[$i]}" = "$word" ] && return 1
  done
  printf '%s' "$head"
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

    # Rules 1, 2 and 4 look at syntax, so they skip a PR, issue or commit body
    # (see heredoc_head). Rules 3 and 5 always see the raw command.
    syn="$cmd"
    head="$(heredoc_head "$cmd")" && syn="$head"

    # 1. Force pushes rewrite shared history. Within one command segment (no
    #    "|", ";" or "&") this catches "git", any global options (-C and -c
    #    take one value, so "git -C repo push -f" counts, while a subcommand
    #    like "git commit -m 'push -f'" does not), "push", and then either
    #      - a force flag: -f, a short cluster containing f (-fu, -uf),
    #        --force, or --force-with-lease with or without =<ref>
    #        (long options like --follow-tags are not flags), or
    #      - a refspec starting with "+" (+main, +HEAD:main), which forces
    #        that ref without any flag.
    git_push='git([[:space:]]+(-[Cc][[:space:]]+[^[:space:]|;&]+|-[^[:space:]|;&]+))*[[:space:]]+push([^|;&]*)[[:space:]]'
    force_flag='(-[A-Za-z0-9]*f[A-Za-z0-9]*|--force|--force-with-lease(=[^[:space:]]*)?)([[:space:]]|$)'
    force_refspec='\+[^[:space:]|;&]'
    if printf '%s' "$syn" | grep -Eq "${git_push}(${force_flag}|${force_refspec})"; then
      deny "no-force-push" "force pushes are blocked. Open a PR or ask a teammate to help with history rewrites."
    fi

    # 2. Piped installers run unreviewed code.
    if printf '%s' "$syn" | grep -Eq '(curl|wget)[^|]*\|[[:space:]]*(sudo[[:space:]]+)?(ba|z|da)?sh'; then
      deny "no-piped-installers" "piping a download into a shell is blocked. Download the script, read it, then run it."
    fi

    # 3. Direct production access from an assistant session.
    if printf '%s' "$cmd" | grep -Eiq '(psql|pg_dump|mysql)[^|;&]*(prod|production)'; then
      deny "no-prod-db" "direct production database access is blocked. Use read replicas or the approved data tooling."
    fi

    # 4. Infrastructure deploys go through CI, not a laptop.
    if printf '%s' "$syn" | grep -Eq '(^|[;&|[:space:]])(cdk|terraform|pulumi)[[:space:]]+(deploy|apply|up)([[:space:]]|$)'; then
      deny "no-local-deploy" "infrastructure deploys run in CI. Open a PR instead."
    fi

    # 5. Reading secrets through the shell.
    #    .env files match by whole file name (".env" or ".env.<anything>",
    #    like ".env.local" or ".env.production.local"), the same as the Read
    #    tool rule below, so "config.env" is not caught. A name
    #    starts after whitespace, "/", "=", ",", ":" or a quote (so
    #    --include=.env, "a,.env" and a quoted ".env" count), and ends at
    #    whitespace, ",", ":", a quote or the end of the line. Key files
    #    (id_rsa, *.pem ...) likewise end at whitespace, a quote or the end.
    #    ".env.example" is a committed template without secrets: it is taken
    #    out of the command first, so it stays readable but a real .env named
    #    alongside it is still blocked. Only the exact name is exempt:
    #    ".env.example.bak" is blocked. Each pass consumes the separator
    #    shared by two neighbours, so it repeats until nothing changes.
    #
    #    Readers: cat less more head tail grep source "." match as before.
    #    awk sed base64 xxd od strings bat must be a whole word (start of
    #    line or a character that is not a letter, digit or "_"). This rule
    #    also scans PR and commit text, and without that boundary "we used
    #    .env files" would be blocked, because "used" contains "sed". Both
    #    patterns use the same reader list.
    #
    #    cp is checked separately: it is blocked only when the secret is a
    #    SOURCE, that is, followed by whitespace and another argument in the
    #    same segment. "cp .env /tmp/x" is blocked; "cp .env.example .env"
    #    is fine (the template is stripped first, leaving ".env" as the last
    #    argument, the destination). Limit: "cp -t dir .env" still gets
    #    through, because there the secret is the last argument.
    scan="$cmd"
    while :; do
      next="$(printf '%s' "$scan" | sed -E 's#(^|[[:space:]/=,:"'\''])\.env\.example([[:space:],:"'\'']|$)#\1\2#g')"
      [ "$next" = "$scan" ] && break
      scan="$next"
    done
    readers='(cat|less|more|head|tail|grep|source|\.)|((^|[^A-Za-z0-9_])(awk|sed|base64|xxd|od|strings|bat))'
    env_name='\.env(\.[A-Za-z0-9_.-]+)?'
    key_name='(id_rsa|id_ed25519|\.pem|credentials)'
    cp_word='(^|[^A-Za-z0-9_])cp[[:space:]]+'
    if printf '%s' "$scan" | grep -Eq "(${readers})[[:space:]]([^|;&]*[[:space:]/=,:\"'])?${env_name}([[:space:],:\"']|\$)" \
      || printf '%s' "$scan" | grep -Eq "(${readers})[[:space:]]+[^|;&]*${key_name}([[:space:]\"']|\$)" \
      || printf '%s' "$scan" | grep -Eq "${cp_word}([^|;&]*[[:space:]/=,:\"'])?${env_name}[[:space:],:\"']+[^[:space:]|;&]" \
      || printf '%s' "$scan" | grep -Eq "${cp_word}[^|;&]*${key_name}[[:space:]\"']+[^[:space:]|;&]"; then
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
