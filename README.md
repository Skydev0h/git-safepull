# git-safepull

`git-safepull` is a conservative `git pull` replacement plus an archive mode for volatile upstream repositories.

It is meant for repositories where upstream history may disappear: force-pushes, deleted branches, recreated repos, pressured takedowns, or forks that briefly contain useful commits. The default mode keeps a normal working copy safe. `--archive` acts more like a low-cost upstream flight recorder.

## Modes

### Safe Pull Mode

```bash
git safepull
```

Safe pull mode operates on the current branch and its actual upstream (`@{upstream}`).

Behavior:

1. Saves the current `HEAD` as a permanent safepull tag/ref.
2. Fetches the upstream remote.
3. Fast-forwards only when the update is safe.
4. Leaves local-ahead branches untouched.
5. On divergence, saves the old state and stops by default.
6. Refuses worktree-moving operations when there are uncommitted changes.

This means a rewritten upstream is archived, but your branch is not reset unless you explicitly ask for that:

```bash
git safepull --accept-rewrite
```

If the worktree is dirty, even `--accept-rewrite` refuses to run unless you pass the explicit destructive override:

```bash
git safepull --accept-rewrite --discard-dirty
```

### Archive Mode

```bash
git safepull --archive
```

Archive mode is for cron jobs and repository monitoring.

Behavior:

1. Snapshots existing `refs/remotes/*` and tags before fetch.
2. Fetches all remotes with tags.
3. Prunes deleted remote branches by default, after the pre-fetch snapshot exists.
4. Detects remote branch rewrites/deletions and fetch failures.
5. Stores cheap preservation refs under `refs/safepull/*`.
6. Creates a bundle only when an interesting destructive event happens.
7. Does not update or reset the working tree.

Recommended cron usage:

```bash
git safepull --archive --quiet
```

No-op archive runs are intentionally cheap and idempotent. They do not create bundles, and they do not create new timestamped refs for the same observed commits. The first run creates `refs/safepull/*`; later no-op runs update the same refs to the same objects.

To also update the current branch from archive mode when it is safe:

```bash
git safepull --archive --update-worktree
```

## What Gets Preserved

Safe pull mode:

| Artifact | Location | Purpose |
|---|---|---|
| Tag | `refs/tags/safepull/YYYYMMDD-HHMMSS-HASH` | Human-visible marker for current `HEAD` |
| Internal ref | `refs/safepull/heads/<branch>/YYYYMMDD-HHMMSS-HASH` | Keeps current `HEAD` reachable |
| Branch on divergence | `refs/heads/pre-rewrite/<timestamp>/<branch>` | Browse old local branch state |
| Bundle on divergence | `.git/safepull-bundles/*.bundle` | Self-contained backup |

Archive mode:

| Artifact | Location | Purpose |
|---|---|---|
| Remote ref snapshot | `refs/safepull/remotes/<remote>/<branch>/YYYYMMDD-HHMMSS-HASH` | Keeps observed remote branch states reachable |
| Tag snapshot | `refs/safepull/tags/<tag>/YYYYMMDD-HHMMSS-HASH` | Keeps observed tag targets reachable |
| Bundle on event | `.git/safepull-bundles/*.bundle` | Self-contained backup when something destructive happened |

Snapshot names are based on the target commit date plus short hash, not wall-clock time. Re-running on the same unchanged repo should not accumulate new snapshot refs.

## Bundle Policy

Refs are cheap. Bundles are not.

By default:

- safe pull mode creates a bundle on divergence;
- archive mode creates a bundle on destructive events;
- archive no-op and normal fast-forward runs do not create bundles.

Useful flags:

```bash
# Always create a bundle this run
git safepull --bundle

# Never create bundles automatically
git safepull --archive --no-bundle

# Create a routine bundle at most once per interval
git safepull --archive --bundle-interval 24h

# Keep only the newest 20 bundles
git safepull --archive --keep-bundles 20

# Delete bundles older than 90 days
git safepull --archive --keep-bundles-days 90
```

Bundle files are verified after creation with `git bundle verify`.

## Examples

Normal replacement for `git pull --ff-only`:

```bash
git safepull
```

Accept a known upstream rewrite after archiving the old state:

```bash
git safepull --accept-rewrite
```

Monitor a directory of volatile repos:

```bash
for d in ~/watched-repos/*/; do
  (cd "$d" && git safepull --archive --quiet)
done
```

Run from cron every 15 minutes:

```cron
*/15 * * * * for d in /home/user/watched-repos/*/; do (cd "$d" && git safepull --archive --quiet); done >> /tmp/safepull.log 2>&1
```

Archive mode without pruning deleted remote-tracking refs:

```bash
git safepull --archive --no-prune
```

## Options

```text
--archive             snapshot all remote refs and fetch all remotes; do not update worktree
--update-worktree     with --archive, also update current branch when it is safe
--accept-rewrite      after archiving a divergence, reset current branch to upstream
--discard-dirty       allow worktree-moving operations to discard local changes
--hierarchic          snapshot current remote's branches before fetch
--bundle              always create a .bundle backup this run
--no-bundle           never create .bundle automatically
--bundle-on-event     create bundle on rewrite/delete/fetch-failure events; archive default
--bundle-interval N   optional routine bundle interval, e.g. 24h, 3600s, 7d
--keep-bundles N      keep only the newest N bundle files
--keep-bundles-days N delete bundle files older than N days
--no-prune            with --archive, do not prune deleted remote branches
--dry-run             fetch/report but do not update the working tree
--quiet               minimal output
-h, --help            show help
```

## Install

```bash
# Option 1: install.sh (copies to ~/.local/bin)
./install.sh

# Option 2: manual
cp git-safepull ~/.local/bin/
chmod +x ~/.local/bin/git-safepull

# Option 3: anywhere on PATH
sudo cp git-safepull /usr/local/bin/
```

Git discovers `git-*` executables on `PATH` as subcommands. After installation:

```bash
git safepull -h
```

`git safepull --help` is handled by Git itself and looks for a `git-safepull` manpage. The script help is available through `git safepull -h` or direct execution with `git-safepull --help`.

## Housekeeping

List safepull refs:

```bash
git for-each-ref refs/safepull
```

List human-visible safepull tags:

```bash
git tag -l 'safepull/*'
```

Delete a specific safepull ref:

```bash
git update-ref -d refs/safepull/remotes/origin/main/20260429-021500-abcdef12
```

Delete old bundles manually:

```bash
find .git/safepull-bundles -type f -name '*.bundle' -mtime +90 -delete
```

## Notes

- Archive mode protects branch history best. Tag tracking is based on local tag refs after fetch, so remote-specific tag provenance is not modeled separately.
- Archive mode respects the repository's configured remote fetch refspecs. A shallow single-branch clone will keep monitoring only that configured branch unless you broaden the refspec, for example with `git remote set-branches origin '*'` followed by `git fetch origin --depth=1`.
- Shallow clones stay shallow. Bundles created from them preserve the objects that are present locally, but they do not reconstruct history from before the shallow boundary.
- `--dry-run` asks Git to fetch in dry-run mode and skips post-fetch snapshot changes.
- `--discard-dirty` is intentionally explicit because it permits destructive worktree updates.

## License

MIT
