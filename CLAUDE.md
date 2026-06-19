# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

**IMPORTANT:** Follow documentation rules in [CONTRIBUTING.md](CONTRIBUTING.md) - especially the file creation and naming conventions.

## Project Overview

`notebooklm-py` is an unofficial Python client for Google NotebookLM that uses undocumented RPC APIs. The library enables programmatic automation of NotebookLM features including notebook management, source integration, AI querying, and studio artifact generation (podcasts, videos, quizzes, etc.).

**Critical constraint**: This uses Google's internal `batchexecute` RPC protocol with obfuscated method IDs that Google can change at any time. All RPC method IDs in `src/notebooklm/rpc/types.py` are undocumented and subject to breakage.

## Development Commands

```bash
# Canonical contributor install (respects uv.lock; full guide: docs/installation.md)
uv sync --frozen --extra browser --extra dev --extra markdown
source .venv/bin/activate
uv run playwright install chromium

# Run all tests (excluding e2e by default)
uv run pytest

# Run with coverage
uv run pytest --cov

# Run e2e tests (requires authentication)
uv run pytest tests/e2e -m e2e

# CLI testing
uv run notebooklm --help

# Type checking
uv run mypy src/notebooklm --ignore-missing-imports

# Lint / format
uv run ruff check src/ tests/
uv run ruff format src/ tests/

# Re-record VCR cassettes
NOTEBOOKLM_VCR_RECORD=1 uv run pytest tests/integration/ -v
```

> **pip users**: `pip install notebooklm-py` and `pip install "notebooklm-py[browser]"` work too — `uv` is recommended for contributors to honour the lock file.

## Pre-Commit Checks

The pre-commit hook (`.pre-commit-config.yaml`) runs ruff formatting + linting automatically on staged files.

Before pushing, also run mypy + pytest manually to avoid CI failures:
```bash
uv run mypy src/notebooklm --ignore-missing-imports
uv run pytest
```

## Architecture

### Layered Design

```
CLI Layer (cli/)
    ↓
Client Layer (client.py, _*.py APIs)
    ↓
Core Layer (_core.py + _core_*.py seam modules)
    ↓
RPC Layer (rpc/)
```

1. **RPC Layer** (`src/notebooklm/rpc/`):
   - `types.py`: All RPC method IDs and enums (source of truth)
   - `encoder.py`: Request encoding
   - `decoder.py`: Response parsing
   - `overrides.py`: Drift-detection overrides for evolving RPC schema
   - `_safe_index.py`: Schema-drift safety helpers (`safe_index`); strict-decode mode via `NOTEBOOKLM_STRICT_DECODE=1`

2. **Core Layer** (`src/notebooklm/_core.py` + `_core_*.py` seam modules):
   - `_core.py`: `ClientCore` orchestrator; HTTP client lifecycle; late-binding wrappers
   - `_core_transport.py`, `_core_rpc.py`: HTTP client + RPC call abstraction
   - `_core_auth.py`, `_core_cookie_persistence.py`: Auth refresh + cookie storage
   - `_core_metrics.py`, `_core_drain.py`, `_core_reqid.py`: Telemetry, drain coordination, request-counter handling
   - `_core_cache.py`, `_core_polling.py`: Conversation cache + artifact polling helpers
   - `_core_constants.py`, `_core_helpers.py`, `_core_error_injection.py`: Module-level constants, helper utilities, synthetic-error transport
   - `_core_lifecycle.py`: Open/close lifecycle (loop-affinity guard + keepalive task)
   - `_capabilities.py`: Capability adapters for feature APIs

3. **Client Layer** (`src/notebooklm/client.py`, `_*.py`):
   - `NotebookLMClient`: Main async client with namespaced APIs
   - `_notebooks.py`, `_sources.py`, `_artifacts.py`, `_chat.py`, `_notes.py`, `_research.py`, `_settings.py`, `_sharing.py`: Domain APIs
   - Private service modules (`_source_add.py`, `_artifact_generation.py`, etc.): Decomposed operation logic

4. **CLI Layer** (`src/notebooklm/cli/`):
   - Modular Click commands
   - `cli/services/`: UI-layer service orchestrators for interactive flows

