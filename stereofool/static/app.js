const appStateEl = document.getElementById('app_state');
let appState = {};
if (appStateEl && appStateEl.textContent) {
    try {
        appState = JSON.parse(appStateEl.textContent);
    } catch (e) {
        appState = {};
    }
}
const socket = window.io ? io() : { emit: () => {}, on: () => {} };
let running = Boolean(appState.running);
const ptyList = Array.isArray(appState.pty_list) ? appState.pty_list : [];


    function setTab(id, evt) {
        document.querySelectorAll('.content').forEach(el => el.classList.remove('active'));
        document.querySelectorAll('.tab-btn').forEach(el => el.classList.remove('active'));
        document.getElementById(id).classList.add('active');
        if (evt && evt.currentTarget) {
            evt.currentTarget.classList.add('active');
        }
    }

    function updateLevel(val) {
        document.getElementById('mpx_pilot_val').textContent = parseFloat(val).toFixed(2);
        socket.emit('update', { pilot_level: val });
        updateDeviationLabels();
    }
    function updateToneFreq(val) {
        socket.emit('update', { test_tone_freq: val });
    }
    function updateSourceMode(val) {
        socket.emit('update', { source_mode: val });
        updateSourceVisibility();
    }
    function updateTestToneMode(val) { socket.emit('update', { test_tone_mode: val }); }
    function updateMpxDeviation(val) {
        document.getElementById('mpx_dev_val').textContent = parseFloat(val).toFixed(0);
        socket.emit('update', { mpx_deviation_khz: val });
        updateDeviationLabels();
    }
    function updateOutputGain(val) {
        document.getElementById('mpx_output_gain_val').textContent = parseFloat(val).toFixed(1);
        socket.emit('update', { output_gain_db: val });
    }
    function updateWavRecordEnabled(enabled) {
        socket.emit('update', { wav_record_enabled: enabled });
    }

    function updateMonitorEnabled(enabled) {
        socket.emit('update', { monitor_enabled: enabled });
    }

    function updateMonitorDevice(value) {
        socket.emit('update', { monitor_device_idx: Number(value) });
    }

    function updateMonitorRate(value) {
        socket.emit('update', { monitor_rate_hz: Number(value) });
    }
    function updateBlocksize(value) {
        socket.emit('update', { blocksize: Number(value) });
    }
    function updateWavRecordPath(val) {
        socket.emit('update', { wav_record_path: val });
    }
    function updateDeviationLabels() {
        const pilotEl = document.getElementById('mpx_pilot_level');
        const rdsEl = document.getElementById('rds_level');
        const pilotKHzEl = document.getElementById('pilot_dev_khz');
        const pilotPctEl = document.getElementById('pilot_dev_pct');
        const rdsKHzEl = document.getElementById('rds_dev_khz');
        if (!pilotEl || !rdsEl) return;
        const pilotLevel = parseFloat(pilotEl.value || '0');
        const rdsLevel = parseFloat(rdsEl.value || '0');
        const devEl = document.getElementById('mpx_deviation_khz');
        const maxDev = devEl ? parseFloat(devEl.value || '75') : 75.0;
        const pilotKHz = pilotLevel * maxDev;
        const rdsKHz = rdsLevel * (maxDev / 75.0);
        if (pilotKHzEl) pilotKHzEl.textContent = pilotKHz.toFixed(2);
        if (pilotPctEl) pilotPctEl.textContent = (pilotLevel * 100.0).toFixed(1);
        if (rdsKHzEl) rdsKHzEl.textContent = rdsKHz.toFixed(2);
    }
    function updateStereoCoder(enabled) {
        socket.emit('update', { mono_mode: !enabled });
    }
    function updatePreemphasis(val) { socket.emit('update', { preemphasis_us: val }); }
    function updateHpfHz(val) { socket.emit('update', { hpf_hz: val }); }
    function updateHfTrimDb(val) {
        document.getElementById('mpx_hf_trim_val').textContent = parseFloat(val).toFixed(1);
        socket.emit('update', { hf_trim_db: val });
    }
    function updateHfTrimHz(val) { socket.emit('update', { hf_trim_hz: val }); }
    function updateProcessingRate(val) { socket.emit('update', { processing_rate_hz: val }); }
    function toggleBypass() {
        const btn = document.getElementById('bypassBtn');
        const active = btn?.classList.contains('on');
        socket.emit('update', { processing_bypass: !active });
    }
    function updateMultibandEnabled(val) { socket.emit('update', { multiband_enabled: val }); }
    function updateMultibandLowThreshold(val) { socket.emit('update', { multiband_low_threshold_db: val }); }
    function updateMultibandLowRatio(val) { socket.emit('update', { multiband_low_ratio: val }); }
    function updateMultibandLowAttack(val) { socket.emit('update', { multiband_low_attack_ms: val }); }
    function updateMultibandLowRelease(val) { socket.emit('update', { multiband_low_release_ms: val }); }
    function updateMultibandMidThreshold(val) { socket.emit('update', { multiband_mid_threshold_db: val }); }
    function updateMultibandMidRatio(val) { socket.emit('update', { multiband_mid_ratio: val }); }
    function updateMultibandMidAttack(val) { socket.emit('update', { multiband_mid_attack_ms: val }); }
    function updateMultibandMidRelease(val) { socket.emit('update', { multiband_mid_release_ms: val }); }
    function updateMultibandHighThreshold(val) { socket.emit('update', { multiband_high_threshold_db: val }); }
    function updateMultibandHighRatio(val) { socket.emit('update', { multiband_high_ratio: val }); }
    function updateMultibandHighAttack(val) { socket.emit('update', { multiband_high_attack_ms: val }); }
    function updateMultibandHighRelease(val) { socket.emit('update', { multiband_high_release_ms: val }); }
    function updateWidenEnabled(val) { socket.emit('update', { stereo_widen_enabled: val }); }
    function updateWidenWidth(val) {
        document.getElementById('mpx_widen_width_val').textContent = parseFloat(val).toFixed(2);
        socket.emit('update', { stereo_widen_width: val });
    }
    function updateWidenCenter(val) {
        document.getElementById('mpx_widen_center_val').textContent = parseFloat(val).toFixed(2);
        socket.emit('update', { stereo_widen_center: val });
    }
    function updateWidenMix(val) {
        document.getElementById('mpx_widen_mix_val').textContent = parseFloat(val).toFixed(2);
        socket.emit('update', { stereo_widen_mix: val });
    }
    function updatePreemphasisLimiter(val) { socket.emit('update', { preemphasis_limit_enabled: val }); }
    function updatePreemphasisThreshold(val) {
        document.getElementById('mpx_preemph_val').textContent = parseFloat(val).toFixed(2);
        socket.emit('update', { preemphasis_limit_threshold: val });
    }
    function updateCompositeClipper(val) { socket.emit('update', { composite_clip_enabled: val }); }
    function updateCompositeThreshold(val) {
        document.getElementById('mpx_comp_val').textContent = parseFloat(val).toFixed(2);
        socket.emit('update', { composite_clip_threshold: val });
    }
    function updateInputGain(val) {
        document.getElementById('mpx_input_gain_val').textContent = parseFloat(val).toFixed(1);
        socket.emit('update', { input_gain_db: val });
    }
    function updateLimitMpx(val) { socket.emit('update', { limit_mpx: val }); }
    function updateLimitLookahead(val) { socket.emit('update', { limit_lookahead_enabled: val }); }
    function updateLimitLookaheadMs(val) { socket.emit('update', { limit_lookahead_ms: val }); }
    function updateOutputEnabled(val) { socket.emit('update', { output_enabled: val }); }
    function updateLimitThreshold(val) {
        document.getElementById('mpx_limit_val').textContent = parseFloat(val).toFixed(2);
        socket.emit('update', { limit_threshold: val });
    }
    function updateRdsEnable(enabled) {
        socket.emit('update', { en_rds: enabled });
    }

    const mpxDevIn = document.getElementById('mpx_dev_in');
    const mpxDevOut = document.getElementById('mpx_dev_out');

    if (mpxDevIn) {
        mpxDevIn.addEventListener('change', (e) => {
            socket.emit('update', { device_in_idx: e.target.value });
        });
    }
    if (mpxDevOut) {
        mpxDevOut.addEventListener('change', (e) => {
            socket.emit('update', { device_out_idx: e.target.value });
        });
    }

    function updateSourceVisibility() {
        const mode = document.getElementById('mpx_source_mode').value;
        const toneFields = document.getElementById('mpx_tone_fields');
        const toneFreqField = document.getElementById('mpx_tone_freq_field');
        if (mode === 'tone') {
            toneFields.style.display = 'block';
            toneFreqField.style.display = 'block';
        } else {
            toneFields.style.display = 'none';
            toneFreqField.style.display = 'none';
        }
    }

    function drawScope(canvasId, samples) {
        const canvas = document.getElementById(canvasId);
        if (!canvas || !samples.length) return;
        const ctx = canvas.getContext('2d');
        if (!ctx) return;
        const w = canvas.width;
        const h = canvas.height;
        ctx.clearRect(0, 0, w, h);
        ctx.strokeStyle = '#22c55e';
        ctx.lineWidth = 1;
        ctx.beginPath();
        const mid = h / 2;
        const step = samples.length > 1 ? (w / (samples.length - 1)) : w;
        for (let i = 0; i < samples.length; i += 1) {
            const x = i * step;
            const y = mid - (samples[i] * (h * 0.45));
            if (i === 0) {
                ctx.moveTo(x, y);
            } else {
                ctx.lineTo(x, y);
            }
        }
        ctx.stroke();
    }

    function togglePower() {
        const devOut = mpxDevOut ? mpxDevOut.value : 0;
        const devIn = mpxDevIn ? mpxDevIn.value : -1;
        if (!running) {
            socket.emit('control', { action: 'start', dev_out: devOut, dev_in: devIn });
        } else {
            socket.emit('control', { action: 'stop' });
        }
    }

    let lastMonitorUpdateMs = 0;
    let monitorPollBusy = false;

    function applyMonitorData(data) {
        lastMonitorUpdateMs = Date.now();
        const hb = document.getElementById('heartbeat');
        if (hb) hb.style.opacity = hb.style.opacity === '0.3' ? '1' : '0.3';
        running = data.running;
        const pwr = document.getElementById('pwrBtn');
        if (running) {
            pwr.classList.add('on');
            pwr.textContent = 'ON AIR';
        } else {
            pwr.classList.remove('on');
            pwr.textContent = 'OFF AIR';
        }
        if (typeof data.processing_bypass !== 'undefined') {
            const bypassBtn = document.getElementById('bypassBtn');
            if (bypassBtn) {
                if (data.processing_bypass) {
                    bypassBtn.classList.add('on');
                    bypassBtn.textContent = 'BYPASS ON';
                } else {
                    bypassBtn.classList.remove('on');
                    bypassBtn.textContent = 'BYPASS';
                }
            }
        }
        const inputMeterL = document.getElementById('mpx_input_meter_l');
        const inputMeterR = document.getElementById('mpx_input_meter_r');
        const mpxMeter = document.getElementById('mpx_mpx_meter');
        const inputDb = document.getElementById('mpx_input_db');
        const mpxDb = document.getElementById('mpx_mpx_db');
        const inputPeak = document.getElementById('mpx_input_peak');
        const mpxPeak = document.getElementById('mpx_mpx_peak');
        const inputVuL = document.getElementById('mpx_input_vu_l');
        const inputVuR = document.getElementById('mpx_input_vu_r');
        const mpxVu = document.getElementById('mpx_mpx_vu');
        const modMeter = document.getElementById('modulation_meter');
        const modKHz = document.getElementById('modulation_khz');
        const inputLevel = Math.min(1.0, Math.max(0.0, data.input_rms || 0));
        const inputLevelL = Math.min(1.0, Math.max(0.0, data.input_rms_l || 0));
        const inputLevelR = Math.min(1.0, Math.max(0.0, data.input_rms_r || 0));
        const mpxLevel = Math.min(1.0, Math.max(0.0, data.mpx_rms || 0));
        const inputPk = Math.min(1.0, Math.max(0.0, data.input_peak || 0));
        const mpxPkRaw = data.mpx_peak || 0;
        const mpxPk = Math.min(1.0, Math.max(0.0, mpxPkRaw));
        const inputVuVal = Math.min(1.0, Math.max(0.0, data.input_vu || 0));
        const inputVuLVal = Math.min(1.0, Math.max(0.0, data.input_vu_l || inputVuVal));
        const inputVuRVal = Math.min(1.0, Math.max(0.0, data.input_vu_r || inputVuVal));
        const mpxVuVal = Math.min(1.0, Math.max(0.0, data.mpx_vu || 0));
        const devEl = document.getElementById('mpx_deviation_khz');
        const maxDev = devEl ? parseFloat(devEl.value || '75') : 75.0;
        const modDev = mpxPkRaw * maxDev;
        const modPct = Math.min(1.0, Math.max(0.0, modDev / 100.0));
        const meterScale = (v) => Math.min(1.0, Math.max(0.0, Math.pow(v, 0.5)));
        if (inputMeterL) inputMeterL.style.width = `${Math.round(meterScale(inputLevelL) * 100)}%`;
        if (inputMeterR) inputMeterR.style.width = `${Math.round(meterScale(inputLevelR) * 100)}%`;
        if (mpxMeter) mpxMeter.style.width = `${Math.round(meterScale(mpxLevel) * 100)}%`;
        if (modMeter) modMeter.style.width = `${Math.round(modPct * 100)}%`;
        const toDb = (v) => {
            const n = Number(v);
            if (!Number.isFinite(n)) return '--';
            return n > 1e-6 ? (20 * Math.log10(n)).toFixed(1) : '-inf';
        };
        if (inputDb) inputDb.textContent = `${toDb(inputLevel)} dBFS`;
        if (mpxDb) mpxDb.textContent = `${toDb(mpxLevel)} dBFS`;
        if (inputPeak) inputPeak.textContent = `${toDb(inputPk)} pk`;
        if (mpxPeak) mpxPeak.textContent = `${toDb(mpxPk)} pk`;
        if (inputVuL) inputVuL.textContent = `L ${toDb(inputVuLVal)} VU`;
        if (inputVuR) inputVuR.textContent = `R ${toDb(inputVuRVal)} VU`;
        if (mpxVu) mpxVu.textContent = `${toDb(mpxVuVal)} VU`;
        if (modKHz) {
            modKHz.textContent = `${modDev.toFixed(1)} kHz`;
            if (modDev > maxDev) {
                modKHz.classList.add('text-red-400');
                modKHz.classList.remove('text-gray-400');
            } else {
                modKHz.classList.remove('text-red-400');
            }
        }

        const setText = (id, v) => {
            const el = document.getElementById(id);
            if (!el) return;
            if (v === undefined || v === null || v === '') {
                el.innerText = '—';
                return;
            }
            el.innerText = v;
        };
        setText('live_ps', data.ps);
        setText('live_rt', data.rt);
        setText('live_lps', data.lps);
        setText('live_ptyn', data.ptyn);
        setText('live_af', data.af);
        setText('live_rt_plus', data.rt_plus_info);
        setText('live_pi', data.pi);
        setText('live_pty', ptyList[data.pty_idx] || "None");
        if (data.device_out_name || data.device_in_name) {
            const outName = data.device_out_name || 'None';
            const inName = data.device_in_name || 'None';
            setText('live_device_out', inName);
            setText('live_device_in', outName);
        } else {
            setText('live_device_out', '—');
            setText('live_device_in', '—');
        }
        if (typeof data.limiter_active !== 'undefined') {
            setText('live_limiter', data.limiter_active ? 'Limiting' : 'Idle');
        }
        const onOffText = (enabled) => (enabled ? 'On' : 'Off');
        if (typeof data.multiband_enabled !== 'undefined') {
            setText('live_multiband', onOffText(data.multiband_enabled));
        }
        if (typeof data.stereo_widen_enabled !== 'undefined') {
            setText('live_widener', onOffText(data.stereo_widen_enabled));
        }
        if (typeof data.preemph_limit_enabled !== 'undefined') {
            setText('live_preemph_limit', onOffText(data.preemph_limit_enabled));
        }
        if (typeof data.composite_clip_enabled !== 'undefined') {
            setText('live_composite_clip', onOffText(data.composite_clip_enabled));
        }
        if (Array.isArray(data.input_wave)) {
            drawScope('scope_input', data.input_wave);
        }
        if (Array.isArray(data.mpx_wave)) {
            drawScope('scope_mpx', data.mpx_wave);
        }
        if (typeof data.pilot_generated !== 'undefined') {
            setText('pilot_status', data.pilot_generated ? 'Generated' : 'Disabled');
            setText('live_pilot', data.pilot_generated ? 'On' : 'Off');
        }
        if (typeof data.rds_carrier !== 'undefined') {
            setText('live_rds_carrier', data.rds_carrier ? 'On' : 'Off');
        }
        updateDeviationLabels();
    }

    async function pollMonitorFallback() {
        if (monitorPollBusy) return;
        if ((Date.now() - lastMonitorUpdateMs) < 1500) return;
        monitorPollBusy = true;
        try {
            const res = await fetch('/monitor_snapshot', {
                method: 'GET',
                credentials: 'same-origin',
                cache: 'no-store',
            });
            if (res.ok) {
                const data = await res.json();
                applyMonitorData(data);
            }
        } catch (e) {
            // Ignore fallback fetch errors; websocket may recover.
        } finally {
            monitorPollBusy = false;
        }
    }

    socket.on('connect', () => {
        const hb = document.getElementById('heartbeat');
        if (hb) hb.style.opacity = '1';
    });

    socket.on('disconnect', () => {
        const hb = document.getElementById('heartbeat');
        if (hb) hb.style.opacity = '0.2';
    });

    socket.on('monitor', applyMonitorData);
    setInterval(pollMonitorFallback, 1000);

    function updateRTVisibility() {
        const manual = document.getElementById('rt_manual_buffers');
        const singleMode = document.getElementById('rt_single_mode');
        const dualMode = document.getElementById('rt_dual_mode');
        const rtPlusSingle = document.getElementById('rt_plus_single_mode');
        const rtPlusDual = document.getElementById('rt_plus_dual_mode');
        if (!manual || !singleMode || !dualMode) return;
        const enabled = manual.checked;
        singleMode.style.display = enabled ? 'none' : 'block';
        dualMode.style.display = enabled ? 'block' : 'none';
        if (rtPlusSingle) rtPlusSingle.style.display = enabled ? 'none' : 'block';
        if (rtPlusDual) rtPlusDual.style.display = enabled ? 'block' : 'none';
    }

    function updateCycleControls() {
        const cycleEl = document.getElementById('rt_cycle_ab');
        const timeWrap = document.getElementById('time_seconds_wrap');
        const cyclesWrap = document.getElementById('rt_cycles_wrap');
        const manualEl = document.getElementById('rt_manual_buffers');
        const dualCycleEl = document.getElementById('rt_cycle');
        const activeWrap = document.getElementById('rt_active_wrap');
        if (!timeWrap || !cyclesWrap) return;
        const manual = manualEl ? manualEl.checked : false;
        if (manual && dualCycleEl) {
            timeWrap.style.display = dualCycleEl.checked ? 'block' : 'none';
            cyclesWrap.style.display = 'none';
            if (activeWrap) activeWrap.style.display = dualCycleEl.checked ? 'none' : 'flex';
            return;
        }
        if (!cycleEl) return;
        const cycleAB = cycleEl.checked;
        timeWrap.style.display = cycleAB ? 'none' : 'block';
        cyclesWrap.style.display = cycleAB ? 'block' : 'none';
        if (activeWrap) activeWrap.style.display = 'none';
    }

    async function saveSettings() {
        const statusEl = document.getElementById('settings_status');
        if (statusEl) statusEl.innerText = 'Saving...';
        const payload = {
            user: document.getElementById('auth_user').value.trim(),
            allow_subnets: document.getElementById('allow_subnets')?.value.trim() || ''
        };
        const passEl = document.getElementById('auth_pass');
        if (passEl && passEl.value.trim()) payload.password = passEl.value.trim();
        try {
            const res = await fetch('/settings', {
                method: 'POST',
                credentials: 'same-origin',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify(payload)
            });
            if (res.ok) {
                if (statusEl) statusEl.innerText = 'Saved. Password updated if provided.';
                if (passEl) passEl.value = '';
            } else {
                if (statusEl) statusEl.innerText = 'Save failed (unauthorized or server error).';
            }
        } catch (e) {
            if (statusEl) statusEl.innerText = 'Save failed (network error).';
        }
    }

    function sync() {
        const getVal = (id) => {
            let el = document.getElementById(id);
            if (!el) return null;
            if (el.type === 'checkbox') return el.checked;
            if (el.type === 'number' || el.type === 'range') return parseFloat(el.value);
            return el.value;
        };
        const getTextVal = (id) => {
            const el = document.getElementById(id);
            return el ? el.value : '';
        };
        const getRTPlusFormatA = () => {
            const manual = Boolean(getVal('rt_manual_buffers'));
            if (manual) {
                return getTextVal('rt_plus_format_a_dual');
            }
            return getTextVal('rt_plus_format_a_single') || getTextVal('rt_plus_format_a_dual');
        };

        const setValText = (valId, srcId) => {
            const valEl = document.getElementById(valId);
            const srcEl = document.getElementById(srcId);
            if (valEl && srcEl) valEl.innerText = srcEl.value;
        };
        setValText('val_rds', 'rds_level');
        setValText('val_pilot', 'pilot_level');
        updateDeviationLabels();

        let data = {
            rds_level: getVal('rds_level'),
            pilot_level: getVal('pilot_level'),
            pi: getVal('pi'), pty: getVal('pty'), tp: getVal('tp'), ta: getVal('ta'), ms: getVal('ms'),
            di_stereo: getVal('di_stereo'), di_head: getVal('di_head'), di_comp: getVal('di_comp'), di_dyn: getVal('di_dyn'), en_af: getVal('en_af'), af_list: getVal('af_list'),
            ps_dynamic: getVal('ps_dynamic'), ps_centered: getVal('ps_centered'),
            rt_text: getVal('rt_text'), rt_manual_buffers: getVal('rt_manual_buffers'), rt_cycle_ab: getVal('rt_cycle_ab'),
            rt_a: getVal('rt_a'), rt_b: getVal('rt_b'), rt_mode: getVal('rt_mode'),
            rt_cycle: getVal('rt_cycle'), rt_active_buffer: getVal('rt_active_buffer'), rt_centered: getVal('rt_centered'), rt_cr: getVal('rt_cr'),
            rt_cycle_time: getVal('rt_cycle_time'),
            rt_ab_cycle_count: getVal('rt_ab_cycle_count'),
            rt_plus_format_a: getRTPlusFormatA(),
            rt_plus_format_b: getVal('rt_plus_format_b'),
            en_rt_plus: getVal('en_rt_plus'),
            ptyn: getVal('ptyn'), en_ptyn: getVal('en_ptyn'), ptyn_centered: getVal('ptyn_centered'),
            ecc: getVal('ecc'), lic: getVal('lic'), tz_offset: getVal('tz_offset'), en_ct: getVal('en_ct'), en_id: getVal('en_id'),
            ps_long_32: getVal('ps_long_32'), en_lps: getVal('en_lps'), lps_centered: getVal('lps_centered'), lps_cr: getVal('lps_cr'),
            group_sequence: getVal('group_sequence'), scheduler_auto: getVal('scheduler_auto'), scheduler_standard: getVal('scheduler_standard'), scheduler_standard_lps: getVal('scheduler_standard_lps')
        };
        socket.emit('update', data);
    }

    setInterval(() => {
        updateCycleControls();
    }, 1000);

    updateSourceVisibility();
    updateRTVisibility();
    updateCycleControls();
    updateDeviationLabels();
