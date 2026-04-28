# Releasing Acta

Releases publish to [rubygems.org](https://rubygems.org/gems/acta) via
GitHub Actions Trusted Publishing (OIDC) — no long-lived API key in
CI, no `gem push` from a laptop. The pipeline is:

```
git tag vX.Y.Z → push tag → .github/workflows/release.yml
                            ├── runs the test suite as a gate
                            └── if green: rubygems mints an OIDC token
                                          and publishes acta-X.Y.Z.gem
```

## Cutting a release

1. **Update `CHANGELOG.md`.** Move entries under `[Unreleased]` to a
   new `[X.Y.Z] — YYYY-MM-DD` section. Leave `[Unreleased]` empty above it.

2. **Bump the version.** Edit `lib/acta/version.rb` to `VERSION = "X.Y.Z"`.

3. **Run the suite locally.** `bundle exec rake` — tests + rubocop.
   Don't tag a red main.

4. **Commit, tag, push.**
   ```bash
   git commit -am "Release X.Y.Z"
   git tag -a vX.Y.Z -m "Release X.Y.Z"
   git push origin main vX.Y.Z
   ```

5. **Watch the workflow.** Actions tab → Release → in-flight run.
   Takes ~2 min. If it goes red, fix forward: revert the version bump
   commit, push that, then re-do steps 1-4 with the next patch number
   (X.Y.Z+1) — tags are immutable once a release has used them, even
   if the publish failed.

6. **Verify.** Once green:
   - https://rubygems.org/gems/acta should show the new version
   - `gem info acta -r` from any machine should resolve it
   - The Releases page on GitHub should have the tag entry (the workflow
     creates it from `release-gem@v1`)

## Choosing the version number

Pre-1.0, breaking changes are allowed in minor bumps. The convention
this project uses:

- **Patch (0.2.0 → 0.2.1)** — bug fixes, doc updates, internal
  refactors that don't change behavior
- **Minor (0.2.x → 0.3.0)** — new features, deprecations, breaking
  changes
- **Major (0.x → 1.0)** — only when the API has settled enough to
  promise stability

Consumers are expected to pin `~> 0.2` (or whatever minor) until 1.0.

## One-time setup (already done — kept for posterity)

If this ever needs to be redone (e.g. moving to a new GitHub repo or
rubygems account):

1. **rubygems.org account** — `tom@gladhill.ca`, MFA enabled.

2. **Trusted Publisher entry** — rubygems.org → Profile → Trusted
   Publishers → Add a publisher:

   | Field | Value |
   |---|---|
   | Repository | `whoojemaflip/acta` |
   | Workflow filename | `release.yml` |
   | Environment name | `rubygems` |

3. **GitHub Actions environment** — Repo Settings → Environments →
   `rubygems`. The workflow's `release` job is gated on it via
   `environment: rubygems`.

4. **Gemspec hardening** — `acta.gemspec` already sets
   `rubygems_mfa_required = "true"`. This means any future manual
   `gem push` (bypassing the workflow) requires an MFA-authenticated
   API key. Trusted Publishing isn't affected — OIDC bypasses API
   keys entirely.

## Yanking a bad release

If a published version turns out to be broken:

```bash
gem yank acta -v X.Y.Z
```

Yanking removes the version from the index — `gem install acta -v X.Y.Z`
will fail, but anyone who already locked it in a Gemfile.lock can
still resolve it. So yank is for "stop the bleeding," not a do-over.
The fix-forward pattern is to ship X.Y.Z+1 with the correction.

## Manual fallback (don't use unless the workflow is broken)

The keys to do this are not configured by default. If you need to
emergency-publish from a laptop:

```bash
gem signin                         # interactive — needs MFA
gem build acta.gemspec
gem push acta-X.Y.Z.gem
```

Document why the workflow couldn't be used in the commit message.
