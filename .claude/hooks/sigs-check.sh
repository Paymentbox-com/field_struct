#!/usr/bin/env bash
# PreToolUse hook: before a `git commit`, verify the committed type signature
# (`sig/field_struct.rbs`) is not stale relative to the YARD comments it is
# generated from (`rake sigs:check`). On failure, deny the commit and feed the
# check's output back as the reason, so the sig is regenerated
# (`rake sigs:generate`) and committed before the commit lands.
#
# The hook is registered on the Bash matcher with NO `if` gate. A gate only
# prefix-matches the command text, which fails in both directions: `git add -A
# && git commit …` slips past it, and — observed during the v0.10.0 work — a
# non-matching gate can leave the hook running on EVERY Bash call, so the deny
# output buried the results of unrelated commands. Instead we read the command
# from stdin and detect a real `git commit` ourselves, then exit 0 (allow) for
# everything else. Ported from actionable v1.2.1.
#
# sigs:check is the right per-commit guard (it runs in ~2s and `sig/` is the one
# committed generated artifact); the heavier specs/rubocop/docs battery stays in
# `rake release:check`, run by hand before a release commit.
set -uo pipefail

# Repo root = two levels up from this script (.claude/hooks/).
cd "$(dirname "$0")/../.." || exit 0

command=$(cat | jq -r '.tool_input.command // ""')

# Match `git [global-flags] commit` as a real command, anywhere on any line:
#   - grep runs per line, so `^` also anchors statements after a newline
#     (e.g. `git add -A` then `git commit …` on the next line);
#   - `(^|[;&|(])` anchors statements after `;`, `&&`, `||`, `|`, or `(`;
#   - optional `-flag` tokens may sit between `git` and `commit`;
#   - `commit` must be followed by a command delimiter or end-of-line, so
#     `git commit-tree` and quoted prose like `echo "git commit"` don't match.
# (We keep the git→commit gap to flags only on purpose: matching arbitrary
# tokens there would false-block innocent commands like
# `git diff -- commit_helper.rb`. The rare `git -c k=v commit` form isn't caught.)
if ! printf '%s' "$command" |
  grep -Eq '(^|[;&|(])[[:space:]]*git([[:space:]]+-[^[:space:]]+)*[[:space:]]+commit([[:space:];)&|]|$)'; then
  exit 0 # not a git commit — allow
fi

if out=$(bundle exec rake sigs:check 2>&1); then
  exit 0 # check passed — allow the commit (no output = default allow)
fi

# Failed — deny, with the check's output as the reason. Sord's per-method
# generation log ([OMIT]/[DUCK]/[INFO] lines, ~150 of them) is noise here; the
# staleness marker and the diff are the actionable part, so drop the log and
# keep the rest.
reason=$(printf '%s' "$out" | grep -vE '^\[(OMIT|DUCK|INFO|DONE)[[:space:]]*\]' | jq -Rsa .)
printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":%s}}' "$reason"
exit 0
