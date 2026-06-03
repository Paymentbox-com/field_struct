#!/usr/bin/env bash
# PreToolUse hook: before a `git commit`, verify the committed type signature
# (`sig/field_struct.rbs`) is not stale relative to the YARD comments it is
# generated from (`rake sigs:check`). On failure, deny the commit and feed the
# check's output back as the reason, so the sig is regenerated
# (`rake sigs:generate`) and committed before the commit lands. Gated to
# `git commit*` via the hook's `if` in .claude/settings.json, so other Bash
# commands never reach this script.
#
# sigs:check is the right per-commit guard (it runs in ~2s and `sig/` is the one
# committed generated artifact); the heavier specs/rubocop/docs battery stays in
# `rake release:check`, run by hand before a release commit.
set -uo pipefail

# Repo root = two levels up from this script (.claude/hooks/).
cd "$(dirname "$0")/../.." || exit 0

if out=$(bundle exec rake sigs:check 2>&1); then
  exit 0 # check passed — allow the commit (no output = default allow)
fi

# Failed — emit a PreToolUse deny with the check output as the reason.
reason=$(printf '%s' "$out" | jq -Rsa .)
printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":%s}}' "$reason"
exit 0
