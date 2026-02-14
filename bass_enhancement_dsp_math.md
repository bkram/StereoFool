# Audio Bass Boost / Enhancement DSP Research
## Mathematical Foundations and Implementation

---

## 1. Audio Bass Boost Algorithm - Harmonic Generation

### Overview
Harmonic generation creates additional harmonics from the fundamental bass frequencies, adding richness and perceived loudness to bass content.

### Mathematical Foundation

#### Nonlinear Waveshaping Function
The core approach uses a nonlinear transfer function to generate harmonics:

```
y(n) = f(x(n))
```

Where common transfer functions include:

**Soft Clipping (Hyperbolic Tangent):**
```
y(n) = tanh(k · x(n))
```
- k = drive/gain parameter (typically 1-10)
- Generates odd harmonics primarily

**Polynomial Waveshaping:**
```
y(n) = a₁·x(n) + a₂·x²(n) + a₃·x³(n) + ... + aₙ·xⁿ(n)
```
- Even powers (x², x⁴) generate even harmonics
- Odd powers (x³, x⁵) generate odd harmonics
- For bass enhancement, typically use: `y(n) = x(n) + 0.3·x²(n) + 0.1·x³(n)`

**Chebyshev Polynomial Shaping:**
```
Tₙ(x) = cos(n · arccos(x))
```
- T₂(x) = 2x² - 1 (generates 2nd harmonic)
- T₃(x) = 4x³ - 3x (generates 3rd harmonic)

### Implementation Steps

1. **Bandpass Filter Input** (isolate bass frequencies)
   ```
   fc_low = 20 Hz
   fc_high = 150 Hz (adjustable)
   ```

2. **Apply Nonlinear Function**
   ```
   y_harmonics(n) = tanh(k · x_bass(n))
   ```

3. **High-Pass Filter** (remove DC offset)
   ```
   H(z) = (1 - z⁻¹) / (1 - α·z⁻¹)
   where α = e^(-2π·fc/fs)
   fc = 10 Hz
   ```

4. **Mix with Original Signal**
   ```
   y_output(n) = x(n) + wet_mix · y_harmonics(n)
   wet_mix ∈ [0, 1]
   ```

### Frequency Domain Analysis

For input fundamental frequency f₀, the harmonic series generated is:
```
f_harmonics = {f₀, 2f₀, 3f₀, 4f₀, ..., nf₀}
```

The amplitude of the nth harmonic depends on the nonlinearity:
```
Aₙ = (2/π) ∫₀^π f(sin(θ)) · cos(nθ) dθ
```

---

## 2. Subharmonic Bass Synthesis - Clean Sine Wave DSP

### Overview
Generates subharmonics (frequencies below the fundamental) to extend perceived bass response on systems with limited low-frequency reproduction.

### Mathematical Foundation

#### Frequency Tracking
First, extract the fundamental frequency using autocorrelation or zero-crossing detection:

**Autocorrelation Method:**
```
R(τ) = Σ[n=0 to N-1] x(n) · x(n+τ)
```
Find the first peak after zero to determine period T:
```
f₀ = fs / T
```

#### Subharmonic Generation

**Direct Sine Synthesis:**
```
y_sub(n) = A · sin(2π · f_sub · n/fs + φ)
```
Where:
- `f_sub = f₀ / k` (k = 2 for octave down, k = 3 for perfect fifth down, etc.)
- A = amplitude (typically 0.3-0.7)
- φ = phase alignment (important for coherence)

**Phase-Locked Loop (PLL) Approach:**

1. **Phase Detector:**
   ```
   φ_error(n) = φ_input(n) - φ_VCO(n)
   ```

2. **Loop Filter:**
   ```
   φ_filtered(n) = φ_filtered(n-1) + α·φ_error(n)
   ```
   where α is the loop gain (0.01 - 0.1)

3. **Voltage Controlled Oscillator (VCO):**
   ```
   y_VCO(n) = sin(φ_filtered(n) / k)
   ```

### Advanced Subharmonic Synthesis

**Wavelet-Based Approach:**
```
y_sub(n) = IDWT(DWT(x(n)) ↓ k)
```
Where DWT = Discrete Wavelet Transform, ↓k = downsample by k

**Rectification and Filtering Method:**
```
1. x_rect(n) = |x(n)|²           (full-wave rectification)
2. Apply LPF at f₀/k
3. y_sub(n) = LPF(x_rect(n))
```

### Clean Sine Wave Extraction

To ensure clean subharmonics without artifacts:

**Windowed Overlap-Add (WOLA):**
```
1. Frame signal: x_frame(n) = x(n) · w(n)
   where w(n) = 0.5(1 - cos(2πn/N))  (Hann window)

2. FFT: X(k) = FFT(x_frame(n))

3. Find fundamental bin: k₀ = round(f₀ · N / fs)

4. Generate subharmonic:
   k_sub = k₀ / ratio
   Y(k_sub) = |X(k₀)| · e^(j·arg(X(k₀))/ratio)

5. IFFT and overlap-add
```

### Amplitude Envelope Following

Match subharmonic dynamics to input:
```
env(n) = α · |x(n)| + (1-α) · env(n-1)
```
where α = 1 - e^(-2.2/τ·fs), τ = time constant (10-50 ms)

Apply to subharmonic:
```
y_sub_env(n) = y_sub(n) · env(n)
```

---

## 3. Bass EQ Shelf Filter Algorithm

### Overview
Shelving filters boost or cut frequencies below a specified corner frequency, ideal for bass enhancement.

### Low Shelf Filter Design

#### Biquad Implementation

**Transfer Function:**
```
H(z) = (b₀ + b₁·z⁻¹ + b₂·z⁻²) / (1 + a₁·z⁻¹ + a₂·z⁻²)
```

**Difference Equation:**
```
y(n) = b₀·x(n) + b₁·x(n-1) + b₂·x(n-2) - a₁·y(n-1) - a₂·y(n-2)
```

#### Coefficient Calculation (Robert Bristow-Johnson)

Parameters:
- fc = corner frequency (Hz)
- fs = sample rate (Hz)
- G = gain (dB)
- Q = shelf slope (typically 0.707 for Butterworth response)

**Precompute:**
```
A = 10^(G/40)
ω₀ = 2π·fc/fs
cos_ω₀ = cos(ω₀)
sin_ω₀ = sin(ω₀)
α = sin_ω₀/(2·Q)
```

**Low Shelf Coefficients:**
```
A_plus_1 = A + 1
A_minus_1 = A - 1
sqrt_A = √A

b₀ = A · ((A+1) - (A-1)·cos_ω₀ + 2·√A·α)
b₁ = 2·A · ((A-1) - (A+1)·cos_ω₀)
b₂ = A · ((A+1) - (A-1)·cos_ω₀ - 2·√A·α)

a₀ = (A+1) + (A-1)·cos_ω₀ + 2·√A·α
a₁ = -2 · ((A-1) + (A+1)·cos_ω₀)
a₂ = (A+1) + (A-1)·cos_ω₀ - 2·√A·α
```

