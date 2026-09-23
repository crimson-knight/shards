# Postinstall without arbitrary execution

Status: design proposal, 2026-08-06
Author: drafted for crimson-knight / AgentC
Follows: `security/checksum-before-scripts` (checksum now verified *before* any
dependency script runs)

## The question

Postinstall scripts are genuinely useful: they build native extensions, compile
a binary, fetch a pinned upstream. We do not want to delete the feature. But
today an installed dependency, including one you never named yourself, runs
arbitrary shell on your machine as you. That is the exact mechanism the 2026
npm worms used.

So: how do you keep the feature and still know that what runs is safe?

## Why the obvious answer does not work

The instinct is an allowlist of commands: the shard declares what it will run,
shards checks that against a list of known-safe programs.

This fails, and it fails in a way that is worth stating plainly, because the
design only gets interesting once you accept it.

**1. Allowlisting an interpreter allowlists everything it can interpret.**
Look at the actual commands in the wild (survey below): `make package`,
`sh scripts/install_llamacpp.sh`, `script/precompile_tasks`, `shards build`.
Every one of these is a pointer to a file that contains arbitrary code. If
`make` is on the allowlist, then so is every Makefile anyone ever ships. An
allowlist of command *names* would have approved all seven real postinstalls
in our corpus while placing exactly zero constraint on their behaviour.

**2. Shell is dynamic, so no static matcher holds.**
`$(printf 'Y3VybCBl' | base64 -d)` is a command name that does not exist until
runtime. The npm worm payloads used this class of obfuscation directly. Any
string-matching gate is a speed bump with a published bypass.

**3. A command that was safe is not a command that is safe.**
The script text is a pointer to files that change. Verifying `make package` in
version 1.2.0 tells you nothing about 1.2.1.

The conclusion is not "give up." It is that **safety is the wrong predicate.**
"Is this command safe?" is undecidable in general and trivially evaded in
practice. Three neighbouring questions are all decidable, and together they
cover the actual threat:

| Property     | Question                                      | Mechanism            |
|--------------|-----------------------------------------------|----------------------|
| **Identity** | Do I know exactly which bytes will run?       | checksum (shipped)   |
| **Consent**  | Did a human knowingly agree to these bytes?   | approval in shard.yml|
| **Authority**| Even if it runs, what can it reach?           | declared capabilities|

Nothing here proves a script is benign. The point is that a malicious script
cannot reach anything it did not declare, cannot change without voiding its
approval, and cannot run at all on a machine where nobody approved it.

## What postinstall is actually used for

Measured 2026-08-06 across every shard cached or installed on this machine:
**146 repositories with a readable `shard.yml`, of which 7 declare a `scripts:`
block (4.8%).** Adding locally-installed shards not in the cache brings the
distinct real-world corpus to the following complete list:

| Shard          | Command                                              | What it actually needs        |
|----------------|------------------------------------------------------|-------------------------------|
| ameba          | `shards build -Dpreview_mt`                          | exec compiler, write own dir  |
| micrate        | `shards build`                                       | exec compiler, write own dir  |
| avram          | `BUILD_WITHOUT_DEVELOPMENT=true script/precompile_tasks` | exec compiler, write own dir, one env var |
| carbon         | `BUILD_WITHOUT_DEVELOPMENT=true script/precompile_tasks` | same                       |
| myhtml         | `cd src/ext && make package`                         | exec cc/make, write own dir   |
| lexbor         | `crystal src/ext/build_ext.cr`                        | exec cc, write own dir, network (fetches lexbor) |
| sam.cr         | `cp examples/sam.template ../../sam.cr`              | **write into the consumer's project root** |
| llamero (ours) | `sh scripts/install_llamacpp.sh --postinstall`        | network, write `$HOME/.llamero`, exec git/cmake/cc |

This distribution is the single most important input to the design:

- **Six of eight need nothing beyond "run a compiler, write inside my own
  directory."** No network. No home directory. No writes outside `lib/<name>`.
