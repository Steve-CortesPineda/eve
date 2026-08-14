#!/bin/sh
# bench.sh -- measure the sqlite engine against the default one, on THIS machine.
#
# The numbers in docs/13-engines.md came out of this script. They are not a
# promise about your machine. An older CPU, a spinning disk, an encrypted or
# network filesystem, or a box under load moves every row in the table, and the
# store size where an index starts paying for itself moves with them. That is
# the whole reason this exists: run it, read your own numbers, decide from those.
#
#   ./bench.sh                 everything: latency, maintenance, agreement, proofs
#   ./bench.sh 200 2000        latency at those store sizes only
#   ./bench.sh --maintenance N what the index costs to keep honest, at size N
#   ./bench.sh --agreement     do the two engines return the same memories
#   ./bench.sh --proofs        the correctness checks, no timing
#
# WHAT IT TOUCHES
#   A throwaway tree under ${TMPDIR:-/tmp}, removed on exit. It builds its own
#   memory store, its own copy of bin/eve and its own hooks. It never reads,
#   writes or times anything in your real $EVE_HOME, and it never modifies the
#   repository -- including bin/eve, which it patches only in the copy.
#
# DEPENDENCIES
#   sh, awk, sqlite3, and python3 for a millisecond clock. Stock macOS `date`
#   has no %N, so there is no portable sub-second timer in the shell. The engine
#   itself needs none of this.

set -u

REPO=$(cd "$(dirname "$0")/../.." 2>/dev/null && pwd) || REPO=''
[ -n "$REPO" ] || { printf 'cannot locate the repository root\n' >&2; exit 1; }
ENGINE="$REPO/engines/sqlite/eve-engine-sqlite"

[ -x "$ENGINE" ] || { printf 'not executable: %s\n' "$ENGINE" >&2; exit 1; }
[ -f "$REPO/bin/eve" ] || { printf 'no bin/eve under %s\n' "$REPO" >&2; exit 1; }

command -v sqlite3 >/dev/null 2>&1 || {
	printf 'no sqlite3 in PATH -- there is nothing to benchmark\n' >&2
	exit 1
}

WORK=$(mktemp -d "${TMPDIR:-/tmp}/eve-bench.XXXXXX") || exit 1
cleanup() { [ -n "${WORK:-}" ] && rm -rf "$WORK"; }
trap cleanup EXIT HUP INT TERM

now_ms() {
	python3 -c 'import time;print(int(time.time()*1000))' 2>/dev/null || printf '0'
}

if [ "$(now_ms)" = "0" ]; then
	printf 'no python3 for a millisecond clock; timing rows will be skipped\n' >&2
	HAVE_CLOCK=0
else
	HAVE_CLOCK=1
fi

# One prompt, in the shape the harness delivers it.
PROMPT='{"prompt":"how does harborlight handle queue backpressure and retries","session_id":"bench"}'

# ---------------------------------------------------------------------------
# a synthetic store
# ---------------------------------------------------------------------------
#
# Fictional systems, fictional topics, deterministic from a seed so two runs
# measure the same store. Shaped like a real memory: frontmatter, a one-sentence
# claim, a "why" paragraph, a handful of bullets. At 2,000 files it comes to
# 7.8 MB, which is the store the default engine's published numbers were
# measured on.