**Normalize:**
```
b₀ = b₀/a₀
b₁ = b₁/a₀
b₂ = b₂/a₀
a₁ = a₁/a₀
a₂ = a₂/a₀
```

### Frequency Response

**Magnitude Response:**
```
|H(ω)| = √[(b₀ + b₁·cos(ω) + b₂·cos(2ω))² + (b₁·sin(ω) + b₂·sin(2ω))²] / 
         √[(1 + a₁·cos(ω) + a₂·cos(2ω))² + (a₁·sin(ω) + a₂·sin(2ω))²]
```

Where ω = 2πf/fs

**Phase Response:**
```
φ(ω) = atan2(b₁·sin(ω) + b₂·sin(2ω), b₀ + b₁·cos(ω) + b₂·cos(2ω)) -
       atan2(a₁·sin(ω) + a₂·sin(2ω), 1 + a₁·cos(ω) + a₂·cos(2ω))
```

### Alternative: State Variable Filter

**Low Shelf SVF:**
```
LP(n) = LP(n-1) + F · BP(n-1)
BP(n) = BP(n-1) + F · (x(n) - LP(n) - Q · BP(n-1))
y(n) = x(n) + G · LP(n)
```

Where:
```
F = 2·sin(π·fc/fs)
Q = damping (0.5 to 10)
G = shelf gain factor
```

### Cascaded Shelf Design

For steeper shelf slopes, cascade multiple stages:
```
H_total(z) = H₁(z) · H₂(z) · ... · Hₙ(z)
```

Each stage uses:
- Same fc
- G_stage = G_total^(1/n)
- Q typically 0.707 for flat response

---

## 4. Psychoacoustic Bass Enhancement Technique

### Overview
Exploits psychoacoustic phenomena where the brain reconstructs missing fundamentals from harmonics (missing fundamental effect/virtual pitch).

### Missing Fundamental Theory

When harmonics are present without the fundamental:
```
Input: {2f₀, 3f₀, 4f₀, 5f₀, ...}
Perceived: f₀ (virtual fundamental)
```

**Mathematical Model:**
The pitch salience function S(f) for a complex tone:
```
S(f) = Σᵢ W(i) · cos(2π·i·f·τ)
```
Where:
- i = harmonic number
- W(i) = harmonic weight (decreases with i)
- τ = autocorrelation lag

### Implementation Algorithm

#### 1. Harmonic Generation from Bass

**Input Filtering:**
```
H_bp(z) = bandpass filter [40 Hz - 150 Hz]
x_bass(n) = H_bp(z) · x(n)
```

**Generate Harmonics (non-linear processing):**
```
x_nl(n) = tanh(k · x_bass(n))
```

**Extract Harmonic Band:**
```
H_harmonics(z) = bandpass filter [f₀·2 to f₀·6]
x_harmonics(n) = H_harmonics(z) · x_nl(n)
```

#### 2. Frequency Domain Processing

**STFT-based approach:**
```
X(k) = Σ[n=0 to N-1] x(n) · w(n) · e^(-j2πkn/N)
```

For each detected fundamental frequency bin k₀:
1. Measure amplitude: A₀ = |X(k₀)|
2. Suppress or remove fundamental: X'(k₀) = 0 or X'(k₀) = 0.3·X(k₀)
3. Enhance harmonics:
   ```
   X'(2k₀) = β₂ · X(2k₀)  (β₂ = 1.2-1.5)
   X'(3k₀) = β₃ · X(3k₀)  (β₃ = 1.1-1.3)
   X'(4k₀) = β₄ · X(4k₀)  (β₄ = 1.0-1.2)
   ```

#### 3. Temporal Masking

**Forward Masking Model:**
```
M(t, f) = L₀ · e^(-α·t) · 10^(-β·|f-fc|)
```
Where:
- L₀ = masker level (dB)
- α = temporal decay constant (≈ 0.1 ms⁻¹)
- β = frequency spread constant
- fc = masker center frequency

**Apply Masking Threshold:**
Only boost components above masking threshold:
```
if |X(k)| > M(t, f_k):
    X'(k) = G · X(k)
else:
    X'(k) = X(k)
```

#### 4. Equal Loudness Contours

Account for Fletcher-Munson curves to compensate for reduced bass perception at low SPL:

**Loudness Level Adjustment:**
```
L_adj(f) = L(f) + C(f, L_ref)
```

Where C(f, L_ref) is the correction factor from ISO 226:2003 standard.

**Approximate correction at 50 Hz:**
```
Gain_50Hz(L) = 20·log₁₀(1 + e^((40-L)/10))
```

### Transient Preservation

Critical to maintain bass attack and punch:

**Transient Detection:**
```
d(n) = |x(n)| - |x(n-1)|
if d(n) > threshold:
    transient_flag = true
```

**Bypass Enhancement During Transients:**
```
if transient_flag:
    y(n) = x(n)  (for T_hold samples)
else:
    y(n) = enhanced(x(n))
```

### Binaural Bass Enhancement

For headphone listening, create phantom bass using interaural time differences:

**ITD Processing:**
```
y_L(n) = x(n) + α · x(n - τ_L)
y_R(n) = x(n) + α · x(n - τ_R)
```

Where:
- τ_L, τ_R = delay samples (0.1-0.8 ms difference)
- α = wet mix (0.3-0.6)

**Frequency-dependent ITD:**
```
τ(f) = τ_max · (f₀/f)  for f < 500 Hz
```

### Combined Psychoacoustic Algorithm

**Full Processing Chain:**

```
1. Input: x(n)

2. Transient Detection:
   detect_transients(x(n)) → flags

3. Frequency Analysis:
   X(k) = STFT(x(n))
   f₀ = find_fundamental(X(k))

4. Harmonic Enhancement:
   if not transient:
       X_harm(k) = enhance_harmonics(X(k), f₀)
   
5. Fundamental Suppression:
   X_enh(k₀) = suppress_ratio · X(k₀)
   
6. Loudness Compensation:
   X_loud(k) = apply_equal_loudness(X_enh(k))
   
7. Reconstruction:
   y(n) = ISTFT(X_loud(k))
   
8. Output mixing:
   y_out(n) = (1-mix) · x(n) + mix · y(n)
```

### Perceptual Metrics

**Loudness Calculation (ITU-R BS.1770):**
```
L_K = -0.691 + 10·log₁₀(Σ G_i · z²_i)
```
Where G_i are channel weights and z_i are filtered channel levels.