### Key Files

| File | Purpose |
|------|---------|
| `client.py` | Main `NotebookLMClient` class |
| `_core.py` | `ClientCore` orchestrator; HTTP client lifecycle; late-binding wrappers |
| `_core_constants.py` | `DEFAULT_*` knobs and module-level constants |
| `_core_helpers.py` | `is_auth_error`, `AUTH_ERROR_PATTERNS`, `_resolve_keepalive_interval` |
| `_core_error_injection.py` | `_SyntheticErrorTransport` + env-var guard for fault injection |
| `_core_metrics.py` | `ClientMetrics` — `ClientMetricsSnapshot` counters + `on_rpc_event` callback |
| `_core_drain.py` | `TransportDrainTracker` — in-flight transport counters + `_TransportOperationToken` |
| `_core_reqid.py` | `ReqidCounter` — monotonic `_reqid` for the chat backend |
| `_core_auth.py` | `AuthRefreshCoordinator` — refresh task + auth-snapshot lock |
| `_core_lifecycle.py` | `ClientLifecycle` — loop-affinity guard + keepalive task |
| `_core_rpc.py` | RPC dispatch executor with `DecodeResponse` + `RpcOwner` Protocols |
| `_core_transport.py` | Authed POST path, retry loops, `_AuthedTransportHost` Protocol |
| `_core_cache.py` | Per-instance LRU conversation cache for `ChatAPI` |
| `_core_polling.py` | Pending-poll registry for long-running artifact generations |
| `_core_cookie_persistence.py` | Cookie-jar persistence + `__Secure-1PSIDTS` rotation |
| `_capabilities.py` | Narrow capability Protocols + `ClientCoreCapabilities` adapter for sub-clients |
| `_notebooks.py` | `client.notebooks` API |
| `_sources.py` | `client.sources` API |
| `_artifacts.py` | `client.artifacts` API |
| `_chat.py` | `client.chat` API |
| `_notes.py` | `client.notes` API |
| `_research.py` | `client.research` API |
| `_settings.py` | `client.settings` API — user tier, account limits, output language |
| `_sharing.py` | `client.sharing` API — public links, user permissions |
| `_sharing_manager.py` | `ShareManager` — legacy share-link URL composition |
| `_mind_map.py` | Note-backed mind-map service shared by `ArtifactsAPI` and `NotesAPI` |
| `_source_add.py` | URL/YouTube/text/Drive source creation; YouTube detection; idempotent probes |
| `_source_listing.py` | `SourceLister` — parses sources from `GET_NOTEBOOK` RPC responses |
| `_source_content.py` | `SourceContentRenderer` — source guide (summary + keywords) + fulltext via RPC |
| `_source_polling.py` | `SourcePoller` — polls source readiness with exponential backoff |
| `_source_upload.py` | File upload pipeline (concurrent uploads, resumable chunks, idempotent create) |
| `_artifact_generation.py` | Artifact creation request building + polling loop orchestration |
| `_artifact_listing.py` | `ArtifactListingService` — lists/filters artifacts |
| `_artifact_downloads.py` | Multi-URL download batching with `DownloadResult` + trusted-domain validation |
| `_artifact_polling.py` | `ArtifactPollingService` — async polling loop with exponential backoff |
| `_artifact_formatters.py` | Quiz/flashcard HTML parsing; markdown formatting |
| `_chat_protocol.py` | Streamed-chat wire request construction + response parsing |
| `_notebook_metadata.py` | `NotebookMetadataService` — concurrent notebook + source summary composition |
| `_idempotency.py` | `idempotent_create()` wrapper + `IdempotencyRegistry` with 6-policy classification |
| `_backoff.py` | `compute_backoff_delay()` — exponential backoff with bounded jitter |
| `_callbacks.py` | `maybe_await_callback()` — uniform sync/async callback dispatch |
| `_loop_affinity.py` | `assert_bound_loop()` — cross-event-loop usage guard |
| `_atomic_io.py` | Crash-safe JSON writes via `os.replace()` + cross-process `filelock` |
| `_logging.py` | Logging with credential redaction; per-task `ContextVar` correlation IDs |
| `_env.py` | Environment variable lookup (base URLs, language defaults, strict-decode toggle) |
| `_url_utils.py` | URL validation using proper hostname parsing (YouTube, Google auth redirects) |
| `_version_check.py` | Runtime Python ≥ 3.10 gate with user-friendly error message |
| `migration.py` | Idempotent flat → profile-based `~/.notebooklm/` layout migration |
| `paths.py` | Centralized path resolution for config/profile storage |
| `config.py` | Public re-export of runtime config helpers from `_env` |
| `exceptions.py` | Exception hierarchy (all inherit `NotebookLMError`); response truncation for safe logging |
| `log.py` | Public facade re-exporting `install_redaction()` from `_logging` |
| `urls.py` | Public facade re-exporting URL validation helpers |
| `io.py` | Public facade re-exporting atomic I/O helpers |
| `utils.py` | `resolve_chat_reference_passage()` — fetch surrounding source text for citation spans |
| `research.py` | Report URL extraction, normalisation, citation matching |
| `auth.py` | Authentication facade — re-exports + `_AuthFacadeModule` shim that forwards monkeypatches to `_auth/*` seams |
| `rpc/types.py` | RPC method IDs (source of truth) |
| `rpc/overrides.py` | Drift-detection overrides for evolving RPC schema |
| `rpc/_safe_index.py` | Schema-drift safety helpers (`safe_index`) |

