#!/usr/bin/env node
/*
 * eve-recall -- the npm delivery shim for Eve.
 *
 * WHAT THIS IS
 *   Twelve lines of dispatch around the shell scripts that are the actual
 *   product. npm is a delivery channel here, not a runtime: nothing Eve does
 *   at recall time is JavaScript. After `init`, the code that runs on every
 *   prompt is `sh` and `awk` under ~/.eve, and this file is never invoked
 *   again. You can delete node and Eve keeps working.
 *
 * WHAT IT DELIBERATELY DOES NOT DO
 *   There is no `postinstall` script in package.json. Installing this package
 *   writes files into node_modules and nothing else -- it does not create
 *   ~/.eve, does not touch ~/.claude/settings.json, and does not edit your
 *   CLAUDE.md. A package manager that rewrites your editor's config because
 *   you typed `npm i` is a package manager you stop trusting. Every write
 *   outside node_modules happens because you named a subcommand:
 *
 *     init            create ~/.eve and install Eve's scripts there.
 *                     Touches nothing under ~/.claude.
 *     install-hooks   the explicit opt-in: merge Eve's three hook entries
 *                     into ~/.claude/settings.json and the rule block into
 *                     CLAUDE.md. This is the only command that edits Claude
 *                     Code's configuration.
 *     uninstall       remove that wiring again. Never deletes a memory.
 *
 *   Anything else is handed to the `eve` CLI unchanged.
 *
 * WHICH COPY OF `eve` RUNS
 *   $EVE_HOME/bin/eve when it exists, and only otherwise the copy inside this
 *   package. That ordering is deliberate: the hooks call $EVE_HOME/bin/eve, so
 *   pinning the terminal to the same binary means what you see when you run
 *   `search` by hand is produced by the code that actually runs on your
 *   prompts. Two copies of a scorer is how you spend an afternoon debugging
 *   the one that is not running (docs/05-design-laws.md, law 7).
 */

'use strict';

var path = require('path');
var fs = require('fs');
var spawnSync = require('child_process').spawnSync;

var ROOT = path.resolve(__dirname, '..');
var EVE_HOME = process.env.EVE_HOME || path.join(os_home(), '.eve');

function os_home() {
	return require('os').homedir() || process.env.HOME || '.';
}

function die(msg, code) {
	process.stderr.write('eve-recall: ' + msg + '\n');
	process.exit(code === undefined ? 1 : code);
}

/*
 * Always `sh <script>`, never `<script>` directly.
 *
 * npm does preserve the executable bit through a tarball, but it is one
 * `umask`, one zip round-trip or one Windows-hosted CI job away from not
 * doing so, and the failure mode is EACCES on someone else's machine where
 * you cannot see it. Invoking the interpreter explicitly makes the mode bit
 * irrelevant.
 */
function run(script, args) {
	var full = path.join(ROOT, script);
	if (!fs.existsSync(full)) {
		die('missing from this install: ' + script + '\n' +
			'  the package looks incomplete; reinstall, or clone the repo:\n' +
			'  https://github.com/Steve-CortesPineda/eve', 69);
	}
	var r = spawnSync('sh', [full].concat(args || []), {
		stdio: 'inherit',
		cwd: ROOT,
		env: process.env
	});
	if (r.error) die('cannot run sh: ' + r.error.message, 69);
	// A shell killed by a signal has no exit code. Report it the way a shell
	// does rather than silently exiting 0.
	if (r.status === null) process.exit(r.signal ? 129 : 1);
	return r.status;
}

function sh(script, args) {
	process.exit(run(script, args));
}

/* The eve CLI: the installed copy wins over the packaged one. See the header. */
function eve(args) {
	var installed = path.join(EVE_HOME, 'bin', 'eve');
	var script = fs.existsSync(installed) ? installed : path.join(ROOT, 'bin', 'eve');
	if (!fs.existsSync(script)) {
		die('no eve CLI found at ' + installed + ' or in this package.\n' +
			'  run:  npx eve-recall init', 69);
	}
	var r = spawnSync('sh', [script].concat(args || []), {
		stdio: 'inherit',
		env: process.env
	});
	if (r.error) die('cannot run sh: ' + r.error.message, 69);
	if (r.status === null) process.exit(r.signal ? 129 : 1);
	process.exit(r.status);
}

