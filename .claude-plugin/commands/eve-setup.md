---
description: Create the Eve memory store at ~/.eve so the plugin's hooks have something to read
---

The Eve plugin's hooks are already wired — installing the plugin did that. What
they do not have yet is a store to read. Until one exists, all three hooks exit
0 and print nothing, which is why the plugin appears to do nothing on a fresh
install.

Set it up:

1. Run the installer that ships with this plugin, in files-only mode:

   ```sh
   sh "${CLAUDE_PLUGIN_ROOT}/install.sh" --yes --no-hooks --no-claude-md
   ```

   `--no-hooks` is not optional here and it is not a preference: the plugin
   already registers the hooks. Letting the installer also write them into
   `~/.claude/settings.json` would run every hook twice — two recall blocks per
   prompt, two session-end writes — and the second copy would keep firing after
   the plugin was uninstalled, with nothing left to point at the cause.

2. Report what it created, then write the user's first memory. Ask them for
   one correction they have typed more than twice — a standing preference, a
   constraint of their system, a decision they are tired of re-litigating —
   and scaffold it:

   ```sh
   ~/.eve/bin/eve add "the claim, stated as a sentence"
   ```

   Then open that file and fill in the two sections that matter: **Why:** (the
   evidence — what happened that makes this true) and **How to apply:** (what
   you should do differently when it surfaces). A rule without its reason gets
   applied literally and wrongly.

3. Rebuild the index and confirm retrieval actually works:

   ```sh
   ~/.eve/bin/eve index
   ~/.eve/bin/eve search --query "<a few words from that memory>"
   ```

   Show the user the raw output. If the search prints the memory, the hooks
   will inject it, because the hooks call this exact command.

Do not tell the user it is working because you read their memory. That is a
sentence, not a measurement — and you are the least reliable possible witness
to your own context. The evidence is the bytes from `eve search` above, and
whether the next answer reflects a constraint that exists only in that file.

Full documentation: `${CLAUDE_PLUGIN_ROOT}/docs/00-index.md`
