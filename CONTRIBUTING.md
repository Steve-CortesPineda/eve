# Contributing

Small repo, small rules. Read this once and you will not have to guess.

## The one rule that is not negotiable

**No personal data. Ever. Not yours, not anyone's.**

This repo is about a system that stores what you tell it — which means example
files are the natural place for real details to leak. Every example in this
repo is fiction, and contributions must keep it that way:

- No real names, usernames, or handles.
- No real hostnames, IPs, ports, tokens, keys, or absolute paths from your
  machine. Use `staging.harborlight.internal`, `$DEPLOY_HOST`, `~/.eve`.
- No real employer, client, or project names. The fictional project is
  **Harborlight**, a shipping-manifest API. Reuse it.
- No pasted logs or transcripts. Write a fresh, obviously synthetic example.

If you are unsure whether a detail is personal, cut it. The pattern is the
value; the detail never is. Reviewers will reject a PR over this even when
everything else is good, and it is nothing personal — it is that a public repo
about memory files is the last place you want a habit of pasting real ones.

## Testing a hook

A Claude Code hook is a program that reads one JSON object on stdin and writes
to stdout. That means you can test one without Claude Code, and you should,
because the alternative — starting a session and hoping — tells you almost
nothing when it goes wrong.

```sh
# recall: does a real prompt produce a block?
printf '{"session_id":"t1","prompt":"what is our deploy window"}' \
  | EVE_HOME=/tmp/eve-test sh hooks/eve-recall.sh; echo "exit=$?"

# recall: does a junk prompt stay silent? (it must)
printf '{"session_id":"t1","prompt":"ok"}' \
  | EVE_HOME=/tmp/eve-test sh hooks/eve-recall.sh; echo "exit=$?"

# recall: does malformed input still exit 0? (it must)
printf 'not json at all' \
  | EVE_HOME=/tmp/eve-test sh hooks/eve-recall.sh; echo "exit=$?"

# session end: print the payload instead of writing it.
# It needs a transcript that exists and has at least two assistant turns --
# without one the hook correctly writes nothing, and you will think it is
# broken when it is doing its job.
printf '%s\n' \
  '{"type":"user","message":{"content":"why is the deploy failing"}}' \
  '{"type":"assistant","message":{"content":[{"type":"text","text":"Looking at it."}]}}' \
  '{"type":"assistant","message":{"content":[{"type":"text","text":"The lock is held by the reconcile job."}]}}' \
  > /tmp/t.jsonl
printf '{"session_id":"t1","transcript_path":"/tmp/t.jsonl","reason":"exit"}' \
  | EVE_DRY_RUN=1 EVE_HOME=/tmp/eve-test sh hooks/eve-session-end.sh
```

What you are checking, in order of importance:

1. **Exit status is 0.** Always, for every input, including garbage. A
   `UserPromptSubmit` hook that exits non-zero degrades every prompt for the
   rest of the session. There is no error worth that.
2. **stderr is empty on the happy path.** stderr surfaces to the user.
3. **stdout is empty when there is nothing worth saying.** Silence is the
   normal outcome, not a bug.
4. **The bytes are what you expect.** Read them. Do not start a session and ask
   Claude whether it saw your memory — it will say yes.

Then run the doctor, which ends by doing all of the above against a real store
and printing the bytes:

```sh
EVE_HOME=/tmp/eve-test sh scripts/doctor.sh
```

If the repo ships `tests/run.sh`, run that too. Never point tests or the doctor
at your real store while developing — use a throwaway `EVE_HOME` under `/tmp`,
and if you add tests, assert that `EVE_HOME` is under a temp directory before
writing anything.

The installer is worth testing the same way, against a throwaway home:

```sh
H=$(mktemp -d)
mkdir -p "$H/.claude"
HOME="$H" EVE_HOME="$H/.eve" CLAUDE_CONFIG_DIR="$H/.claude" sh ./install.sh --yes
HOME="$H" EVE_HOME="$H/.eve" CLAUDE_CONFIG_DIR="$H/.claude" sh ./install.sh --yes  # must be a no-op
HOME="$H" EVE_HOME="$H/.eve" CLAUDE_CONFIG_DIR="$H/.claude" sh ./uninstall.sh --yes
```

Never run `install.sh` against your own `~/.claude` to check a change.

## Style bar

**Shell.** POSIX `sh`, not bash. macOS ships bash 3.2, so no associative
arrays, no `${x^^}`, no `mapfile`, no `readarray`. Do not use `timeout(1)` — it
is not on stock macOS. `stat` flags differ between BSD and GNU; go through one
helper that tries both. `realpath` and `readlink -f` are not portable; resolve
with `cd "$(dirname "$f")" && pwd` in a subshell.

**Discipline.** `set -eu` at the top. Quote every expansion. Never `eval` a
value that came from a file or a prompt. Enumerate files with `find`, not a
glob — an unmatched glob expands to itself in POSIX sh and you end up processing
a literal `*.md`.

**Idempotence.** Every script here can be run twice. The second run must change
nothing and say so. If you add a script, add a test that runs it twice and
diffs.

**Destruction.** Nothing in this repo deletes a user's file. Not a stale mirror,
not an orphan, not an expired memory. Report it and print the command; let the
human run it. If your change adds an `rm` that touches anything outside a temp
directory, expect to defend it.

**Prose.** Write like a good engineering README: state the problem, state the
mechanism, show the command, state the failure mode. No marketing voice. No
adjective lists. Plain ASCII in script output — no emoji, and no box-drawing
that will not survive somebody's terminal.

**Dependencies.** The default path must work on a stock macOS or minimal Linux
box with nothing installed. `jq` and `python3` may be used when present and must
degrade cleanly when absent. Anything heavier is opt-in, off by default, and
falls back to the default path silently if it is missing or broken.

## Design changes

Before adding a component, read [docs/05-design-laws.md](docs/05-design-laws.md)
and check your change against the list at the end. Two of them come up in almost
every PR:

- **Every producer names its consumer.** If you add something that writes a
  file, say in a comment at the top of that file what reads it. If you cannot,
  the answer is to not write the file.
- **Prefer the smallest change that removes the failure mode.** If your fix is a
  new penalty, exclusion list, or special case, spend five minutes looking for
  the structural change that would delete it instead. Most of the compensating
  machinery in systems like this exists because two kinds of file share a
  directory.

## Pull requests

- One change per PR. A doc fix and a scoring change are two PRs.
- Say what failure the change removes. "Improves relevance" is not a failure;
  "a two-word query matched every file that mentioned `deploy`" is.
- Include the before/after output if the change affects what gets injected —
  the bytes are the interface.
- New behaviour needs a test. Tests here are plain `sh` with no framework; copy
  the case above yours.

Bug reports are more useful with the doctor's output attached
(`sh scripts/doctor.sh`). Redact freely — it prints paths and memory titles, and
we do not need either to help you.
