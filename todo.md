# StereoFool TODO

## High Priority

- [ ] Add optional real-time scheduling / process priority profiles per OS (safe defaults, opt-in).
- [ ] Add a final composite true-peak guard stage (oversampled) with clear meter/readout.
- [ ] Add worker telemetry for control-loop timing and late-apply counters.
- [ ] Add stress test for rapid UI parameter changes (multi-client, slider spam, reconnect storm).

## Medium Priority

- [ ] Add lock-free snapshot/ring-buffer path for monitor telemetry to reduce lock contention further.
- [ ] Add widener quality modes (`safe` default, optional `enhanced` mode).
- [ ] Add monitor meter presets (VU, PPM, Broadcast Fast, Broadcast Slow).
- [ ] Add sticky peak reset-all + auto-reset timer option.

## Processor Parity

- [ ] Add true final full-MPX lookahead limiter after pilot+RDS sum (absolute legal deviation guard).
  Math target: `D = Fs * t_la`, `e[n] = max(abs(x[n + D]))`, `g[n] = min(1.0, A_max / max(e[n], eps))`, `y[n] = x[n] * g[n]`.
  Constraint: `abs(MPX) <= 1.0` implies legal `75 kHz` peak deviation.
- [ ] Upgrade clipper path to higher-oversampling shaped clipper + reconstruction LPF.
  Math target: piecewise soft-hard curve `y = x` for `abs(x) <= T`, else `y = sign(x) * (T + (abs(x) - T) / (1 + (abs(x) - T)^2))`.
  Filter target: reconstruction low-pass after downsample with `fc ~= 0.45 * Fs`.
- [ ] Split dynamics into multiband AGC + separate multiband peak limiter tier.
  Wideband AGC target: `g[n] = g[n-1] + alpha * (T - E[n])`, `alpha = 1 - exp(-1 / (Fs * tau_attack_release))`.
  Band transfer target: `y = x` for `x < T`, else `y = T + (x - T) / R`.
  Peak limiter target: `p[n] = max(abs(x[n]), p[n-1] * exp(-1 / (Fs * T_r)))`.
- [ ] Rework pre-emphasis path so TX pre-emphasis placement and sidechain model are explicitly matched.
  Sidechain target: pre-emphasis model `H(s) = 1 + s * tau` with `tau = 50e-6` or `75e-6`.
  Control target: `g[n] = min(1.0, A_max / max(p_pre[n], eps))` applied before actual TX pre-emphasis stage.

## Release / QA

- [ ] Run full release checklist for 0.6 before tagging:
- [ ] `ruff format .`
- [ ] `ruff check .`
- [ ] `pyright`
- [ ] `vulture stereofool`
- [ ] `.venv/bin/python tools/mpx_matrix_test.py --config stereofool.ini --duration 1.0 --warmup 0.1`
- [ ] Manual smoke test: start app, login, verify monitoring + processing toggles on-air.

## Docs

- [ ] Document control-rate update loop behavior in `README.md`.
- [ ] Document recommended buffer/blocksize starting points for slow CPUs.
- [ ] Add troubleshooting section for UI reload spikes and expected behavior.