- **One (llamero) needs real reach**: network plus a persistent home-directory
  install path, because it fetches and builds a pinned llama.cpp.
- **One (sam.cr) writes into the consumer's project**, which is the case that
  most deserves to be refused by default.

That first bullet is the whole opportunity. If the *default* execution profile
is "compiler in, own directory out, nothing else," then for ~75% of real
postinstalls the entire worm payload class becomes structurally impossible:
reading `~/.ssh`, `~/.aws`, `~/.npmrc`, POSTing to an attacker host, and
writing a launchd/systemd persistence unit are all outside the profile. The
remaining shards have to *say* they want more, in a line you can read in a diff.

Compare npm, where postinstall does genuinely unbounded things across a very
large corpus, so no default profile fits and the ecosystem is stuck at
"all or nothing." Our corpus is small and boring. That is an advantage we can
spend exactly once, now, before it grows.

## Layer 0: make the common case need no script at all

The best fix for a dangerous feature is not needing it. Four of the eight
commands above are "build myself," which is a shell-out to do something shards
already knows how to do. Give it a declarative form:

```yaml
build:
  targets:
    - name: ameba
      main: src/cli.cr
      flags: [-Dpreview_mt]
      env:
        BUILD_WITHOUT_DEVELOPMENT: "true"
```

and for the C-extension cases:

```yaml
extensions:
  - name: myhtml
    dir: src/ext
    make: package          # runs make(1) directly, no shell, cwd pinned, argv fixed
```

No shell, no interpreter, no capability question, no approval prompt. This
converts the majority of the corpus from "arbitrary code execution" to "data."
Everything below is then the escape hatch: rare, loud, and constrained.

## Layer 1: default deny, with hash-bound consent

ashards already has `PostinstallInfo` (`lib/.shards.postinstall`), which hashes
the script text and refuses to re-run it if it changed since the last run. That
is better than upstream, but it has a hole: **on first install there is no
entry, so the script just runs.** First install is precisely the attack, whether
that is CI on a clean checkout, a new machine, or a newly-added transitive
dependency.

Flip the default. No approval record means the script does not run:

```
$ shards install
Installing llamero (0.4.1)
  llamero declares a postinstall script, which has not been approved:

    sh scripts/install_llamacpp.sh --postinstall

  It requests: network (github.com), write ($LLAMERO_HOME, $TMPDIR),
               exec (git, cmake, cc)

  Not running it. To review and approve:
      shards script review llamero      # prints the script and its capabilities
      shards script approve llamero     # records approval in shard.yml
```

The approval binds to a **triple**, and any change to any element voids it:

```yaml
scripts_policy:
  approved:
    llamero:
      script:  sha256:0f3c…   # the command string
      package: sha256:9a71…   # the delivered source tree (we already compute this)
      grants:  [network, write_home, exec_toolchain]
      by:      crimson-knight
      at:      2026-08-06
```

Binding to the *package* checksum, not only the script text, is what defeats
the worm. The attacker who moves a tag leaves the command string untouched and
changes the files it executes. Script-hash-only approval sails straight
through. Package-checksum approval evaporates, and the install stops with an
explanation.

Putting this in `shard.yml` rather than a dotfile is deliberate: approval
becomes a committed, diffable, code-reviewable artifact. "This PR grants
network access to a dependency's install script" should be a visible line in a
review, not a state file in someone's `lib/`.

In `--frozen` (CI) mode, an unapproved script is a hard error, never a prompt.

## Layer 2: capabilities, declared by the author

The author states what the script needs, not what it runs:

```yaml
scripts:
  postinstall:
    run: sh scripts/install_llamacpp.sh --postinstall
    needs:
      network: [github.com]
      write:   ["$LLAMERO_HOME", "$TMPDIR"]
      exec:    [git, cmake, cc, c++]
```

Omitting `needs:` means the default profile: read the world, write only
`lib/<name>` and a private temp dir, exec the Crystal toolchain and a C
compiler, no network, no environment beyond a scrubbed allowlist.

