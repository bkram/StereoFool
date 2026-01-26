# Agent Instructions

## Project basics

- Primary entrypoint: `stereofool/app.py`
- Config file: `stereofool.ini`
- Requirements: `requirements.txt`

## How to run

```bash
python stereofool/app.py
```

Default port is `8300`. Use `--port` to override.

## Code change guidance

- Keep all runtime behavior in `stereofool/app.py` unless introducing new modules is required.
- The web UI is a single unified navigation; avoid reintroducing separate Stereo/RDS menus.
- Prefer small, testable helpers if you refactor DSP logic.
- Avoid adding non-ASCII characters to source or docs.

## Testing

- Use the offline MPX matrix suite for DSP validation after changes:
  - `python tools/mpx_matrix_test.py --config stereofool.ini --duration 1.0 --warmup 0.1`
- For a single offline WAV capture (no soundcard), use:
  - `python tools/mpx_matrix_test.py --config stereofool.ini --single-wav output.wav --duration 5`
- If you change runtime logic, perform a manual smoke test by starting the server and verifying the UI loads.
- Use `ruff format .` for formatting and `pyright` for type checks.
- Use `vulture stereofool` to audit dead code.

## Release prep

- Before release, use this checklist:
  - Update version + `CHANGELOG.md` as needed.
  - Run `ruff format .` and `ruff check .`.
  - Run `pyright`.
  - Run `vulture stereofool`.
  - Audit dead code/config/docs (e.g., `vulture stereofool`, JS/CSS scan, remove stale docs).
  - Manual smoke test: start the server and verify the UI loads.

## Notes

- Audio device indices are platform-specific; avoid hardcoding device IDs.
- Real-time DSP is sensitive to blocking I/O; keep callbacks lightweight.
- RDS carrier frequency is config-only; the UI exposes carrier level and program data.
- The monitoring view includes scopes, MPX meters, and limiter status; keep it lightweight.
- RDS baseband uses EN 50067 biphase shaping and a pilot-locked subcarrier.
- Standards reference PDFs live in `documents/`.
