# Where this folder came from

Copied with the author's permission from github.com/MELcodes99/kiyoshi at commit
`9200aff667e993300bf33117872fbaff9773e15c` (16 Nov 2026), without its git history.

Changes since the copy:
* `package.json`: `engines.node >= 22`; `tsx` moved to `dependencies` so `npm run base-desk` works on a host that
  skips dev dependencies (Railway).
* CI moved to `/.github/workflows/kiyoshi.yml` (GitHub only runs workflows from the repo root).

To pull in Mel's later changes, diff against a fresh clone of his repo and copy across what's needed.