**Just Noticeable Difference (JND) for Frequency:**
```
Δf/f ≈ 0.002 to 0.005 (for pure tones)
Δf ≈ 1 Hz (for bass frequencies)
```

Use JND to determine minimum frequency resolution for processing.

---

## Implementation Considerations

### Sample Rate Requirements
- Minimum: 44.1 kHz
- Recommended: 48 kHz or higher
- For subharmonic synthesis below 20 Hz: 96 kHz recommended

### Latency Management
```
Total_latency = Filter_latency + Processing_latency + Buffer_latency

Typical values:
- Biquad filter: ~0.5-2 ms
- FFT processing (2048 samples @ 48kHz): ~43 ms
- Real-time target: <10 ms total
```

### Numeric Stability

**Avoid Direct Form I for IIR filters** when |a₁|, |a₂| are large.

**Use Direct Form II Transposed:**
```
w(n) = x(n) - a₁·w(n-1) - a₂·w(n-2)
y(n) = b₀·w(n) + b₁·w(n-1) + b₂·w(n-2)
```

**Fixed-point considerations:**
- Use Q15 or Q31 format
- Apply gain compensation: multiply by 2^(-scale) before processing, 2^scale after

### Anti-Aliasing for Nonlinear Processing

**Oversample before waveshaping:**
```
1. Upsample by factor L (typically 4x or 8x)
2. Apply nonlinear function
3. Lowpass filter at fs/2
4. Downsample by L
```

---

## Example Parameter Sets

### Subtle Bass Enhancement (mixing)
- Harmonic generation: k=1.5, mix=0.2
- Subharmonic: none
- Shelf filter: +3dB @ 80Hz, Q=0.707
- Psychoacoustic: fundamental suppress 0.7, harmonics +1.5dB

### Aggressive Bass Boost (EDM/Hip-Hop)
- Harmonic generation: k=3.0, mix=0.4
- Subharmonic: octave down, amplitude=0.4
- Shelf filter: +6dB @ 100Hz, Q=1.0
- Psychoacoustic: fundamental suppress 0.5, harmonics +3dB

### Headphone Bass Extension
- Harmonic generation: k=2.0, mix=0.3
- Subharmonic: octave down, amplitude=0.5
- Shelf filter: +4dB @ 60Hz, Q=0.707
- Psychoacoustic: binaural processing, ITD=0.3ms

### Small Speaker Compensation
- Harmonic generation: k=2.5, mix=0.5
- Subharmonic: octave down + 5th down, amplitude=0.6
- Shelf filter: +8dB @ 120Hz, Q=1.2
- Psychoacoustic: strong harmonic emphasis, fundamental suppress 0.3

---

## 5. Waveshaping Tanh Soft Clipping - Artifacts & HF Noise Mitigation

### Overview
While tanh() provides smooth saturation for harmonic generation, it introduces high-frequency artifacts and aliasing that must be managed for clean bass enhancement.

### Problem Analysis

**Tanh Nonlinearity:**
```
y(n) = tanh(k · x(n)) = (e^(kx) - e^(-kx)) / (e^(kx) + e^(-kx))
```

**Issues:**
1. **Aliasing** - Harmonics beyond Nyquist fold back into audible range
2. **HF Noise** - Rapid transitions create broadband noise
3. **Intermodulation** - Multiple frequencies create sum/difference products
4. **DC Offset** - Asymmetric signals can introduce DC

### Artifact Mitigation Techniques

#### 1. Oversampling and Downsampling

**Process Flow:**
```
x(n) → [Upsample L] → [Tanh] → [LPF] → [Downsample L] → y(n)
```

**Upsampling (Zero-Stuffing + Interpolation):**
```
x_up(n) = { x(n/L)  if n mod L = 0
          { 0       otherwise

H_interp(z) = Σ[k=0 to M] h(k) · z^(-k)
```

Where h(k) is a lowpass FIR filter with cutoff at fs/(2L).

**Typical Oversampling Factors:**
- 2x: Minimal, only catches first fold
- 4x: Good balance of quality/CPU
- 8x: Excellent quality for critical applications
- 16x: Overkill for most bass processing

**Mathematical Justification:**
If input has content up to fs/2, after oversampling by L:
- Original content: 0 to fs/2
- Tanh harmonics extend to: n·fs/2
- Safe harmonics before aliasing: up to L·fs/2

For bass processing (input band-limited to 150 Hz):
```
Max_harmonic = floor((L·fs/2) / f_input)

Example: 48kHz, 4x oversample, 100Hz input
Max_harmonic = floor((4·24000) / 100) = 960th harmonic
```

#### 2. Anti-Aliasing Filter Design

**Minimum-Phase FIR Filter:**
```
h(n) = w(n) · sinc(π·n·fc/fs)
```

Where w(n) is a Kaiser window:
```
w(n) = I₀(β·√(1-(2n/N-1)²)) / I₀(β)
```

- I₀ = modified Bessel function of first kind
- β = shape parameter (5-9 for audio)
- N = filter length (typically 64-256 taps)
- fc = cutoff at fs_original/2

**Optimized Polyphase Implementation:**

For L=4 oversampling, split FIR into 4 phases:
```
h₀(n) = h(4n)
h₁(n) = h(4n+1)
h₂(n) = h(4n+2)
h₃(n) = h(4n+3)
```

Filtering becomes:
```
y₀(m) = Σ h₀(k)·x(m-k)
y₁(m) = Σ h₁(k)·x(m-k)
y₂(m) = Σ h₂(k)·x(m-k)
y₃(m) = Σ h₃(k)·x(m-k)
```

#### 3. Bandlimited Waveshaping

**Polynomial Approximation of Tanh:**

Instead of direct tanh, use bandlimited polynomial series:
```
tanh(x) ≈ x - x³/3 + 2x⁵/15 - 17x⁷/315 + ...
```

For bass (low-frequency) input, truncate at desired harmonic:
```
y_bl(x) = x - x³/3  (only generates 3rd harmonic)
```

**Piecewise Linear Approximation:**
```
         { k·x           if |x| < T₁
y_pwl = { T₁·k + (x-T₁)·m  if T₁ ≤ |x| < T₂
         { T₂              if |x| ≥ T₂
```

Where:
- T₁ = linear threshold (0.3-0.5)
- T₂ = hard limit (0.9-1.0)
- m = slope in transition region (0.1-0.3)

#### 4. Pre-filtering

**Aggressive Input Bandlimiting:**
```
H_pre(z) = cascaded lowpass at fc = 200-300 Hz
```

Reduces harmonic content before nonlinear stage, limiting maximum generated frequency.

