# Review the repository before pushing

Run from the repository root in a checkout with valid Git metadata. These commands inspect the files selected for version control:

```bash
git status --short
git diff --stat
git diff --check
git ls-files -ci --exclude-standard
```

The last command lists **already tracked files that now match ignore rules**. Adding a path to `.gitignore` does not remove it from the index or earlier commits.

## Stop tracking local files

After reviewing that list, these commands remove the known local configuration and dataset paths from the index while keeping the working files:

```bash
git rm --cached --ignore-unmatch -- \
  "01 - basic/.env" \
  "02 - db indexing/.env" \
  "03 - multi-worker scaling/.env" \
  "04 - horizontal scalling (k8s)/.env" \
  workload-test/k6/.env \
  db/yelp_database.csv \
  workload-test/k6/load-read.html
```

For other reported paths, use `git rm --cached -- "PATH"`; for an entire local tool directory, use `git rm -r --cached -- "DIRECTORY"`. Review the paths first. Keep `.env.example`, code, manifests, and curated reports inside named k6 stage directories.

If a real credential was committed earlier, removing it from the index does not remove it from history; rotate it. A large CSV already present in commits can still prevent a normal push even after it is removed from the latest tree.

## Stage and review

```bash
git add .
git diff --cached --stat
git diff --cached --check
git diff --cached
```

Review the staged contents before committing. Verify that local passwords, the dataset, account configuration, and temporary reports are absent. Then create the commit and push to the repository's configured branch:

```bash
git commit -m "Update project docs and debugging commands"
git push
```

The documentation cleanup does not create a commit or push automatically. The [root README](../README.md) explains the exclusions and stage layout.
