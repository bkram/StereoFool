# UI templates for StereoFool.

LOGIN_HTML = r"""

<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <title>StereoFool - Login</title>
    <script src="https://cdn.tailwindcss.com"></script>
    <link rel="stylesheet" href="/static/style.css">
</head>
<body class="login-body min-h-screen flex items-center justify-center px-4">
    <div class="glass rounded-md p-8 w-full max-w-sm">
        <div class="text-center mb-6">
            <div class="text-2xl font-bold text-white">Stereo<span class="text-pink-400">Fool</span></div>
            <div class="text-xs text-gray-400">Composite MPX + RDS • v{{ app_version }}</div>
        </div>
        {% if msg %}
        <div class="mb-4 text-sm text-red-300 bg-red-900/40 border border-red-700 rounded px-3 py-2">{{ msg }}</div>
        {% endif %}
        <form method="POST" class="stack">
            <div class="stack-tight">
                <label class="block text-xs text-gray-400">Username</label>
                <input type="text" name="user" value="{{ user }}" class="w-full bg-black/60 border border-gray-700 rounded px-3 py-2 text-sm focus:outline-none focus:ring-1 focus:ring-pink-500" autocomplete="username" autofocus>
            </div>
            <div class="stack-tight">
                <label class="block text-xs text-gray-400">Password</label>
                <input type="password" name="pass" class="w-full bg-black/60 border border-gray-700 rounded px-3 py-2 text-sm focus:outline-none focus:ring-1 focus:ring-pink-500" autocomplete="current-password">
            </div>
            <button type="submit" class="w-full bg-pink-600 hover:bg-pink-500 text-white font-semibold rounded py-2 transition">Sign In</button>
        </form>
    </div>
</body>
</html>
"""

