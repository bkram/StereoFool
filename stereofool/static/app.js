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
    function updateMonitorDspParallel(enabled) {
        socket.emit('update', { monitor_dsp_parallel: enabled });
    }
    function updateDropoutGuard(enabled) {
        socket.emit('update', { dropout_guard_enabled: enabled });
    }
    function updateBlocksize(value) {
        socket.emit('update', { blocksize: Number(value) });
    }
    function updateAudioPriorityProfile(value) {
        socket.emit('update', { audio_priority_profile: value });
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
    function updateMultibandMode(val) { socket.emit('update', { multiband_mode: Number(val) }); }
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
    function updateMultibandKnee(val) {
        document.getElementById('mpx_mb_knee_val').textContent = parseFloat(val).toFixed(1);
        socket.emit('update', { multiband_knee_db: parseFloat(val) });
    }
    function updateMultibandLinkStrength(val) {
        document.getElementById('mpx_mb_link_val').textContent = parseFloat(val).toFixed(2);
        socket.emit('update', { multiband_link_strength: parseFloat(val) });
    }
    function updateMultibandMakeup(val) {
        document.getElementById('mpx_mb_makeup_val').textContent = parseFloat(val).toFixed(1);
        socket.emit('update', { multiband_makeup_db: parseFloat(val) });
    }
    function updateMultibandReleaseProgramDependent(val) {
        socket.emit('update', { multiband_release_program_dependent: val });
    }
    function updateOrbassEnabled(val) { socket.emit('update', { orbass_enabled: val }); }
    function updateOrbassAmount(val) {
        document.getElementById('mpx_orbass_amount_val').textContent = parseFloat(val).toFixed(2);
        socket.emit('update', { orbass_amount: parseFloat(val) });
    }
    function updateOrbassFreq(val) {
        document.getElementById('mpx_orbass_freq_val').textContent = `${Math.round(parseFloat(val))}`;
        socket.emit('update', { orbass_freq_hz: parseFloat(val) });
    }
    function updateOrbassHarmonics(val) {
        document.getElementById('mpx_orbass_harmonics_val').textContent = parseFloat(val).toFixed(2);
        socket.emit('update', { orbass_harmonics: parseFloat(val) });
    }
    function updateOrbassDrive(val) {
        document.getElementById('mpx_orbass_drive_val').textContent = parseFloat(val).toFixed(2);
        socket.emit('update', { orbass_drive: parseFloat(val) });
    }
    function updateOrbassDensity(val) {
        document.getElementById('mpx_orbass_density_val').textContent = parseFloat(val).toFixed(2);
        socket.emit('update', { orbass_density: parseFloat(val) });
    }
    function updateOrbassSubharmonicsEnabled(val) {
        socket.emit('update', { orbass_subharmonics_enabled: val });
    }
    function updateOrbassSubharmonicsAmount(val) {
        document.getElementById('mpx_orbass_subharmonics_amount_val').textContent = parseFloat(val).toFixed(2);
        socket.emit('update', { orbass_subharmonics_amount: parseFloat(val) });
    }
    function applyOrbassPreset(name) {
        const presets = {
            chr: {
                orbass_enabled: true,
                orbass_amount: 0.76,
                orbass_freq_hz: 70,
                orbass_harmonics: 0.78,
                orbass_drive: 1.45,
                orbass_density: 0.86,
                orbass_subharmonics_enabled: true,
                orbass_subharmonics_amount: 0.55,
            },
            urban: {
                orbass_enabled: true,
                orbass_amount: 0.72,
                orbass_freq_hz: 68,
                orbass_harmonics: 0.74,
                orbass_drive: 1.35,
                orbass_density: 0.82,
                orbass_subharmonics_enabled: true,
                orbass_subharmonics_amount: 0.52,
            },
            rock: {
                orbass_enabled: true,
                orbass_amount: 0.58,
                orbass_freq_hz: 84,
                orbass_harmonics: 0.44,
                orbass_drive: 1.18,
                orbass_density: 0.72,
                orbass_subharmonics_enabled: true,
                orbass_subharmonics_amount: 0.34,
            },
            ac: {
                orbass_enabled: true,
                orbass_amount: 0.42,
                orbass_freq_hz: 94,
                orbass_harmonics: 0.30,
                orbass_drive: 1.00,
                orbass_density: 0.66,
                orbass_subharmonics_enabled: false,
                orbass_subharmonics_amount: 0.20,
            },
            talk: {
                orbass_enabled: true,
                orbass_amount: 0.22,
                orbass_freq_hz: 118,
                orbass_harmonics: 0.16,
                orbass_drive: 0.72,
                orbass_density: 0.55,
                orbass_subharmonics_enabled: false,
                orbass_subharmonics_amount: 0.10,
            },
        };
        const p = presets[name];
        if (!p) return;
        const enEl = document.getElementById('mpx_orbass_enabled');
        const amountEl = document.getElementById('mpx_orbass_amount');
        const freqEl = document.getElementById('mpx_orbass_freq_hz');
        const harmEl = document.getElementById('mpx_orbass_harmonics');
        const driveEl = document.getElementById('mpx_orbass_drive');
        const densityEl = document.getElementById('mpx_orbass_density');
        const subEnableEl = document.getElementById('mpx_orbass_subharmonics_enabled');
        const subAmountEl = document.getElementById('mpx_orbass_subharmonics_amount');
        const amountValEl = document.getElementById('mpx_orbass_amount_val');
        const freqValEl = document.getElementById('mpx_orbass_freq_val');
        const harmValEl = document.getElementById('mpx_orbass_harmonics_val');
        const driveValEl = document.getElementById('mpx_orbass_drive_val');
        const densityValEl = document.getElementById('mpx_orbass_density_val');
        const subAmountValEl = document.getElementById('mpx_orbass_subharmonics_amount_val');
        if (enEl) enEl.checked = Boolean(p.orbass_enabled);
        if (amountEl) amountEl.value = String(p.orbass_amount);
        if (freqEl) freqEl.value = String(p.orbass_freq_hz);
        if (harmEl) harmEl.value = String(p.orbass_harmonics);
        if (driveEl) driveEl.value = String(p.orbass_drive);
        if (densityEl) densityEl.value = String(p.orbass_density);
        if (subEnableEl) subEnableEl.checked = Boolean(p.orbass_subharmonics_enabled);
        if (subAmountEl) subAmountEl.value = String(p.orbass_subharmonics_amount);
        if (amountValEl) amountValEl.textContent = Number(p.orbass_amount).toFixed(2);
        if (freqValEl) freqValEl.textContent = `${Math.round(Number(p.orbass_freq_hz))}`;
        if (harmValEl) harmValEl.textContent = Number(p.orbass_harmonics).toFixed(2);
        if (driveValEl) driveValEl.textContent = Number(p.orbass_drive).toFixed(2);
        if (densityValEl) densityValEl.textContent = Number(p.orbass_density).toFixed(2);
        if (subAmountValEl) subAmountValEl.textContent = Number(p.orbass_subharmonics_amount).toFixed(2);
        socket.emit('update', p);
    }
    function applyMultibandPreset(name) {
        const clampNum = (value, min, max) => Math.min(max, Math.max(min, Number(value)));
        const getPresetIntensityCurve = () => {
            const el = document.getElementById('mpx_mb_preset_intensity');
            const mode = String((el && el.value) || 'normal').toLowerCase();
            if (mode === 'light') {
                return { thresholdDbOffset: 1.5, ratioMul: 0.9, attackMul: 1.2, releaseMul: 1.15 };
            }
            if (mode === 'heavy') {
                return { thresholdDbOffset: -1.5, ratioMul: 1.12, attackMul: 0.88, releaseMul: 0.9 };
            }
            return { thresholdDbOffset: 0.0, ratioMul: 1.0, attackMul: 1.0, releaseMul: 1.0 };
        };
        const presets = {
            '3_chr': {
                multiband_enabled: true,
                multiband_mode: 3,
                multiband_low_hz: 260,
                multiband_high_hz: 2300,
                multiband_low_threshold_db: -25,
                multiband_low_ratio: 2.6,
                multiband_low_attack_ms: 18,
                multiband_low_release_ms: 290,
                multiband_mid_threshold_db: -23,
                multiband_mid_ratio: 2.3,
                multiband_mid_attack_ms: 12,
                multiband_mid_release_ms: 220,
                multiband_high_threshold_db: -21,
                multiband_high_ratio: 1.8,
                multiband_high_attack_ms: 7,
                multiband_high_release_ms: 150,
            },
            '3_rock': {
                multiband_enabled: true,
                multiband_mode: 3,
                multiband_low_hz: 290,
                multiband_high_hz: 2400,
                multiband_low_threshold_db: -23,
                multiband_low_ratio: 2.4,
                multiband_low_attack_ms: 20,
                multiband_low_release_ms: 310,
                multiband_mid_threshold_db: -20,
                multiband_mid_ratio: 2.2,
                multiband_mid_attack_ms: 13,
                multiband_mid_release_ms: 230,
                multiband_high_threshold_db: -18,
                multiband_high_ratio: 1.7,
                multiband_high_attack_ms: 8,
                multiband_high_release_ms: 165,
            },
            '3_ac': {
                multiband_enabled: true,
                multiband_mode: 3,
                multiband_low_hz: 310,
                multiband_high_hz: 2550,
                multiband_low_threshold_db: -20,
                multiband_low_ratio: 2.0,
                multiband_low_attack_ms: 24,
                multiband_low_release_ms: 340,
                multiband_mid_threshold_db: -18,
                multiband_mid_ratio: 1.8,
                multiband_mid_attack_ms: 16,
                multiband_mid_release_ms: 260,
                multiband_high_threshold_db: -17,
                multiband_high_ratio: 1.4,
                multiband_high_attack_ms: 10,
                multiband_high_release_ms: 190,
            },
            '3_country': {
                multiband_enabled: true,
                multiband_mode: 3,
                multiband_low_hz: 300,
                multiband_high_hz: 2450,
                multiband_low_threshold_db: -21,
                multiband_low_ratio: 2.2,
                multiband_low_attack_ms: 22,
                multiband_low_release_ms: 320,
                multiband_mid_threshold_db: -19,
                multiband_mid_ratio: 1.9,
                multiband_mid_attack_ms: 15,
                multiband_mid_release_ms: 250,
                multiband_high_threshold_db: -17,
                multiband_high_ratio: 1.5,
                multiband_high_attack_ms: 10,
                multiband_high_release_ms: 185,
            },
            '3_talk': {
                multiband_enabled: true,
                multiband_mode: 3,
                multiband_low_hz: 340,
                multiband_high_hz: 3000,
                multiband_low_threshold_db: -16,
                multiband_low_ratio: 1.6,
                multiband_low_attack_ms: 34,
                multiband_low_release_ms: 420,
                multiband_mid_threshold_db: -15,
                multiband_mid_ratio: 1.5,
                multiband_mid_attack_ms: 28,
                multiband_mid_release_ms: 340,
                multiband_high_threshold_db: -14,
                multiband_high_ratio: 1.3,
                multiband_high_attack_ms: 18,
                multiband_high_release_ms: 270,
            },
            '3_urban': {
                multiband_enabled: true,
                multiband_mode: 3,
                multiband_low_hz: 250,
                multiband_high_hz: 2200,
                multiband_low_threshold_db: -24,
                multiband_low_ratio: 2.7,
                multiband_low_attack_ms: 16,
                multiband_low_release_ms: 280,
                multiband_mid_threshold_db: -22,
                multiband_mid_ratio: 2.4,
                multiband_mid_attack_ms: 11,
                multiband_mid_release_ms: 210,
                multiband_high_threshold_db: -20,
                multiband_high_ratio: 1.9,
                multiband_high_attack_ms: 6,
                multiband_high_release_ms: 145,
            },
            '3_dance': {
                multiband_enabled: true,
                multiband_mode: 3,
                multiband_low_hz: 240,
                multiband_high_hz: 2100,
                multiband_low_threshold_db: -26,
                multiband_low_ratio: 2.9,
                multiband_low_attack_ms: 14,
                multiband_low_release_ms: 260,
                multiband_mid_threshold_db: -24,
                multiband_mid_ratio: 2.6,
                multiband_mid_attack_ms: 10,
                multiband_mid_release_ms: 200,
                multiband_high_threshold_db: -22,
                multiband_high_ratio: 2.0,
                multiband_high_attack_ms: 5,
                multiband_high_release_ms: 135,
            },
            '3_news': {
                multiband_enabled: true,
                multiband_mode: 3,
                multiband_low_hz: 360,
                multiband_high_hz: 3200,
                multiband_low_threshold_db: -15,
                multiband_low_ratio: 1.4,
                multiband_low_attack_ms: 38,
                multiband_low_release_ms: 480,
                multiband_mid_threshold_db: -14,
                multiband_mid_ratio: 1.35,
                multiband_mid_attack_ms: 30,
                multiband_mid_release_ms: 390,
                multiband_high_threshold_db: -13,
                multiband_high_ratio: 1.25,
                multiband_high_attack_ms: 22,
                multiband_high_release_ms: 320,
            },
            '3_jazz': {
                multiband_enabled: true,
                multiband_mode: 3,
                multiband_low_hz: 330,
                multiband_high_hz: 2800,
                multiband_low_threshold_db: -18,
                multiband_low_ratio: 1.7,
                multiband_low_attack_ms: 30,
                multiband_low_release_ms: 420,
                multiband_mid_threshold_db: -17,
                multiband_mid_ratio: 1.55,
                multiband_mid_attack_ms: 24,
                multiband_mid_release_ms: 330,
                multiband_high_threshold_db: -16,
                multiband_high_ratio: 1.35,
                multiband_high_attack_ms: 16,
                multiband_high_release_ms: 250,
            },
            '3_classic': {
                multiband_enabled: true,
                multiband_mode: 3,
                multiband_low_hz: 360,
                multiband_high_hz: 3400,
                multiband_low_threshold_db: -14,
                multiband_low_ratio: 1.35,
                multiband_low_attack_ms: 42,
                multiband_low_release_ms: 520,
                multiband_mid_threshold_db: -13,
                multiband_mid_ratio: 1.3,
                multiband_mid_attack_ms: 36,
                multiband_mid_release_ms: 430,
                multiband_high_threshold_db: -12,
                multiband_high_ratio: 1.2,
                multiband_high_attack_ms: 26,
                multiband_high_release_ms: 340,
            },
            '5_chr': {
                multiband_enabled: true,
                multiband_mode: 5,
                multiband_x1_hz: 80,
                multiband_x2_hz: 300,
                multiband_x3_hz: 1250,
                multiband_x4_hz: 5000,
                multiband_low_threshold_db: -25,
                multiband_low_ratio: 2.8,
                multiband_low_attack_ms: 14,
                multiband_low_release_ms: 270,
                multiband_mid_threshold_db: -23,
                multiband_mid_ratio: 2.4,
                multiband_mid_attack_ms: 10,
                multiband_mid_release_ms: 210,
                multiband_high_threshold_db: -21,
                multiband_high_ratio: 1.9,
                multiband_high_attack_ms: 5,
                multiband_high_release_ms: 140,
            },
            '5_rock': {
                multiband_enabled: true,
                multiband_mode: 5,
                multiband_x1_hz: 85,
                multiband_x2_hz: 320,
                multiband_x3_hz: 1400,
                multiband_x4_hz: 5400,
                multiband_low_threshold_db: -23,
                multiband_low_ratio: 2.5,
                multiband_low_attack_ms: 18,
                multiband_low_release_ms: 300,
                multiband_mid_threshold_db: -21,
                multiband_mid_ratio: 2.1,
                multiband_mid_attack_ms: 12,
                multiband_mid_release_ms: 225,
                multiband_high_threshold_db: -19,
                multiband_high_ratio: 1.8,
                multiband_high_attack_ms: 7,
                multiband_high_release_ms: 160,
            },
            '5_ac': {
                multiband_enabled: true,
                multiband_mode: 5,
                multiband_x1_hz: 80,
                multiband_x2_hz: 320,
                multiband_x3_hz: 1500,
                multiband_x4_hz: 5800,
                multiband_low_threshold_db: -20,
                multiband_low_ratio: 1.9,
                multiband_low_attack_ms: 22,
                multiband_low_release_ms: 330,
                multiband_mid_threshold_db: -18,
                multiband_mid_ratio: 1.8,
                multiband_mid_attack_ms: 14,
                multiband_mid_release_ms: 260,
                multiband_high_threshold_db: -17,
                multiband_high_ratio: 1.5,
                multiband_high_attack_ms: 10,
                multiband_high_release_ms: 190,
            },
            '5_classic': {
                multiband_enabled: true,
                multiband_mode: 5,
                multiband_x1_hz: 90,
                multiband_x2_hz: 360,
                multiband_x3_hz: 1700,
                multiband_x4_hz: 6500,
                multiband_low_threshold_db: -17,
                multiband_low_ratio: 1.5,
                multiband_low_attack_ms: 36,
                multiband_low_release_ms: 450,
                multiband_mid_threshold_db: -16,
                multiband_mid_ratio: 1.4,
                multiband_mid_attack_ms: 30,
                multiband_mid_release_ms: 360,
                multiband_high_threshold_db: -15,
                multiband_high_ratio: 1.25,
                multiband_high_attack_ms: 20,
                multiband_high_release_ms: 280,
            },
            '5_talk': {
                multiband_enabled: true,
                multiband_mode: 5,
                multiband_x1_hz: 100,
                multiband_x2_hz: 400,
                multiband_x3_hz: 1800,
                multiband_x4_hz: 7000,
                multiband_low_threshold_db: -16,
                multiband_low_ratio: 1.5,
                multiband_low_attack_ms: 38,
                multiband_low_release_ms: 480,
                multiband_mid_threshold_db: -15,
                multiband_mid_ratio: 1.4,
                multiband_mid_attack_ms: 32,
                multiband_mid_release_ms: 380,
                multiband_high_threshold_db: -14,
                multiband_high_ratio: 1.2,
                multiband_high_attack_ms: 22,
                multiband_high_release_ms: 300,
            },
            '5_urban': {
                multiband_enabled: true,
                multiband_mode: 5,
                multiband_x1_hz: 75,
                multiband_x2_hz: 280,
                multiband_x3_hz: 1100,
                multiband_x4_hz: 4700,
                multiband_low_threshold_db: -24,
                multiband_low_ratio: 2.7,
                multiband_low_attack_ms: 14,
                multiband_low_release_ms: 270,
                multiband_mid_threshold_db: -22,
                multiband_mid_ratio: 2.3,
                multiband_mid_attack_ms: 10,
                multiband_mid_release_ms: 205,
                multiband_high_threshold_db: -20,
                multiband_high_ratio: 1.9,
                multiband_high_attack_ms: 5,
                multiband_high_release_ms: 140,
            },
            '5_dance': {
                multiband_enabled: true,
                multiband_mode: 5,
                multiband_x1_hz: 70,
                multiband_x2_hz: 260,
                multiband_x3_hz: 1000,
                multiband_x4_hz: 4300,
                multiband_low_threshold_db: -26,
                multiband_low_ratio: 3.0,
                multiband_low_attack_ms: 12,
                multiband_low_release_ms: 250,
                multiband_mid_threshold_db: -24,
                multiband_mid_ratio: 2.6,
                multiband_mid_attack_ms: 9,
                multiband_mid_release_ms: 190,
                multiband_high_threshold_db: -22,
                multiband_high_ratio: 2.1,
                multiband_high_attack_ms: 4,
                multiband_high_release_ms: 130,
            },
            '5_news': {
                multiband_enabled: true,
                multiband_mode: 5,
                multiband_x1_hz: 110,
                multiband_x2_hz: 450,
                multiband_x3_hz: 2100,
                multiband_x4_hz: 7600,
                multiband_low_threshold_db: -15,
                multiband_low_ratio: 1.4,
                multiband_low_attack_ms: 40,
                multiband_low_release_ms: 500,
                multiband_mid_threshold_db: -14,
                multiband_mid_ratio: 1.35,
                multiband_mid_attack_ms: 34,
                multiband_mid_release_ms: 400,
                multiband_high_threshold_db: -13,
                multiband_high_ratio: 1.25,
                multiband_high_attack_ms: 24,
                multiband_high_release_ms: 320,
            },
            '5_jazz': {
                multiband_enabled: true,
                multiband_mode: 5,
                multiband_x1_hz: 95,
                multiband_x2_hz: 360,
                multiband_x3_hz: 1600,
                multiband_x4_hz: 6200,
                multiband_low_threshold_db: -18,
                multiband_low_ratio: 1.65,
                multiband_low_attack_ms: 32,
                multiband_low_release_ms: 430,
                multiband_mid_threshold_db: -17,
                multiband_mid_ratio: 1.5,
                multiband_mid_attack_ms: 26,
                multiband_mid_release_ms: 340,
                multiband_high_threshold_db: -16,
                multiband_high_ratio: 1.35,
                multiband_high_attack_ms: 17,
                multiband_high_release_ms: 260,
            },
            '5_oldies': {
                multiband_enabled: true,
                multiband_mode: 5,
                multiband_x1_hz: 90,
                multiband_x2_hz: 340,
                multiband_x3_hz: 1450,
                multiband_x4_hz: 5600,
                multiband_low_threshold_db: -20,
                multiband_low_ratio: 1.8,
                multiband_low_attack_ms: 26,
                multiband_low_release_ms: 360,
                multiband_mid_threshold_db: -18,
                multiband_mid_ratio: 1.7,
                multiband_mid_attack_ms: 18,
                multiband_mid_release_ms: 280,
                multiband_high_threshold_db: -17,
                multiband_high_ratio: 1.45,
                multiband_high_attack_ms: 11,
                multiband_high_release_ms: 210,
            },
        };
        const base = presets[name];
        if (!base) return;
        const advancedProfiles = {
            '3_chr': { multiband_knee_db: 2.0, multiband_link_strength: 0.36, multiband_release_program_dependent: true },
            '3_rock': { multiband_knee_db: 2.2, multiband_link_strength: 0.40, multiband_release_program_dependent: true },
            '3_ac': { multiband_knee_db: 2.8, multiband_link_strength: 0.44, multiband_release_program_dependent: true },
            '3_country': { multiband_knee_db: 2.6, multiband_link_strength: 0.42, multiband_release_program_dependent: true },
            '3_talk': { multiband_knee_db: 3.8, multiband_link_strength: 0.58, multiband_release_program_dependent: true },
            '3_urban': { multiband_knee_db: 2.1, multiband_link_strength: 0.38, multiband_release_program_dependent: true },
            '3_dance': { multiband_knee_db: 1.9, multiband_link_strength: 0.34, multiband_release_program_dependent: true },
            '3_news': { multiband_knee_db: 4.0, multiband_link_strength: 0.62, multiband_release_program_dependent: true },
            '3_jazz': { multiband_knee_db: 3.2, multiband_link_strength: 0.52, multiband_release_program_dependent: true },
            '3_classic': { multiband_knee_db: 4.6, multiband_link_strength: 0.66, multiband_release_program_dependent: true },
            '5_chr': { multiband_knee_db: 1.8, multiband_link_strength: 0.34, multiband_release_program_dependent: true },
            '5_rock': { multiband_knee_db: 2.1, multiband_link_strength: 0.38, multiband_release_program_dependent: true },
            '5_ac': { multiband_knee_db: 2.8, multiband_link_strength: 0.44, multiband_release_program_dependent: true },
            '5_classic': { multiband_knee_db: 4.5, multiband_link_strength: 0.60, multiband_release_program_dependent: true },
            '5_talk': { multiband_knee_db: 4.2, multiband_link_strength: 0.62, multiband_release_program_dependent: true },
            '5_urban': { multiband_knee_db: 1.9, multiband_link_strength: 0.36, multiband_release_program_dependent: true },
            '5_dance': { multiband_knee_db: 1.7, multiband_link_strength: 0.32, multiband_release_program_dependent: true },
            '5_news': { multiband_knee_db: 4.3, multiband_link_strength: 0.64, multiband_release_program_dependent: true },
            '5_jazz': { multiband_knee_db: 3.4, multiband_link_strength: 0.54, multiband_release_program_dependent: true },
            '5_oldies': { multiband_knee_db: 3.0, multiband_link_strength: 0.48, multiband_release_program_dependent: true },
        };
        const advanced = advancedProfiles[name] || {};
        const curve = getPresetIntensityCurve();
        const p = { ...base, ...advanced };
        if (typeof p.multiband_knee_db === 'undefined') p.multiband_knee_db = 2.0;
        if (typeof p.multiband_link_strength === 'undefined') p.multiband_link_strength = 0.22;
        if (typeof p.multiband_release_program_dependent === 'undefined') {
            p.multiband_release_program_dependent = true;
        }
        Object.keys(p).forEach((key) => {
            const raw = p[key];
            if (typeof raw !== 'number') return;
            if (key.endsWith('_threshold_db')) {
                p[key] = clampNum(raw + curve.thresholdDbOffset, -36.0, -6.0);
                return;
            }
            if (key.endsWith('_ratio')) {
                p[key] = clampNum(raw * curve.ratioMul, 1.0, 4.0);
                return;
            }
            if (key.endsWith('_attack_ms')) {
                p[key] = clampNum(raw * curve.attackMul, 1.0, 200.0);
                return;
            }
            if (key.endsWith('_release_ms')) {
                p[key] = clampNum(raw * curve.releaseMul, 50.0, 1000.0);
            }
        });
        const setValue = (id, value) => {
            const el = document.getElementById(id);
            if (el) el.value = String(value);
        };
        const setChecked = (id, value) => {
            const el = document.getElementById(id);
            if (el) el.checked = Boolean(value);
        };
        setChecked('mpx_multiband_enabled', p.multiband_enabled);
        setValue('mpx_multiband_mode', p.multiband_mode);
        setValue('mpx_mb_low_threshold_db', p.multiband_low_threshold_db);
        setValue('mpx_mb_low_ratio', p.multiband_low_ratio);
        setValue('mpx_mb_low_attack_ms', p.multiband_low_attack_ms);
        setValue('mpx_mb_low_release_ms', p.multiband_low_release_ms);
        setValue('mpx_mb_mid_threshold_db', p.multiband_mid_threshold_db);
        setValue('mpx_mb_mid_ratio', p.multiband_mid_ratio);
        setValue('mpx_mb_mid_attack_ms', p.multiband_mid_attack_ms);
        setValue('mpx_mb_mid_release_ms', p.multiband_mid_release_ms);
        setValue('mpx_mb_high_threshold_db', p.multiband_high_threshold_db);
        setValue('mpx_mb_high_ratio', p.multiband_high_ratio);
        setValue('mpx_mb_high_attack_ms', p.multiband_high_attack_ms);
        setValue('mpx_mb_high_release_ms', p.multiband_high_release_ms);
        setValue('mpx_mb_knee_db', Number(p.multiband_knee_db).toFixed(1));
        setValue('mpx_mb_link_strength', Number(p.multiband_link_strength).toFixed(2));
        if (Object.prototype.hasOwnProperty.call(p, 'multiband_makeup_db')) {
            setValue('mpx_mb_makeup_db', Number(p.multiband_makeup_db).toFixed(1));
        }
        setChecked('mpx_mb_release_pd', p.multiband_release_program_dependent);
        const kneeValEl = document.getElementById('mpx_mb_knee_val');
        const linkValEl = document.getElementById('mpx_mb_link_val');
        const makeupValEl = document.getElementById('mpx_mb_makeup_val');
        if (kneeValEl) kneeValEl.textContent = Number(p.multiband_knee_db).toFixed(1);
        if (linkValEl) linkValEl.textContent = Number(p.multiband_link_strength).toFixed(2);
        if (makeupValEl && Object.prototype.hasOwnProperty.call(p, 'multiband_makeup_db')) {
            makeupValEl.textContent = Number(p.multiband_makeup_db).toFixed(1);
        }
        socket.emit('update', p);
    }
    let widenUpdateTimer = null;
    const widenPendingUpdate = {};
    function flushWidenUpdate() {
        if (Object.keys(widenPendingUpdate).length) {
            socket.emit('update', widenPendingUpdate);
            Object.keys(widenPendingUpdate).forEach((k) => { delete widenPendingUpdate[k]; });
        }
        widenUpdateTimer = null;
    }
    function queueWidenUpdate(key, value) {
        widenPendingUpdate[key] = value;
        if (widenUpdateTimer !== null) return;
        widenUpdateTimer = window.setTimeout(flushWidenUpdate, 40);
    }
    function updateWidenEnabled(val) { socket.emit('update', { stereo_widen_enabled: val }); }
    function updateWidenWidth(val) {
        document.getElementById('mpx_widen_width_val').textContent = parseFloat(val).toFixed(2);
        queueWidenUpdate('stereo_widen_width', parseFloat(val));
    }
    function updateWidenCenter(val) {
        document.getElementById('mpx_widen_center_val').textContent = parseFloat(val).toFixed(2);
        queueWidenUpdate('stereo_widen_center', parseFloat(val));
    }
    function updateWidenMix(val) {
        document.getElementById('mpx_widen_mix_val').textContent = parseFloat(val).toFixed(2);
        queueWidenUpdate('stereo_widen_mix', parseFloat(val));
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
    const meterAnim = {
        mpx_input_meter_l: { current: 0, target: 0 },
        mpx_input_meter_r: { current: 0, target: 0 },
        mpx_mpx_meter: { current: 0, target: 0 },
        modulation_meter: { current: 0, target: 0 },
    };
    const holdAnim = {
        mpx_input_hold_l: { value: 0, holdMs: 0 },
        mpx_input_hold_r: { value: 0, holdMs: 0 },
        mpx_mpx_hold: { value: 0, holdMs: 0 },
        modulation_hold: { value: 0, holdMs: 0 },
    };
    const textHoldAnim = {
        inputPk: { value: 0, holdUntilMs: 0, lastMs: 0 },
        mpxPk: { value: 0, holdUntilMs: 0, lastMs: 0 },
        inputVuL: { value: 0, holdUntilMs: 0, lastMs: 0 },
        inputVuR: { value: 0, holdUntilMs: 0, lastMs: 0 },
        mpxVu: { value: 0, holdUntilMs: 0, lastMs: 0 },
    };
    const stickyPeaksEl = document.getElementById('monitor_sticky_peaks');
    const peakHoldMsEl = document.getElementById('monitor_peak_hold_ms');
    const peakFallDbpsEl = document.getElementById('monitor_peak_fall_dbps');
    const peakResetEl = document.getElementById('monitor_peak_reset');
    let stickyPeaksEnabled = false;
    let peakHoldMs = 1500;
    let peakFallDbPerSec = 18;
    let lastMeterAnimMs = 0;
    const meterTauRise = 0.018;
    const meterTauFall = 0.11;
    const levelMeterFloorDb = -36.0;
    const levelMeterCurve = 0.88;

    function clamp01(value) {
        return Math.min(1.0, Math.max(0.0, Number(value) || 0));
    }

    function dbFallFactor(dtMs) {
        const dtSec = Math.max(0, dtMs) / 1000.0;
        return Math.pow(10, -(peakFallDbPerSec * dtSec) / 20.0);
    }

    function levelMeterScale(value) {
        const linear = Math.max(1e-9, Number(value) || 0);
        const db = 20.0 * Math.log10(linear);
        const norm = clamp01((db - levelMeterFloorDb) / (0.0 - levelMeterFloorDb));
        return Math.pow(norm, levelMeterCurve);
    }

    function modulationMeterScale(devKhz, targetKhz) {
        const dev = Math.max(0.0, Number(devKhz) || 0);
        const target = Math.max(1.0, Number(targetKhz) || 75.0);
        return clamp01(dev / target);
    }

    function clearHeldState() {
        Object.keys(holdAnim).forEach((k) => {
            holdAnim[k].value = 0;
            holdAnim[k].holdMs = 0;
            const markerEl = document.getElementById(k);
            if (markerEl) {
                markerEl.style.left = '0%';
                markerEl.style.opacity = '0';
            }
        });
        Object.keys(textHoldAnim).forEach((k) => {
            textHoldAnim[k].value = 0;
            textHoldAnim[k].holdUntilMs = 0;
            textHoldAnim[k].lastMs = 0;
        });
    }

    function applyPeakControlState() {
        if (peakHoldMsEl) {
            const storedHoldMs = Number(localStorage.getItem('sf_peak_hold_ms'));
            if (Number.isFinite(storedHoldMs) && storedHoldMs > 0) {
                peakHoldMs = storedHoldMs;
            }
            const holdOptions = Array.from(peakHoldMsEl.options).map((opt) => Number(opt.value));
            const holdTarget = Math.round(peakHoldMs);
            const holdValue = holdOptions.includes(holdTarget)
                ? holdTarget
                : holdOptions.reduce((best, opt) => (
                    Math.abs(opt - holdTarget) < Math.abs(best - holdTarget) ? opt : best
                ), holdOptions[0]);
            peakHoldMs = holdValue;
            peakHoldMsEl.value = String(holdValue);
        }
        if (peakFallDbpsEl) {
            const storedFall = Number(localStorage.getItem('sf_peak_fall_dbps'));
            if (Number.isFinite(storedFall) && storedFall > 0) {
                peakFallDbPerSec = storedFall;
            }
            const fallOptions = Array.from(peakFallDbpsEl.options).map((opt) => Number(opt.value));
            const fallTarget = Math.round(peakFallDbPerSec);
            const fallValue = fallOptions.includes(fallTarget)
                ? fallTarget
                : fallOptions.reduce((best, opt) => (
                    Math.abs(opt - fallTarget) < Math.abs(best - fallTarget) ? opt : best
                ), fallOptions[0]);
            peakFallDbPerSec = fallValue;
            peakFallDbpsEl.value = String(fallValue);
        }
    }

    function heldValue(key, liveValue, nowMs) {
        const state = textHoldAnim[key];
        const v = clamp01(liveValue);
        if (!state) return v;
        if (!stickyPeaksEnabled) {
            state.value = v;
            state.holdUntilMs = 0;
            state.lastMs = nowMs;
            return v;
        }
        if (v >= state.value) {
            state.value = v;
            state.holdUntilMs = nowMs + peakHoldMs;
            state.lastMs = nowMs;
            return state.value;
        }
        const dtMs = state.lastMs > 0 ? Math.min(250, Math.max(0, nowMs - state.lastMs)) : 0;
        state.lastMs = nowMs;
        if (nowMs < state.holdUntilMs) {
            return state.value;
        }
        state.value = Math.max(v, state.value * dbFallFactor(dtMs));
        if (state.value < 1e-6) state.value = 0;
        return state.value;
    }

    if (stickyPeaksEl) {
        stickyPeaksEnabled = localStorage.getItem('sf_sticky_peaks') === '1';
        stickyPeaksEl.checked = stickyPeaksEnabled;
        stickyPeaksEl.addEventListener('change', () => {
            stickyPeaksEnabled = Boolean(stickyPeaksEl.checked);
            localStorage.setItem('sf_sticky_peaks', stickyPeaksEnabled ? '1' : '0');
            if (!stickyPeaksEnabled) {
                clearHeldState();
            }
        });
    }
    applyPeakControlState();
    if (peakHoldMsEl) {
        peakHoldMsEl.addEventListener('change', () => {
            peakHoldMs = Math.max(100, Number(peakHoldMsEl.value) || 1500);
            localStorage.setItem('sf_peak_hold_ms', String(Math.round(peakHoldMs)));
        });
    }
    if (peakFallDbpsEl) {
        peakFallDbpsEl.addEventListener('change', () => {
            peakFallDbPerSec = Math.max(1, Number(peakFallDbpsEl.value) || 18);
            localStorage.setItem('sf_peak_fall_dbps', String(Math.round(peakFallDbPerSec)));
        });
    }
    if (peakResetEl) {
        peakResetEl.addEventListener('click', () => {
            clearHeldState();
        });
    }

    function setMeterTarget(id, value) {
        const state = meterAnim[id];
        if (!state) return;
        state.target = clamp01(value);
    }

    function pushHold(id, value) {
        if (!stickyPeaksEnabled) return;
        const state = holdAnim[id];
        if (!state) return;
        const v = clamp01(value);
        if (v >= state.value) {
            state.value = v;
            state.holdMs = peakHoldMs;
        }
    }

    function animateMeters(timestampMs) {
        const nowMs = Number.isFinite(timestampMs) ? timestampMs : performance.now();
        const dtMs = lastMeterAnimMs > 0 ? Math.min(120, Math.max(0, nowMs - lastMeterAnimMs)) : 16.67;
        const dtSec = dtMs / 1000.0;
        lastMeterAnimMs = nowMs;
        Object.keys(meterAnim).forEach((id) => {
            const state = meterAnim[id];
            const el = document.getElementById(id);
            if (!el) return;
            const tau = state.target > state.current ? meterTauRise : meterTauFall;
            const alpha = 1.0 - Math.exp(-dtSec / tau);
            state.current += (state.target - state.current) * alpha;
            state.current = clamp01(state.current);
            el.style.width = `${(state.current * 100).toFixed(2)}%`;
        });
        Object.keys(holdAnim).forEach((id) => {
            const state = holdAnim[id];
            const el = document.getElementById(id);
            if (!el) return;
            if (!stickyPeaksEnabled) {
                state.value = 0;
                state.holdMs = 0;
                el.style.opacity = '0';
                return;
            }
            if (state.holdMs > 0) {
                state.holdMs = Math.max(0, state.holdMs - dtMs);
            } else {
                state.value = Math.max(0, state.value * dbFallFactor(dtMs));
            }
            el.style.left = `calc(${(state.value * 100).toFixed(2)}% - 1px)`;
            el.style.opacity = state.value > 0.002 ? '0.95' : '0';
        });
        window.requestAnimationFrame(animateMeters);
    }
    window.requestAnimationFrame(animateMeters);

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
        const inputDb = document.getElementById('mpx_input_db');
        const mpxDb = document.getElementById('mpx_mpx_db');
        const inputPeak = document.getElementById('mpx_input_peak');
        const mpxPeak = document.getElementById('mpx_mpx_peak');
        const inputVuL = document.getElementById('mpx_input_vu_l');
        const inputVuR = document.getElementById('mpx_input_vu_r');
        const mpxVu = document.getElementById('mpx_mpx_vu');
        const modKHz = document.getElementById('modulation_khz');
        const inputLevel = Math.min(1.0, Math.max(0.0, data.input_rms || 0));
        const inputLevelL = Math.min(1.0, Math.max(0.0, data.input_rms_l || 0));
        const inputLevelR = Math.min(1.0, Math.max(0.0, data.input_rms_r || 0));
        const mpxLevel = Math.min(1.0, Math.max(0.0, data.mpx_rms || 0));
        const inputPkLive = Math.min(1.0, Math.max(0.0, data.input_peak || 0));
        const mpxPkRawLive = data.mpx_peak || 0;
        const mpxPkLive = Math.min(1.0, Math.max(0.0, mpxPkRawLive));
        const inputVuVal = Math.min(1.0, Math.max(0.0, data.input_vu || 0));
        const inputVuLValLive = Math.min(1.0, Math.max(0.0, data.input_vu_l || inputVuVal));
        const inputVuRValLive = Math.min(1.0, Math.max(0.0, data.input_vu_r || inputVuVal));
        const mpxVuValLive = Math.min(1.0, Math.max(0.0, data.mpx_vu || 0));
        const nowMs = performance.now();
        const inputPk = heldValue('inputPk', inputPkLive, nowMs);
        const mpxPk = heldValue('mpxPk', mpxPkLive, nowMs);
        const inputVuLVal = heldValue('inputVuL', inputVuLValLive, nowMs);
        const inputVuRVal = heldValue('inputVuR', inputVuRValLive, nowMs);
        const mpxVuVal = heldValue('mpxVu', mpxVuValLive, nowMs);
        const devEl = document.getElementById('mpx_deviation_khz');
        const maxDev = devEl ? parseFloat(devEl.value || '75') : 75.0;
        const modDev = mpxPkLive * maxDev;
        const modPct = modulationMeterScale(modDev, maxDev);
        const meterInputL = levelMeterScale(inputLevelL);
        const meterInputR = levelMeterScale(inputLevelR);
        const meterMpx = levelMeterScale(mpxLevel);
        const meterMod = modPct;
        setMeterTarget('mpx_input_meter_l', meterInputL);
        setMeterTarget('mpx_input_meter_r', meterInputR);
        setMeterTarget('mpx_mpx_meter', meterMpx);
        setMeterTarget('modulation_meter', meterMod);
        pushHold('mpx_input_hold_l', meterInputL);
        pushHold('mpx_input_hold_r', meterInputR);
        pushHold('mpx_mpx_hold', meterMpx);
        pushHold('modulation_hold', meterMod);
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
                modKHz.classList.add('text-gray-400');
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
        if (typeof data.orbass_enabled !== 'undefined') {
            setText('live_orbass', onOffText(data.orbass_enabled));
        }
        if (typeof data.stereo_widen_enabled !== 'undefined') {
            setText('live_widener', onOffText(data.stereo_widen_enabled));
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

    let authRedirecting = false;
    function redirectToLogin() {
        if (authRedirecting) return;
        authRedirecting = true;
        window.location.assign('/login');
    }

    function handleUnauthorizedStatus(res) {
        if (res && res.status === 401) {
            redirectToLogin();
            return true;
        }
        return false;
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
            if (handleUnauthorizedStatus(res)) return;
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
    socket.on('connect_error', (err) => {
        const msg = String((err && err.message) || '').toLowerCase();
        if (msg.includes('unauthorized')) {
            redirectToLogin();
        }
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
            if (handleUnauthorizedStatus(res)) return;
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