**Multi-band Processing:**
```
1. Split input into bands:
   Band 1: 20-80 Hz
   Band 2: 80-200 Hz
   Band 3: 200-500 Hz (optional)

2. Apply different tanh drives per band:
   k₁ = 3.0 (sub-bass, strong effect)
   k₂ = 2.0 (mid-bass, moderate)
   k₃ = 1.0 (upper-bass, subtle)

3. Recombine with crossover filters
```

#### 5. DC Blocking

**High-Pass Filter (DC Removal):**
```
H_dc(z) = (1 - z^(-1)) / (1 - α·z^(-1))
```

Where:
```
α = e^(-2π·fc/fs)
fc = 5-10 Hz (subsonic cutoff)
```

**DC Detection and Compensation:**
```
dc_estimate(n) = α·dc_estimate(n-1) + (1-α)·y(n)
y_corrected(n) = y(n) - dc_estimate(n)

α = 0.995 to 0.999 (slow tracking)
```

#### 6. Dithering for Low-Level Signals

When processing at low amplitudes, quantization can add HF noise:

**TPDF Dither:**
```
dither(n) = (rand() - rand()) · LSB/2
y_dithered(n) = y(n) + dither(n)
```

Where LSB = 2^(-bits+1)

#### 7. Dynamic Limiting

**Pre-Emphasis with Soft Knee:**
```
if |x(n)| > threshold:
    x_limited(n) = sign(x(n)) · (threshold + (|x(n)|-threshold)/ratio)
else:
    x_limited(n) = x(n)
```

Prevents excessive drive into tanh, reducing HF content.

### Complete Clean Tanh Implementation

```
Algorithm: Clean_Tanh_Bass_Enhancement

Input: x(n), fs, drive_k, mix

1. Pre-filter (bandlimit to bass):
   x_bass(n) = BPF(x(n), 30Hz, 180Hz)

2. Upsample 4x:
   x_up(n) = Interpolate(x_bass(n), L=4)
   fs_up = 4 · fs

3. Apply tanh with DC blocking:
   y_up(n) = tanh(drive_k · x_up(n))
   y_up(n) = HPF(y_up(n), fc=10Hz)

4. Anti-alias filter:
   y_filt(n) = LPF(y_up(n), fc=fs/2, order=8)

5. Downsample 4x:
   y(n) = Decimate(y_filt(n), L=4)

6. Remove residual DC:
   y(n) = DCBlock(y(n))

7. High-shelf to compensate HF roll-off:
   y(n) = HighShelf(y(n), fc=5kHz, gain=1.5dB)

8. Mix with dry signal:
   output(n) = (1-mix)·x(n) + mix·y(n)

Return: output(n)
```

### Measuring Artifacts

**THD+N (Total Harmonic Distortion + Noise):**
```
THD+N = √(P_harmonics + P_noise) / P_fundamental
```

**SINAD (Signal to Noise and Distortion):**
```
SINAD = 20·log₁₀(P_signal / P_noise+distortion)
```

**Target Values:**
- THD+N < 0.1% (-60 dB) for clean processing
- SINAD > 70 dB

**IMD (Intermodulation Distortion) Test:**
Use dual-tone input (e.g., 60 Hz + 7 kHz):
```
f₁ = 60 Hz
f₂ = 7000 Hz

Measure artifacts at:
f₂ ± n·f₁ (n = 1,2,3,...)
```

### Optimized Tanh Approximation

**Rational Function (Faster than std::tanh):**
```
fast_tanh(x) = x·(27 + x²) / (27 + 9·x²)

Error: < 0.001 for |x| < 3
```

**Lookup Table with Linear Interpolation:**
```
table_size = 8192
x_scaled = x · (table_size/2)
index = floor(x_scaled)
frac = x_scaled - index
y = table[index] + frac·(table[index+1] - table[index])
```

---

## 6. FM Broadcast Bass Processor - Clean Without RDS Interference

### Overview
FM broadcast requires bass processing that maintains peak modulation control, doesn't interfere with 19kHz pilot tone or 57kHz RDS subcarrier, and meets ITU-R BS.412 specs.

### FM Broadcast Constraints

**Critical Frequencies:**
- Pilot tone: 19 kHz (±2 Hz)
- L-R stereo: 23-53 kHz (suppressed carrier at 38 kHz)
- RDS/RBDS: 57 kHz ±2 Hz (subcarrier)
- SCA (optional): 67 kHz, 92 kHz
- Maximum deviation: ±75 kHz (USA), ±50 kHz (Europe)

**Modulation Limits:**
```
Total_modulation = L+R + pilot + (L-R) + RDS
Must not exceed: ±75 kHz deviation
```

### Pre-Emphasis Considerations

**Standard Pre-Emphasis (75µs USA, 50µs Europe):**
```
H_pre(s) = (1 + s·τ) / (s·τ)

τ_USA = 75µs → fc = 2.12 kHz
τ_EUR = 50µs → fc = 3.18 kHz
```

**Digital Implementation (75µs):**
```
K = 2·fs·τ
b₀ = K/(K+1)
b₁ = -K/(K+1)
a₁ = (K-1)/(K+1)

y(n) = b₀·x(n) + b₁·x(n-1) - a₁·y(n-1)
```

Bass boost must account for pre-emphasis already boosting highs 17dB @ 15kHz.

### Bass Processing Architecture

#### Stage 1: Clean Bass Extraction

**Ultra-Steep Lowpass Filter:**
```
Cutoff: 150 Hz
Stopband: >19 kHz
Attenuation: >80 dB @ 19 kHz
```

Use elliptic (Cauer) filter for steep transition:
```
Order: 8-10
Ripple: 0.1 dB
Stopband: 80 dB
```

**Elliptic Filter Design:**
```
H(s) = K · Π(s² + ω²ᵢ) / Π(s² + 2ζⱼωⱼs + ω²ⱼ)
```

Convert to digital using bilinear transform with pre-warping:
```
ω_analog = (2/T)·tan(ω_digital·T/2)
s → (2/T)·(1-z⁻¹)/(1+z⁻¹)
```

#### Stage 2: Bass Enhancement Without HF Pollution

**Strictly Bandlimited Harmonic Generation:**

```
1. Extract bass band (20-150 Hz)
2. Oversample 8x (to 384 kHz for 48kHz source)
3. Apply soft tanh: y = tanh(k·x)
4. Brick-wall LPF at 500 Hz
5. Downsample 8x
6. Verify no content >1 kHz (FFT analysis)
```

**Wavelet-Based Bass Enhancement:**
```
1. DWT (Discrete Wavelet Transform):
   W = DWT(x(n))
   
2. Enhance only bass scale coefficients:
   W'[scale_bass] = gain · W[scale_bass]
   
3. Suppress all scales >500 Hz:
   W'[scale_high] = 0
   
4. Reconstruct:
   y(n) = IDWT(W')
```

Wavelets guarantee no HF leakage due to time-frequency localization.

