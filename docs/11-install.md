# 11 · Installing

Two ways in. They install the same files and end at the same place: Eve's
scripts under `~/.eve`, and three hook entries pointing at them. Pick based on
how much you want to read before you run something.

> **Note:** Previous versions of this document referenced `npx eve-recall`.
> That package is not published on npm. Use the clone method below.

| | Command | Best when | The catch |
|---|---|---|---|
| **Clone** | `git clone … && ./install.sh` | You want to read the shell before you run it. **Canonical.** | You keep a clone around, and update it yourself with `git pull`. |
| **Plugin** | `/plugin marketplace add …` | You are in Claude Code and want the native path, with hooks wired for you. | Clones over SSH by default; fails without a key. See [the gotcha](#the-plugin-ssh-gotcha). |

**Recommendation: clone.** Not out of caution theatre — Eve's whole claim is
that you can read it. It is shell and awk, the retrieval engine is one file
(`bin/eve`), and the reason to prefer the clone is that the claim is checkable
in about ten minutes. The plugin path exists because that is not everyone's
first ten minutes.

Clone and plugin install the same files. The store lives in `~/.eve`, separate
from the code, and neither installer touches existing memories.

---

## Before you start

| Required | `sh`, `awk`, `grep`, `sed`, `find`, `date`. Stock on macOS and every Linux. |
|---|---|
| Optional | `jq` (installer only; there is a paste fallback), `python3` (stdlib only, for `kb/` and as a JSON fallback in hooks). |
| **Windows** | Not supported natively — this is POSIX shell. It runs unchanged under **WSL**; install from inside the WSL shell. |

---

## 1 · Clone (canonical)

```sh
git clone https://github.com/Steve-CortesPineda/eve.git
cd eve

./install.sh --dry-run    # the whole plan, writes nothing
./install.sh              # merge hooks; never overwrites settings.json
```

Read `install.sh --dry-run` output first. It prints every file it would write
and every JSON key it would merge, and it is the same code path as the real run
with the writes turned off.

Useful flags:

| | |
|---|---|
| `--no-hooks` | Install the files, leave `settings.json` alone. Tier 0: format and rules, no automation. |
| `--no-claude-md` | Do not merge the rule block into `CLAUDE.md`. |
| `--print-hooks` | Print the JSON block and exit, so you can paste it yourself. |
| `--eve-home PATH` | Somewhere other than `~/.eve`. |
| `-y` / `--yes` | No prompts. For scripts and CI. |

The installer is idempotent: run it twice and `settings.json` is byte-identical
and `CLAUDE.md` has exactly one Eve block. It backs `settings.json` up to
`settings.json.eve.bak` before touching it, and if it cannot merge safely it
prints the exact JSON and says so rather than guessing.

**Updating:** `git pull && ./install.sh`. Your memories are in `~/.eve`, not in
the clone, so nothing you wrote is at risk.

**Uninstalling:**

```sh
./uninstall.sh            # removes the three hook entries and the CLAUDE.md block
rm -rf ~/.eve             # only if you also want the memories gone. Your call.
```

---

## 3 · Claude Code plugin (most native)

The plugin registers the three hooks itself, so there is no `settings.json`
merge at all.

```
/plugin marketplace add Steve-CortesPineda/eve
/plugin install eve@eve-marketplace
```

Then create the store, which the plugin deliberately does not do for you:

```
/eve-setup
```

Or by hand, if you would rather not have an agent run your installer:

```sh
sh ~/.claude/plugins/cache/*/eve/install.sh --yes --no-hooks --no-claude-md
```

`--no-hooks` is not optional here. The plugin has already registered them;
letting the installer add them to `settings.json` too means every hook fires
twice — two recall blocks per prompt — and the duplicate keeps firing after the
plugin is uninstalled, with nothing left pointing at the cause.

### The plugin does nothing until a store exists

This is by design and worth knowing before you conclude it is broken. All three
hooks check for a non-empty store and exit 0 silently if there is not one. A
fresh plugin install therefore looks exactly like a plugin that is not working.
It starts behaving the moment you write your first memory:

```sh
~/.eve/bin/eve add "your rule, stated as a claim"
~/.eve/bin/eve index
```

Hooks are read at session start. **Restart Claude Code** after installing, or
the current session will not have them.

### The plugin SSH gotcha

`/plugin marketplace add owner/repo` — the GitHub shorthand — **clones over SSH
by default.** With no GitHub SSH key loaded in `ssh-agent`, it fails with a
permission-denied or host-verification error that does not mention SSH, so the
obvious conclusion is that the marketplace does not exist.

Three ways out, cheapest first:

```sh
# 1. Tell Claude Code to prefer HTTPS for shorthand sources
export CLAUDE_CODE_PLUGIN_PREFER_HTTPS=1
```

```
# 2. Give it an explicit HTTPS URL instead of the shorthand
/plugin marketplace add https://github.com/Steve-CortesPineda/eve.git
```

```sh
# 3. Fix SSH properly, if you use it for other repos anyway
ssh-add ~/.ssh/id_ed25519
ssh -T git@github.com          # accepts the host key
```

Test whether git can authenticate on its own before blaming the plugin:

```sh
git ls-remote https://github.com/Steve-CortesPineda/eve.git >/dev/null && echo ok
```

For HTTPS against private repos, `gh auth setup-git` stores the credential
where Claude Code's git will find it.

**Uninstalling:**

```
/plugin uninstall eve@eve-marketplace
/plugin marketplace remove eve-marketplace
```

```sh
rm -rf ~/.eve                  # only if you also want the memories gone
```

Uninstalling the plugin removes the hooks with it — they were never in your
`settings.json`. If you also ran the installer *with* hooks at some point, run
`~/.eve/uninstall.sh` to clear that second copy.

---

## Verifying, for real

Whichever path you took, the check is the same and it is not "ask Claude
whether it read my memory". It will say yes. That is a sentence, not a
measurement, and the model is the least reliable available witness to its own
context.

```sh
~/.eve/bin/eve-doctor
```

Every check prints PASS, WARN or FAIL with a one-line remedy. The last one
feeds a synthetic prompt through the real hook and shows you the bytes that
came back. You can run that by hand too:

```sh
printf '{"prompt":"<something your memory covers>","session_id":"t1"}' \
  | ~/.eve/hooks/eve-recall.sh
```

If that prints an `<eve-memory>` block, retrieval works, because it is the same
command Claude Code runs. If it prints nothing, nothing cleared the relevance
gate — which is the normal outcome for most prompts and is not an error.
`eve search --query "..." --all` shows every candidate with its score and is
the tool for "why did that not come back".

### Expected complaints on a fresh install

| The doctor says | It means |
|---|---|
| `memory store is empty` | Correct. The store starts empty on purpose — seeding it with the fictional examples would seed it with fiction. |
| `cannot probe: no memories to find` | Same cause. The probe can only measure a store with something in it. |
| `no settings.json` after clone + `./install.sh --no-hooks` | Correct. `--no-hooks` is files-only. Run without that flag when you want them. |

---

## Turning it off

Without uninstalling anything:

```sh
eve off      # sets EVE_DISABLE=1; every hook exits immediately
eve on
```

Costs about 6 ms per prompt while off, and touches nothing else.

---

## Where things live

| | |
|---|---|
| `~/.eve/memory/` | Your memories. One claim per file. **No installer ever writes here except to add `TEMPLATE.md`, and none ever deletes.** |
| `~/.eve/bin/` | `eve`, `eve-doctor`, `eve-new-memory`. |
| `~/.eve/hooks/` | The hooks Claude Code calls, and `lib/common.sh`. |
| `~/.eve/config` | Key=value. Never sourced, so it cannot execute code. |
| `~/.eve/state/`, `~/.eve/sessions/` | Generated. Deliberately a different tree from `memory/`, so machine output can never bury a hand-written rule in the ranking. |
| `~/.claude/settings.json` | Three hook entries — unless you installed the plugin, which keeps them in its own config. |
| `~/.claude/settings.json.eve.bak` | Snapshot from install time. |

`EVE_HOME` moves the first five. `CLAUDE_CONFIG_DIR` moves the last two.

Nothing here makes a network call, and there is no telemetry, account, or sync.
The one exception in the whole repo is the `reality-reconcile` loop with
`--net`, which is Tier 2, off by default, and opt-in per run — see
[04-loops.md](04-loops.md).
