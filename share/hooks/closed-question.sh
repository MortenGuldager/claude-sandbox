#!/usr/bin/env bash
# UserPromptSubmit hook: bind the shape of the answer to the shape of the
# question. A closed question ("er det ...?", "can we ...?") reliably grew
# into pages of argument, because the output style only asks for concision
# in the abstract and competes with every other standing instruction. This
# pushes a checkable form rule into the turn itself, where it is the most
# recent thing in context.
#
# Deliberately one heuristic, not a parser: the first word is a yes/no
# opener, the prompt contains a question mark, and the prompt is short. A
# long prompt that opens with "kan" is a work request, not a closed
# question, so it is left alone. Emits the documented
# hookSpecificOutput.additionalContext JSON, since plain stdout is not a
# contract we want to rely on.
#
# Fails open on purpose: no `set -e`, and every step guarded. A nonzero
# exit from a UserPromptSubmit hook can block the user's prompt, and a
# style nicety must never cost someone their turn.
set -u

command -v jq >/dev/null 2>&1 || exit 0

# Claude Code passes the hook payload as JSON on stdin.
prompt="$(jq -r '.prompt // ""' 2>/dev/null)" || exit 0
[ -n "$prompt" ] || exit 0

case "$prompt" in
    *'?'*) ;;
    *) exit 0 ;;
esac

# Long prompts are work requests, not closed questions, whatever they
# open with.
[ "${#prompt}" -le 600 ] || exit 0

# First word only. No character-class filtering: the openers are ASCII,
# but Danish prompts are UTF-8, and byte-wise `tr` mangles æøå.
read -r first _ <<<"$prompt" || exit 0
first="${first,,}"

case " er var kan kunne vil ville skal skulle har havde må bør burde gør gjorde virker findes is are was were am can could will would shall should do does did has have had may might " in
    *" $first "*) ;;
    *) exit 0 ;;
esac

cat <<'RULE' | jq -Rs '{hookSpecificOutput:{hookEventName:"UserPromptSubmit",additionalContext:.}}'
# Closed question: answer in this shape

The user asked a yes/no or either/or question. Answer in this form, and treat
the form as a hard constraint rather than a suggestion:

1. The first word is the answer: Ja, Nej, or the name of the option you pick.
2. Then at most 2 sentences of grounds, covering only what makes that answer
   true.
3. Then stop.

Leave out alternatives you are not recommending, trade-offs the user did not
ask about, caveats that do not change the answer, and any summary of what you
just wrote. Cut those dimensions, do not shorten them.

Two exceptions, each one sentence. If the honest answer is "it depends", name
what it depends on in one sentence and stop. If a fact would change the user's
decision (data loss, breaking change, cost, security), state it in one
sentence and stop. Offer to expand rather than expanding.
RULE
