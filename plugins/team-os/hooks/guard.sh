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
#     cannot be a flag or a pipe.
#   - a quoted string without whitespace is kept, quotes removed, so
#     "--force" and "sh" still count.
#   - heredoc bodies are dropped.
#   - a "#" at the start of a word begins a comment to the end of the line.
#     It is dropped, so an apostrophe in a comment does not pair with a quote
#     on another line. This is safe because a backslash (which could escape
#     the "#") fails strict, see below.
# The parser only understands plain text. It gives up and prints the command
# unchanged (so it is checked as before) on anything it cannot read cleanly:
#   - an unclosed quote or an unterminated heredoc
#   - a backslash, a backtick, $( ${ $[ (( or $' (command substitution,
#     expansions, arithmetic, ANSI-C quoting), anywhere in the command,
#     including inside quotes. The one exception is the body of a heredoc
#     with a quoted delimiter (<<'EOF'), which the shell does not expand.
#   - the body of a heredoc with an unquoted delimiter, if it contains $, a
#     backtick or a backslash: the shell expands those.
# It then returns 1, so syntax_view knows. (syntax_view below decides when the
# stripped copy may be used alone.)
strip_text() {
  local out
  out="$(printf '%s\n' "$1" | awk '
    # Position of the next ch at or after from, or 0. A plain loop, so a long
    # heredoc body is read once (substr(s, i) per line would be quadratic).
    function find(ch, from,   j) {
      for (j = from; j <= n; j++) if (substr(s, j, 1) == ch) return j
      return 0
    }
    # Does t hold anything the parser does not follow?
    function unreadable(t) {
      return index(t, "\\") || index(t, "`") || index(t, "$(") || index(t, "${") \
        || index(t, "$[") || index(t, "((") || index(t, "$" sq)
    }
    { s = s $0 "\n" }
    END {
      sq = sprintf("%c", 39); n = length(s); i = 1; out = ""; np = 0
      while (i <= n) {
        c = substr(s, i, 1)
        if (c == sq) {
          j = find(sq, i + 1)
          if (j == 0) exit 1
          if (unreadable(substr(s, i, j - i + 1))) exit 1
          body = substr(s, i + 1, j - i - 1); i = j + 1
          if (body ~ /[ \t\n]/) body = ""
          out = out body; continue
        }
        if (c == "\"") {
          j = find("\"", i + 1)
          if (j == 0) exit 1
          if (unreadable(substr(s, i, j - i + 1))) exit 1
          body = substr(s, i + 1, j - i - 1); i = j + 1
          if (body ~ /[ \t\n]/) body = ""
          out = out body; continue
        }
        if (unreadable(substr(s, i, 2))) exit 1
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
          if (unreadable(w) || index(w, "$")) exit 1
          if (w == "") { out = out "<<"; i += 2; continue }
          np++; pw[np] = w; pd[np] = dash; pq[np] = quoted
          out = out "<<"; i = k; continue
        }
        if (c == "#" && (i == 1 || substr(s, i - 1, 1) ~ /[ \t\n;&|()]/)) {
          # Drop the comment text; the newline stays for the heredoc handling.
          i = find("\n", i); continue
        }
        if (c == "\n") {
          out = out "\n"; i++
          for (p = 1; p <= np; p++) {
            done = 0
            while (i <= n) {
              e = find("\n", i)
              line = substr(s, i, e - i); i = e + 1
              t = line
              if (pd[p]) sub(/^\t+/, "", t)
              if (t == pw[p]) { done = 1; break }
              if (!pq[p] && (index(line, "$") || index(line, "`") || index(line, "\\"))) exit 1
            }
            if (!done) exit 1
          }
          np = 0; continue
        }
        out = out c; i++
      }
      printf "%s", out
    }')" || { printf '%s' "$1"; return 1; }
  printf '%s' "$out"
}

# The command as the syntax rules should see it. The stripped copy drops
# quoted prose, which is only safe when nothing in the line runs a quoted
# string or heredoc body as code (sh -c "...", eval, trap, source, a variable
# used as the command, flock ... -c, at <<EOF, ssh host "..." and so on).
# So the line is split into simple commands (at ; && || | & newline,
# parentheses and backticks) and the stripped copy is used ALONE only if every command word
# is on a short allowlist of commands that never run their arguments as code:
#   echo printf cat tee jq cd ls mkdir touch true
#   gh with pr, issue, release, api, label or repo
#   git with add commit tag notes status log diff show fetch pull push switch
#     checkout branch merge stash restore reset remote rm mv
# A command that starts with a NAME=value assignment is not on the list (it
# can change what runs: GIT_PAGER, GIT_SSH_COMMAND, EDITOR). A git option
# before the subcommand (for example -c) and git config/rebase/bisect/filter-branch/
# submodule are not on the list, because they can run a string as a command.
# Neither is a git command with --upload-pack, --receive-pack or --exec,
# which name a program for fetch, pull or push to run.
# The allowlist is deliberately short. Any other command word, including one
# we do not know, brings back the old raw check, so the guard stays strict:
# the stripped copy, the raw command and the raw command with its quote marks
# blanked (so "git push --force" ends in a space, not a quote) are all checked.
syntax_view() {
  local stripped rest line word w i safe=1
  # If the parser gave up, the "stripped" copy is the raw command: not safe.
  stripped="$(strip_text "$1")" || safe=0
  # Redirections like 2>&1 and &> are not command separators.
  rest="$(printf '%s' "$stripped" | sed -E 's/[0-9]*[<>]&[0-9-]*//g; s/&>>?//g')"
  while [ "$safe" -eq 1 ] && IFS= read -r line; do
    # read -a splits on whitespace without expanding wildcards, so a command
    # word like "ech?" is never matched against files in the current folder.
    read -r -a w <<< "$line"
    [ "${#w[@]}" -eq 0 ] && continue
    # A leading NAME=value can change what a command runs (GIT_PAGER,
    # GIT_SSH_COMMAND, EDITOR, GIT_CONFIG_*), so it is not allowlisted.
    if [[ "${w[0]}" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; then safe=0; break; fi
    case "${w[0]}" in
      echo|printf|cat|tee|jq|cd|ls|mkdir|touch|true) ;;
      gh)
        case "${w[1]:-}" in
          pr|issue|release|api|label|repo) ;;
          *) safe=0; break ;;
        esac ;;
      git)
        case "${w[1]:-}" in
          add|commit|tag|notes|status|log|diff|show|fetch|pull|push|switch|checkout|branch|merge|stash|restore|reset|remote|rm|mv) ;;
          *) safe=0; break ;;
        esac
        for word in "${w[@]}"; do
          case "$word" in
            --upload-pack*|--receive-pack*|--exec*) safe=0; break 2 ;;
          esac
        done ;;
      *) safe=0; break ;;
    esac
  done < <(printf '%s\n' "$rest" | tr ';&|()`' '\n\n\n\n\n\n')
  if [ "$safe" -eq 1 ]; then
    printf '%s' "$stripped"
  else
    printf '%s\n%s\n%s' "$stripped" "$1" "$(printf '%s' "$1" | tr "\"'" '  ')"
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