mk_store() { # DIR N
	mkdir -p "$1" || return 1
	awk -v dir="$1" -v n="$2" '
    function rnd() { seed = (seed * 1103515245 + 12345) % 2147483648; return seed / 2147483648 }
    function w() { return word[int(rnd() * nw) + 1] }
    BEGIN {
      seed = 20260814
      ns = split("harborlight tidewater kestrel brightpath northgate alloy sablewood meridian quarry lattice foxglove ironvale pennant driftwood calyx", sys, " ")
      nt = split("ingest retries deploys schema-migrations rate-limits auth-tokens caching queue-backpressure idempotency timeouts feature-flags observability rollback secrets-rotation pagination webhooks batch-jobs cold-starts connection-pools clock-skew", top, " ")
      nv = split("is must never always runs fails returns requires blocks replaces", vb, " ")
      nk = split("feedback project decision reference note", kind, " ")
      nw = split("service worker queue consumer manifest shipment retry backoff jitter deadline budget token refresh window quota throttle partition replica primary follower snapshot checkpoint cursor offset schema column migration rollback deploy release canary flag rollout metric latency percentile alert page dashboard trace span log line cache invalidate stale warm cold start pool connection socket timeout header status code payload envelope signature secret rotate expire clock skew drift sequence", word, " ")
      for (i = 0; i < n; i++) {
        s = sys[(i % ns) + 1]
        t = top[(int(i / ns) % nt) + 1]
        k = kind[(i % nk) + 1]
        id = sprintf("%s-%s-%04d", s, t, i)
        f = dir "/" id ".md"
        t2 = t; gsub(/-/, " ", t2)
        cap = toupper(substr(s, 1, 1)) substr(s, 2)
        title = cap " " t2 " " vb[(i % nv) + 1] " under load"
        printf "---\nid: %s\ntitle: %s\ntype: %s\n", id, title, k > f
        printf "status: %s\n", (i % 37 == 0 ? "superseded" : "current") > f
        printf "tags: [%s, %s, %s]\n", s, t, w() > f
        printf "source: internal design note, 2026-0%d-1%d\n", 1 + i % 9, i % 10 > f
        printf "created: 2026-0%d-0%d\nupdated: 2026-0%d-1%d\n", 1 + i % 9, 1 + i % 9, 1 + i % 9, i % 10 > f
        printf "verified_on: 2026-0%d-1%d\nconfidence: high\n---\n\n", 1 + i % 9, i % 10 > f
        printf "%s handles %s with one owner, and %s %s %s %s.\n\n", cap, t2, w(), w(), w(), w() > f
        printf "**Why:** " > f
        for (j = 0; j < 90; j++) printf "%s ", w() > f
        printf "\n\n**How to apply:**\n" > f
        for (b = 0; b < 6; b++) {
          printf "- " > f
          for (j = 0; j < 12; j++) printf "%s ", w() > f
          printf "\n" > f
        }
        close(f)
      }
    }
  ' </dev/null
}

# ---------------------------------------------------------------------------
# the queries
# ---------------------------------------------------------------------------
#
# Half hand-written, half DERIVED FROM THE STORE, and the derived half is the
# one that matters. A fixed list of invented questions looked fine and was
# nearly worthless: against synthetic memories, eleven of fifteen returned
# nothing from EITHER engine, and "15/15 agree" was fifteen agreements about
# silence. Two engines that both return nothing agree about nothing.
#
# The derived queries are built from real titles in the store being measured, so
# each has an answer by construction. `verify` prints how many of the queries
# actually returned hits beside the agreement count, so this cannot quietly rot
# again.

HAND_QUERIES="what is our rule about schema migrations
should we deploy tonight or wait until tomorrow
who owns the ingest path
idempotency for webhook delivery
zzsubject that no memory in this store covers"

mk_queries() { # HOME N -> query list on stdout
	ls "$1"/memory/*.md 2>/dev/null |
		awk -v want="$2" '
      { files[++n] = $0 }
      END {
        if (n == 0) exit 0
        step = int(n / want); if (step < 1) step = 1
        for (i = 1; i <= n && k < want; i += step) {
          t = ""; dash = 0
          while ((getline line < files[i]) > 0) {
            if (line ~ /^title:/) { sub(/^title:[ \t]*/, "", line); t = line; break }
            if (line ~ /^---[ \t]*$/ && ++dash == 2) break
          }
          close(files[i])
          if (t == "") continue
          k++
          # Vary the framing, so the stopword list and the stemmer are actually
          # exercised instead of the title being handed straight back.
          if (k % 3 == 0)      print "what should I know about " t
          else if (k % 3 == 1) print "how does " t " actually work in practice"
          else                 print "remind me what we decided about " t
        }
      }
    '
	printf '%s\n' "$HAND_QUERIES"
}

# ---------------------------------------------------------------------------
# a throwaway EVE_HOME, with bin/eve patched exactly as docs/13-engines.md says
# ---------------------------------------------------------------------------
#
# The patch is applied to a COPY. Nothing in the repository is modified. If the
# insertion stops matching -- because bin/eve moved on -- this fails loudly
# rather than quietly measuring the unpatched default engine twice and reporting
# that the two engines perform identically.