### Auth Subpackage (`_auth/`)

| File | Purpose |
|------|---------|
| `_auth/paths.py` | Profile-aware storage path resolution |
| `_auth/extraction.py` | Cookie/token extraction from NotebookLM HTML (`WIZ_global_data`) |
| `_auth/headers.py` | HTTP header construction (`x-goog-authuser`, etc.) |
| `_auth/cookies.py` | RFC 6265 cookie handling; Netscape + HTML5 format support |
| `_auth/cookie_policy.py` | Cookie-domain allowlist; personal/enterprise host policy |
| `_auth/account.py` | `Account` dataclass; `authuser=N` probing; multi-account discovery |
| `_auth/session.py` | Protocol defining core refresh boundary |
| `_auth/storage.py` | Cookie snapshot/delta persistence; atomic save/load |
| `_auth/keepalive.py` | Periodic session poke requests (configurable interval + jitter) |
| `_auth/refresh.py` | Token refresh: `NOTEBOOKLM_REFRESH_CMD` subprocess flow; per-loop coalescing; redaction |

### Types Subpackage (`_types/`)

| File | Purpose |
|------|---------|
| `_types/common.py` | `Notebook`, `Source`, `Artifact`, `Note` base dataclasses |
| `_types/notebooks.py` | `NotebookMetadata`, `NotebookSummary`, notebook-specific types |
| `_types/sources.py` | `SourceStatus`, `SourceSummary`, `SourceFulltext` |
| `_types/artifacts.py` | `GenerationStatus`, `ArtifactType`, artifact-specific enums |
| `_types/chat.py` | `ChatReference`, `ChatMode`, `AskResult`, conversation types |
| `_types/notes.py` | `Note` dataclass |
| `_types/sharing.py` | `ShareStatus`, `SharePermission`, `ShareViewLevel` |

### Repository Structure