Two properties make this worth more than a comment:

1. **It is the review surface.** A human cannot audit a Makefile in a code
   review. A human can absolutely notice that a logging shard now wants
   `network: [*]` and `write: ["$HOME"]`.
2. **It cannot lie**, because layer 3 enforces it. A declaration that is merely
   documentation is theatre; the enforcement is what turns it into a control.

## Layer 3: enforcement

This is the part that must be real, and it is the only part with meaningful
per-platform cost. Honest assessment:

- **macOS** — `sandbox-exec` with a generated SBPL profile. Officially
  deprecated, still fully functional, and it is exactly how Homebrew sandboxes
  formula builds today. Longer term, a small C shim over `sandbox_init`; we
  already ship C shims elsewhere, so this is familiar ground.
- **Linux** — user namespaces plus a read-only bind-mount root, a private
  `/tmp`, a writable bind for the package dir and any declared paths, and
  `CLONE_NEWNET` with no interfaces when `network:` is absent. Bubblewrap-style
  but implemented directly, since taking a dependency on `bwrap` to fix a
  dependency problem would be poor taste. seccomp filtering is a later refinement.
- **Windows** — weakest story. Restricted tokens plus job objects give process
  and filesystem limits; network denial realistically needs WFP and is a larger
  project. First release should ship layers 0-2 on Windows and say plainly that
  layer 3 is partial, rather than implying a boundary that is not there.

Note the phasing consequence: **layers 0, 1 and 2 deliver most of the value and
cost comparatively little.** Even with no sandbox at all, a script that starts
phoning home is a visible diff in `shard.yml` and an invalidated approval. The
sandbox is what stops a script that lies about its declaration, which is the
narrower (and later) problem.

## The hole this does not close

Removing install-time execution does not remove *build*-time execution.
Crystal's `{{ run(...) }}` and `{% system %}` macros execute arbitrary programs
during compilation. Anyone who can land code in your `lib/` gets execution the
moment you build, whether or not a postinstall script ever ran. Rust has the
identical problem with proc macros.

This must be stated in any public writeup, or the claim becomes false security.
It is also an opportunity: we own `crystal-alpha`, so the same capability model
can extend to macro execution at compile time. As far as I can find, no major
language toolchain does this today. That is a genuine differentiator, and it is
a much larger project than this one.

## Proposed phasing

| Phase | Scope | Rough cost | Value |
|-------|-------|-----------|-------|
| 1 | Declarative `build:` / `extensions:` blocks (layer 0) | small | removes the script entirely for ~50% of the corpus |
| 2 | Default-deny + triple-bound approval in `shard.yml`, `shards script review/approve`, hard error under `--frozen` (layer 1) | small-medium | closes the first-install hole, which is the actual attack |
| 3 | `needs:` declaration parsed, recorded in the approval, shown at review time (layer 2, unenforced) | small | makes capability creep visible in diffs |
| 4 | macOS + Linux enforcement (layer 3) | medium-large | the declaration stops being advisory |
| 5 | Compile-time macro capabilities in crystal-alpha | large | closes the remaining door; nobody else has this |

Phases 1-3 are worth doing regardless of whether 4 ever happens.

## Decisions that need the owner

1. **How hard is the default?** Default-deny breaks `shards install` for anyone
   depending on ameba/micrate/avram until they approve once. That is the
   correct security posture and a real adoption cost. Options: deny by default
   (recommended, with a one-line approve command), or warn-and-run for one
   release with a deprecation notice.
2. **Do we ship this as a Crystal upstream proposal or keep it in ashards?**
   Upstream adoption helps the ecosystem and slows us down; ashards-only ships
   now and becomes a reason to use ashards. The checksum work has the same
   question attached.
3. **Does `sam.cr`'s pattern (writing into the consumer's project) stay legal
   at all?** It is a scaffolding operation wearing an install script's clothes.
   Arguably it should be an executable the user runs deliberately, and the
   capability model should refuse `write: ["../../"]` outright rather than
   letting it be granted.