#### Stage 3: Peak Modulation Control

**Composite Clipper:**

Must prevent total modulation >100%:
```
composite(t) = (L+R) + pilot + stereo(L-R) + RDS
```

**Fast Peak Detector:**
```
peak(n) = max(|composite(n)|, α·peak(n-1))

α = e^(-1/(fs·τ_release))
τ_release = 100ms to 500ms
```

**Soft Knee Limiter:**
```
if peak(n) > threshold:
    gain_reduction = threshold / peak(n)
    gain_smooth(n) = α_attack·gain_reduction + (1-α_attack)·gain_smooth(n-1)
else:
    gain_smooth(n) = 1.0

output(n) = input(n) · gain_smooth(n)
```

Attack time: 0.1-1.0 ms
Release time: 100-500 ms

#### Stage 4: RDS Protection Filter

**Notch at 57 kHz:**
```
H_notch(z) = (b₀ + b₁·z⁻¹ + b₂·z⁻²) / (1 + a₁·z⁻¹ + a₂·z⁻²)
```

**Design parameters:**
- fc = 57 kHz
- Q = 20-50 (narrow notch)
- Depth: -40 dB minimum

**Coefficient Calculation:**
```
ω₀ = 2π·fc/fs
α = sin(ω₀)/(2·Q)
cos_ω₀ = cos(ω₀)

b₀ = 1
b₁ = -2·cos_ω₀
b₂ = 1
a₀ = 1 + α
a₁ = -2·cos_ω₀
a₂ = 1 - α

Normalize by a₀
```

**Cascaded Protection:**
```
H_total(z) = H_notch_57kHz(z) · H_notch_19kHz(z) · H_notch_38kHz(z)
```

### Multiband Processing for FM

**Crossover Frequencies:**
```
Band 1: 20-100 Hz (sub-bass)
Band 2: 100-300 Hz (bass)
Band 3: 300-3000 Hz (mids)
Band 4: 3k-15k Hz (highs)
```

**Linkwitz-Riley Crossover (4th order):**
```
H_LP(s) = 1 / (1 + s/ωc)²
H_HP(s) = (s/ωc)² / (1 + s/ωc)²

Property: |H_LP|² + |H_HP|² = 1 (perfect reconstruction)
```

**Per-Band Processing:**
```
Band 1: +6 dB shelf, light compression (3:1)
Band 2: +3 dB shelf, moderate compression (4:1)
Band 3: +0 dB, heavy compression (10:1) for loudness
Band 4: +2 dB (pre-emphasis compensates), soft limit
```

### AGC (Automatic Gain Control)

**Slow AGC for Consistency:**
```
envelope(n) = max(α·envelope(n-1), |x(n)|)
α = e^(-1/(fs·τ))
τ = 1-5 seconds

gain(n) = target_level / envelope(n)
gain_limited = clip(gain, min=0.5, max=2.0)
```

**Fast AGC for Peak Control:**
```
τ_attack = 1ms
τ_release = 100ms

Fast peaks are caught, slow release maintains loudness
```

### Stereo Encoding Considerations

**L-R Bandwidth Limiting:**

Bass boost in L-R channel increases deviation:
```
Δf_total ∝ |L+R| + |L-R|
```

**Solution: Bass correlation in low frequencies:**
```
if f < 100 Hz:
    L_out = 0.5·(L + R)
    R_out = 0.5·(L + R)
    
Result: L-R ≈ 0 for bass, reduced deviation
```

### Complete FM Bass Processor

```
Algorithm: FM_Broadcast_Bass_Processor

Input: L(n), R(n), fs=192kHz (or 96kHz minimum)

1. Pre-processing:
   L_sum = L + R
   L_diff = L - R

2. Bass extraction from sum channel:
   bass_sum(n) = Elliptic_LPF(L_sum, fc=150Hz)

3. Bass enhancement (strictly bandlimited):
   bass_enh(n) = Oversample_8x(bass_sum)
   bass_enh(n) = tanh(2.0 · bass_enh(n))
   bass_enh(n) = BrickWall_LPF(bass_enh(n), fc=400Hz)
   bass_enh(n) = Downsample_8x(bass_enh(n))

4. Bass to mono below 100Hz:
   bass_final(n) = bass_enh(n)  // mono by nature of sum channel

5. Recombine:
   L_full(n) = HighPass(L(n), 150Hz) + bass_final(n)
   R_full(n) = HighPass(R(n), 150Hz) + bass_final(n)

6. Multiband compression:
   L_comp(n), R_comp(n) = FourBand_Compress(L_full, R_full)

7. Stereo encode:
   L_R_sum = L_comp + R_comp
   L_R_diff = L_comp - R_comp

8. RDS/Pilot protection:
   L_R_sum = Notch_Cascade(L_R_sum, [19k, 38k, 57k])
   L_R_diff = Notch_Cascade(L_R_diff, [19k, 38k, 57k])

9. Peak limiting:
   composite = L_R_sum + pilot + modulated_L_R_diff + RDS
   composite = Soft_Limit(composite, threshold=-1.0dB)

10. Pre-emphasis:
    L_out = PreEmph_75us(L_final)
    R_out = PreEmph_75us(R_final)

Return: L_out(n), R_out(n), composite_MPX
```

### Monitoring and Compliance

**Real-Time Measurements:**
```
1. Peak deviation: max|composite(t)|
2. RMS deviation: sqrt(mean(composite²(t)))
3. Pilot injection: 8-10% (±0.75 kHz deviation)
4. Spectral analysis: FFT showing pilot, stereo, RDS
```

**ITU-R BS.412 Compliance:**
- Peak deviation: ≤75 kHz (100% modulation)
- Pilot tone: 19 kHz ±2 Hz, 8-10% injection
- RDS: 57 kHz ±2 Hz, 2-4% injection
- Pre-emphasis: 75µs (USA) or 50µs (Europe)

---

## 7. MaxxBass Algorithm Implementation DSP

### Overview
MaxxBass (by Waves Audio) is a psychoacoustic bass enhancement that generates harmonics to create the perception of lower frequencies on small speakers. This is a clean-room mathematical implementation.

### Core Principle

**Missing Fundamental Perception:**

When harmonics 2f₀, 3f₀, 4f₀ are present, the brain perceives f₀ even if it's absent:
```
Input: [2f₀, 3f₀, 4f₀, 5f₀, ...]
Perceived: f₀ (phantom fundamental)
```

### Algorithm Architecture

#### Stage 1: Frequency Analysis & Tracking

**Real-Time Pitch Detection:**

Use autocorrelation for robust fundamental detection:
```
R(τ) = Σ[n=0 to N-1] x(n)·x(n+τ)
```

