---
id: {{ID}}
title: {{TITLE}}
type: {{TYPE}}
status: current
tags: []
source: you
created: {{DATE}}
updated: {{DATE}}
verified_on: {{DATE}}
confidence: medium
---

{{TITLE}}.

**Why:**

**How to apply:**
-
-

<!-- eve:template-help
Delete nothing above this comment; the generator strips this block.

id          The filename stem. Written down so the id survives a copy.
title       The CONCLUSION in one line, not the topic.
            Good: "Deploys are blocked after 18:00 UTC"
            Bad:  "Deploy notes"
type        feedback | project | decision | reference | note
            feedback  a standing rule about you or about how to work
            project   how one system of yours is built, and why
            decision  a call you made, with the reasoning that made it
            reference an external fact you cannot derive from your own code
            note      anything that does not fit yet
status      current | draft | superseded
            superseded is a tombstone. Never delete a reversed decision;
            demote it and point at what replaced it.
tags        lowercase, kebab-case, flow list: [deploy, api]
source      where this came from: "you", a person, a file, a doc + date.
            An unattributed claim is indistinguishable from an invented one.
created     first written. updated: last edited. Both YYYY-MM-DD.
verified_on the last date someone checked this is still true. This is the
            field that decides whether an agent may assert it flatly.
confidence  high | medium | low. Be honest; low is useful, wrong is not.

Body shape:
  Line 1     the claim, stated flat, so it reads well as a one-line snippet.
  Why        the evidence. What actually happened. Without this, the rule
             gets applied literally in a situation it was never about.
  How to     concrete triggers and actions. If you cannot write this
  apply      section, you are writing reference material, not a memory.

Cross-reference other memories with [[their-id]]. Link only to ids that
exist -- a dangling link is a claim that something was written down when it
was not.

One file, one claim. If you want an "Also" section about an unrelated
thing, that is a second memory.
-->
