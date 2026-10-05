# %% [markdown]
# # OJAS - Ocean x Waveform dataset generator (fixed version)
#
# What changed vs. the original notebook (see the chat reply for details):
#  1. Absorption is now ocean-dependent (Francois-Garrison: T, S, depth, pH), not Thorp.
#  2. Target range is a scenario axis (several ranges per ocean row), not one constant.
#  3. Noise is frequency-dependent (thermal + wind), not a flat 60 dB.
#  4. Turbidity acts through volume reverberation, not through noise / a ~0.05 dB term.
#  5. Selection no longer does argmax over all -inf (which silently returned C01).
#  6. PSL / ISL are computed from sampled baseband waveforms, not hard-coded.
#  7. Phase-coded pulses use chip = 1/B so that B and Tp are consistent.

# %%
import numpy as np
import pandas as pd

# ------------------------------------------------------------------
# CONFIG  (replace with your real AUV / transducer numbers)
# ------------------------------------------------------------------
IN_CSV  = "/content/ocean_data.csv"          # original ocean dataset
OUT_CSV = "/content/real_ocean_data_fixed.csv"

RANGES_M            = list(np.round(np.geomspace(10, 250, 12), 1))  # every ocean row x every range
RNG_SEED            = 42
# Per-row mission scenarios (sampled uniformly). Narrow them if you know your real mission.
TARGET_STRENGTH_RANGE_DB = (-25.0, 0.0)       # small/weak target ... strong target
WIND_NOISE_1K_RANGE_DB   = (45.0, 65.0)       # calm sea ... rough sea (Wenz level at 1 kHz)
MAX_RANGE_RES_RANGE_M    = (0.04, 0.08)       # mission needs resolution at least this fine
SOURCE_LEVEL_DB     = 180.0                   # dB re 1uPa @ 1 m (amplitude=1)
RX_NOISE_FIGURE_DB  = 10.0                    # receiver/electronics noise added to ambient
PH                  = 8.05                    # not in your data -> assumed constant
MIN_DETECTION_SNR_DB = 10.0                   # required processed SINR

# Reverberation (turbidity) model - tunable proxies
SV_REF_DB           = -85.0                   # volume backscatter at 1 NTU, 100 kHz (dB re 1/m)
SV_FREQ_EXPONENT    = 3.0                     # Sv ~ f^(10*exponent) dB per decade (Rayleigh-ish)
BEAM_SOLID_ANGLE_DB = -15.0                   # equivalent beam solid angle (dB re 1 sr)
SCAT_REF_HZ         = 100_000

# Hardware limits
MIN_FREQ_HZ, MAX_FREQ_HZ = 50_000, 600_000
MIN_BW_HZ,   MAX_BW_HZ   = 10_000, 20_000
MAX_ENERGY_J             = 1.0
DAC_RATE_HZ              = 2_000_000          # need >= 2*(fc+B/2). 200 kHz CANNOT make 590 kHz carriers.

# Selection weights (score only ranks candidates that already meet detection)
W_RES, W_PSL, W_ISL, W_MARGIN, W_ENERGY = 0.30, 0.30, 0.15, 0.25, 0.15
MARGIN_CAP_DB = 10.0                          # extra margin beyond this earns no extra score

# %%
# ------------------------------------------------------------------
# Physics helpers
# ------------------------------------------------------------------
def francois_garrison(f_khz, T, S, D, pH, c):
    """Seawater absorption in dB/km (Francois & Garrison 1982).
    f_khz: (1,K) or scalar, T/S/D/c: (N,1) arrays.  Valid ~0.4-1000 kHz."""
    theta = 273.0 + T
    # boric acid
    A1 = (8.86 / c) * 10 ** (0.78 * pH - 5)
    f1 = 2.8 * np.sqrt(S / 35.0) * 10 ** (4 - 1245.0 / theta)
    # magnesium sulphate
    A2 = 21.44 * (S / c) * (1 + 0.025 * T)
    P2 = 1 - 1.37e-4 * D + 6.2e-9 * D**2
    f2 = 8.17 * 10 ** (8 - 1990.0 / theta) / (1 + 0.0018 * (S - 35.0))
    # pure water
    P3 = 1 - 3.83e-5 * D + 4.9e-10 * D**2
    A3 = np.where(
        T <= 20,
        4.937e-4 - 2.59e-5 * T + 9.11e-7 * T**2 - 1.50e-8 * T**3,
        3.964e-4 - 1.146e-5 * T + 1.45e-7 * T**2 - 6.5e-10 * T**3,
    )
    f2_ = f_khz**2
    return (A1 * f1 * f2_ / (f1**2 + f2_)
            + A2 * P2 * f2 * f2_ / (f2**2 + f2_)
            + A3 * P3 * f2_)