Find maximum in expected bass range:
```
τ_min = fs / f_max  (e.g., fs/200Hz)
τ_max = fs / f_min  (e.g., fs/40Hz)

τ_peak = argmax{R(τ) : τ_min ≤ τ ≤ τ_max}
f₀ = fs / τ_peak
```

**Improved YIN Algorithm:**
```
d(τ) = Σ[n=0 to N-1] (x(n) - x(n+τ))²

d'(τ) = d(τ) / [(1/τ)·Σ[j=1 to τ] d(j)]

τ_best = argmin{d'(τ)}
```

#### Stage 2: Harmonic Extraction

**Comb Filtering:**

Extract harmonics at integer multiples of f₀:
```
H_comb(z) = (1 - α·z^(-M)) / (1 - z^(-M))
```

Where:
- M = fs/f₀ (delay samples)
- α = 0.95-0.99 (feedback gain)

**Multi-Tap Harmonic Filter:**
```
y(n) = Σ[k=1 to K] w_k · x(n - k·M)

Where:
M = fs/f₀
K = number of harmonics (typically 3-6)
w_k = harmonic weights (decreasing with k)
```

#### Stage 3: Nonlinear Harmonic Generation

**Controlled Distortion Function:**

MaxxBass uses asymmetric waveshaping to emphasize even harmonics:
```
if x(n) ≥ 0:
    y(n) = x(n)·(1 + k₁·x(n))
else:
    y(n) = x(n)·(1 + k₂·x(n)²)
```

Where k₁ ≠ k₂ creates even harmonics.

**Optimized Transfer Function:**
```
y = x / (1 + |x|^p)

p = 1.5 to 2.5
```

Generates smooth harmonic spectrum without harsh clipping.

#### Stage 4: Harmonic Placement

**Intelligent Frequency Shifting:**

Place harmonics at perceptually optimal locations:
```
For fundamental f₀:
  h₂ = 2·f₀ (octave)
  h₃ = 3·f₀ (octave + fifth)
  h₄ = 4·f₀ (2 octaves)

If f₀ < 50Hz:
  emphasis on h₂ and h₃
If f₀ > 80Hz:
  emphasis on h₂ only
```

**Adaptive Harmonic Balance:**
```
w₂(f₀) = 1.0
w₃(f₀) = 0.5 + 0.5·(150-f₀)/100  (decreases as f₀ increases)
w₄(f₀) = 0.3
```

#### Stage 5: Spectral Weighting

**Perceptual EQ Curve:**

Apply equal-loudness compensation:
```
W(f) = √(f² + f_a²) / (f² + f_b²)

f_a = 500 Hz
f_b = 50 Hz
```

This boosts perceptually important mid-bass harmonics.

**Dynamic EQ:**
```
For bass-heavy content:
  reduce harmonic gain

For bass-light content:
  increase harmonic gain

gain_factor = 1.0 / (1.0 + bass_energy/reference_energy)
```

#### Stage 6: Transient Preservation

**Critical for punch and clarity:**

```
1. Detect transients:
   d(n) = |x(n)| - |x(n-1)|
   if d(n) > threshold:
       transient_flag = true

2. During transients (0-20ms):
   bypass_harmonic_generation()
   output = input  (preserve attack)

3. After transient (20-100ms):
   fade_in_harmonics()
   output = lerp(input, enhanced, fade_factor)
```

**Envelope Shaper:**
```
env(n) = α_attack·|x(n)| + (1-α_attack)·env(n-1)  if |x(n)| > env(n-1)
env(n) = α_release·|x(n)| + (1-α_release)·env(n-1)  if |x(n)| ≤ env(n-1)

α_attack = 1 - e^(-1/(fs·τ_attack))
α_release = 1 - e^(-1/(fs·τ_release))

τ_attack = 5ms
τ_release = 50ms
```

### Complete MaxxBass Implementation

```
Algorithm: MaxxBass_Enhancement

Input: x(n), fs, f_cutoff, intensity

Parameters:
  f_cutoff = 200 Hz (upper bass limit)
  intensity = 0.0 to 1.0 (effect strength)

1. Extract bass region:
   x_bass(n) = Butterworth_LPF(x(n), fc=f_cutoff, order=4)

2. Detect fundamental frequency:
   f₀(n) = YIN_pitch_detect(x_bass(n))
   f₀_smooth(n) = median_filter(f₀(n), window=5)

3. Generate harmonic structure:
   // Split into fine frequency bands
   X(k) = FFT(x_bass(n))
   
   for each detected_fundamental f₀:
       // Enhance harmonics
       k₂ = round(2·f₀·N/fs)
       k₃ = round(3·f₀·N/fs)
       k₄ = round(4·f₀·N/fs)
       
       X'(k₂) = X(k₂) · (1 + 0.8·intensity)
       X'(k₃) = X(k₃) · (1 + 0.5·intensity)
       X'(k₄) = X(k₄) · (1 + 0.3·intensity)
       
       // Optional: suppress fundamental
       k₀ = round(f₀·N/fs)
       X'(k₀) = X(k₀) · (1 - 0.3·intensity)

4. Nonlinear enhancement (time domain alternative):
   x_nl(n) = x_bass(n) / (1 + |x_bass(n)|^1.8)
   
5. Bandpass filter harmonics:
   x_harm(n) = Butterworth_BPF(x_nl(n), f_low=100Hz, f_high=500Hz)

6. Apply perceptual weighting:
   x_weighted(n) = EQ_curve(x_harm(n))

7. Transient detection and bypass:
   if transient_detected(x_bass(n)):
       x_final(n) = x_bass(n)
   else:
       x_final(n) = x_harm(n)

8. Dynamic level compensation:
   bass_level = RMS(x_bass(n))
   harm_level = RMS(x_harm(n))
   gain_comp = bass_level / (harm_level + ε)
   x_comp(n) = x_harm(n) · min(gain_comp, 2.0)

9. Mix with original:
   x_enhanced(n) = intensity · x_comp(n)
   
10. Recombine with full-range signal:
    x_high(n) = HPF(x(n), fc=f_cutoff)
    output(n) = x_high(n) + x_enhanced(n)

Return: output(n)
```

### Perceptual Optimization

**Critical Bands Approach:**

Use Bark scale for frequency grouping:
```
Bark(f) = 13·atan(0.00076·f) + 3.5·atan((f/7500)²)
```

Process each critical band independently:
```
For band_center in [50, 70, 100, 150, 200] Hz:
    extract_band()
    generate_harmonics()
    apply_masking_threshold()
    recombine()
```

**Masking Threshold:**
```
Threshold(f, f_masker) = SPL_masker - Attenuation(f - f_masker)

Attenuation(Δf) = {
    -27 + 0.37·max(SPL-40, 0)     if Δf < 0 (below masker)
    -27 + 0.37·max(SPL-40, 0)·Δf  if Δf > 0 (above masker)
}
```