```
src/notebooklm/
├── __init__.py                  # Public exports
├── __main__.py                  # python -m notebooklm entry point
├── client.py                    # NotebookLMClient
├── auth.py                      # Authentication facade
├── types.py                     # Public type re-exports
├── exceptions.py                # Exception hierarchy (NotebookLMError + subclasses)
├── paths.py                     # Config/profile path resolution
├── config.py                    # Runtime config helpers (re-exports from _env)
├── log.py                       # Logging facade (re-exports from _logging)
├── urls.py                      # URL validation facade (re-exports from _url_utils)
├── io.py                        # Atomic I/O facade (re-exports from _atomic_io)
├── utils.py                     # Chat citation helper
├── research.py                  # Report URL extraction + citation matching
├── migration.py                 # Flat → profile layout migration
├── _env.py                      # Environment variable lookup
├── _logging.py                  # Logging + credential redaction
├── _url_utils.py                # URL validation
├── _atomic_io.py                # Crash-safe JSON I/O + file locking
├── _version_check.py            # Python ≥ 3.10 runtime gate
├── _backoff.py                  # Exponential backoff with bounded jitter
├── _callbacks.py                # Sync/async callback dispatch
├── _loop_affinity.py            # Cross-event-loop usage guard
├── _idempotency.py              # Idempotent create wrapper + registry
├── _capabilities.py             # Capability Protocols + ClientCoreCapabilities adapter
│
├── _core.py                     # Core orchestration (ClientCore)
├── _core_constants.py           # DEFAULT_* knobs + module-level constants
├── _core_helpers.py             # is_auth_error / AUTH_ERROR_PATTERNS / keepalive helpers
├── _core_error_injection.py     # _SyntheticErrorTransport + fault-injection env-var guard
├── _core_transport.py           # HTTP client + transport-layer concerns
├── _core_rpc.py                 # RPC call abstraction
├── _core_auth.py                # Auth refresh seam
├── _core_cookie_persistence.py  # Cookie storage seam
├── _core_metrics.py             # Telemetry / metrics seam
├── _core_drain.py               # In-flight drain coordinator
├── _core_reqid.py               # Request-counter / request-id helpers
├── _core_cache.py               # Conversation cache seam
├── _core_polling.py             # Artifact polling helpers
├── _core_lifecycle.py           # Open/close lifecycle seam (loop affinity + keepalive task)
│
├── _auth/                       # Auth subpackage (forwarded through auth.py facade)
│   ├── __init__.py
│   ├── paths.py
│   ├── extraction.py
│   ├── headers.py
│   ├── cookies.py
│   ├── cookie_policy.py
│   ├── account.py
│   ├── session.py
│   ├── storage.py
│   ├── keepalive.py
│   └── refresh.py
│
├── _types/                      # Type dataclasses subpackage
│   ├── __init__.py
│   ├── common.py
│   ├── notebooks.py
│   ├── sources.py
│   ├── artifacts.py
│   ├── chat.py
│   ├── notes.py
│   └── sharing.py
│
├── _notebooks.py                # NotebooksAPI
├── _sources.py                  # SourcesAPI
├── _artifacts.py                # ArtifactsAPI
├── _chat.py                     # ChatAPI
├── _notes.py                    # NotesAPI
├── _research.py                 # ResearchAPI
├── _settings.py                 # SettingsAPI
├── _sharing.py                  # SharingAPI
├── _sharing_manager.py          # ShareManager (legacy share-link composition)
├── _mind_map.py                 # Mind-map service (shared by ArtifactsAPI + NotesAPI)
├── _chat_protocol.py            # Streamed-chat wire protocol
├── _notebook_metadata.py        # NotebookMetadataService
├── _source_add.py               # Source creation service
├── _source_listing.py           # SourceLister
├── _source_content.py           # SourceContentRenderer
├── _source_polling.py           # SourcePoller
├── _source_upload.py            # File upload pipeline
├── _artifact_generation.py      # Artifact creation + polling orchestration
├── _artifact_listing.py         # ArtifactListingService
├── _artifact_downloads.py       # Multi-URL download batching
├── _artifact_polling.py         # ArtifactPollingService
├── _artifact_formatters.py      # Quiz/flashcard HTML → markdown formatters
│
├── notebooklm_cli.py            # Entry-point assembler
├── rpc/                         # RPC protocol layer
│   ├── __init__.py
│   ├── types.py                 # Method IDs and enums
│   ├── encoder.py               # Request encoding
│   ├── decoder.py               # Response parsing
│   ├── overrides.py             # Drift-detection overrides
│   └── _safe_index.py           # Schema-drift safety helpers
└── cli/                         # CLI implementation
    ├── __init__.py
    ├── helpers.py
    ├── options.py               # Reusable Click option definitions
    ├── input.py                 # Interactive input / file reading
    ├── rendering.py             # Output formatting (tables, JSON, spinners)
    ├── resolve.py               # Notebook/artifact/source ID resolution
    ├── context.py               # Context file handling (current notebook/source selection)
    ├── language.py              # Language code handling
    ├── completion.py            # Shell completion support
    ├── error_handler.py         # CLI error formatting
    ├── grouped.py               # Click command grouping helpers
    ├── runtime.py               # CLI runtime management
    ├── auth_runtime.py          # Auth-aware command wrapper
    ├── session.py               # login, logout, cache, profile management
    ├── profile.py               # Multi-account profile management
    ├── notebook.py              # list, create, delete, rename, summary, metadata
    ├── source.py                # source add, list, delete, content
    ├── artifact.py              # artifact commands
    ├── generate.py              # generate audio, video, etc.
    ├── download.py              # download commands
    ├── download_helpers.py      # download utilities
    ├── chat.py                  # ask, configure, history
    ├── note.py                  # note commands
    ├── research.py              # research start, list
    ├── research_import.py       # import sources from research reports
    ├── share.py                 # sharing commands
    ├── doctor.py                # diagnostics command
    ├── agent.py                 # agent-specific commands
    ├── agent_templates.py       # agent template definitions
    ├── skill.py                 # Claude Code skill integration
    ├── _chromium_profiles.py    # Chromium profile enumeration for browser-cookies auth
    ├── _firefox_containers.py   # Firefox container enumeration for browser-cookies auth
    ├── _encoding.py             # Encoding helper
    └── services/                # UI-layer service orchestrators
        ├── __init__.py
        ├── login.py             # Interactive login flow
        ├── source_add.py        # Source addition UI
        ├── source_clean.py      # Source cleanup
        └── artifact_generation.py  # Artifact generation UI
```