def ambient_noise_psd_db(f_hz, wind_1k_db):
    """Thermal + wind noise, dB re 1uPa^2/Hz (simplified Wenz)."""
    fk = f_hz / 1000.0
    thermal = -15.0 + 20 * np.log10(fk)
    wind = wind_1k_db - 17.0 * np.log10(fk)
    return 10 * np.log10(10 ** (thermal / 10) + 10 ** (wind / 10))


def db(x):
    return 10 * np.log10(np.maximum(x, 1e-30))

# %%
# ------------------------------------------------------------------
# Candidate library (same 24 as before; phase-coded Tp made consistent)
# ------------------------------------------------------------------
fc = [60e3, 100e3, 150e3, 200e3, 300e3, 400e3, 500e3, 590e3]
bw = {
    "LFM":         [10e3, 12e3, 14e3, 16e3, 18e3, 20e3, 20e3, 20e3],
    "GSFM":        [20e3, 18e3, 16e3, 14e3, 12e3, 10e3, 18e3, 20e3],
    "Phase-coded": [10e3, 12e3, 14e3, 16e3, 18e3, 20e3, 18e3, 20e3],
}
tp = [0.005, 0.008, 0.010, 0.012, 0.015, 0.018, 0.020, 0.020]
codes = ["Barker-7"] * 3 + ["Barker-13"] * 5

rows = []
for fam in ["LFM", "GSFM", "Phase-coded"]:
    for i in range(8):
        n_chips = int(codes[i].split("-")[1]) if fam == "Phase-coded" else 0
        B = bw[fam][i]
        rows.append(dict(
            waveform_type=fam,
            center_frequency_hz=fc[i],
            bandwidth_hz=B,
            # Barker: chip = 1/B  ->  Tp = N/B  (so B*Tp = N, gain = 10log N)
            pulse_duration_s=(n_chips / B) if fam == "Phase-coded" else tp[i],
            amplitude=0.75 if fam == "Phase-coded" else 0.80,
            phase_code=codes[i] if fam == "Phase-coded" else "none",
        ))
cand = pd.DataFrame(rows)
cand.insert(0, "candidate_id", [f"C{i+1:02d}" for i in range(len(cand))])
K = len(cand)

# %%
# ------------------------------------------------------------------
# PSL / ISL from sampled complex-baseband waveforms
# (envelope metrics do not depend on the carrier, so fs = 8*B is enough)
# ------------------------------------------------------------------
BARKER = {
    7:  [1, 1, 1, -1, -1, 1, -1],
    13: [1, 1, 1, 1, 1, -1, -1, 1, 1, -1, 1, -1, 1],
}

def baseband(row, sps=8):
    B, T = row.bandwidth_hz, row.pulse_duration_s
    fs = sps * B
    n = int(round(T * fs))
    t = (np.arange(n) / fs) - T / 2
    if row.waveform_type == "LFM":
        x = np.exp(1j * np.pi * (B / T) * t**2)
    elif row.waveform_type == "GSFM":
        # spectrally-shaped nonlinear FM (Hamming-weighted group delay, stationary phase)
        f = np.linspace(-B / 2, B / 2, 4001)
        w = 0.54 + 0.46 * np.cos(2 * np.pi * f / B)
        tau = np.cumsum(w); tau = (tau - tau[0]) / (tau[-1] - tau[0]) * T - T / 2
        inst_f = np.interp(t, tau, f)
        x = np.exp(1j * 2 * np.pi * np.cumsum(inst_f) / fs)
    else:
        code = np.array(BARKER[int(row.phase_code.split("-")[1])], float)
        x = np.repeat(code, sps).astype(complex)[:n]
    return x

def sidelobe_metrics(x):
    r = np.abs(np.correlate(x, x, mode="full"))
    c0 = len(x) - 1
    pos = r[c0:]
    # first local minimum = end of main lobe
    d = np.diff(pos)
    idx = np.where((d[:-1] < 0) & (d[1:] >= 0))[0]
    m = (idx[0] + 1) if len(idx) else 1
    main = pos[0]
    side = np.concatenate([pos[m:], pos[m:]])      # both sides
    psl = 20 * np.log10(side.max() / main)
    isl = 10 * np.log10(np.sum(side**2) / (pos[0]**2 + 2 * np.sum(pos[1:m]**2)))
    return psl, isl