patch_eve() { # SRC DST
	awk -v q="'" '
    { print }
    /^cmd_search\(\) \{$/ && !ds {
      ds = 1
      print "\t# --- optional engines (docs/13-engines.md) --------------------------"
      print "\t# EVE_ENGINE names one. Anything unknown, anything not installed, and"
      print "\t# any engine that already gave up (_EVE_ENGINE_FALLBACK) uses the"
      print "\t# default path below. `exec`, so there is no extra process."
      print "\tif [ \"${EVE_ENGINE:-awk}\" != awk ] && [ \"${_EVE_ENGINE_FALLBACK:-0}\" != 1 ]; then"
      print "\t\t_eng=\"$EVE_HOME/engines/eve-engine-${EVE_ENGINE}\""
      print "\t\t[ -x \"$_eng\" ] && exec \"$_eng\" search \"$@\""
      print "\tfi"
    }
    /^cmd_index\(\) \{$/ && !di {
      di = 1
      print "\t# `eve index --engine NAME` rebuilds that engine index, not INDEX.md."
      print "\tcase \"${1:-}\" in"
      print "\t--engine)"
      print "\t\t[ $# -ge 2 ] || die \"index: --engine needs a value\" 64"
      print "\t\t_eng=\"$EVE_HOME/engines/eve-engine-$2\"; shift 2"
      print "\t\t[ -x \"$_eng\" ] || die \"no engine at $_eng\" 69"
      print "\t\texec \"$_eng\" index \"$@\""
      print "\t\t;;"
      print "\t--engine=*)"
      print "\t\t_eng=\"$EVE_HOME/engines/eve-engine-${1#--engine=}\"; shift"
      print "\t\t[ -x \"$_eng\" ] || die \"no engine at $_eng\" 69"
      print "\t\texec \"$_eng\" index \"$@\""
      print "\t\t;;"
      print "\tesac"
    }
    /^\t_d_disable=0$/ && !dc1 { dc1 = 1; print "\t_d_engine=awk" }
    /^\t_f_disable=..$/ && !dc2 { dc2 = 1; print "\t_f_engine=" q q }
    /EVE_DISABLE\) _f_disable=\$_v ;;$/ && !dc3 { dc3 = 1; print "\t\t\tEVE_ENGINE) _f_engine=$_v ;;" }
    /^\tEVE_DISABLE=\$_r$/ && !dc4 {
      dc4 = 1
      print "\tresolve \"${EVE_ENGINE+x}\" \"${EVE_ENGINE:-}\" \"$_f_engine\" \"$_d_engine\""
      print "\tEVE_ENGINE=$_r"
    }
    END {
      miss = ""
      if (!ds)  miss = miss " cmd_search"
      if (!di)  miss = miss " cmd_index"
      if (!dc1) miss = miss " _d_disable"
      if (!dc2) miss = miss " _f_disable"
      if (!dc3) miss = miss " EVE_DISABLE-case"
      if (!dc4) miss = miss " EVE_DISABLE-resolve"
      if (miss != "") {
        print "bench.sh: the documented patch no longer matches bin/eve; missing anchors:" miss > "/dev/stderr"
        exit 1
      }
    }
  ' "$1" >"$2" || return 1
	chmod +x "$2"
	sh -n "$2" || return 1
	return 0
}

set_engine() { # HOME NAME
	printf 'EVE_DISABLE=0\nEVE_RECALL_LIMIT=3\nEVE_ENGINE=%s\n' "$2" >"$1/config"
}

mk_home() { # DIR N
	_h=$1
	mkdir -p "$_h/bin" "$_h/hooks/lib" "$_h/state" "$_h/sessions" "$_h/engines" || return 1
	mk_store "$_h/memory" "$2" || return 1
	patch_eve "$REPO/bin/eve" "$_h/bin/eve" || return 1
	cp "$REPO/hooks/eve-recall.sh" "$_h/hooks/" || return 1
	cp "$REPO/hooks/lib/common.sh" "$_h/hooks/lib/" || return 1
	cp "$ENGINE" "$_h/engines/eve-engine-sqlite" || return 1
	chmod +x "$_h/hooks/eve-recall.sh" "$_h/engines/eve-engine-sqlite"
	set_engine "$_h" awk
	return 0
}

# One prompt through the real UserPromptSubmit hook: process startup, JSON
# parse, retrieval, dedupe bookkeeping. Nothing is stubbed out.
#
# ONE session_id for every iteration, which is the shape of the measurement in
# docs/03-hooks.md and, more to the point, the shape of a real session. It
# matters more than it looks: with a fresh id each time there is no seen-file, so
# the hook never runs its cross-turn dedupe and never calls eve_store_count --
# and on a large store that difference alone was 70 ms a prompt in an early
# version of this script. Measuring the path users are not on is the classic way
# to publish a number nobody can reproduce.
#
# The first runs are discarded so a cold page cache is not charged to whichever
# engine happened to go first.
hook_ms() { # HOME ITER
	_h=$1; _it=$2
	EVE_HOME=$_h; export EVE_HOME
	_i=0
	while [ "$_i" -lt 3 ]; do
		printf '%s' "$PROMPT" | "$_h/hooks/eve-recall.sh" >/dev/null 2>&1
		_i=$((_i + 1))
	done
	_t0=$(now_ms)
	_i=0
	while [ "$_i" -lt "$_it" ]; do
		printf '%s' "$PROMPT" | "$_h/hooks/eve-recall.sh" >/dev/null 2>&1
		_i=$((_i + 1))
	done
	_t1=$(now_ms)
	awk -v a="$_t0" -v b="$_t1" -v n="$_it" 'BEGIN { printf "%.0f", (b - a) / n }'
}

ms_since() { awk -v a="$1" -v b="$2" 'BEGIN { printf "%.0f", b - a }'; }

report_delta() { # T0 T1 STEADY LABEL
	_v=$(awk -v a="$1" -v b="$2" -v s="$3" 'BEGIN { printf "%.0f %+.0f", (b - a) / 10, (b - a) / 10 - s }')
	printf '%-44s %5s ms  (%s)\n' "$4" "${_v% *}" "${_v#* }"
}

# ---------------------------------------------------------------------------
# latency
# ---------------------------------------------------------------------------

run_sizes() {
	printf '\n== latency, through the real UserPromptSubmit hook ==\n'
	printf '%6s  %10s  %10s  %10s  %10s  %9s\n' \
		size grep-ms sqlite-ms build-ms index store
	for n in "$@"; do
		H="$WORK/h$n"
		mk_home "$H" "$n" || exit 1

		set_engine "$H" awk
		G=$(hook_ms "$H" 10)

		EVE_HOME=$H; export EVE_HOME
		B0=$(now_ms)
		"$H/bin/eve" index --engine sqlite >/dev/null 2>&1 || exit 1
		B1=$(now_ms)
		BUILD=$(ms_since "$B0" "$B1")
		ISIZE=$(du -h "$H/state/eve-fts.db" 2>/dev/null | cut -f1 | tr -d ' ')
		SSIZE=$(du -sh "$H/memory" 2>/dev/null | cut -f1 | tr -d ' ')

		set_engine "$H" sqlite
		S=$(hook_ms "$H" 10)

		printf '%6s  %10s  %10s  %10s  %10s  %9s\n' "$n" "$G" "$S" "$BUILD" "$ISIZE" "$SSIZE"
		rm -rf "$H"
	done
}

# ---------------------------------------------------------------------------
# what the index costs to keep honest
# ---------------------------------------------------------------------------
#
# The steady-state row is the easy number to publish and the least interesting
# one. An index is only worth having if the query AFTER you change something is
# still fast, because that is the query you make right after writing a memory --
# and "fast until you use it" is how a benchmark lies.
#
# Each row mutates the store and then measures one full hook run, ten times. The
# mutation is inside the timed region: a shell builtin for the edit and add
# rows, one `rm` for the delete row.

run_maint() { # N
	n=${1:-2000}
	H="$WORK/m$n"
	mk_home "$H" "$n" || exit 1
	EVE_HOME=$H; export EVE_HOME
	set_engine "$H" sqlite
	"$H/bin/eve" index --engine sqlite >/dev/null 2>&1 || exit 1

	printf '\n== index maintenance on the prompt path, %s memories ==\n' "$n"

	_i=0
	while [ "$_i" -lt 3 ]; do
		printf '%s' "$PROMPT" | "$H/hooks/eve-recall.sh" >/dev/null 2>&1
		_i=$((_i + 1))
	done

	_t0=$(now_ms); _i=0
	while [ "$_i" -lt 10 ]; do
		printf '%s' "$PROMPT" | "$H/hooks/eve-recall.sh" >/dev/null 2>&1
		_i=$((_i + 1))
	done
	_t1=$(now_ms)
	STEADY=$(awk -v a="$_t0" -v b="$_t1" 'BEGIN { printf "%.0f", (b - a) / 10 }')
	printf '%-44s %5s ms\n' "steady state, nothing changed" "$STEADY"

	_t0=$(now_ms); _i=0
	while [ "$_i" -lt 10 ]; do
		printf '\nedit %s\n' "$_i" >>"$(ls "$H/memory"/tidewater-*.md | head -$((_i + 1)) | tail -1)"
		printf '%s' "$PROMPT" | "$H/hooks/eve-recall.sh" >/dev/null 2>&1
		_i=$((_i + 1))
	done
	_t1=$(now_ms)
	report_delta "$_t0" "$_t1" "$STEADY" "first query after one memory edited"

	_t0=$(now_ms); _i=0
	while [ "$_i" -lt 10 ]; do
		printf -- '---\nid: zzadd%s\ntitle: added %s\ntype: note\n---\n\nA new claim.\n' "$_i" "$_i" >"$H/memory/zzadd$_i.md"
		printf '%s' "$PROMPT" | "$H/hooks/eve-recall.sh" >/dev/null 2>&1
		_i=$((_i + 1))
	done
	_t1=$(now_ms)
	report_delta "$_t0" "$_t1" "$STEADY" "first query after one memory added"

	_t0=$(now_ms); _i=0
	while [ "$_i" -lt 10 ]; do
		rm -f "$H/memory/zzadd$_i.md"
		printf '%s' "$PROMPT" | "$H/hooks/eve-recall.sh" >/dev/null 2>&1
		_i=$((_i + 1))
	done
	_t1=$(now_ms)
	report_delta "$_t0" "$_t1" "$STEADY" "first query after one memory deleted"

	printf '%-44s %5s\n' "index size" "$(du -h "$H/state/eve-fts.db" 2>/dev/null | cut -f1 | tr -d ' ')"
	printf '%-44s %5s\n' "rows indexed" "$(sqlite3 "$H/state/eve-fts.db" 'SELECT count(*) FROM docs;' 2>/dev/null)"
	rm -rf "$H"
}

# ---------------------------------------------------------------------------
# agreement
# ---------------------------------------------------------------------------
#
# Agreement is not one number, it is a curve. The two engines choose candidates
# differently -- the default one greps for a token as a SUBSTRING of the raw
# file, this one matches it as a word PREFIX in the index -- and that can only
# show up once a store is big enough for the 300-candidate cap to bind. Report
# the size at which they part company, rather than a flat claim of equivalence.

run_agreement() {
	printf '\n== agreement with the default engine, by store size ==\n'
	printf '%6s  %s\n' size result
	for n in "$@"; do
		H="$WORK/a$n"
		mk_home "$H" "$n" || exit 1
		EVE_HOME=$H; export EVE_HOME
		set_engine "$H" sqlite
		"$H/bin/eve" index --engine sqlite >/dev/null 2>&1 || exit 1
		r=$(mk_queries "$H" 12 | "$H/engines/eve-engine-sqlite" verify | tail -1)
		printf '%6s  %s\n' "$n" "$r"
		rm -rf "$H"
	done
}

# ---------------------------------------------------------------------------
# the correctness proofs
# ---------------------------------------------------------------------------

proofs() {
	H="$WORK/proof"
	mk_home "$H" 400 || exit 1
	EVE_HOME=$H; export EVE_HOME
	set_engine "$H" sqlite
	"$H/bin/eve" index --engine sqlite >/dev/null 2>&1 || exit 1

	printf '\n== 0. scorer parity, line by line ==\n'
	# The strongest form of this check and the cheapest. `verify` asks whether
	# the two engines AGREE on some queries; this asks whether they are
	# computing the same thing at all. Every line that does scoring arithmetic
	# is pulled out of both files, comments and indentation dropped, and the two
	# sequences compared. A dozen queries can miss a changed constant. A diff
	# cannot -- and bin/eve's scorer changed three times under this engine
	# during development, which is how the check earned its place at number 0.
	cat >"$WORK/scorer-lines.awk" <<'AWKEOF'
/^[ \t]*#/ { next }
/w\[t\] *=/ || /if \(hit_(title|id|tag|body)\[/ ||
/sc \+= best/ || /sc = sc \*/ || /sc = int/ || /if \(hits == 0\)/ ||
/if \(best == 0\)/ || /if \(nfld > 1\)/ || /if \(sc <= 0\)/ ||
/if \(norm\(out\)/ || /if \(length\(out\)/ {
  gsub(/^[ \t]+|[ \t]+$/, "")
  gsub(/[ \t]+/, " ")
  print
}
AWKEOF
	awk -f "$WORK/scorer-lines.awk" "$REPO/bin/eve" >"$WORK/sc-eve.txt"
	awk -f "$WORK/scorer-lines.awk" "$ENGINE" >"$WORK/sc-sqlite.txt"
	if cmp -s "$WORK/sc-eve.txt" "$WORK/sc-sqlite.txt"; then
		printf 'identical: %s scoring lines\n' "$(wc -l <"$WORK/sc-eve.txt" | tr -d ' ')"
	else
		printf 'DIFFER -- the engine scores by a formula bin/eve has moved on from:\n'
		diff "$WORK/sc-eve.txt" "$WORK/sc-sqlite.txt" | head -30
	fi

	printf '\n== 1. tokeniser parity ==\n'
	# The reference is extracted from bin/eve at run time rather than copied
	# here: a third transcription would be a third thing to keep in step, and
	# this check exists precisely because copies drift.
	sed -n '/^STOPWORDS=/,/^}$/p' "$REPO/bin/eve" >"$WORK/tok-eve.sh"
	sed -n '/^STOPWORDS=/,/^}$/p' "$ENGINE" >"$WORK/tok-sqlite.sh"
	_bad=0
	_n=0
	while IFS= read -r q; do
		[ -n "$q" ] || continue
		_n=$((_n + 1))
		a=$(sh -c '. "$1"; tokenise "$2"' _ "$WORK/tok-eve.sh" "$q" 2>/dev/null)
		b=$(sh -c '. "$1"; tokenise "$2"' _ "$WORK/tok-sqlite.sh" "$q" 2>/dev/null)
		if [ "$a" != "$b" ]; then
			_bad=$((_bad + 1))
			printf 'TOKENS DIFFER for: %s\n  eve:    %s\n  sqlite: %s\n' \
				"$q" "$(printf '%s' "$a" | tr '\n' ' ')" "$(printf '%s' "$b" | tr '\n' ' ')"
		fi
	done <<TOKEOF
$(mk_queries "$H" 12)
TOKEOF
	printf 'tokenisers agree on %s of %s queries\n' "$((_n - _bad))" "$_n"

	printf '\n== 2. agreement with the default engine ==\n'
	mk_queries "$H" 12 | "$H/engines/eve-engine-sqlite" verify

	printf '\n== 3. the staleness guard ==\n'
	# Delete a memory behind the index. The row is still in the index; the only
	# question is whether it can reach the output.
	VICTIM=$("$H/engines/eve-engine-sqlite" search --query "harborlight queue backpressure" --format tsv |
		head -1 | cut -f7)
	if [ -z "$VICTIM" ] || [ ! -f "$VICTIM" ]; then
		printf 'SKIP: no hit to delete\n'
	else
		printf 'top hit:        %s\n' "${VICTIM##*/}"
		printf 'still indexed:  %s row(s)\n' \
			"$(sqlite3 "$H/state/eve-fts.db" "SELECT count(*) FROM docs WHERE path='$VICTIM';")"
		rm -f "$VICTIM"
		OUT=$("$H/engines/eve-engine-sqlite" search --query "harborlight queue backpressure" --format hook)
		if printf '%s' "$OUT" | grep -Fq "${VICTIM##*/}"; then
			printf 'after rm:       RETURNED IT ANYWAY -- FAIL\n'
		else
			printf 'after rm:       not returned  OK\n'
		fi
		printf 'index rows now: %s\n' \
			"$(sqlite3 "$H/state/eve-fts.db" "SELECT count(*) FROM docs WHERE path='$VICTIM';")"
	fi

	printf '\n== 4. an edit and an addition behind the index ==\n'
	# --all, so the relevance gate does not hide the answer: the question here
	# is "did the index notice", not "is one body term worth seven points".
	TARGET=$(ls "$H/memory"/kestrel-*.md 2>/dev/null | head -1)
	if [ -n "$TARGET" ]; then
		printf '\nzzedittoken appears here now.\n' >>"$TARGET"
		A=$("$H/engines/eve-engine-sqlite" search --query "zzedittoken" --all --format tsv | cut -f2 | tr '\n' ' ')
		B=$(EVE_ENGINE=awk _EVE_ENGINE_FALLBACK=1 "$H/bin/eve" search --query "zzedittoken" --all --format tsv | cut -f2 | tr '\n' ' ')
		printf 'edited %s\n  sqlite: %s\n  grep:   %s\n' "${TARGET##*/}" "${A:-(nothing)}" "${B:-(nothing)}"
		if [ "$A" = "$B" ] && [ -n "$A" ]; then printf '  agree   OK\n'; else printf '  FAIL\n'; fi
	fi
	NEWF="$H/memory/zznew-memory-written-behind-the-index.md"
	printf -- '---\nid: zznew-memory-written-behind-the-index\ntitle: A zzaddtoken claim written after the index was built\ntype: note\nstatus: current\n---\n\nThe zzaddtoken claim.\n' >"$NEWF"
	A=$("$H/engines/eve-engine-sqlite" search --query "zzaddtoken claim" --format tsv | cut -f2 | tr '\n' ' ')
	B=$(EVE_ENGINE=awk _EVE_ENGINE_FALLBACK=1 "$H/bin/eve" search --query "zzaddtoken claim" --format tsv | cut -f2 | tr '\n' ' ')
	printf 'added  %s\n  sqlite: %s\n  grep:   %s\n' "${NEWF##*/}" "${A:-(nothing)}" "${B:-(nothing)}"
	if [ "$A" = "$B" ] && [ -n "$A" ]; then printf '  agree   OK\n'; else printf '  FAIL\n'; fi
	rm -rf "$H"

	printf '\n== 5. the index stays bounded under churn ==\n'
	# 60 edits with the compaction threshold pulled down to 20, so the loop
	# crosses it three times. The claim under test is that a long-lived index
	# does not creep upward forever. The numbers are bytes.
	HB="$WORK/bound"
	mk_home "$HB" 1000 || exit 1
	EVE_HOME=$HB; export EVE_HOME
	printf 'EVE_DISABLE=0\nEVE_ENGINE=sqlite\nEVE_SQLITE_COMPACT_EVERY=20\n' >"$HB/config"
	"$HB/bin/eve" index --engine sqlite >/dev/null 2>&1 || exit 1
	printf 'fresh build:      %s bytes\n' "$(wc -c <"$HB/state/eve-fts.db" | tr -d ' ')"
	_i=0
	while [ "$_i" -lt 60 ]; do
		printf '\nchurn %s\n' "$_i" >>"$(ls "$HB/memory"/tidewater-*.md | head -$((_i % 60 + 1)) | tail -1)"
		printf '%s' "$PROMPT" | "$HB/hooks/eve-recall.sh" >/dev/null 2>&1
		_i=$((_i + 1))
	done
	printf 'after 60 edits:   %s bytes\n' "$(wc -c <"$HB/state/eve-fts.db" | tr -d ' ')"
	printf 'and it still agrees: '
	mk_queries "$HB" 12 | "$HB/engines/eve-engine-sqlite" verify | tail -1
	rm -rf "$HB"

	# Proofs 6 to 8 run on a FRESH store. The checks above deliberately mutate
	# the one they share -- a memory deleted, two edited, one added -- and a
	# fallback test whose reference query has been quietly starved by an earlier
	# step proves nothing.
	HF="$WORK/fb"
	mk_home "$HF" 200 || exit 1
	EVE_HOME=$HF; export EVE_HOME
	set_engine "$HF" sqlite
	"$HF/bin/eve" index --engine sqlite >/dev/null 2>&1 || exit 1

	# Pick a reference query the DEFAULT engine actually answers, rather than
	# naming one and hoping. A fallback test whose reference returns nothing
	# passes by comparing one silence to another, which is exactly what a broken
	# fallback would also produce.
	FQ=''
	REF=''
	while IFS= read -r q; do
		[ -n "$q" ] || continue
		r=$(EVE_ENGINE=awk _EVE_ENGINE_FALLBACK=1 "$HF/bin/eve" search --query "$q" --format hook 2>&1)
		if [ -n "$r" ]; then FQ=$q; REF=$r; break; fi
	done <<FQEOF
$(mk_queries "$HF" 12)
FQEOF
	printf '\nreference query: %s\n' "${FQ:-NONE FOUND}"
	[ -n "$REF" ] || printf 'INCONCLUSIVE: the default engine answers none of the queries\n'

	printf '\n== 6. fallback with no sqlite3 in PATH ==\n'
	# A PATH that is the real one MINUS sqlite3. Hand-listing the commands the
	# default engine needs was the first attempt and it tested the wrong thing:
	# bin/eve grew a `tee`, the list did not, and the "fallback" that failed was
	# the harness. Mirror everything, remove one binary, change one variable.
	FAKEBIN="$WORK/nosqlite"
	rm -rf "$FAKEBIN"
	mkdir -p "$FAKEBIN"
	_ifs=$IFS
	IFS=:
	for d in $PATH; do
		[ -d "$d" ] || continue
		for f in "$d"/*; do
			[ -f "$f" ] && [ -x "$f" ] || continue
			b=${f##*/}
			[ "$b" = sqlite3 ] && continue
			[ -e "$FAKEBIN/$b" ] || ln -s "$f" "$FAKEBIN/$b" 2>/dev/null
		done
	done
	IFS=$_ifs
	OUT=$(PATH="$FAKEBIN" EVE_HOME="$HF" "$HF/bin/eve" search --query "$FQ" --format hook 2>&1)
	printf 'sqlite3 present: %s\n' "$(PATH="$FAKEBIN" command -v sqlite3 2>/dev/null || printf 'no')"
	if [ "$OUT" = "$REF" ] && [ -n "$REF" ]; then
		printf 'output identical to the default engine, %s hit(s)  OK\n' \
			"$(printf '%s' "$OUT" | grep -c '^- ')"
	else
		printf 'FAIL: fallback output differs\n---got---\n%s\n---want---\n%s\n' "$OUT" "$REF"
	fi

	printf '\n== 7. eve itself changing disarms the engine ==\n'
	# The scorer in the engine is a transcription of the one in bin/eve. If
	# bin/eve changes, the copy may no longer agree -- so the engine is expected
	# to stop trusting itself and hand the query back, rather than keep ranking
	# by a formula that has moved on.
	printf '\n# touched by the drift test\n' >>"$HF/bin/eve"
	OUT=$(EVE_HOME="$HF" "$HF/bin/eve" search --query "$FQ" --format hook 2>&1)
	if [ "$OUT" = "$REF" ] && [ -n "$REF" ]; then
		printf 'fell back to the default engine  OK\n'
	else
		printf 'FAIL: still served from the index after eve changed\n'
	fi
	printf 'and re-arms after a rebuild: '
	EVE_HOME="$HF" "$HF/bin/eve" index --engine sqlite >/dev/null 2>&1
	printf '%s\n' "$FQ" | "$HF/engines/eve-engine-sqlite" verify

	printf '\n== 8. a corrupt index falls back too ==\n'
	printf 'this is not a database' >"$HF/state/eve-fts.db"
	OUT=$(EVE_HOME="$HF" "$HF/bin/eve" search --query "$FQ" --format hook 2>&1)
	if [ "$OUT" = "$REF" ] && [ -n "$REF" ]; then
		printf 'output identical to the default engine  OK\n'
	else
		printf 'FAIL: corrupt index did not fall back cleanly\n%s\n' "$OUT"
	fi
	rm -rf "$HF"
}

# ---------------------------------------------------------------------------

case "${1:-}" in
--proofs) proofs ;;
--maintenance)
	shift
	[ "$HAVE_CLOCK" = 1 ] && run_maint "${1:-2000}"
	;;
--agreement)
	shift
	[ $# -gt 0 ] || set -- 50 200 400 700 1000 2000
	run_agreement "$@"
	;;
'')
	if [ "$HAVE_CLOCK" = 1 ]; then
		run_sizes 10 50 200 500 1000 2000
		run_maint 2000
	fi
	run_agreement 50 200 400 700 1000 2000
	proofs
	;;
*) [ "$HAVE_CLOCK" = 1 ] && run_sizes "$@" ;;
esac
printf '\n'