## API Patterns

### Client Usage

```python
# Correct pattern - uses namespaced APIs
async with await NotebookLMClient.from_storage() as client:
    notebooks = await client.notebooks.list()
    await client.sources.add_url(nb_id, url)
    result = await client.chat.ask(nb_id, question)
    status = await client.artifacts.generate_audio(nb_id)
    await client.sharing.set_public(nb_id, enabled=True)
    tier = await client.settings.get_user_tier()
```

### CLI Structure

Commands are organized as:
- **Top-level**: `login`, `use`, `status`, `clear`, `list`, `create`, `ask`
- **Grouped**: `source add/list/delete/content`, `artifact list/download`, `generate audio/video/quiz/flashcards/infographic/data-table/mind-map/report`, `note create/list/delete`, `research start/list/import`, `share notebook`, `download video/audio`
- **Admin**: `doctor` (diagnostics), `completion` (shell completion), `profile` (multi-account)

## Testing Strategy

- **Unit tests** (`tests/unit/`): Test encoding/decoding, no network
- **Integration tests** (`tests/integration/`): VCR-backed HTTP fixture tests (`@pytest.mark.vcr`); cassettes in `tests/cassettes/`
- **E2E tests** (`tests/e2e/`): Real API, require auth, marked `@pytest.mark.e2e`

### Test Markers

- `@pytest.mark.e2e` — authenticated, live API
- `@pytest.mark.vcr` — VCR cassette playback
- `@pytest.mark.variants` — parameterised API-variant matrix
- `@pytest.mark.readonly` — read-only safe (no mutations)
- `@pytest.mark.characterization` — documents current behaviour (not contracts)

### Coverage

- Global floor: **90%** (enforced by CI)
- Per-file overrides exist for CLI doctor/diagnostic commands (63–83%)

### E2E Test Status

- ✅ Notebook operations (list, create, rename, delete)
- ✅ Source operations (add URL/text/YouTube, rename)
- ✅ Download operations (audio, video, infographic, slides)
- ⚠️ Artifact generation may fail due to rate limiting

## Common Pitfalls