pm = [sidelobe_metrics(baseband(r)) for r in cand.itertuples()]
cand["PSL_dB"] = [p for p, _ in pm]
cand["ISL_dB"] = [i for _, i in pm]
cand["energy_J"] = cand.amplitude**2 * cand.pulse_duration_s
cand["time_bandwidth"] = cand.bandwidth_hz * cand.pulse_duration_s
print(cand[["candidate_id", "waveform_type", "center_frequency_hz", "bandwidth_hz",
            "pulse_duration_s", "time_bandwidth", "PSL_dB", "ISL_dB"]].round(2).to_string(index=False))

# %%
# ------------------------------------------------------------------
# Load ocean data and build ocean x range scenario table
# ------------------------------------------------------------------
ocean = pd.read_csv(IN_CSV)
ocean = ocean.drop(columns=[c for c in ocean.columns if c.startswith("Unnamed")])
ocean = ocean.reset_index(drop=True)
ocean["ocean_row_id"] = np.arange(len(ocean))
ocean["pressure_dbar"] = ocean["depth_m"] / 10.1

df = (ocean.loc[ocean.index.repeat(len(RANGES_M))].reset_index(drop=True))
df["target_range_m"] = np.tile(RANGES_M, len(ocean)).astype(float)
M = len(df)
rng = np.random.default_rng(RNG_SEED)
df["target_strength_dB"] = rng.uniform(*TARGET_STRENGTH_RANGE_DB, M)
df["wind_noise_1kHz_dB"] = rng.uniform(*WIND_NOISE_1K_RANGE_DB, M)
df["max_range_resolution_m"] = rng.uniform(*MAX_RANGE_RES_RANGE_M, M)

T = df["temperature_C"].values[:, None]
S = df["salinity_PSU"].values[:, None]
D = df["depth_m"].values[:, None]
c = df["sound_speed_mps_mackenzie"].values[:, None]
turb = df["turbidity_NTU"].values[:, None]
R = df["target_range_m"].values[:, None]
TS = df["target_strength_dB"].values[:, None]
WIND = df["wind_noise_1kHz_dB"].values[:, None]
DR_MAX = df["max_range_resolution_m"].values[:, None]

F = cand["center_frequency_hz"].values[None, :]
B = cand["bandwidth_hz"].values[None, :]
Tp = cand["pulse_duration_s"].values[None, :]
A = cand["amplitude"].values[None, :]
E = cand["energy_J"].values[None, :]

# %%
# ------------------------------------------------------------------
# Sonar equation for every (row, candidate)   shape (M, K)
# ------------------------------------------------------------------
alpha = francois_garrison(F / 1000.0, T, S, D, PH, c)            # dB/km, ocean-dependent
TL = 20 * np.log10(R) + alpha * R / 1000.0                       # one-way
SL = SOURCE_LEVEL_DB + 20 * np.log10(A)
RL = SL - 2 * TL + TS

NL_B = ambient_noise_psd_db(F, WIND) + RX_NOISE_FIGURE_DB + 10 * np.log10(B)
Gp = np.broadcast_to(10 * np.log10(B * Tp), (M, K))

# volume reverberation from turbid water (after pulse compression, cell = c/(2B))
Sv = SV_REF_DB + 10 * np.log10(turb) + 10 * SV_FREQ_EXPONENT * np.log10(F / SCAT_REF_HZ)
V_dB = 10 * np.log10(c / (2 * B)) + BEAM_SOLID_ANGLE_DB + 20 * np.log10(R)
RevL = SL - 2 * TL + Sv + V_dB

snr_noise = RL - NL_B + Gp                    # processed, noise-limited
srr = RL - RevL                               # signal-to-reverb (no processing gain)
inv = 10 ** (-snr_noise / 10) + 10 ** (-srr / 10)
SINR = -10 * np.log10(inv)
margin = SINR - MIN_DETECTION_SNR_DB

snr_in = 10 ** ((RL - NL_B) / 10)             # pre-compression, in-band
CC = np.sqrt(snr_in / (1 + snr_in))           # corr. between noisy rx and clean replica

range_res = c / (2 * B)
res_ok = range_res <= DR_MAX

# %%
# ------------------------------------------------------------------
# Constraints + selection (with a real fallback)
# ------------------------------------------------------------------
hw_ok = ((F >= MIN_FREQ_HZ) & (F <= MAX_FREQ_HZ) & (B >= MIN_BW_HZ) & (B <= MAX_BW_HZ)
         & (E <= MAX_ENERGY_J) & (DAC_RATE_HZ >= 2 * (F + B / 2)))
hw_ok = np.broadcast_to(hw_ok, (M, K))
detect_ok = margin >= 0
valid = hw_ok & detect_ok & res_ok