### Small Speaker Optimization

**Frequency-Dependent Processing:**

```
For speaker cutoff fc_speaker:
  
  if f₀ < fc_speaker:
    // Strong harmonic generation needed
    intensity_adjusted = min(intensity · 1.5, 1.0)
    suppress_fundamental = 0.5
  
  else if f₀ < fc_speaker + 50Hz:
    // Moderate enhancement
    intensity_adjusted = intensity
    suppress_fundamental = 0.3
  
  else:
    // Minimal processing
    intensity_adjusted = intensity · 0.5
    suppress_fundamental = 0.0
```

### Quality Metrics

**Perceptual Bass Extension:**
```
f_perceived = f₀_original / 2

Quality = log₂(f_original / f_perceived)
```

Target: 1 octave extension (quality = 1.0)

**Harmonic Distortion Control:**
```
THD_target < 5% for musical content
THD_target < 1% for speech/broadcast
```

**Artifacts Check:**
```
1. No "buzzing" at sustained notes
2. No "fizziness" in attacks
3. Smooth tonal balance
4. No pumping or breathing
```

---

## 8. Bass Frequency Equalizer - Shelf Biquad Coefficients (Extended)

### Overview
Comprehensive biquad coefficient formulas for all common shelf filter types used in bass equalization, including variations and optimizations.

### Standard Low Shelf (RBJ)

**Already covered in Section 3, repeated with additions:**

```
Parameters:
  fc = shelf frequency (Hz)
  fs = sample rate (Hz)
  G = gain (dB)
  Q = shelf slope

Precompute:
  A = 10^(G/40)
  ω₀ = 2π·fc/fs
  cos_ω₀ = cos(ω₀)
  sin_ω₀ = sin(ω₀)
  α = sin_ω₀/(2·Q)
  sqrt_A = √A

Coefficients:
  b₀ = A·((A+1) - (A-1)·cos_ω₀ + 2·√A·α)
  b₁ = 2·A·((A-1) - (A+1)·cos_ω₀)
  b₂ = A·((A+1) - (A-1)·cos_ω₀ - 2·√A·α)
  
  a₀ = (A+1) + (A-1)·cos_ω₀ + 2·√A·α
  a₁ = -2·((A-1) + (A+1)·cos_ω₀)
  a₂ = (A+1) + (A-1)·cos_ω₀ - 2·√A·α

Normalize:
  b₀ /= a₀
  b₁ /= a₀
  b₂ /= a₀
  a₁ /= a₀
  a₂ /= a₀
```

### High-Order Linkwitz-Riley Low Shelf

For steeper shelf slopes:

**2nd Order (standard):**
```
Same as RBJ above with Q = 0.707
```

**4th Order (cascaded):**
```
Stage 1: Q₁ = 0.54
Stage 2: Q₂ = 1.31
G_stage = √G  (for each stage)

Property: Magnitude responses multiply
|H_total| = |H₁| · |H₂|
```

**Design Procedure:**
```
1. Calculate G_stage = 10^(G_dB/80)  // Half the gain per stage
2. Design two biquads with:
   - Same fc
   - G_stage for each
   - Q₁ = 0.54, Q₂ = 1.31
3. Cascade: y = biquad₂(biquad₁(x))
```

### Proportional-Q Low Shelf

Automatically adjusts Q based on gain for natural sound:

```
Q_proportional = 1 / √(2·A)  where A = 10^(G/40)

For G = +12 dB: Q ≈ 0.50
For G = +6 dB:  Q ≈ 0.63
For G = +3 dB:  Q ≈ 0.71
For G = 0 dB:   Q = 0.71 (unity gain)
```

Then use standard RBJ formulas with calculated Q.

### Butterworth Low Shelf

Maximally flat passband:

```
For 2nd order:
Q = 0.707 (1/√2)

For 4th order (two cascaded 2nd order):
Q₁ = 0.541
Q₂ = 1.307

For 6th order (three cascaded 2nd order):
Q₁ = 0.518
Q₂ = 0.707
Q₃ = 1.932
```

### Chebyshev Low Shelf

Steeper roll-off with ripple in passband:

**Type I Chebyshev (passband ripple):**
```
Ripple: 0.5 dB or 1.0 dB typical

For 2nd order, 0.5dB ripple:
  ε = √(10^(0.5/10) - 1) = 0.3493
  Q = 1/ε = 2.863

For 4th order (cascaded):
  Calculate pole positions from Chebyshev polynomial
  Convert to biquad sections
```

### Adjustable Slope Shelf

Varies from gentle to steep:

```
slope_factor = 0.1 to 10.0

Q_adjusted = Q_base / slope_factor

slope_factor < 1: Gentler slope
slope_factor > 1: Steeper slope
slope_factor = 1: Standard response
```

### Asymmetric Shelf

Different slopes below and above fc:

```
Two separate biquads:
1. Low region (20Hz to fc): Q₁, G₁
2. High region (fc to Nyquist): Q₂, G₂

Transition frequency = fc
```

### Shelving Biquad with Resonance

Adds peak at shelf frequency:

```
Standard shelf coefficients + resonance term:

b₀ = A·((A+1) - (A-1)·cos_ω₀ + 2·√A·α·(1+R))
...

Where R = resonance factor (0 to 1)
R = 0: No resonance (standard shelf)
R = 1: Significant peak at fc
```

### Matched Z-Transform Low Shelf

Alternative digital design:

```
Analog prototype:
H(s) = (s + ω₀/A) / (s + ω₀)

Digital (impulse invariant):
H(z) = K·(1 - e^(-ω₀·T/A)·z⁻¹) / (1 - e^(-ω₀·T)·z⁻¹)

Where:
  T = 1/fs
  K = normalization constant
```

### Parametric Shelf (Hybrid)

Combines shelf and peak:

```
blend = 0 to 1

H_final = blend·H_shelf + (1-blend)·H_peak

Allows smooth transition between shelf and parametric EQ
```

### Coefficient Calculation Examples

**Example 1: +6dB Low Shelf at 80Hz, fs=48kHz, Q=0.707**

