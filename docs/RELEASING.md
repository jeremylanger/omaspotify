# Release process

Backend releases are source-bound artifacts. Do not commit an executable under
`backend/`, attach a locally built binary, or accept a checksum stored beside an
otherwise unproven binary as provenance.

## Prepare the source snapshot

1. Update `manifest.json`, `backend/Cargo.toml`, `backend/Cargo.lock`, and the
   changelog together.
2. Run `./scripts/test.sh` and a locked release build.
3. Commit and push the reviewed source. The release commit must be clean.
4. Create `v<manifest version>` at that exact commit and push the tag. Never
   move or reuse a release tag; fix a failed release forward with a new version.

The tag starts `.github/workflows/release-backend.yml`. Native GitHub-hosted
x86_64 and aarch64 runners build `Cargo.lock` with Rust 1.97.1. Every action is
pinned to an immutable commit. The workflow attests each raw executable before
publishing it with `SHA256SUMS` in the matching GitHub release.

## Verify the published artifacts

For each downloaded executable, verify the checksum and then independently bind
GitHub's attestation to all of the following:

- repository `jeremylanger/omaspotify`;
- `.github/workflows/release-backend.yml` at the exact version tag;
- the release commit digest; and
- a GitHub-hosted runner.

The installer enforces that policy with `gh attestation verify`. If any check is
unavailable or fails, it never installs the download; it uses a locked local
source build or the packaged spotifyd fallback.

After both release assets and their attestations are available, submit the exact
release commit in a new marketplace Verify ticket. Include the workflow run and
release links so the reviewer can independently repeat the source-digest-bound
verification.
