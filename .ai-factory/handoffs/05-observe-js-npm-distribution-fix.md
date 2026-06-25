# Handoff — observe-js-npm-distribution-fix

## 1. Frame
`observe-js` cannot be consumed as a git or file dependency without manual intervention because `dist/` is not committed and the `prepare` build script requires an unchecked-out git submodule — the chat is compacted but the problem is fully described below; rehydrate from this note, don't trust memory.

## 2. Read-first map

### Must-read now (minimal rehydration set)
- `package.json` — defines `prepare: "npm run build"` (the root cause) and `"files": ["dist"]`
- `tsup.config.ts` — build configuration, entry points
- `.gitmodules` — shows `contract` is a submodule pointing to `https://github.com/mind-systems/observe-contract`

### Read on demand
- `src/core/levels.ts` — imports `../../contract/levels.json`; the only file that depends on the submodule
- `contract/` — git submodule directory (empty when cloned without `--recurse-submodules`)

## 3. Current state

**Done:**
- Root cause identified: `prepare` script triggers `npm run build` on every `npm install`; build requires `contract/levels.json` from the git submodule; submodule is not populated when npm clones the package from `git+https://`
- Workaround applied in consumers (`mind_api` and `mind_web`): vendored `dist/` as `vendor/observe-js-0.0.0.tgz` with `prepare` script manually stripped from the vendored `package.json`; referenced via `"observe-js": "file:./vendor/observe-js-0.0.0.tgz"` in each consumer's `package.json`

**In-flight:**
- `observe-js` itself is not fixed — the workaround lives in the consumers, not the source
- Every time `observe-js` is updated, consumers must re-vendor manually

**Uncommitted working-tree state:**
- None in `observability/` — changes are in `mind_api` and `mind_web`

## 4. Next step
Fix `observe-js` so it can be consumed directly via `git+https://github.com/mind-systems/observe-js.git#<tag>` without any consumer-side workaround:

1. **Remove `prepare` from `package.json` scripts** (rename to `build` only — keep it callable manually but not auto-triggered on install)
2. **Commit `dist/` to git** — add dist files, remove `dist/` from `.gitignore` if present; `"files": ["dist"]` is already correct
3. **Tag a new release** (e.g. `v0.2.0`) so consumers can pin to it
4. **Consumers update**: change `"observe-js": "file:./vendor/observe-js-0.0.0.tgz"` back to `"observe-js": "git+https://github.com/mind-systems/observe-js.git#v0.2.0"` and delete vendor files

Alternative if committing dist is not desired: publish to a private npm registry and have consumers use the registry URL.

## 5. Working discipline
Show the plan before making changes. The `contract/` submodule situation (whether to keep it, inline the JSON, or drop the submodule entirely) may need a decision — stop and ask if the right approach is unclear.

## 6. Error log
- **Mistake:** Assumed `git+https://` would work for npm because the repo is public — it doesn't work because npm does not clone git submodules, so `contract/levels.json` is always missing during the `prepare` build
- **Mistake:** Tried `file:./vendor/observe-js` symlink approach — `npm install` silently replaced `vendor/observe-js/dist/` with `node_modules/` making dist disappear; tgz approach required instead
- **Mistake:** `npm pack` produced a tgz with only `package.json` because `dist/` had already been wiped; had to source `dist/` from `mind_api/vendor/observe-js/` (which was untouched) and pack fresh

## 7. Orientation
- **`contract/`** is a git submodule pointing to a separate repo `mind-systems/observe-contract`; it contains `levels.json` which maps log level names to OTLP severity numbers. It is only needed at build time, not at runtime — `dist/` contains the baked-in values.
- **Two consumers** are affected: `mind_api` (NestJS, `github:mind-systems/observe-js#main`) and `mind_web` (React/Vite, `git+https://...#v0.1.0`) — both need updating after the fix is tagged.
- Consumer paths: `~/projects/mind/mind_api/` and `~/projects/mind/mind_web/`

## 8. Domain model spine
- `dist/` contains all compiled outputs (CJS, ESM, `.d.ts`) for browser, node, and winston entry points — this is the artifact that consumers need; don't re-litigate whether to commit it, the answer is yes
- `contract/levels.json` is only a build-time input — it gets inlined by tsup into `dist/`; consumers never need the raw JSON

## 9. Hard rules
- Do not delete or rename the `build` script — only remove `prepare` (which is the auto-trigger alias)
- Tag releases semantically so consumers can pin to immutable refs
- Do not break the existing `dist/` entry point structure (`browser`, `node`, `winston`) — consumers import from the root and rely on the exports map