```
fc = 80, fs = 48000, G = 6, Q = 0.707

A = 10^(6/40) = 1.9953
ω₀ = 2π·80/48000 = 0.010472
cos_ω₀ = 0.999945
sin_ω₀ = 0.010472
α = 0.010472/(2·0.707) = 0.007403
√A = 1.4125

b₀ = 1.9953·((1.9953+1) - (1.9953-1)·0.999945 + 2·1.4125·0.007403)
   = 1.9953·(2.9953 - 0.9952 + 0.0209)
   = 1.9953·2.0210
   = 4.0325

b₁ = 2·1.9953·((1.9953-1) - (1.9953+1)·0.999945)
   = 3.9906·(0.9953 - 2.9947)
   = 3.9906·(-1.9994)
   = -7.9782

b₂ = 1.9953·((1.9953+1) - (1.9953-1)·0.999945 - 2·1.4125·0.007403)
   = 1.9953·(2.9953 - 0.9952 - 0.0209)
   = 1.9953·1.9792
   = 3.9491

a₀ = (1.9953+1) + (1.9953-1)·0.999945 + 2·1.4125·0.007403
   = 2.9953 + 0.9952 + 0.0209
   = 4.0114

a₁ = -2·((1.9953-1) + (1.9953+1)·0.999945)
   = -2·(0.9953 + 2.9947)
   = -2·3.9900
   = -7.9800

a₂ = (1.9953+1) + (1.9953-1)·0.999945 - 2·1.4125·0.007403
   = 2.9953 + 0.9952 - 0.0209
   = 3.9696

Normalized:
b₀ = 4.0325/4.0114 = 1.0053
b₁ = -7.9782/4.0114 = -1.9887
b₂ = 3.9491/4.0114 = 0.9845
a₁ = -7.9800/4.0114 = -1.9891
a₂ = 3.9696/4.0114 = 0.9896
```

**Example 2: -10dB Low Shelf at 120Hz, fs=44.1kHz, Q=1.0**

```
fc = 120, fs = 44100, G = -10, Q = 1.0

A = 10^(-10/40) = 0.3162
ω₀ = 2π·120/44100 = 0.017104
cos_ω₀ = 0.999854
sin_ω₀ = 0.017103
α = 0.017103/(2·1.0) = 0.008552
√A = 0.5623

b₀ = 0.3162·((1.3162) - (-0.6838)·0.999854 + 2·0.5623·0.008552)
   = 0.3162·(1.3162 + 0.6837 + 0.0096)
   = 0.3162·2.0095
   = 0.6354

b₁ = 2·0.3162·((-0.6838) - (1.3162)·0.999854)
   = 0.6324·(-0.6838 - 1.3160)
   = 0.6324·(-1.9998)
   = -1.2647

b₂ = 0.3162·((1.3162) - (-0.6838)·0.999854 - 2·0.5623·0.008552)
   = 0.3162·(1.3162 + 0.6837 - 0.0096)
   = 0.3162·1.9903
   = 0.6293

a₀ = (1.3162) + (-0.6838)·0.999854 + 2·0.5623·0.008552
   = 1.3162 - 0.6837 + 0.0096
   = 0.6421

a₁ = -2·((-0.6838) + (1.3162)·0.999854)
   = -2·(-0.6838 + 1.3160)
   = -2·0.6322
   = -1.2644

a₂ = (1.3162) + (-0.6838)·0.999854 - 2·0.5623·0.008552
   = 1.3162 - 0.6837 - 0.0096
   = 0.6229

Normalized:
b₀ = 0.6354/0.6421 = 0.9896
b₁ = -1.2647/0.6421 = -1.9693
b₂ = 0.6293/0.6421 = 0.9801
a₁ = -1.2644/0.6421 = -1.9688
a₂ = 0.6229/0.6421 = 0.9701
```

### Frequency and Phase Response Analysis

**Magnitude at any frequency f:**
```
ω = 2π·f/fs

num_real = b₀ + b₁·cos(ω) + b₂·cos(2ω)
num_imag = b₁·sin(ω) + b₂·sin(2ω)
den_real = 1 + a₁·cos(ω) + a₂·cos(2ω)
den_imag = a₁·sin(ω) + a₂·sin(2ω)

|H(ω)| = √(num_real² + num_imag²) / √(den_real² + den_imag²)

|H(ω)|_dB = 20·log₁₀(|H(ω)|)
```

**Phase response:**
```
φ_num = atan2(num_imag, num_real)
φ_den = atan2(den_imag, den_real)
φ_total = φ_num - φ_den
```

**Group delay:**
```
τ_g(ω) = -dφ/dω

Approximate:
τ_g ≈ -(φ(ω+Δω) - φ(ω-Δω)) / (2·Δω)
```

### Optimizations

**Fixed-Point Implementation:**
```
Use Q15 or Q31 format:

int32_t b0_fixed = (int32_t)(b0 * (1 << 15));
int32_t acc = (b0_fixed * x_fixed) >> 15;

Ensure no overflow during accumulation
```

**SIMD Vectorization:**
```
Process 4 samples simultaneously using SSE/AVX:

__m128 b0_vec = _mm_set1_ps(b0);
__m128 x_vec = _mm_load_ps(x);
__m128 y_vec = _mm_mul_ps(b0_vec, x_vec);
```

**Transposed Direct Form II:**
```
Most numerically stable:

v(n) = x(n) - a₁·v(n-1) - a₂·v(n-2)
y(n) = b₀·v(n) + b₁·v(n-1) + b₂·v(n-2)
```

### Multi-band Shelf EQ

**Cascaded Shelves:**
```
H_total(z) = H_shelf1(z) · H_shelf2(z) · ... · H_shelfN(z)

Example 3-band bass EQ:
- Sub-bass shelf: +4dB @ 40Hz, Q=0.7
- Mid-bass shelf: +3dB @ 100Hz, Q=0.7
- Upper-bass shelf: +2dB @ 200Hz, Q=1.0
```

**Coefficient Combination:**

Don't cascade difference equations; instead:
1. Calculate each biquad separately
2. Implement as serial chain
3. Or combine using convolution in freq domain

---

## References and Further Reading

1. Zölzer, U. (2011). *DAFX: Digital Audio Effects*. Wiley.
2. Reiss, J. D., & McPherson, A. (2014). *Audio Effects: Theory, Implementation and Application*. CRC Press.
3. Terhardt, E. (1974). "Pitch, consonance, and harmony." *Journal of the Acoustical Society of America*.
4. Laroche, J., & Dolson, M. (1999). "Improved phase vocoder time-scale modification of audio." *IEEE Trans. Speech and Audio Processing*.
5. ISO 226:2003 - Acoustics — Normal equal-loudness-level contours.
6. ITU-R BS.412 - Planning standards for terrestrial FM sound broadcasting.
7. de Cheveigné, A., & Kawahara, H. (2002). "YIN, a fundamental frequency estimator for speech and music." *JASA*.
8. Bristow-Johnson, R. "Cookbook formulae for audio EQ biquad filter coefficients."
9. Orfanidis, S. J. (2006). *Introduction to Signal Processing*. Prentice Hall.
10. Waves Audio. (1998). *MaxxBass Psychoacoustic Bass Enhancement*. Technical documentation.

---

*Document prepared for DSP research and implementation purposes*
*All algorithms presented with mathematical rigor for reproducibility*
*Sections 5-8 added to provide complete bass enhancement toolkit*