function usage() {
	process.stdout.write([
		'eve-recall -- npm delivery for Eve (POSIX sh; node is not a runtime dependency)',
		'',
		'Setup',
		'  npx eve-recall init [--eve-home PATH]',
		'        Install Eve into ' + tilde(EVE_HOME) + '. Creates the store and the',
		'        scripts. Does NOT touch ~/.claude/settings.json or CLAUDE.md.',
		'',
		'  npx eve-recall install-hooks',
		'        The opt-in step. Merges Eve\'s three hook entries into',
		'        ~/.claude/settings.json and the rule block into CLAUDE.md.',
		'        Idempotent, backs the file up first, and prints the JSON for you',
		'        to paste instead if it cannot merge safely.',
		'',
		'  npx eve-recall print-hooks',
		'        Print that JSON block and exit. Writes nothing.',
		'',
		'  npx eve-recall uninstall',
		'        Remove the wiring. Never deletes a memory.',
		'',
		'Everyday use (passed through to the eve CLI)',
		'  npx eve-recall add "the claim, as a sentence"',
		'  npx eve-recall search --query "..."',
		'  npx eve-recall index | list | gaps | on | off | doctor | version',
		'',
		'After init the CLI is at ' + tilde(path.join(EVE_HOME, 'bin', 'eve')) + '.',
		'Put it on your PATH and drop the npx prefix.',
		'',
		'Environment',
		'  EVE_HOME             default ~/.eve',
		'  CLAUDE_CONFIG_DIR    default ~/.claude',
		''
	].join('\n'));
}

/*
 * Where `init` will actually land, given that --eve-home on the command line
 * beats $EVE_HOME. Only used to probe the result afterwards, so a miss costs
 * a spurious non-zero exit rather than a wrong install.
 */
function eveHomeFrom(args) {
	for (var i = 0; i < args.length; i++) {
		if (args[i] === '--eve-home' && i + 1 < args.length) return args[i + 1];
		if (args[i].indexOf('--eve-home=') === 0) return args[i].slice('--eve-home='.length);
	}
	return EVE_HOME;
}

function tilde(p) {
	var h = os_home();
	return p.indexOf(h + path.sep) === 0 ? '~' + p.slice(h.length) : p;
}

var argv = process.argv.slice(2);
var cmd = argv.shift();

if (process.platform === 'win32') {
	die('Eve is POSIX shell and awk; it does not run on native Windows.\n' +
		'  Use WSL, where it runs unchanged, and install from inside the WSL shell.', 65);
}

switch (cmd) {
	case 'init': {
		/*
		 * Files only. --no-hooks and --no-claude-md are what make `init`
		 * honest: after this command, nothing about how Claude Code behaves
		 * has changed, and everything Eve wrote is under one directory you
		 * can delete with one `rm -rf`.
		 */
		var home = eveHomeFrom(argv);
		var st = run('install.sh', ['--yes', '--no-hooks', '--no-claude-md'].concat(argv));

		/*
		 * install.sh ends by running the doctor and exits with the doctor's
		 * status. The doctor reports the absent hook registration as a FAIL --
		 * which is right in general and wrong here, because `init` is the
		 * command that deliberately does not write it. Propagated as-is, a
		 * successful install exits 1 and `npx eve-recall init && ...` breaks.
		 *
		 * So do not take the doctor's word for it in either direction: check
		 * the postcondition this command is actually responsible for -- an
		 * `eve` under EVE_HOME that runs. That is a measurement, not a mask; a
		 * genuine install failure still fails, because the binary will not be
		 * there or will not execute.
		 */
		if (st !== 0) {
			var probe = spawnSync('sh', [path.join(home, 'bin', 'eve'), 'version'], {
				stdio: 'ignore',
				env: process.env
			});
			if (!probe.error && probe.status === 0) st = 0;
		}
		/*
		 * The installer ends by running the doctor, and the doctor -- correctly
		 * -- reports the missing hook registration as a FAIL. After a
		 * deliberate files-only install that reads as "the thing I just ran is
		 * broken", which it is not. The doctor is not wrong and is not this
		 * command's to edit, so say plainly which of its complaints `init` is
		 * supposed to produce. An install that ends on an unexplained FAIL
		 * teaches people to skip the output, and then they skip the real one.
		 */
		process.stderr.write([
			'',
			'--- note from eve-recall init -------------------------------------',
			'Two of the doctor\'s complaints above are expected at this point and',
			'are not failures of the install:',
			'',
			'  "no settings.json" / hooks not registered',
			'      Correct. `init` does not touch Claude Code\'s config. Wire the',
			'      hooks when you want them:   npx eve-recall install-hooks',
			'      Or read the block first:    npx eve-recall print-hooks',
			'',
			'  "memory store is empty" / "cannot probe"',
			'      Correct. The store starts empty on purpose -- seeding it with',
			'      example memories would seed it with fiction. Write one:',
			'          ' + tilde(path.join(EVE_HOME, 'bin', 'eve')) + ' add "your rule, stated as a claim"',
			'      then fill in **Why:** and **How to apply:**, and re-run the',
			'      doctor. The probe can only measure a store that has something',
			'      in it.',
			'-------------------------------------------------------------------',
			''
		].join('\n'));
		process.exit(st);
		break;
	}

	case 'install-hooks':
	case 'hooks':
		sh('install.sh', argv);
		break;

	case 'print-hooks':
		sh('install.sh', ['--print-hooks'].concat(argv));
		break;

	case 'uninstall':
		sh('uninstall.sh', argv);
		break;

	case undefined:
	case '-h':
	case '--help':
	case 'help':
		usage();
		process.exit(0);
		break;

	default:
		eve([cmd].concat(argv));
}
