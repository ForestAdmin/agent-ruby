# CLAUDE.md

## Adding a new package to the monorepo

When scaffolding a new `packages/forest_admin_datasource_*` (or any new)
package, mirror an existing package's scaffold (`Gemfile`, `Gemfile-test`,
`Rakefile`, `.rspec`, gemspec, `LICENSE`, `spec/spec_helper.rb`, `.gitignore`)
and update every one of these in the same PR — missing one breaks CI or
releases silently, not loudly:

1. **`lib/<package>/version.rb`** — must be exactly:
   ```ruby
   module <Module>
     VERSION = "0.1.0"
   end
   ```
   Double quotes, no `.freeze`. The release sed in `.releaserc.js` only
   matches this exact format.

2. **New `.gemspec`** — explicitly opt out of RubyGems MFA, matching every
   other package:
   ```ruby
   spec.metadata['rubygems_mfa_required'] = 'false'
   ```
   Gem publishing runs unattended from CI (`.releaserc.js`), so it can't
   satisfy an MFA prompt.

3. **`.rubocop.yml`** — add the new `version.rb` to:
   - `Style/MutableConstant` Exclude
   - `Style/StringLiterals` Exclude

   And the new `.gemspec` to `Gemspec/RequireMFA` Exclude — the cop flags
   the `'false'` opt-out from step 2 as an offense, so it needs suppressing.

   (Other per-file excludes — `Metrics/MethodLength`, `Metrics/BlockLength`,
   `Naming/PredicatePrefix` — are added case-by-case only if the cop actually
   fires; don't copy them blindly.)

4. **`.releaserc.js`** — add the package in all three spots:
   - `prepareCmd`: `sed -i 's/VERSION = ".*"/VERSION = "${nextRelease.version}"/g' packages/<package>/lib/<package>/version.rb;`
   - `successCmd`: `( cd packages/<package> && gem build && gem push <package>-*.gem );`
   - `@semantic-release/git` `assets`: `packages/<package>/lib/<package>/version.rb`

5. **`.github/workflows/build.yml`** — add the package name to:
   - the `lint` job's `packages` matrix
   - the `test` job's `packages` matrix
   - the codecov step's `files:` list (`.../<package>/coverage.json`)

After merging, verify the next release actually bumps the new `version.rb` —
the sed in step 3 silently no-ops if the format from step 1 is off, with no
CI failure to catch it.