1. **RPC method IDs change**: Check network traffic and update `rpc/types.py`
2. **Nested list structures**: Params are position-sensitive. Check existing implementations.
3. **Source ID nesting**: Different methods need `[id]`, `[[id]]`, `[[[id]]]`, or `[[[[id]]]]`
4. **CSRF tokens expire**: Use `client.refresh_auth()` or re-run `notebooklm login`
5. **Rate limiting**: Add delays between bulk operations
6. **Concurrency**: One `NotebookLMClient` instance is bound to its open()-time event loop. See [Concurrency contract](docs/python-api.md#concurrency-contract). Common bugs:
   - Re-using a client across threads → not supported; create one per thread.
   - Re-using a client across event loops → raises `RuntimeError` on first authed POST.
   - Sharing across `AuthTokens` tenants → never (`ChatAPI._cache` is per-instance).
7. **Schema drift**: Wrap new RPC index accesses with `safe_index` from `rpc/_safe_index.py`; enable `NOTEBOOKLM_STRICT_DECODE=1` during development to surface mis-indexing early.
8. **Auth facade monkeypatching**: Write-through shim in `auth.py` forwards monkeypatches to `_auth/*` seams — do not bypass the facade.
9. **File layout migration**: `migration.py` runs on CLI startup; code that reads storage paths must handle both flat and profile-based layouts during migration window.

## Documentation

All docs use lowercase-kebab naming in `docs/`:
- `docs/installation.md` - Installation, extras matrix, platform notes (canonical install guide)
- `docs/cli-reference.md` - CLI commands
- `docs/cli-exit-codes.md` - Exit code reference
- `docs/python-api.md` - Python API reference
- `docs/configuration.md` - Storage, settings, environment variables
- `docs/troubleshooting.md` - Known issues
- `docs/development.md` - Architecture, testing, releasing
- `docs/releasing.md` - Release process and version management
- `docs/stability.md` - Stability guarantees and breaking change policy
- `docs/auth-keepalive.md` - Keepalive mechanism, cookie rotation, refresh coordination
- `docs/rpc-development.md` - RPC capture and debugging
- `docs/rpc-reference.md` - RPC payload structures

## When to Suggest CLI vs API

- **CLI**: Quick tasks, shell scripts, LLM agent automation
- **Python API**: Application integration, complex workflows, async operations

## Agent Guidelines (AGENTS.md)

For parallel or automated agents:
- Use `--json` output + explicit notebook IDs (don't rely on `notebooklm use`)
- Isolate profiles with `NOTEBOOKLM_PROFILE=agent-<id>` (each agent gets `~/.notebooklm/profiles/<name>/`)
- For headless auth: `notebooklm login --browser-cookies <browser>` (requires `pip install "notebooklm-py[cookies]"`)
- Do not share a single `NotebookLMClient` across concurrent tasks — one instance per task

## Pull Request Workflow (REQUIRED)

After creating a PR, you MUST monitor and address feedback.

### GitHub MCP Tools (remote Claude Code environments)

In remote Claude Code sessions (claude.ai/code), use GitHub MCP tools — the `gh` CLI is not available:

| Task | MCP Tool |
|------|---------|
| List PRs | `mcp__github__list_pull_requests` |
| View PR | `mcp__github__pull_request_read` |
| Post comment | `mcp__github__add_issue_comment` |
| Reply to review comment | `mcp__github__add_reply_to_pull_request_comment` |
| Update PR | `mcp__github__update_pull_request` |
| Watch for activity | `mcp__github__subscribe_pr_activity` |

### `gh` CLI (local environments)

```bash
# Check CI status (repeat until all pass)
gh pr checks <PR_NUMBER>

# Get review comments
gh api repos/Pansl3/notebooklm-py/pulls/<PR_NUMBER>/comments \
  --jq '.[] | "File: \(.path):\(.line)\nComment: \(.body)\n---"'

# Reply to a review thread
gh api repos/Pansl3/notebooklm-py/pulls/<PR>/comments/<COMMENT_ID>/replies \
  -f body="Addressed in commit <SHA>: <brief description>"

# Ensure PR is ready to merge
gh pr view <PR_NUMBER> --json state,mergeStateStatus,mergeable
```

### Feedback Loop

For each review comment (especially from `gemini-code-assist` or `coderabbit`):
1. Read and understand the feedback
2. Make the suggested fix if it improves the code
3. Commit with a descriptive message referencing the feedback
4. Push and re-check CI
5. Reply to the review thread confirming the fix

**Important**: Do NOT consider a PR complete until:
- All CI checks pass
- All review comments are addressed
- `mergeStateStatus` is `CLEAN`

### Requesting a Claude review on a PR

Automatic Claude review on every PR is disabled. To request a review, comment `@claude review` on the PR — the `.github/workflows/claude.yml` workflow will pick it up.
