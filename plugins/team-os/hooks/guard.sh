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

# Print a "syntax-only" copy of a command, for the rules that look at shell
# syntax (flags, pipes, subcommands). Text that only mentions a blocked pattern
# must not trip them: a PR body, a commit message, an echo.
#   - a quoted string with whitespace is dropped: it is one argument, so it
#     cannot be a flag or a pipe. (Unless a double-quoted one has $( or a
#     backtick: that runs code, so it is kept.)
#   - a quoted string without whitespace is kept, quotes removed, so
#     "--force" and "sh" still count.
#   - heredoc bodies are dropped. An unquoted-delimiter body with $( or a
#     backtick runs code, so it fails strict.
#   - anything we cannot read cleanly (unclosed quote, unterminated heredoc)
#     prints the command unchanged, so it is checked as before.
strip_text() {
  local out
  out="$(printf '%s\n' "$1" | awk '
    { s = s $0 "\n" }
    END {
      sq = sprintf("%c", 39); n = length(s); i = 1; out = ""; np = 0
      while (i <= n) {
        c = substr(s, i, 1)
        if (c == "\\") { out = out substr(s, i, 2); i += 2; continue }
        if (c == sq) {
          j = index(substr(s, i + 1), sq)
          if (j == 0) exit 1
          body = substr(s, i + 1, j - 1); i += j + 1
          if (body ~ /[ \t\n]/) body = ""
          out = out body; continue
        }
        if (c == "\"") {
          j = i + 1
          while (j <= n) {
            d = substr(s, j, 1)
            if (d == "\\") j += 2
            else if (d == "\"") break
            else j++
          }
          if (j > n) exit 1
          body = substr(s, i + 1, j - i - 1); i = j + 1
          if (body ~ /[ \t\n]/ && body !~ /[$][(]|`/) body = ""
          out = out body; continue
        }
        if (c == "<" && substr(s, i, 3) == "<<<") { out = out "<<<"; i += 3; continue }
        if (c == "<" && substr(s, i, 2) == "<<") {
          k = i + 2; dash = 0
          if (substr(s, k, 1) == "-") { dash = 1; k++ }
          while (substr(s, k, 1) ~ /[ \t]/) k++
          w = ""; quoted = 0
          while (k <= n) {
            d = substr(s, k, 1)
            if (d == sq || d == "\"") { quoted = 1; k++; continue }
            if (d ~ /[ \t\n;&|<>()]/) break
            w = w d; k++
          }
          if (w == "") { out = out "<<"; i += 2; continue }
          np++; pw[np] = w; pd[np] = dash; pq[np] = quoted
          out = out "<<"; i = k; continue
        }
        if (c == "\n") {
          out = out "\n"; i++
          for (p = 1; p <= np; p++) {
            done = 0
            while (i <= n) {
              e = index(substr(s, i), "\n")
              line = substr(s, i, e - 1); i += e
              t = line
              if (pd[p]) sub(/^\t+/, "", t)
              if (t == pw[p]) { done = 1; break }
              if (!pq[p] && line ~ /[$][(]|`/) exit 1
            }
            if (!done) exit 1
          }
          np = 0; continue
        }
        out = out c; i++
      }
      printf "%s", out
    }')" || { printf '%s' "$1"; return; }
  printf '%s' "$out"
}

# The command as the syntax rules should see it. If the stripped copy hands
# text to a shell (sh -c "...", eval "...", bash <<EOF, cat <<EOF | sh,
# ssh host "..."), the quoted text or heredoc body is code, not prose: then
# the stripped copy, the raw command and the raw command with its quote marks
# blanked (so "git push --force" ends in a space, not a quote) are all
# checked. A word counts only
# as a whole word, so "install.sh", "--bash" and "git-sh" do not.
syntax_view() {
  local stripped
  stripped="$(strip_text "$1")"
  if printf '%s' "$stripped" | grep -Eq '(^|[^[:alnum:]_.-])(sh|bash|zsh|dash|ksh|fish|eval|ssh|su)([^[:alnum:]_.-]|$)'; then
    printf '%s\n%s\n%s' "$stripped" "$1" "$(printf '%s' "$1" | tr "\"'" '  ')"
  else
    printf '%s' "$stripped"
  fi
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

    # Two kinds of Bash rules. Syntax rules (1, 2, 4) look at flags, pipes and
    # subcommands, so they run on $syn, the command without quoted prose and
    # heredoc bodies. Argument rules (3, 5) look at what a command is pointed
    # at, which is usually inside quotes, so they run on the raw $cmd.
    syn="$(syntax_view "$cmd")"

    # 1. Force pushes rewrite shared history.
    if printf '%s' "$syn" | grep -Eq 'git[[:space:]]+push([^|;&]*)[[:space:]](-f|--force|--force-with-lease)([[:space:]]|$)'; then
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
    #    starts after whitespace, "/", "=", "," or ":" (so --include=.env and
    #    "a,.env" count).
    #    ".env.example" is a committed template without secrets: it is taken
    #    out of the command first, so it stays readable but a real .env named
    #    alongside it is still blocked. Only the exact name is exempt:
    #    ".env.example.bak" is blocked. Each pass consumes the separator
    #    shared by two neighbours, so it repeats until nothing changes.
    scan="$cmd"
    while :; do
      next="$(printf '%s' "$scan" | sed -E 's#(^|[[:space:]/=,:])\.env\.example([[:space:],:]|$)#\1\2#g')"
      [ "$next" = "$scan" ] && break
      scan="$next"
    done
    if printf '%s' "$scan" | grep -Eq '(cat|less|more|head|tail|grep|source|\.)[[:space:]]([^|;&]*[[:space:]/=,:])?\.env(\.[A-Za-z0-9_.-]+)?([[:space:],:]|$)' \
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
