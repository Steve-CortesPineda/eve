---
kind: note
date: 2030-02-03
review_by: none
---

# On-call rotation

> FICTIONAL FIXTURE. Nothing here describes a real system.

## Handoff

The rotation changes hands on **Thursday at 10:00 local time**. Thursday rather than
Monday, so that whoever is handing over is still around for two working days
afterwards to answer questions about whatever they are handing over.

## Handoff contents

The outgoing on-call writes a short note covering: anything still open, anything
that fired and was silenced rather than fixed, and anything they changed. The note
goes in `notes/` with the date, like everything else.

## Escalation

If the on-call does not acknowledge, escalation follows the rotation order — the
next person on the list, then the one after. Which tool does the paging, and on what
timer, is not recorded here.