MPX_HTML = r"""

<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <title>StereoFool</title>
    <script src="https://cdnjs.cloudflare.com/ajax/libs/socket.io/4.7.5/socket.io.min.js" crossorigin="anonymous"></script>
    <script src="https://cdn.tailwindcss.com"></script>
    <link rel="stylesheet" href="/static/style.css">
</head>
<body class="app-body">
    <div class="app-container">
        <div class="header">
            <div class="logo">Stereo<span>Fool</span> <span class="text-[10px] text-gray-400 align-middle">v{{ app_version }}</span></div>
            <div class="flex items-center gap-4">
                <div class="text-[10px] text-gray-400 flex items-center gap-2">
                    <span id="heartbeat" class="text-xs"></span>
                </div>
                <button id="bypassBtn" onclick="toggleBypass()" class="bypass-btn{% if state.processing_bypass %} on{% endif %}">{% if state.processing_bypass %}BYPASS ON{% else %}BYPASS{% endif %}</button>
                <button id="pwrBtn" onclick="togglePower()" class="pwr-btn">OFF AIR</button>
                <button onclick="window.location.href='/logout'" class="top-btn">Logout</button>
            </div>
        </div>
        <div class="workspace">
            <div class="sidebar">
                <div class="tab-btn active" onclick="setTab('monitoring', event)">Monitoring</div>
                <div class="tab-btn" onclick="setTab('system', event)">System</div>
                <div class="tab-btn" onclick="setTab('interface', event)">Interfaces</div>
                <div class="tab-btn" onclick="setTab('processing', event)">Processing</div>
                <div class="tab-btn" onclick="setTab('levels', event)">Levels</div>
                <div class="tab-btn" onclick="setTab('rds_program', event)">RDS</div>
                <div class="tab-btn" onclick="setTab('rds_advanced', event)">RDS Advanced</div>
                <div class="tab-btn" onclick="setTab('help', event)">Help</div>
                <div class="tab-btn" onclick="setTab('about', event)">About</div>
                <div class="tab-btn" onclick="setTab('settings', event)">Settings</div>
            </div>

            <div id="system" class="content">
                <div class="section">
                    <div class="section-header">System</div>
                    <div class="section-body">
                        <div class="flex items-center gap-2">
                            <label>Stereo Enable <span class="rec-badge">Recommended</span></label>
                            <input type="checkbox" class="toggle-checkbox" id="mpx_stereo_coder" {% if not state.mono_mode %}checked{% endif %} onchange="updateStereoCoder(this.checked)">
                        </div>
                        <div class="flex items-center gap-2">
                            <label>MPX Output Enable</label>
                            <input type="checkbox" class="toggle-checkbox" id="mpx_output_enable" {% if state.output_enabled %}checked{% endif %} onchange="updateOutputEnabled(this.checked)">
                        </div>
                        <div class="flex items-center gap-2">
                            <label>RDS Enable <span class="rec-badge">Recommended</span></label>
                            <input type="checkbox" class="toggle-checkbox" id="mpx_rds_enable" {% if state.en_rds %}checked{% endif %} onchange="updateRdsEnable(this.checked)">
                        </div>
                    </div>
                </div>
            </div>

            <div id="interface" class="content">
                <div class="section">
                    <div class="section-header">Audio Devices</div>
                    <div class="section-body">
                        <div>
                            <label>Input Device</label>
                            <select id="mpx_dev_in">
                                <option value="-1" {% if state.device_in_idx == -1 %}selected{% endif %}>None</option>
                                {% for d in inputs %}
                                <option value="{{d.index}}" {% if d.index == state.device_in_idx %}selected{% endif %}>{{d.name}}</option>
                                {% endfor %}
                            </select>
                        </div>
                        <div>
                            <label>Output Device</label>
                            <select id="mpx_dev_out">
                                <option value="-1" {% if state.device_out_idx == -1 %}selected{% endif %}>None</option>
                                {% for d in outputs %}
                                <option value="{{d.index}}" {% if d.index == state.device_out_idx %}selected{% endif %}>{{d.name}}</option>
                                {% endfor %}
                            </select>
                        </div>
                    </div>
                </div>
                <div class="section">
                    <div class="section-header">Monitor Output</div>
                    <div class="section-body">
                        <div class="flex items-center gap-2">
                            <label>Enable Monitor Output <span class="help-tip" data-tip="Simulates the sound of the FM transmission for testing.">?</span></label>
                            <input type="checkbox" class="toggle-checkbox" id="mpx_monitor_enable" {% if state.monitor_enabled %}checked{% endif %} onchange="updateMonitorEnabled(this.checked)">
                        </div>
                        <div>
                            <label>Monitor Device</label>
                            <select id="mpx_monitor_out" onchange="updateMonitorDevice(this.value)">
                                <option value="-1" {% if state.monitor_device_idx == -1 %}selected{% endif %}>None</option>
                                {% for d in outputs %}
                                <option value="{{d.index}}" {% if d.index == state.monitor_device_idx %}selected{% endif %}>{{d.name}}</option>
                                {% endfor %}
                            </select>
                        </div>
                        <div>
                            <label>Monitor Rate</label>
                            <select id="mpx_monitor_rate" onchange="updateMonitorRate(this.value)">
                                <option value="48000" {% if state.monitor_rate_hz == 48000 %}selected{% endif %}>48 kHz</option>
                                <option value="96000" {% if state.monitor_rate_hz == 96000 %}selected{% endif %}>96 kHz</option>
                                <option value="192000" {% if state.monitor_rate_hz == 192000 %}selected{% endif %}>192 kHz</option>
                            </select>
                        </div>
                        <div class="text-[11px] text-gray-400 mt-1">Demodulated stereo monitor output.</div>
                    </div>
                </div>
                <div class="section">
                    <div class="section-header">Audio Engine</div>
                    <div class="section-body">
                        <div>
                            <label>Block Size <span class="help-tip" data-tip="Higher values reduce CPU load and dropouts but increase latency. Restart required.">?</span></label>
                            <select id="mpx_blocksize" onchange="updateBlocksize(this.value)">
                                <option value="512" {% if state.blocksize == 512 %}selected{% endif %}>512</option>
                                <option value="1024" {% if state.blocksize == 1024 %}selected{% endif %}>1024</option>
                                <option value="2048" {% if state.blocksize == 2048 %}selected{% endif %}>2048</option>
                                <option value="4096" {% if state.blocksize == 4096 %}selected{% endif %}>4096</option>
                                <option value="8192" {% if state.blocksize == 8192 %}selected{% endif %}>8192</option>
                                <option value="16384" {% if state.blocksize == 16384 %}selected{% endif %}>16384</option>
                                {% if state.blocksize not in [512, 1024, 2048, 4096, 8192, 16384] %}
                                <option value="{{state.blocksize}}" selected>{{state.blocksize}}</option>
                                {% endif %}
                            </select>
                            <div class="text-[11px] text-gray-400 mt-1">Higher values improve stability on slower systems.</div>
                        </div>
                        <div>
                            <label>Audio Priority Profile <span class="help-tip" data-tip="MacOS-only process/thread priority hints. Restart required.">?</span></label>
                            <select id="mpx_audio_priority_profile" onchange="updateAudioPriorityProfile(this.value)">
                                <option value="normal" {% if state.audio_priority_profile == 'normal' %}selected{% endif %}>Normal</option>
                                <option value="high" {% if state.audio_priority_profile == 'high' %}selected{% endif %}>High</option>
                                <option value="realtime-attempt" {% if state.audio_priority_profile == 'realtime-attempt' %}selected{% endif %}>Realtime Attempt</option>
                            </select>
                            <div class="text-[11px] text-gray-400 mt-1">Safe fallback to normal if unsupported or denied.</div>
                        </div>
                    </div>
                </div>
                <div class="section">
                    <div class="section-header">Source</div>
                    <div class="section-body">
                        <div>
                            <label>Source Mode</label>
                            <select id="mpx_source_mode" onchange="updateSourceMode(this.value)">
                                <option value="tone" {% if state.source_mode == 'tone' %}selected{% endif %}>Test Tone</option>
                                <option value="input" {% if state.source_mode == 'input' %}selected{% endif %}>Audio Input</option>
                            </select>
                        </div>
                        <div id="mpx_tone_fields">
                            <label>Test Tone Mode</label>
                            <select id="mpx_test_tone_mode" onchange="updateTestToneMode(this.value)">
                                <option value="mono" {% if state.test_tone_mode == 'mono' %}selected{% endif %}>Tone</option>
                                <option value="left" {% if state.test_tone_mode == 'left' %}selected{% endif %}>Tone Left</option>
                                <option value="right" {% if state.test_tone_mode == 'right' %}selected{% endif %}>Tone Right</option>
                                <option value="stereo" {% if state.test_tone_mode == 'stereo' %}selected{% endif %}>Tone Stereo</option>
                            </select>
                        </div>
                        <div id="mpx_tone_freq_field">
                            <label>Test Tone Frequency (Hz)</label>
                            <input class="w-full" type="number" min="100" max="15000" step="10" id="mpx_test_tone_freq" value="{{state.test_tone_freq}}" onchange="updateToneFreq(this.value)">
                        </div>
                    </div>
                </div>
                <div class="section">
                    <div class="section-header">Input Gain</div>
                    <div class="section-body">
                        <div>
                            <label>Input Gain (dB)</label>
                            <div class="slider-container">
                                <input type="range" min="-24" max="24" step="0.1" id="mpx_input_gain_db" value="{{state.input_gain_db}}" oninput="updateInputGain(this.value)">
                                <div class="slider-val" id="mpx_input_gain_val">{{state.input_gain_db}}</div>
                            </div>
                            <div class="text-[11px] text-gray-400 mt-1">Static gain/attenuation before processing.</div>
                        </div>
                    </div>
                </div>
                <div class="section">
                    <div class="section-header">Output Gain</div>
                    <div class="section-body">
                        <div>
                            <label>Output Gain (dB)</label>
                            <div class="slider-container">
                                <input type="range" min="-24" max="24" step="0.1" id="mpx_output_gain_db" value="{{state.output_gain_db}}" oninput="updateOutputGain(this.value)">
                                <div class="slider-val" id="mpx_output_gain_val">{{state.output_gain_db}}</div>
                            </div>
                            <div class="text-[11px] text-gray-400 mt-1">Post-MPX gain before the soundcard.</div>
                        </div>
                    </div>
                </div>
                <div class="section">
                    <div class="section-header">Capture</div>
                    <div class="section-body">
                        <div class="flex items-center gap-2">
                            <label>Write MPX WAV (192 kHz/16-bit)</label>
                            <input type="checkbox" class="toggle-checkbox" id="mpx_wav_record" {% if state.wav_record_enabled %}checked{% endif %} onchange="updateWavRecordEnabled(this.checked)">
                        </div>
                        <div>
                            <label>WAV Path</label>
                            <input type="text" id="mpx_wav_record_path" value="{{state.wav_record_path}}" onchange="updateWavRecordPath(this.value)">
                            <div class="text-[11px] text-gray-400 mt-1">Mono MPX capture for analysis.</div>
                        </div>
                    </div>
                </div>
            </div>

            <div id="processing" class="content">
                <div class="section">
                    <div class="section-header">Input Conditioning</div>
                    <div class="section-body">
                        <div>
                            <label>Processing Rate <span class="help-tip" data-tip="Use Native for maximum bandwidth. 48 kHz reduces CPU but limits stereo band.">?</span></label>
                            <select id="mpx_processing_rate" onchange="updateProcessingRate(this.value)">
                                <option value="0" {% if state.processing_rate_hz == 0 %}selected{% endif %}>Native (Output)</option>
                                <option value="48000" {% if state.processing_rate_hz == 48000 %}selected{% endif %}>48 kHz</option>
                            </select>
                            <div class="text-[11px] text-gray-400 mt-1">Restart required to apply.</div>
                        </div>
                        <div>
                            <label>Low-Cut (Hz) <span class="help-tip" data-tip="Removes infrasonic content that can cause excessive deviation.">?</span></label>
                            <input class="w-full" type="number" min="10" max="200" step="1" id="mpx_hpf_hz" value="{{state.hpf_hz}}" onchange="updateHpfHz(this.value)">
                            <div class="text-[11px] text-gray-400 mt-1">Higher values reduce bass-driven deviation.</div>
                        </div>
                        <div>
                            <label>HF Trim (dB) <span class="help-tip" data-tip="High-shelf attenuation before pre-emphasis to tame bright sources.">?</span></label>
                            <div class="slider-container">
                                <input type="range" min="-12" max="0" step="0.5" id="mpx_hf_trim_db" value="{{state.hf_trim_db}}" oninput="updateHfTrimDb(this.value)">
                                <div class="slider-val" id="mpx_hf_trim_val">{{state.hf_trim_db}}</div>
                            </div>
                            <div class="text-[11px] text-gray-400 mt-1">High-shelf cut before pre-emphasis.</div>
                        </div>
                        <div>
                            <label>HF Trim Corner (Hz) <span class="help-tip" data-tip="Corner frequency for the HF trim shelf. Lower values reduce more of the band.">?</span></label>
                            <input class="w-full" type="number" min="500" max="12000" step="100" id="mpx_hf_trim_hz" value="{{state.hf_trim_hz}}" onchange="updateHfTrimHz(this.value)">
                            <div class="text-[11px] text-gray-400 mt-1">Shelf corner frequency for the HF trim.</div>
                        </div>
                    </div>
                </div>
                <div class="section">
                    <div class="section-header">Orbass Low Enhancer</div>
                    <div class="section-body">
                        <div class="flex items-center gap-2">
                            <label>Enable Orbass <span class="help-tip" data-tip="Adaptive low-end enhancer with harmonic support. Inserted before multiband to keep bass controlled.">?</span></label>
                            <input type="checkbox" class="toggle-checkbox" id="mpx_orbass_enabled" {% if state.orbass_enabled %}checked{% endif %} onchange="updateOrbassEnabled(this.checked)">
                        </div>
                        <div>
                            <label>Presets</label>
                            <div class="preset-grid">
                                <button type="button" class="mini-btn" onclick="applyOrbassPreset('disco')">Disco Drive</button>
                                <button type="button" class="mini-btn" onclick="applyOrbassPreset('acoustic')">Acoustic Warm</button>
                                <button type="button" class="mini-btn" onclick="applyOrbassPreset('urban')">Urban Punch</button>
                                <button type="button" class="mini-btn" onclick="applyOrbassPreset('rock')">Rock Body</button>
                                <button type="button" class="mini-btn" onclick="applyOrbassPreset('talk')">Talk Safe</button>
                            </div>
                        </div>
                        <div>
                            <label>Amount</label>
                            <div class="slider-container">
                                <input type="range" min="0" max="1" step="0.01" id="mpx_orbass_amount" value="{{state.orbass_amount}}" oninput="updateOrbassAmount(this.value)">
                                <div class="slider-val" id="mpx_orbass_amount_val">{{state.orbass_amount}}</div>
                            </div>
                        </div>
                        <div>
                            <label>Bass Focus (Hz)</label>
                            <div class="slider-container">
                                <input type="range" min="45" max="220" step="1" id="mpx_orbass_freq_hz" value="{{state.orbass_freq_hz}}" oninput="updateOrbassFreq(this.value)">
                                <div class="slider-val" id="mpx_orbass_freq_val">{{state.orbass_freq_hz|int}}</div>
                            </div>
                        </div>
                        <div>
                            <label>Harmonics</label>
                            <div class="slider-container">
                                <input type="range" min="0" max="1" step="0.01" id="mpx_orbass_harmonics" value="{{state.orbass_harmonics}}" oninput="updateOrbassHarmonics(this.value)">
                                <div class="slider-val" id="mpx_orbass_harmonics_val">{{state.orbass_harmonics}}</div>
                            </div>
                            <div class="text-[11px] text-gray-400 mt-1">Adds upper bass harmonics to keep bass audible on small speakers.</div>
                        </div>
                    </div>
                </div>
                <div class="section">
                    <div class="section-header">Multiband Dynamics</div>
                    <div class="section-body">
                        <div class="flex items-center gap-2">
                            <label>Multiband Compressor <span class="rec-badge">Recommended</span><span class="help-tip" data-tip="Adds density by compressing lows/mids/highs separately.">?</span></label>
                            <input type="checkbox" class="toggle-checkbox" id="mpx_multiband_enabled" {% if state.multiband_enabled %}checked{% endif %} onchange="updateMultibandEnabled(this.checked)">
                        </div>
                        <div class="grid grid-cols-1 md:grid-cols-2 gap-2 mb-2">
                            <div>
                                <label>Band Mode <span class="help-tip" data-tip="3-band is lighter CPU. 5-band is denser and closer to enterprise processors.">?</span></label>
                                <select id="mpx_multiband_mode" onchange="updateMultibandMode(this.value)">
                                    <option value="3" {% if state.multiband_mode|int == 3 %}selected{% endif %}>3-Band (Default)</option>
                                    <option value="5" {% if state.multiband_mode|int == 5 %}selected{% endif %}>5-Band (Dense)</option>
                                </select>
                            </div>
                            <div class="text-[11px] text-gray-400 mt-5">5-band uses 4 split points (defaults: 80 / 320 / 1200 / 5000 Hz).</div>
                        </div>
                        <div>
                            <label>3-Band Music Presets</label>
                            <div class="preset-grid">
                                <button type="button" class="mini-btn" onclick="applyMultibandPreset('3_chr')">3B CHR/EDM</button>
                                <button type="button" class="mini-btn" onclick="applyMultibandPreset('3_rock')">3B Rock</button>
                                <button type="button" class="mini-btn" onclick="applyMultibandPreset('3_ac')">3B AC/Pop</button>
                                <button type="button" class="mini-btn" onclick="applyMultibandPreset('3_country')">3B Country</button>
                                <button type="button" class="mini-btn" onclick="applyMultibandPreset('3_talk')">3B Talk</button>
                            </div>
                        </div>
                        <div>
                            <label>5-Band Music Presets</label>
                            <div class="preset-grid">
                                <button type="button" class="mini-btn" onclick="applyMultibandPreset('5_chr')">5B CHR/EDM</button>
                                <button type="button" class="mini-btn" onclick="applyMultibandPreset('5_rock')">5B Rock</button>
                                <button type="button" class="mini-btn" onclick="applyMultibandPreset('5_ac')">5B AC/Pop</button>
                                <button type="button" class="mini-btn" onclick="applyMultibandPreset('5_classic')">5B Classical/Jazz</button>
                                <button type="button" class="mini-btn" onclick="applyMultibandPreset('5_talk')">5B Talk</button>
                            </div>
                        </div>
                        <div>
                            <label>Preset Intensity <span class="help-tip" data-tip="Scales how aggressively presets apply compression. Light is gentler, Heavy is denser.">?</span></label>
                            <select id="mpx_mb_preset_intensity">
                                <option value="light">Light</option>
                                <option value="normal" selected>Normal</option>
                                <option value="heavy">Heavy</option>
                            </select>
                        </div>
                        <div class="grid grid-cols-1 md:grid-cols-3 gap-2">
                            <div>
                                <label>Knee (dB) <span class="help-tip" data-tip="Soft-knee width around threshold. Higher values sound smoother and less abrupt.">?</span></label>
                                <div class="slider-container">
                                    <input type="range" min="0" max="12" step="0.5" id="mpx_mb_knee_db" value="{{state.multiband_knee_db}}" oninput="updateMultibandKnee(this.value)">
                                    <div class="slider-val" id="mpx_mb_knee_val">{{state.multiband_knee_db}}</div>
                                </div>
                            </div>
                            <div>
                                <label>Band Link <span class="help-tip" data-tip="Links band envelopes to reduce spectral pumping. 0 = independent, 1 = strongly linked.">?</span></label>
                                <div class="slider-container">
                                    <input type="range" min="0" max="1" step="0.01" id="mpx_mb_link_strength" value="{{state.multiband_link_strength}}" oninput="updateMultibandLinkStrength(this.value)">
                                    <div class="slider-val" id="mpx_mb_link_val">{{state.multiband_link_strength}}</div>
                                </div>
                            </div>
                            <div class="flex items-center gap-2 mt-4">
                                <label>Program-Dependent Release <span class="help-tip" data-tip="Release adapts to crest factor for steadier loudness on mixed material.">?</span></label>
                                <input type="checkbox" class="toggle-checkbox" id="mpx_mb_release_pd" {% if state.multiband_release_program_dependent %}checked{% endif %} onchange="updateMultibandReleaseProgramDependent(this.checked)">
                            </div>
                        </div>
                        <div class="section-subheader">Per-band</div>
                        <div class="grid grid-cols-1 md:grid-cols-3 gap-2">
                            <div class="stack-tight">
                                <div class="text-[11px] text-gray-400 font-semibold">Low Band</div>
                                <label>Threshold (dBFS)</label>
                                <input class="w-full" type="number" min="-36" max="-6" step="1" id="mpx_mb_low_threshold_db" value="{{state.multiband_low_threshold_db}}" onchange="updateMultibandLowThreshold(this.value)">
                                <label>Ratio</label>
                                <input class="w-full" type="number" min="1.0" max="4.0" step="0.1" id="mpx_mb_low_ratio" value="{{state.multiband_low_ratio}}" onchange="updateMultibandLowRatio(this.value)">
                                <label>Attack (ms)</label>
                                <input class="w-full" type="number" min="1" max="200" step="1" id="mpx_mb_low_attack_ms" value="{{state.multiband_low_attack_ms}}" onchange="updateMultibandLowAttack(this.value)">
                                <label>Release (ms)</label>
                                <input class="w-full" type="number" min="50" max="1000" step="10" id="mpx_mb_low_release_ms" value="{{state.multiband_low_release_ms}}" onchange="updateMultibandLowRelease(this.value)">
                            </div>
                            <div class="stack-tight">
                                <div class="text-[11px] text-gray-400 font-semibold">Mid Band</div>
                                <label>Threshold (dBFS)</label>
                                <input class="w-full" type="number" min="-36" max="-6" step="1" id="mpx_mb_mid_threshold_db" value="{{state.multiband_mid_threshold_db}}" onchange="updateMultibandMidThreshold(this.value)">
                                <label>Ratio</label>
                                <input class="w-full" type="number" min="1.0" max="4.0" step="0.1" id="mpx_mb_mid_ratio" value="{{state.multiband_mid_ratio}}" onchange="updateMultibandMidRatio(this.value)">
                                <label>Attack (ms)</label>
                                <input class="w-full" type="number" min="1" max="200" step="1" id="mpx_mb_mid_attack_ms" value="{{state.multiband_mid_attack_ms}}" onchange="updateMultibandMidAttack(this.value)">
                                <label>Release (ms)</label>
                                <input class="w-full" type="number" min="50" max="1000" step="10" id="mpx_mb_mid_release_ms" value="{{state.multiband_mid_release_ms}}" onchange="updateMultibandMidRelease(this.value)">
                            </div>
                            <div class="stack-tight">
                                <div class="text-[11px] text-gray-400 font-semibold">High Band</div>
                                <label>Threshold (dBFS)</label>
                                <input class="w-full" type="number" min="-36" max="-6" step="1" id="mpx_mb_high_threshold_db" value="{{state.multiband_high_threshold_db}}" onchange="updateMultibandHighThreshold(this.value)">
                                <label>Ratio</label>
                                <input class="w-full" type="number" min="1.0" max="4.0" step="0.1" id="mpx_mb_high_ratio" value="{{state.multiband_high_ratio}}" onchange="updateMultibandHighRatio(this.value)">
                                <label>Attack (ms)</label>
                                <input class="w-full" type="number" min="1" max="200" step="1" id="mpx_mb_high_attack_ms" value="{{state.multiband_high_attack_ms}}" onchange="updateMultibandHighAttack(this.value)">
                                <label>Release (ms)</label>
                                <input class="w-full" type="number" min="50" max="1000" step="10" id="mpx_mb_high_release_ms" value="{{state.multiband_high_release_ms}}" onchange="updateMultibandHighRelease(this.value)">
                            </div>
                        </div>
                    </div>
                </div>
                <div class="section">
                    <div class="section-header">Stereo Width</div>
                    <div class="section-body">
                        <div class="flex items-center gap-2">
                            <label>Widener <span class="help-tip" data-tip="Airwindows Wider-style mid/side shaping.">?</span></label>
                            <input type="checkbox" class="toggle-checkbox" id="mpx_widen_enabled" {% if state.stereo_widen_enabled %}checked{% endif %} onchange="updateWidenEnabled(this.checked)">
                        </div>
                        <div>
                            <label>Width</label>
                            <div class="slider-container">
                                <input type="range" min="0" max="1" step="0.01" id="mpx_widen_width" value="{{state.stereo_widen_width}}" oninput="updateWidenWidth(this.value)">
                                <div class="slider-val" id="mpx_widen_width_val">{{state.stereo_widen_width}}</div>
                            </div>
                        </div>
                        <div>
                            <label>Center</label>
                            <div class="slider-container">
                                <input type="range" min="0" max="1" step="0.01" id="mpx_widen_center" value="{{state.stereo_widen_center}}" oninput="updateWidenCenter(this.value)">
                                <div class="slider-val" id="mpx_widen_center_val">{{state.stereo_widen_center}}</div>
                            </div>
                        </div>
                        <div>
                            <label>Mix</label>
                            <div class="slider-container">
                                <input type="range" min="0" max="1" step="0.01" id="mpx_widen_mix" value="{{state.stereo_widen_mix}}" oninput="updateWidenMix(this.value)">
                                <div class="slider-val" id="mpx_widen_mix_val">{{state.stereo_widen_mix}}</div>
                            </div>
                        </div>
                    </div>
                </div>
                <div class="section">
                    <div class="section-header">Pre-emphasis</div>
                    <div class="section-body">
                        <div>
                            <label>Pre-emphasis <span class="help-tip" data-tip="Use 50 us in most of Europe; 75 us in North America. Off for testing.">?</span></label>
                            <select id="mpx_preemphasis_us" onchange="updatePreemphasis(this.value)">
                                <option value="0" {% if state.preemphasis_us == 0 %}selected{% endif %}>Off</option>
                                <option value="50" {% if state.preemphasis_us == 50 %}selected{% endif %}>50 us</option>
                                <option value="75" {% if state.preemphasis_us == 75 %}selected{% endif %}>75 us</option>
                            </select>
                        </div>
                        <div class="flex items-center gap-2">
                            <label>Pre-emphasis Limiter <span class="rec-badge">Recommended</span><span class="help-tip" data-tip="Controls HF overshoot after pre-emphasis.">?</span></label>
                            <input type="checkbox" class="toggle-checkbox" id="mpx_preemph_limit" {% if state.preemphasis_limit_enabled %}checked{% endif %} onchange="updatePreemphasisLimiter(this.checked)">
                        </div>
                        <div>
                            <label>Pre-emphasis Threshold <span class="help-tip" data-tip="Limiter threshold for pre-emphasis. Lower = more limiting.">?</span></label>
                            <div class="slider-container">
                                <input type="range" min="0.7" max="1.0" step="0.01" id="mpx_preemph_threshold" value="{{state.preemphasis_limit_threshold}}" oninput="updatePreemphasisThreshold(this.value)">
                                <div class="slider-val" id="mpx_preemph_val">{{state.preemphasis_limit_threshold}}</div>
                            </div>
                        </div>
                    </div>
                </div>
                <div class="section">
                    <div class="section-header">Peak Protection</div>
                    <div class="section-body">
                        <div class="flex items-center gap-2">
                            <label>Composite Clipper <span class="help-tip" data-tip="Soft clip for MPX peaks. Helps keep deviation within spec.">?</span></label>
                            <input type="checkbox" class="toggle-checkbox" id="mpx_comp_clip" {% if state.composite_clip_enabled %}checked{% endif %} onchange="updateCompositeClipper(this.checked)">
                        </div>
                        <div>
                            <label>Composite Threshold <span class="help-tip" data-tip="Clip threshold for composite MPX. Lower = more clipping.">?</span></label>
                            <div class="slider-container">
                                <input type="range" min="0.5" max="1.0" step="0.01" id="mpx_comp_threshold" value="{{state.composite_clip_threshold}}" oninput="updateCompositeThreshold(this.value)">
                                <div class="slider-val" id="mpx_comp_val">{{state.composite_clip_threshold}}</div>
                            </div>
                        </div>
                        <div class="flex items-center gap-2">
                            <label>Soft Clip (Safety) <span class="help-tip" data-tip="MPX limiter for last-resort peak control.">?</span></label>
                            <input type="checkbox" class="toggle-checkbox" id="mpx_limit_mpx" {% if state.limit_mpx %}checked{% endif %} onchange="updateLimitMpx(this.checked)">
                        </div>
                        <div class="flex items-center gap-2">
                            <label>Lookahead Limiter <span class="help-tip" data-tip="Reduces clipping artifacts by looking ahead.">?</span></label>
                            <input type="checkbox" class="toggle-checkbox" id="mpx_limit_lookahead" {% if state.limit_lookahead_enabled %}checked{% endif %} onchange="updateLimitLookahead(this.checked)">
                        </div>
                        <div>
                            <label>Lookahead (ms) <span class="help-tip" data-tip="Shorter values respond faster; longer values can sound smoother.">?</span></label>
                            <input class="w-full" type="number" min="0" max="20" step="0.5" id="mpx_limit_lookahead_ms" value="{{state.limit_lookahead_ms}}" onchange="updateLimitLookaheadMs(this.value)">
                        </div>
                        <div>
                            <label>Clip Threshold <span class="help-tip" data-tip="Limiter threshold for MPX peak control.">?</span></label>
                            <div class="slider-container">
                                <input type="range" min="0.5" max="1.0" step="0.01" id="mpx_limit_threshold" value="{{state.limit_threshold}}" oninput="updateLimitThreshold(this.value)">
                                <div class="slider-val" id="mpx_limit_val">{{state.limit_threshold}}</div>
                            </div>
                            <div class="text-[11px] text-gray-400 mt-1">Soft clip threshold for peak protection.</div>
                        </div>
                    </div>
                </div>
            </div>

            <div id="levels" class="content">
                <div class="grid grid-cols-1 gap-4">
                    <div class="section">
                        <div class="section-header">Composite Deviation</div>
                        <div class="section-body">
                            <div>
                                <label>Composite Deviation (kHz)</label>
                                <div class="slider-container">
                                    <input type="range" min="10" max="100" step="1" id="mpx_deviation_khz" value="{{state.mpx_deviation_khz}}" oninput="updateMpxDeviation(this.value)">
                                    <div class="slider-val" id="mpx_dev_val">{{state.mpx_deviation_khz}}</div>
                                </div>
                                <div class="text-[11px] text-gray-400 mt-1">Overall composite output deviation.</div>
                                <div class="text-[11px] text-gray-400">Reference: 75 kHz is the standard max deviation (ITU-R/EN).</div>
                            </div>
                        </div>
                    </div>
                    <div class="section">
                        <div class="section-header">Pilot</div>
                        <div class="section-body">
                            <div>
                                <label>Pilot Level</label>
                                <div class="slider-container">
                                    <input type="range" min="0" max="1" step="0.01" id="mpx_pilot_level" value="{{state.pilot_level}}" oninput="updateLevel(this.value)">
                                    <div class="slider-val" id="mpx_pilot_val">{{state.pilot_level}}</div>
                                </div>
                                <div class="text-[11px] text-gray-400 mt-1">19 kHz pilot level when stereo is enabled.</div>
                                <div class="text-[11px] text-gray-400">Nominal deviation: <span id="pilot_dev_khz">0.00</span> kHz (<span id="pilot_dev_pct">0.0</span>%).</div>
                                <div class="text-[11px] text-gray-400">Recommended: 0.08 to 0.10.</div>
                                <div class="text-[11px] text-gray-400">Spec (ITU-R BS.450): 8 to 10% of max composite.</div>
                            </div>
                        </div>
                    </div>
                    <div class="section">
                        <div class="section-header">RDS</div>
                        <div class="section-body">
                            <div>
                                <label>RDS Carrier Deviation (kHz)</label>
                                <div class="slider-container">
                                    <input type="range" id="rds_level" min="0" max="7.5" step="0.1" value="{{rds_state.rds_level}}" oninput="sync()">
                                    <span class="slider-val" id="val_rds">{{rds_state.rds_level}}</span>
                                </div>
                                <div class="text-[11px] text-gray-400 mt-1">Nominal 57 kHz subcarrier deviation.</div>
                                <div class="text-[11px] text-gray-400">Nominal deviation: <span id="rds_dev_khz">0.00</span> kHz (calibrated).</div>
                                <div class="text-[11px] text-gray-400">Recommended: 2.0 kHz (EN 50067 best compromise).</div>
                                <div class="text-[11px] text-gray-400">Spec (EN 50067): +/-1.0 to +/-7.5 kHz at 75 kHz max.</div>
                            </div>
                        </div>
                    </div>
                </div>
            </div>

            <div id="rds_program" class="content">
                <div class="grid grid-cols-1 lg:grid-cols-2 gap-4">
                    <div class="section">
                        <div class="section-header">Program Service (PS)</div>
                        <div class="section-body">
                            <div class="stack">
                                <div class="flex justify-between">
                                    <label>Text Source (Supports \R, \w, 3s:)</label>
                                    <div class="flex gap-2 items-center">
                                        <label>Centre</label>
                                        <input type="checkbox" class="toggle-checkbox" id="ps_centered" {% if rds_state.ps_centered %}checked{% endif %} onchange="sync()">
                                    </div>
                                </div>
                                <div class="text-[9px] text-gray-500">
                                    PS cycles through 8-character labels. Use timing prefixes like 2s:Label.
                                </div>
                                <div class="text-[9px] text-gray-500">
                                    Center pads the PS text with spaces to align short labels.
                                </div>
                                <input type="text" id="ps_dynamic" value="{{rds_state.ps_dynamic}}" onchange="sync()">
                            </div>
                        </div>
                    </div>

                    <div class="section">
                        <div class="section-header">Station Identification</div>
                        <div class="section-body grid-cols-2">
                            <div class="stack">
                                <label>PI Code (Hex)</label>
                                <div class="text-[9px] text-gray-500">4-digit Program Identification code (hex).</div>
                                <input type="text" id="pi" value="{{rds_state.pi}}" maxlength="4" class="font-mono text-center tracking-widest" onchange="sync()">
                            </div>
                            <div class="stack">
                                <label>Program Type (PTY)</label>
                                <div class="text-[9px] text-gray-500">PTY number maps to a receiver category (e.g. News, Rock).</div>
                                <select id="pty" onchange="sync()">{% for p in pty_list %}<option value="{{loop.index0}}" {% if loop.index0 == rds_state.pty %}selected{% endif %}>{{p}}</option>{% endfor %}</select>
                            </div>
                        </div>
                    </div>
                </div>

                <div class="section">
                    <div class="section-header">RadioText (RT)</div>
                    <div class="section-body">
                        <div class="flex justify-between items-center">
                             <label>Manually specify buffers</label>
                             <input type="checkbox" class="toggle-checkbox" id="rt_manual_buffers" {% if rds_state.rt_manual_buffers %}checked{% endif %} onchange="sync(); setTimeout(updateRTVisibility, 100)">
                        </div>
                        <div class="text-[9px] text-gray-500">
                            When enabled, set Buffer A/B directly. When disabled, use the single RadioText field.
                        </div>

                        <div id="rt_single_mode" class="stack" style="display: {% if rds_state.rt_manual_buffers %}none{% else %}block{% endif %}">
                            <div class="stack">
                                <label>RadioText</label>
                                <div class="text-[9px] text-gray-500">Supports timing: 5s:Message1/10s:Message2. A/B flag toggles on message change.</div>
                                <input type="text" id="rt_text" value="{{rds_state.rt_text}}" onchange="sync()">
                            </div>
                            <div class="flex justify-between items-center bg-[#111] p-2 rounded">
                                <div>
                                    <label>Cycle same message on A/B</label>
                                    <div class="text-[9px] text-gray-500">Toggle A/B at interval (ignores message-based toggle)</div>
                                </div>
                                <input type="checkbox" class="toggle-checkbox" id="rt_cycle_ab" {% if rds_state.rt_cycle_ab %}checked{% endif %} onchange="sync(); updateCycleControls()">
                            </div>
                        </div>

                        <div id="rt_dual_mode" class="stack" style="display: {% if rds_state.rt_manual_buffers %}block{% else %}none{% endif %}">
                            <div class="flex gap-2">
                                 <div class="flex-1">
                                     <label>Buffer A</label>
                                     <div class="text-[9px] text-gray-500">Manual RT buffer A (up to 64 chars).</div>
                                     <input type="text" id="rt_a" value="{{rds_state.rt_a}}" onchange="sync()">
                                 </div>
                                 <div class="flex-1">
                                     <label>Buffer B</label>
                                     <div class="text-[9px] text-gray-500">Manual RT buffer B (up to 64 chars).</div>
                                     <input type="text" id="rt_b" value="{{rds_state.rt_b}}" onchange="sync()">
                                 </div>
                            </div>
                            <div class="flex justify-between items-center bg-[#111] p-2 rounded">
                                 <div>
                                     <label>Auto cycle A/B buffers</label>
                                     <div class="text-[9px] text-gray-500">Uses cycle time when enabled</div>
                                 </div>
                                 <input type="checkbox" class="toggle-checkbox" id="rt_cycle" {% if rds_state.rt_cycle %}checked{% endif %} onchange="sync(); updateCycleControls()">
                            </div>
                            <div id="rt_active_wrap" class="flex items-center gap-2">
                                 <label>Active buffer</label>
                                 <span class="text-[9px] text-gray-500">Used when auto cycle is off.</span>
                                 <select id="rt_active_buffer" onchange="sync()">
                                     <option value="0" {% if rds_state.rt_active_buffer == 0 %}selected{% endif %}>A</option>
                                     <option value="1" {% if rds_state.rt_active_buffer == 1 %}selected{% endif %}>B</option>
                                 </select>
                            </div>
                        </div>

                        <div class="flex justify-between items-center bg-[#111] p-2 rounded">
                             <div class="flex gap-4 items-end">
                                 <div class="stack-tight">
                                     <label>Mode</label>
                                     <div class="text-[9px] text-gray-500">2A = 64 chars, 2B = 32 chars.</div>
                                     <select id="rt_mode" onchange="sync()"><option value="2A">2A (64)</option><option value="2B">2B (32)</option></select>
                                 </div>
                                 <div id="time_seconds_wrap" class="stack-tight">
                                     <label>Time (seconds)</label>
                                     <div class="text-[9px] text-gray-500">Cycle duration for RT text or buffers.</div>
                                     <input type="number" id="rt_cycle_time" value="{{rds_state.rt_cycle_time}}" class="w-16" min="1" onchange="sync()">
                                 </div>
                                 <div id="rt_cycles_wrap" class="stack-tight" style="display:none">
                                     <label>RT cycles</label>
                                     <div class="text-[9px] text-gray-500">Number of full cycles before toggling A/B.</div>
                                     <input type="number" id="rt_ab_cycle_count" value="{{rds_state.rt_ab_cycle_count}}" class="w-16" min="1" onchange="sync()">
                                 </div>
                             </div>
                             <div class="flex gap-4">
                                 <div class="flex flex-col items-center">
                                     <label>RT+ Enable</label>
                                     <div class="text-[9px] text-gray-500">Send RT+ tags.</div>
                                     <input type="checkbox" class="toggle-checkbox" id="en_rt_plus" {% if rds_state.en_rt_plus %}checked{% endif %} onchange="sync()">
                                 </div>
                                 <div class="flex flex-col items-center">
                                     <label>Centre</label>
                                     <div class="text-[9px] text-gray-500">Center text with spaces.</div>
                                     <input type="checkbox" class="toggle-checkbox" id="rt_centered" {% if rds_state.rt_centered %}checked{% endif %} onchange="if(this.checked) document.getElementById('rt_cr').checked = false; sync()">
                                 </div>
                                 <div class="flex flex-col items-center">
                                     <label>Append CR</label>
                                     <div class="text-[9px] text-gray-500">Add carriage return terminator.</div>
                                     <input type="checkbox" class="toggle-checkbox" id="rt_cr" {% if rds_state.rt_cr %}checked{% endif %} onchange="sync()">
                                 </div>
                             </div>
                        </div>
                        <div class="flex justify-between items-center">
                            <label>RT+ Format</label>
                        </div>
                        <div class="text-[9px] text-gray-500">
                            Templates for parsing Title/Artist from RadioText.
                        </div>
                        <div id="rt_plus_single_mode" class="stack" style="display: {% if rds_state.rt_manual_buffers %}none{% else %}block{% endif %}">
                            <div class="stack">
                                <label>Format</label>
                                <input type="text" id="rt_plus_format_a_single" value="{{rds_state.rt_plus_format_a}}" placeholder="{artist} - {title}" onchange="sync()">
                            </div>
                        </div>
                        <div id="rt_plus_dual_mode" class="stack" style="display: {% if rds_state.rt_manual_buffers %}block{% else %}none{% endif %}">
                            <div class="flex gap-2">
                                 <div class="flex-1 stack-tight">
                                     <label>Format A</label>
                                     <input type="text" id="rt_plus_format_a_dual" value="{{rds_state.rt_plus_format_a}}" placeholder="{artist} - {title}" onchange="sync()">
                                 </div>
                                 <div class="flex-1 stack-tight">
                                     <label>Format B</label>
                                     <input type="text" id="rt_plus_format_b" value="{{rds_state.rt_plus_format_b}}" placeholder="{artist} - {title}" onchange="sync()">
                                 </div>
                            </div>
                        </div>
                    </div>
                </div>

                <div class="section">
                    <div class="section-header">Traffic & Flags</div>
                    <div class="section-body grid-cols-4">
                        <div class="flex flex-col items-center">
                            <label>Traffic Prog</label>
                            <div class="text-[9px] text-gray-500">TP flag for traffic services.</div>
                            <input type="checkbox" class="toggle-checkbox" id="tp" {% if rds_state.tp %}checked{% endif %} onchange="sync()">
                        </div>
                        <div class="flex flex-col items-center">
                            <label>Traffic Ann</label>
                            <div class="text-[9px] text-gray-500">TA flag for live alerts.</div>
                            <input type="checkbox" class="toggle-checkbox" id="ta" {% if rds_state.ta %}checked{% endif %} onchange="sync()">
                        </div>
                        <div class="flex flex-col items-center">
                            <label>Music/Speech</label>
                            <div class="text-[9px] text-gray-500">MS flag: 1=music, 0=speech.</div>
                            <input type="checkbox" class="toggle-checkbox" id="ms" {% if rds_state.ms %}checked{% endif %} onchange="sync()">
                        </div>
                        <div class="flex flex-col items-center">
                            <label>Stereo</label>
                            <div class="text-[9px] text-gray-500">DI stereo indicator.</div>
                            <input type="checkbox" class="toggle-checkbox" id="di_stereo" {% if rds_state.di_stereo %}checked{% endif %} onchange="sync()">
                        </div>
                        <div class="flex flex-col items-center">
                            <label>Artificial Head</label>
                            <div class="text-[9px] text-gray-500">DI artificial head flag.</div>
                            <input type="checkbox" class="toggle-checkbox" id="di_head" {% if rds_state.di_head %}checked{% endif %} onchange="sync()">
                        </div>
                        <div class="flex flex-col items-center">
                            <label>Compressed</label>
                            <div class="text-[9px] text-gray-500">DI compressed flag.</div>
                            <input type="checkbox" class="toggle-checkbox" id="di_comp" {% if rds_state.di_comp %}checked{% endif %} onchange="sync()">
                        </div>
                        <div class="flex flex-col items-center">
                            <label>Dynamic PTY</label>
                            <div class="text-[9px] text-gray-500">PTY may change with content.</div>
                            <input type="checkbox" class="toggle-checkbox" id="di_dyn" {% if rds_state.di_dyn %}checked{% endif %} onchange="sync()">
                        </div>
                    </div>
                </div>

                <div class="section">
                    <div class="section-header">Alternative Frequencies</div>
                    <div class="section-body">
                         <div class="stack-tight">
                             <div class="flex justify-between">
                                 <label>Enable AF Method A</label>
                                 <input type="checkbox" class="toggle-checkbox" id="en_af" {% if rds_state.en_af %}checked{% endif %} onchange="sync()">
                             </div>
                             <div class="text-[9px] text-gray-500">Broadcast alternate FM frequencies for the same program.</div>
                             <div class="text-[9px] text-gray-500">Comma-separated list in MHz (e.g. 87.5, 98.1).</div>
                             <textarea id="af_list" rows="2" placeholder="87.5, 98.1, 104.2" onchange="sync()">{{rds_state.af_list}}</textarea>
                         </div>
                    </div>
                </div>
            </div>

            <div id="rds_advanced" class="content">
                     <div class="section">
                        <div class="section-header">Scheduler Sequence</div>
                        <div class="section-body">
                             <div class="stack-tight">
                                 <div class="flex justify-between">
                                     <label>Sequence String (e.g. 0A 0A 2A)</label>
                                     <div class="flex items-center gap-2">
                                         <span class="text-[9px] text-gray-400">Manual / Auto</span>
                                         <input type="checkbox" class="toggle-checkbox" id="scheduler_auto" {% if rds_state.scheduler_auto %}checked{% endif %} onchange="sync()">
                                     </div>
                                 </div>
                                 <div class="flex justify-between">
                                     <label>Use Standards Schedule (EN 50067)</label>
                                     <div class="flex items-center gap-2">
                                         <span class="text-[9px] text-gray-400">Uses EN 50067-style repetition rates, overrides manual sequence</span>
                                         <input type="checkbox" class="toggle-checkbox" id="scheduler_standard" {% if rds_state.scheduler_standard %}checked{% endif %} onchange="sync()">
                                     </div>
                                 </div>
                                 <div class="flex justify-between">
                                     <label>Include LPS (Non-Standard)</label>
                                     <div class="flex items-center gap-2">
                                         <span class="text-[9px] text-gray-400">Adds Group 15A even in standards mode</span>
                                         <input type="checkbox" class="toggle-checkbox" id="scheduler_standard_lps" {% if rds_state.scheduler_standard_lps %}checked{% endif %} onchange="sync()">
                                     </div>
                                 </div>
                                 <div class="text-[9px] text-gray-500">Controls which group types are sent and in what order.</div>
                                 <div class="text-[9px] text-gray-500">
                                     Common groups: 0A=PS, 2A=RadioText, 4A=Clock Time, 10A=PTYN, 11A=RT+, 15A=Long PS.
                                 </div>
                                 <input type="text" id="group_sequence" value="{{rds_state.group_sequence}}" onchange="sync()" class="font-mono">
                             </div>
                        </div>
                    </div>

                    <div class="section">
                        <div class="section-header">RDS Cheat Sheet</div>
                        <div class="section-body">
                            <div class="stack-tight">
                                <div class="text-[9px] text-gray-400">Group codes and common meanings:</div>
                                <div class="text-[9px] text-gray-500 leading-relaxed">
                                    0A: Program Service (PS) and flags<br>
                                    2A/2B: RadioText (64/32 chars)<br>
                                    4A: Clock Time (CT)<br>
                                    10A: PTY Name (PTYN)<br>
                                    11A: RT+ tags (Title/Artist)<br>
                                    15A: Long PS (LPS)
                                </div>
                                <div class="text-[9px] text-gray-400">
                                    PI/ECC/LIC are hex codes; PTY is a numeric category shown by receivers.
                                </div>
                            </div>
                        </div>
                    </div>
                    
                    <div class="section">
                        <div class="section-header">Extended Country Code (ECC) & Language (LIC)</div>
                        <div class="section-body grid-cols-3">
                            <div class="stack-tight">
                                <label>ECC</label>
                                <div class="text-[9px] text-gray-500">Extended Country Code (hex).</div>
                                <input type="text" id="ecc" value="{{rds_state.ecc}}" onchange="sync()">
                            </div>
                            <div class="stack-tight">
                                <label>LIC</label>
                                <div class="text-[9px] text-gray-500">Language Identification Code (hex).</div>
                                <input type="text" id="lic" value="{{rds_state.lic}}" onchange="sync()">
                            </div>
                            <div class="stack-tight">
                                <label>Clock Offset</label>
                                <div class="text-[9px] text-gray-500">Local offset from UTC in hours.</div>
                                <input type="number" id="tz_offset" value="{{rds_state.tz_offset}}" onchange="sync()">
                            </div>
                            <div class="stack-tight">
                                <label>Enable CT</label>
                                <div class="text-[9px] text-gray-500">Send clock-time group (4A).</div>
                                <input type="checkbox" class="toggle-checkbox" id="en_ct" {% if rds_state.en_ct %}checked{% endif %} onchange="sync()">
                            </div>
                            <div class="stack-tight">
                                <label>Enable ID (1A)</label>
                                <div class="text-[9px] text-gray-500">Send ECC/LIC identification group.</div>
                                <input type="checkbox" class="toggle-checkbox" id="en_id" {% if rds_state.en_id %}checked{% endif %} onchange="sync()">
                            </div>
                        </div>
                    </div>
                    
                    <div class="section">
                        <div class="section-header">Long PS (Group 15)</div>
                        <div class="section-body">
                             <div class="stack-tight">
                                 <div class="flex gap-2 items-center">
                                     <label>Centre Text</label>
                                     <div class="text-[9px] text-gray-500">Center each 32-char segment.</div>
                                     <input type="checkbox" class="toggle-checkbox" id="lps_centered" {% if rds_state.lps_centered %}checked{% endif %} onchange="sync()">
                                 </div>
                                 <div class="flex gap-2 items-center">
                                     <label>Append CR</label>
                                     <div class="text-[9px] text-gray-500">Add carriage return terminator.</div>
                                     <input type="checkbox" class="toggle-checkbox" id="lps_cr" {% if rds_state.lps_cr %}checked{% endif %} onchange="sync()">
                                 </div>
                                 <div class="flex gap-2 items-center">
                                     <label>Enable LPS</label>
                                     <div class="text-[9px] text-gray-500">Send long PS group (15A).</div>
                                     <input type="checkbox" class="toggle-checkbox" id="en_lps" {% if rds_state.en_lps %}checked{% endif %} onchange="sync()">
                                 </div>
                                 <div class="stack-tight">
                                     <label>Long PS Text</label>
                                     <div class="text-[9px] text-gray-500">Up to 32 characters across multiple groups.</div>
                                     <input type="text" id="ps_long_32" value="{{rds_state.ps_long_32}}" onchange="sync()">
                                 </div>
                             </div>
                        </div>
                    </div>
                    
                    <div class="section">
                        <div class="section-header">PTY Name (Group 10A)</div>
                        <div class="section-body">
                             <div class="stack-tight">
                                 <div class="flex gap-2 items-center">
                                     <label>Centre Text</label>
                                     <div class="text-[9px] text-gray-500">Center the 8-char PTYN.</div>
                                     <input type="checkbox" class="toggle-checkbox" id="ptyn_centered" {% if rds_state.ptyn_centered %}checked{% endif %} onchange="sync()">
                                 </div>
                                 <div class="flex gap-2 items-center">
                                     <label>Enable PTYN</label>
                                     <div class="text-[9px] text-gray-500">Send PTY Name group (10A).</div>
                                     <input type="checkbox" class="toggle-checkbox" id="en_ptyn" {% if rds_state.en_ptyn %}checked{% endif %} onchange="sync()">
                                 </div>
                                 <div class="stack-tight">
                                     <label>PTY Name</label>
                                     <div class="text-[9px] text-gray-500">8-character PTY label shown on receivers.</div>
                                     <input type="text" id="ptyn" value="{{rds_state.ptyn}}" onchange="sync()">
                                 </div>
                             </div>
                        </div>
                    </div>
                    
                </div>
                
                <div id="monitoring" class="content active">
                    <div class="section">
                        <div class="section-header">RDS Monitoring</div>
                        <div class="section-body">
                             <div class="grid grid-cols-4 gap-2">
                                 <div>
                                     <label>PS</label>
                                     <div class="live-display sub" id="live_ps">OFF AIR</div>
                                 </div>
                                 <div>
                                     <label>PI</label>
                                     <div class="live-display sub text-center text-yellow-300" id="live_pi">—</div>
                                 </div>
                                 <div>
                                     <label>PTY</label>
                                     <div class="live-display sub text-center" id="live_pty">—</div>
                                 </div>
                                 <div>
                                     <label>PTYN</label>
                                     <div class="live-display sub" id="live_ptyn">—</div>
                                 </div>
                             </div>

                             <div>
                                 <label class="flex justify-between"><span>RT+ Status</span> <span class="text-xs text-gray-400">AID: 4BD7 (Group 11A)</span></label>
                                 <div class="live-display sub text-orange-300" id="live_rt_plus">—</div>
                             </div>

                            <div>
                                <label>Long PS (Group 15)</label>
                                <div class="live-display sub" id="live_lps">—</div>
                            </div>
                            <div>
                                <label>RadioText (RT)</label>
                                <div class="live-display sub" id="live_rt"></div>
                            </div>
                            <div class="text-[10px] text-gray-500">Live RDS values update while on air.</div>
                    </div>
                    </div>
                    <div class="section">
                        <div class="section-header">MPX Monitoring</div>
                        <div class="section-body">
                            <div class="grid grid-cols-2 gap-2">
                            <div>
                                <label>Input Device</label>
                                <div class="live-display sub" id="live_device_out">—</div>
                            </div>
                            <div>
                                <label>Output Device</label>
                                <div class="live-display sub" id="live_device_in">—</div>
                            </div>
                            </div>
                            <div class="monitor-peak-controls">
                                <div class="flex items-center gap-2">
                                    <label>Sticky Peaks</label>
                                    <input type="checkbox" class="toggle-checkbox" id="monitor_sticky_peaks">
                                    <span class="text-[10px] text-gray-500">Hold markers and text peaks with timed falloff.</span>
                                </div>
                                <div class="monitor-peak-config">
                                    <label for="monitor_peak_hold_ms">Hold</label>
                                    <select id="monitor_peak_hold_ms">
                                        <option value="500">0.5 s</option>
                                        <option value="1000">1.0 s</option>
                                        <option value="1500" selected>1.5 s</option>
                                        <option value="2000">2.0 s</option>
                                        <option value="3000">3.0 s</option>
                                    </select>
                                    <label for="monitor_peak_fall_dbps">Fall</label>
                                    <select id="monitor_peak_fall_dbps">
                                        <option value="8">8 dB/s</option>
                                        <option value="12">12 dB/s</option>
                                        <option value="18" selected>18 dB/s</option>
                                        <option value="24">24 dB/s</option>
                                        <option value="30">30 dB/s</option>
                                    </select>
                                    <button type="button" class="mini-btn" id="monitor_peak_reset">Reset Peaks</button>
                                </div>
                            </div>
                            <div>
                                <label>Input Level (Post Gain) <span class="help-tip" data-tip="Suggested: keep normal program around -18 to -12 dBFS RMS, with peaks typically below -6 dBFS to preserve processing headroom.">?</span></label>
                                <div class="meter-row">
                                    <div class="meter">
                                        <div class="meter-fill" id="mpx_input_meter_l"></div>
                                        <div class="meter-hold" id="mpx_input_hold_l"></div>
                                    </div>
                                    <div class="meter">
                                        <div class="meter-fill" id="mpx_input_meter_r"></div>
                                        <div class="meter-hold" id="mpx_input_hold_r"></div>
                                    </div>
                                    <div class="meter-db" id="mpx_input_db">-inf dBFS</div>
                                    <div class="meter-peak" id="mpx_input_peak">-inf pk</div>
                                    <div class="meter-peak" id="mpx_input_vu_l">L -inf VU</div>
                                    <div class="meter-peak" id="mpx_input_vu_r">R -inf VU</div>
                                </div>
                            </div>
                            <div>
                                <label>MPX Level <span class="help-tip" data-tip="Suggested: run close to target without hard limiting all the time. Keep sustained peaks near 0 dBFS equivalent and avoid frequent over-peak behavior.">?</span></label>
                                <div class="meter-row">
                                    <div class="meter">
                                        <div class="meter-fill" id="mpx_mpx_meter"></div>
                                        <div class="meter-hold" id="mpx_mpx_hold"></div>
                                    </div>
                                    <div class="meter-db" id="mpx_mpx_db">-inf dBFS</div>
                                    <div class="meter-peak" id="mpx_mpx_peak">-inf pk</div>
                                    <div class="meter-peak" id="mpx_mpx_vu">-inf VU</div>
                                </div>
                            </div>
                            <div>
                                <label>Modulation (kHz) <span class="help-tip" data-tip="Suggested FM target: loud passages around 65-75 kHz, occasional peaks near your legal limit. Avoid sustained operation above licensed deviation.">?</span></label>
                                <div class="meter-row">
                                    <div class="meter">
                                        <div class="meter-fill" id="modulation_meter"></div>
                                        <div class="meter-hold" id="modulation_hold"></div>
                                    </div>
                                <div class="meter-db" id="modulation_khz">0.0 kHz</div>
                                <div class="meter-peak text-gray-400">0-100 kHz</div>
                            </div>
                            </div>
                        </div>
                    </div>
                    <div class="section">
                        <div class="section-header">Limiters</div>
                        <div class="section-body">
                            <div class="grid grid-cols-2 gap-2">
                                <div>
                                    <label>MPX Limiter</label>
                                    <div class="live-display sub text-center" id="live_limiter">Idle</div>
                                </div>
                                <div>
                                    <label>Pre-emphasis Limiter</label>
                                    <div class="live-display sub text-center" id="live_preemph_limit">Off</div>
                                </div>
                                <div>
                                    <label>Composite Clipper</label>
                                    <div class="live-display sub text-center" id="live_composite_clip">Off</div>
                                </div>
                            </div>
                        </div>
                    </div>
                    <div class="section">
                        <div class="section-header">Processing</div>
                        <div class="section-body">
                            <div class="grid grid-cols-2 gap-2">
                                <div>
                                    <label>Multiband</label>
                                    <div class="live-display sub text-center" id="live_multiband">Off</div>
                                </div>
                                <div>
                                    <label>Orbass</label>
                                    <div class="live-display sub text-center" id="live_orbass">Off</div>
                                </div>
                                <div>
                                    <label>Widener</label>
                                    <div class="live-display sub text-center" id="live_widener">Off</div>
                                </div>
                            </div>
                        </div>
                    </div>
                    <div class="section">
                        <div class="section-header">Scopes</div>
                        <div class="section-body" style="display: block;">
                            <div class="scope-row">
                                <div class="scope-panel">
                                    <label>Stereo Input Scope</label>
                                    <canvas id="scope_input" width="360" height="120" class="scope-canvas w-full bg-black/70 border border-gray-700 rounded"></canvas>
                                </div>
                                <div class="scope-panel">
                                    <label>MPX Output Scope</label>
                                    <canvas id="scope_mpx" width="360" height="120" class="scope-canvas w-full bg-black/70 border border-gray-700 rounded"></canvas>
                                </div>
                            </div>
                        </div>
                    </div>
                </div>

                <div id="help" class="content">
                    <div class="section">
                        <div class="section-header">Monitor Audio Path</div>
                        <div class="section-body">
                            <div class="text-xs text-gray-400 mb-2">Demodulated monitor signal flow.</div>
                            <ul class="bg-black/50 border border-gray-700 rounded px-3 py-2 text-sm text-gray-200 leading-relaxed list-disc pl-5">
                                <li>MPX pre-gain</li>
                                <li>L+R low-pass (15 kHz)</li>
                                <li>L-R band-pass (23-53 kHz)</li>
                                <li>38 kHz demod</li>
                                <li>L-R low-pass (15 kHz)</li>
                                <li>Stereo decode</li>
                                <li>De-emphasis</li>
                                <li>Resample</li>
                                <li>Monitor out</li>
                            </ul>
                        </div>
                    </div>
                    <div class="section">
                        <div class="section-header">MPX + RDS Chain</div>
                        <div class="section-body">
                            <div class="text-xs text-gray-400 mb-2">Main stereo MPX chain (simplified).</div>
                            <ul class="bg-black/50 border border-gray-700 rounded px-3 py-2 text-sm text-gray-200 leading-relaxed list-disc pl-5">
                                <li>Source input or tone</li>
                                <li>Input gain</li>
                                <li>Wideband AGC (optional)</li>
                                <li>HPF</li>
                                <li>LPF</li>
                                <li>HF trim</li>
                                <li>Pilot notch</li>
                                <li>Orbass (optional)</li>
                                <li>Multiband (optional)</li>
                                <li>Stereo widen (optional)</li>
                                <li>L+R / L-R</li>
                                <li>Pre-emphasis</li>
                                <li>Pre-emphasis HF control (optional)</li>
                                <li>Lookahead limiter (optional)</li>
                                <li>Pre-emphasis limiter (optional)</li>
                                <li>Safety gain (post pre-emphasis)</li>
                                <li>38 kHz DSB + band-pass</li>
                                <li>L+R + DSB sum</li>
                                <li>Audio MPX LPF</li>
                                <li>DC block + notch</li>
                                <li>Composite clip (optional)</li>
                                <li>Deviation scale</li>
                                <li>Audio headroom trim</li>
                                <li>Pilot + RDS add</li>
                                <li>Output gain</li>
                            </ul>
                        </div>
                    </div>
                </div>

                <div id="settings" class="content">
                    <div class="stack">
                        <div class="section">
                            <div class="section-header">Network Access</div>
                            <div class="section-body">
                                <div>
                                    <label>Allowed Subnets (comma-separated)</label>
                                    <input type="text" id="allow_subnets" value="{{ ', '.join(server_config.get('allow_subnets', [])) }}" class="w-full bg-black/60 border border-gray-700 rounded px-3 py-2 text-sm focus:outline-none focus:ring-1 focus:ring-pink-500">
                                    <div class="text-[11px] text-gray-400 mt-1">Defaults to localhost (127.0.0.0/8, ::1/128).</div>
                                </div>
                            </div>
                        </div>
                        <div class="section">
                            <div class="section-header">Credentials</div>
                            <div class="section-body">
                                <div>
                                    <label>Username</label>
                                    <input type="text" id="auth_user" value="{{ auth_config.get('user','') }}" class="w-full bg-black/60 border border-gray-700 rounded px-3 py-2 text-sm focus:outline-none focus:ring-1 focus:ring-pink-500">
                                </div>
                                <div>
                                    <label>New Password</label>
                                    <input type="password" id="auth_pass" placeholder="Leave blank to keep current" class="w-full bg-black/60 border border-gray-700 rounded px-3 py-2 text-sm focus:outline-none focus:ring-1 focus:ring-pink-500">
                                </div>
                                <div class="flex gap-2 items-center">
                                    <button onclick="saveSettings()" class="bg-pink-600 hover:bg-pink-500 text-white font-semibold rounded px-4 py-2 text-sm transition">Save Settings</button>
                                </div>
                                <div id="settings_status" class="text-[11px] text-gray-400 mt-2"></div>
                            </div>
                        </div>
                    </div>
                </div>

                <div id="about" class="content">
                    <div class="section">
                        <div class="section-header">About</div>
                        <div class="section-body">
                            <div>
                                <label>Version</label>
                                <div class="live-display sub">StereoFool v{{ app_version }}</div>
                            </div>
                            <div>
                                <label>Purpose</label>
                                <div class="text-[11px] text-gray-300 leading-relaxed">
                                    Experimental FM MPX + RDS generator with a unified web control panel.
                                    Not certified for broadcast compliance.
                                </div>
                            </div>
                            <div>
                                <label>Standards References</label>
                                <div class="text-[11px] text-gray-300 leading-relaxed">
                                    EN 50067, IEC 62106, ITU-R BS.450.
                                </div>
                            </div>
                            <div>
                                <label>GitHub</label>
                                <div class="text-[11px] text-gray-300 leading-relaxed">
                                    <a href="https://github.com/bkram/stereofool" class="underline text-pink-300 hover:text-pink-200" target="_blank" rel="noopener">https://github.com/Bkram/stereofool</a>
                                </div>
                            </div>
                            <div>
                                <label>Copyright</label>
                                <div class="text-[11px] text-gray-300 leading-relaxed">
                                    Copyright 2026 Bkram.
                                </div>
                            </div>
                            </div>
                        </div>
                    </div>
                </div>

            </div>
        </div>
    </div>

<script id="app_state" type="application/json">{{ {'running': state.running, 'pty_list': pty_list}|tojson }}</script>
<script src="/static/app.js"></script>
</body>
</html>
"""