res_norm = np.clip(range_res.min() / range_res, 0, 1) * np.ones((M, K))
psl_n = np.clip(-cand.PSL_dB.values[None, :] / 40.0, 0, 1) * np.ones((M, K))
isl_n = np.clip(-cand.ISL_dB.values[None, :] / 40.0, 0, 1) * np.ones((M, K))
mar_n = np.clip(margin, 0, MARGIN_CAP_DB) / MARGIN_CAP_DB
en_n = np.clip(E / MAX_ENERGY_J, 0, 1) * np.ones((M, K))

# Sidelobes only matter when reverberation (turbid water) competes with the echo:
# need -> 1 when signal-to-reverb is <= 0 dB, -> 0 when it is >= 25 dB.
sidelobe_need = np.clip((25.0 - srr) / 25.0, 0, 1)
score = (W_RES * res_norm + sidelobe_need * (W_PSL * psl_n + W_ISL * isl_n)
         + W_MARGIN * mar_n - W_ENERGY * en_n)

has_valid = valid.any(axis=1)
score_valid = np.where(valid, score, -np.inf)
# fallback: no candidate detects -> take the hardware-legal one with the largest margin
fallback_score = np.where(hw_ok, margin, -np.inf)
best = np.where(has_valid, score_valid.argmax(axis=1), fallback_score.argmax(axis=1))
ii = np.arange(M)

# %%
# ------------------------------------------------------------------
# Assemble output
# ------------------------------------------------------------------
df["absorption_dB_per_km_100kHz"] = francois_garrison(100.0, T, S, D, PH, c)[:, 0]
df["candidate_id"] = cand.candidate_id.values[best]
df["waveform_type"] = cand.waveform_type.values[best]
df["phase_code"] = cand.phase_code.values[best]
df["center_frequency_Hz"] = F[0, best]
df["bandwidth_Hz"] = B[0, best]
df["pulse_duration_s"] = Tp[0, best]
df["amplitude_normalized"] = A[0, best]
df["absorption_dB_per_km"] = alpha[ii, best]            # selected-candidate, ocean-dependent
df["transmission_loss_dB"] = TL[ii, best]               # one-way
df["two_way_TL_dB"] = 2 * TL[ii, best]
df["received_signal_level_dB"] = RL[ii, best]
df["noise_level_band_dB"] = NL_B[ii, best]
df["reverb_level_dB"] = RevL[ii, best]
df["processing_gain_dB"] = Gp[ii, best]
df["snr_dB"] = SINR[ii, best]
df["detection_margin_dB"] = margin[ii, best]
df["range_resolution_m"] = range_res[ii, best]
df["PSL_dB"] = cand.PSL_dB.values[best]
df["ISL_dB"] = cand.ISL_dB.values[best]
df["correlation_coefficient"] = CC[ii, best]
df["estimated_energy_J"] = E[0, best]
df["hardware_valid"] = hw_ok[ii, best]
df["detection_ok"] = detect_ok[ii, best]
df["resolution_ok"] = res_ok[ii, best]
df["selection_status"] = np.where(has_valid, "optimal_valid", "fallback_max_margin")

# Multi-label targets: which candidates work, and the top-3 ranking.
df["n_feasible_candidates"] = valid.sum(axis=1)
order = np.argsort(-np.where(valid, score, -np.inf), axis=1)[:, :3]
for r in range(3):
    ids = cand.candidate_id.values[order[:, r]]
    df[f"rank{r+1}_candidate_id"] = np.where(valid[ii, order[:, r]], ids, "none")
feas = pd.DataFrame(valid, columns=[f"feasible_{cid}" for cid in cand.candidate_id])
df = pd.concat([df, feas], axis=1)

df.to_csv(OUT_CSV, index=False)
print("Saved", OUT_CSV, df.shape)

# %%
# ------------------------------------------------------------------
# Sanity checks: the original failure modes should be gone
# ------------------------------------------------------------------
print("\nUnique values per key column (should be >> 1):")
for col in ["absorption_dB_per_km", "transmission_loss_dB", "candidate_id",
            "center_frequency_Hz", "bandwidth_Hz", "pulse_duration_s",
            "snr_dB", "correlation_coefficient", "PSL_dB"]:
    print(f"  {col:28s} {df[col].nunique()}")
print("\nSelection status:\n", df.selection_status.value_counts().to_string())
print("\nCandidate usage:\n", df.candidate_id.value_counts().sort_index().to_string())
print("\nBy range:\n", df.groupby("target_range_m").agg(
    valid=("selection_status", lambda s: (s == "optimal_valid").mean()),
    n_candidates=("candidate_id", "nunique"),
    median_fc=("center_frequency_Hz", "median")).round(2).to_string())
