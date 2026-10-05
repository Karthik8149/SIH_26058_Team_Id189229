# OJAS
### Team: Krushn & The SONARsauruses

## Team Members
- Krushn Navnath Surlakar
- Karthik Ramagiri
- Goda Jaswanth
- Baswaraju Ruthvika
- Kondeti Sai Meghana
- Kartikey Shukla

## Smart India Hackathon 2026
**Problem Statement ID:** SIH26058  
**Problem Statement:** Development of a Low-Power, Real-Time Adaptive Software-Defined Sonar Transmitter Payload for Autonomous Underwater Vehicles (AUVs)  
**Theme:** Robotics and Drones / Ministry of Earth Sciences (MoES)  
**Category:** Hardware

## 1. Project Overview

OJAS is a physics-driven, low-power adaptive sonar transmitter system for Autonomous Underwater Vehicles (AUVs). Instead of transmitting the same sonar waveform under all conditions, OJAS selects a suitable waveform according to the current underwater environment and mission state.

The system uses environmental information such as temperature, salinity, depth, turbidity, operating range and noise conditions to estimate the acoustic state of the water. A library of candidate waveforms is then evaluated using acoustic and signal-processing models. Waveforms that do not satisfy the required detection, range-resolution or hardware limits are rejected. The remaining candidates are ranked using an energy-aware multi-objective score, and the selected waveform is stored in a compact lookup structure for real-time use.

The main design principle is:

> **The environment defines the acoustic state; the acoustic state determines which waveform is worth transmitting.**

## 2. Problem Addressed

A conventional sonar transmitter may use a fixed waveform or a small fixed set of waveforms. This can reduce performance when underwater conditions change because acoustic propagation, attenuation, noise and reverberation depend on both the environment and the transmitted frequency.

For an AUV, the problem is harder because onboard computing power and energy are limited. Running a large optimization problem during every transmission cycle is not practical.

OJAS addresses this by separating the problem into two stages:

1. **Offline stage:** detailed acoustic modelling and waveform optimization are performed using a large set of environmental and target-range scenarios.
2. **Runtime stage:** the embedded controller performs a lightweight state-to-waveform lookup and transmits precomputed samples.

This provides adaptive sonar behaviour without placing the full optimization load on the onboard microcontroller.

## 3. Proposed OJAS Workflow

```text
Ocean Data
        |
        v
Environmental State Extraction
        |
        v
Mackenzie Sound-Speed Calculation
        |
        v
Acoustic Propagation and Noise Modelling
        |
        v
24 Candidate Waveforms
        |
        v
Candidate Performance Evaluation
        |
        v
Hard Feasibility Checks
        |
        v
Multi-Objective / Energy-Aware Ranking
        |
        v
Selected Candidate
        |
        v
Compact W01-W24 Lookup Table
        |
        v
STM32 Runtime Selection
        |
        v
Timer + DMA Waveform Transmission
```

## 4. Environmental Input

The starting point is an ocean-environment dataset containing approximately **1,839 observations**. The main environmental variables used by the model are:

- Temperature
- Salinity
- Depth
- Turbidity
- Sound-speed information

The final methodology keeps a clear separation between data supplied by the source dataset and quantities calculated by the model.

For example, pH is not present in the supplied ocean CSV. When it is required by the Francois-Garrison absorption model, it is treated as an engineering assumption rather than a measured value.

## 5. Acoustic State and Sound Speed

The local speed of sound in seawater is calculated using the Mackenzie sound-speed formulation. In simplified form, the sound speed can be written as

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="https://latex.codecogs.com/svg.image?%5Ccolor%7Bwhite%7D%7Bc%20%3D%20f%28T%2CS%2CD%29%2C%7D">
  <source media="(prefers-color-scheme: light)" srcset="https://latex.codecogs.com/svg.image?%5Ccolor%7Bblack%7D%7Bc%20%3D%20f%28T%2CS%2CD%29%2C%7D">
  <img src="https://latex.codecogs.com/svg.image?%5Ccolor%7Bblack%7D%7Bc%20%3D%20f%28T%2CS%2CD%29%2C%7D" alt="c equals f of T, S, D">
</picture>

where <i>T</i> is temperature, <i>S</i> is salinity and <i>D</i> is depth.

Sound speed affects several later calculations. In particular, the theoretical range resolution of a waveform is

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="https://latex.codecogs.com/svg.image?%5Ccolor%7Bwhite%7D%7B%5CDelta%20R%20%3D%20%5Cfrac%7Bc%7D%7B2B%7D%2C%7D">
  <source media="(prefers-color-scheme: light)" srcset="https://latex.codecogs.com/svg.image?%5Ccolor%7Bblack%7D%7B%5CDelta%20R%20%3D%20%5Cfrac%7Bc%7D%7B2B%7D%2C%7D">
  <img src="https://latex.codecogs.com/svg.image?%5Ccolor%7Bblack%7D%7B%5CDelta%20R%20%3D%20%5Cfrac%7Bc%7D%7B2B%7D%2C%7D" alt="Delta R equals c divided by 2B">
</picture>

where <i>B</i> is the waveform bandwidth.

Therefore, the same waveform bandwidth can result in a different theoretical range resolution under different environmental conditions.

## 6. Candidate Waveform Library

OJAS does not assume that one waveform is always best. It evaluates a defined design space of **24 candidates** from three waveform families:

- Linear Frequency Modulation (LFM)
- Generalized / geometric-sweep nonlinear FM (GSFM)
- Phase-coded waveforms using Barker codes

The candidate set spans approximately **60--590 kHz** in center frequency and **10--20 kHz** in bandwidth. Pulse duration is defined consistently with bandwidth, and phase-coded candidates use a chip duration related to the inverse of bandwidth.

For a waveform with bandwidth <i>B</i> and pulse duration <i>T<sub>p</sub></i>, the time-bandwidth product is

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="https://latex.codecogs.com/svg.image?%5Ccolor%7Bwhite%7D%7BBT_p%2C%7D">
  <source media="(prefers-color-scheme: light)" srcset="https://latex.codecogs.com/svg.image?%5Ccolor%7Bblack%7D%7BBT_p%2C%7D">
  <img src="https://latex.codecogs.com/svg.image?%5Ccolor%7Bblack%7D%7BBT_p%2C%7D" alt="B times T sub p">
</picture>

which also contributes to matched-filter processing gain.

## 7. Scenario-Based Candidate Evaluation

Each ocean observation is expanded across **12 target-range scenarios**. Thus, the final offline dataset contains

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="https://latex.codecogs.com/svg.image?%5Ccolor%7Bwhite%7D%7B1839%20%5Ctimes%2012%20%3D%2022068%7D">
  <source media="(prefers-color-scheme: light)" srcset="https://latex.codecogs.com/svg.image?%5Ccolor%7Bblack%7D%7B1839%20%5Ctimes%2012%20%3D%2022068%7D">
  <img src="https://latex.codecogs.com/svg.image?%5Ccolor%7Bblack%7D%7B1839%20%5Ctimes%2012%20%3D%2022068%7D" alt="1839 times 12 equals 22068">
</picture>

environment-range scenarios.

Every scenario is then evaluated against all 24 candidates:

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="https://latex.codecogs.com/svg.image?%5Ccolor%7Bwhite%7D%7B22068%20%5Ctimes%2024%20%3D%20529632%7D">
  <source media="(prefers-color-scheme: light)" srcset="https://latex.codecogs.com/svg.image?%5Ccolor%7Bblack%7D%7B22068%20%5Ctimes%2024%20%3D%20529632%7D">
  <img src="https://latex.codecogs.com/svg.image?%5Ccolor%7Bblack%7D%7B22068%20%5Ctimes%2024%20%3D%20529632%7D" alt="22068 times 24 equals 529632">
</picture>

candidate evaluations.

This large offline evaluation is important because the final lookup table is not a manually chosen mapping. It is a compressed representation of a much larger optimization process.

## 8. Propagation and Absorption Model

The final fixed dataset generator uses the **Francois-Garrison** model for frequency-dependent seawater absorption.

The absorption coefficient is represented as

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="https://latex.codecogs.com/svg.image?%5Ccolor%7Bwhite%7D%7B%5Calpha%20%3D%20%5Calpha%28f%2CT%2CS%2CD%2CpH%2Cc%29%2C%7D">
  <source media="(prefers-color-scheme: light)" srcset="https://latex.codecogs.com/svg.image?%5Ccolor%7Bblack%7D%7B%5Calpha%20%3D%20%5Calpha%28f%2CT%2CS%2CD%2CpH%2Cc%29%2C%7D">
  <img src="https://latex.codecogs.com/svg.image?%5Ccolor%7Bblack%7D%7B%5Calpha%20%3D%20%5Calpha%28f%2CT%2CS%2CD%2CpH%2Cc%29%2C%7D" alt="alpha equals alpha of f, T, S, D, pH, c">
</picture>

with units of dB/km.

This makes the candidate frequency an important part of the optimization. Two waveforms with similar bandwidth but different center frequencies do not experience the same propagation loss.

One-way transmission loss is modelled using geometric spreading and absorption:

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="https://latex.codecogs.com/svg.image?%5Ccolor%7Bwhite%7D%7BTL%20%3D%2020%5Clog_%7B10%7D%28R%29%20%2B%20%5Calpha%5Cfrac%7BR%7D%7B1000%7D%2C%7D">
  <source media="(prefers-color-scheme: light)" srcset="https://latex.codecogs.com/svg.image?%5Ccolor%7Bblack%7D%7BTL%20%3D%2020%5Clog_%7B10%7D%28R%29%20%2B%20%5Calpha%5Cfrac%7BR%7D%7B1000%7D%2C%7D">
  <img src="https://latex.codecogs.com/svg.image?%5Ccolor%7Bblack%7D%7BTL%20%3D%2020%5Clog_%7B10%7D%28R%29%20%2B%20%5Calpha%5Cfrac%7BR%7D%7B1000%7D%2C%7D" alt="TL equals 20 log base 10 of R plus alpha R divided by 1000">
</picture>

where <i>R</i> is range in metres.

For an active sonar return, the propagation loss occurs on both the outgoing and return paths. The received level is therefore modelled as

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="https://latex.codecogs.com/svg.image?%5Ccolor%7Bwhite%7D%7BRL%20%3D%20SL%20-%202TL%20%2B%20TS%2C%7D">
  <source media="(prefers-color-scheme: light)" srcset="https://latex.codecogs.com/svg.image?%5Ccolor%7Bblack%7D%7BRL%20%3D%20SL%20-%202TL%20%2B%20TS%2C%7D">
  <img src="https://latex.codecogs.com/svg.image?%5Ccolor%7Bblack%7D%7BRL%20%3D%20SL%20-%202TL%20%2B%20TS%2C%7D" alt="RL equals SL minus 2TL plus TS">
</picture>

where <i>SL</i> is source level and <i>TS</i> is target strength.

## 9. Noise and Turbidity

Ambient noise is modelled as a frequency-dependent combination of thermal and wind-related components. Receiver noise figure is also included.

The noise level over candidate bandwidth <i>B</i> is represented as

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="https://latex.codecogs.com/svg.image?%5Ccolor%7Bwhite%7D%7BNL_B%20%3D%20NL_%7BPSD%7D%28f%29%20%2B%20NF%20%2B%2010%5Clog_%7B10%7D%28B%29.%7D">
  <source media="(prefers-color-scheme: light)" srcset="https://latex.codecogs.com/svg.image?%5Ccolor%7Bblack%7D%7BNL_B%20%3D%20NL_%7BPSD%7D%28f%29%20%2B%20NF%20%2B%2010%5Clog_%7B10%7D%28B%29.%7D">
  <img src="https://latex.codecogs.com/svg.image?%5Ccolor%7Bblack%7D%7BNL_B%20%3D%20NL_%7BPSD%7D%28f%29%20%2B%20NF%20%2B%2010%5Clog_%7B10%7D%28B%29.%7D" alt="NL sub B equals NL sub PSD of f plus NF plus 10 log base 10 of B">
</picture>

Turbidity is not inserted directly into the Mackenzie sound-speed equation. In the final generator it affects the model through a volume-reverberation term. The reverberation model includes turbidity and frequency dependence so that candidates can be compared under different scattering conditions.

This quantity is **model-derived** and should not be interpreted as a direct measurement of a scattering coefficient.

## 10. Detection, Processing Gain and Resolution

The matched-filter processing gain is approximated from the time-bandwidth product:

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="https://latex.codecogs.com/svg.image?%5Ccolor%7Bwhite%7D%7BG_p%20%5Capprox%2010%5Clog_%7B10%7D%28BT_p%29.%7D">
  <source media="(prefers-color-scheme: light)" srcset="https://latex.codecogs.com/svg.image?%5Ccolor%7Bblack%7D%7BG_p%20%5Capprox%2010%5Clog_%7B10%7D%28BT_p%29.%7D">
  <img src="https://latex.codecogs.com/svg.image?%5Ccolor%7Bblack%7D%7BG_p%20%5Capprox%2010%5Clog_%7B10%7D%28BT_p%29.%7D" alt="G sub p approximately equals 10 log base 10 of B T sub p">
</picture>

A processed noise-limited detection metric is calculated from received level, noise level and processing gain. A separate signal-to-reverberation term is also evaluated. These terms are combined into a processed SINR estimate.

The detection margin is defined relative to the required minimum processed SNR/SINR:

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="https://latex.codecogs.com/svg.image?%5Ccolor%7Bwhite%7D%7BM%20%3D%20SINR%20-%20SINR_%7Bmin%7D.%7D">
  <source media="(prefers-color-scheme: light)" srcset="https://latex.codecogs.com/svg.image?%5Ccolor%7Bblack%7D%7BM%20%3D%20SINR%20-%20SINR_%7Bmin%7D.%7D">
  <img src="https://latex.codecogs.com/svg.image?%5Ccolor%7Bblack%7D%7BM%20%3D%20SINR%20-%20SINR_%7Bmin%7D.%7D" alt="M equals SINR minus SINR sub min">
</picture>

A candidate must have non-negative detection margin and satisfy the required range resolution.

## 11. Waveform Quality: PSL, ISL and Correlation

Waveform quality is evaluated directly from sampled baseband waveforms rather than assigning fixed values to waveform names.

The candidate autocorrelation is used to obtain:

- **Peak Sidelobe Level (PSL)**
- **Integrated Sidelobe Level (ISL)**

Lower sidelobe levels are desirable because they reduce unwanted correlation peaks and can improve target separation when reverberation is significant.

A correlation coefficient between a clean reference and noisy received signal is also estimated as an additional signal-quality metric.

## 12. Hardware and Energy Constraints

The candidate space is filtered using explicit hardware constraints:

| Parameter | Constraint |
|---|---:|
| Centre frequency | 50--600 kHz |
| Bandwidth | 10--20 kHz |
| Maximum estimated energy | 1 J |
| DAC sample rate | 2 MHz check |

The DAC requirement is checked using the implemented condition

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="https://latex.codecogs.com/svg.image?%5Ccolor%7Bwhite%7D%7Bf_s%20%5Cge%202%5Cleft%28f_c%20%2B%20%5Cfrac%7BB%7D%7B2%7D%5Cright%29.%7D">
  <source media="(prefers-color-scheme: light)" srcset="https://latex.codecogs.com/svg.image?%5Ccolor%7Bblack%7D%7Bf_s%20%5Cge%202%5Cleft%28f_c%20%2B%20%5Cfrac%7BB%7D%7B2%7D%5Cright%29.%7D">
  <img src="https://latex.codecogs.com/svg.image?%5Ccolor%7Bblack%7D%7Bf_s%20%5Cge%202%5Cleft%28f_c%20%2B%20%5Cfrac%7BB%7D%7B2%7D%5Cright%29.%7D" alt="f sub s greater than or equal to 2 times open parenthesis f sub c plus B over 2 close parenthesis">
</picture>

The energy value used in the model is an **engineering estimate** based on normalized waveform amplitude and pulse duration. It is not presented as a calibrated electrical power measurement.

## 13. Constrained Waveform Selection

OJAS uses a two-stage selection process.

### Stage 1: Hard Feasibility

A candidate is considered valid only when it satisfies the hardware, detection and resolution requirements:

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="https://latex.codecogs.com/svg.image?%5Ccolor%7Bwhite%7D%7BValid%20%3D%20HW_%7Bok%7D%20%5Cland%20Detection_%7Bok%7D%20%5Cland%20Resolution_%7Bok%7D.%7D">
  <source media="(prefers-color-scheme: light)" srcset="https://latex.codecogs.com/svg.image?%5Ccolor%7Bblack%7D%7BValid%20%3D%20HW_%7Bok%7D%20%5Cland%20Detection_%7Bok%7D%20%5Cland%20Resolution_%7Bok%7D.%7D">
  <img src="https://latex.codecogs.com/svg.image?%5Ccolor%7Bblack%7D%7BValid%20%3D%20HW_%7Bok%7D%20%5Cland%20Detection_%7Bok%7D%20%5Cland%20Resolution_%7Bok%7D.%7D" alt="Valid equals HW sub ok and Detection sub ok and Resolution sub ok">
</picture>

Invalid candidates are removed before scoring.

### Stage 2: Multi-Objective Ranking

For feasible candidates, the score combines normalized resolution, sidelobe performance, detection margin and an energy penalty. In the final implementation, the weights are:

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="https://latex.codecogs.com/svg.image?%5Ccolor%7Bwhite%7D%7Bw_%7Bres%7D%3D0.30%2C%20%20w_%7BPSL%7D%3D0.30%2C%20%20w_%7BISL%7D%3D0.15%2C%20%20w_%7Bmargin%7D%3D0.25%2C%20%20w_%7Benergy%7D%3D0.15.%7D">
  <source media="(prefers-color-scheme: light)" srcset="https://latex.codecogs.com/svg.image?%5Ccolor%7Bblack%7D%7Bw_%7Bres%7D%3D0.30%2C%20%20w_%7BPSL%7D%3D0.30%2C%20%20w_%7BISL%7D%3D0.15%2C%20%20w_%7Bmargin%7D%3D0.25%2C%20%20w_%7Benergy%7D%3D0.15.%7D">
  <img src="https://latex.codecogs.com/svg.image?%5Ccolor%7Bblack%7D%7Bw_%7Bres%7D%3D0.30%2C%20%20w_%7BPSL%7D%3D0.30%2C%20%20w_%7BISL%7D%3D0.15%2C%20%20w_%7Bmargin%7D%3D0.25%2C%20%20w_%7Benergy%7D%3D0.15.%7D" alt="w sub res equals 0.30, w sub PSL equals 0.30, w sub ISL equals 0.15, w sub margin equals 0.25, w sub energy equals 0.15">
</picture>

The implemented score can be represented conceptually as

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="https://latex.codecogs.com/svg.image?%5Ccolor%7Bwhite%7D%7BScore%20%3D%20w_%7Bres%7DR_n%20%2B%20w_s%20S_n%20%2B%20w_%7Bmargin%7DM_n%20-%20w_%7Benergy%7DE_n%2C%7D">
  <source media="(prefers-color-scheme: light)" srcset="https://latex.codecogs.com/svg.image?%5Ccolor%7Bblack%7D%7BScore%20%3D%20w_%7Bres%7DR_n%20%2B%20w_s%20S_n%20%2B%20w_%7Bmargin%7DM_n%20-%20w_%7Benergy%7DE_n%2C%7D">
  <img src="https://latex.codecogs.com/svg.image?%5Ccolor%7Bblack%7D%7BScore%20%3D%20w_%7Bres%7DR_n%20%2B%20w_s%20S_n%20%2B%20w_%7Bmargin%7DM_n%20-%20w_%7Benergy%7DE_n%2C%7D" alt="Score equals w sub res R sub n plus w sub s S sub n plus w sub margin M sub n minus w sub energy E sub n">
</picture>

where the sidelobe contribution is activated more strongly when signal-to-reverberation conditions make sidelobe suppression important.

The highest-scoring feasible candidate is selected. If no candidate passes the full detection and resolution requirements, a defined hardware-legal fallback is used instead of selecting an invalid waveform.

## 14. LUT-Based Runtime Architecture

The complete offline calculation is computationally expensive. OJAS therefore compresses the result into a compact runtime representation.

The deployment side uses:

```text
Environmental Inputs
       |
       v
State / Sound-Speed Processing
       |
       v
W01-W24 LUT Lookup
       |
       v
Waveform Library
       |
       v
STM32 Timer + DMA
       |
       v
DAC / Analog Transmitter Chain
```

At runtime, the STM32 does not repeat the full candidate evaluation. It identifies the current state, selects the corresponding waveform entry and plays the stored waveform samples.

This is the main reason the system can be adaptive while keeping the onboard computational load low.

## 15. Embedded Prototype

The intended prototype architecture is:

**Arduino environmental input → STM32 processing → laptop monitoring**

The Arduino acts as the environmental-data front end in the prototype. The STM32 represents the real-time processing and waveform-generation platform. The laptop is used for monitoring, plotting and validation.

Because the current prototype does not contain a complete oceanographic sensor suite, controlled environmental profiles are used to reproduce sensor inputs during the demonstration. These profiles can later be replaced by calibrated physical sensors.

## 16. MATLAB Validation

The MATLAB validation stage uses the same ocean dataset, sensor/Mackenzie LUT and waveform library used by the deployment representation.

The waveform debugger checks:

- waveform family and parameter selection,
- instantaneous-frequency behaviour for LFM and nonlinear-FM waveforms,
- carrier and phase-code sequence for phase-coded waveforms,
- waveform spectrum and correlation behaviour.

The live demonstration randomly selects a valid ocean condition every 10 seconds and passes it through the same sensor-to-Wxx-to-waveform path. This allows the selected waveform to change as the environmental state changes.

The MATLAB result is a numerical simulation/validation output; it is not represented as a measured DAC or oscilloscope capture unless separate hardware measurements are available.

## 17. Bellhop Position in the Architecture

Bellhop is considered as a higher-fidelity propagation layer for modelling transmission loss and multipath behaviour.

The SIH concept presentation includes Bellhop in the proposed offline methodology. However, the final fixed and validated dataset-generation implementation in this repository uses the analytical acoustic and sonar-equation models described above. The architecture is compatible with replacing or augmenting the propagation layer with Bellhop in a future calibrated version.

This distinction is maintained so that model-derived results are not presented as measured or as Bellhop results when the corresponding run is not archived.

## 18. Innovation and Uniqueness

### Physics-driven adaptation
Waveform selection is linked to the changing acoustic environment instead of using one fixed waveform.

### Energy-aware selection
Energy is included as a design constraint and as a penalty in the candidate ranking, so unnecessary transmitter energy use is discouraged while required detection and resolution are maintained.

### Offline optimization + real-time LUT
The expensive computation is moved offline. The embedded controller performs only lightweight state-based selection and waveform playback.

### Hardware-oriented design
The selected waveform is represented as precomputed samples suitable for Timer + DMA based transmission on the STM32.

## 19. Expected Impact

OJAS is intended to improve AUV sonar efficiency and adaptability by selecting a waveform suited to the current acoustic state.

Potential benefits include:

- reduced unnecessary transmitter energy use,
- better detection and range-resolution performance under changing conditions,
- lower onboard computational load,
- longer mission endurance,
- scalable waveform and LUT design for different hardware platforms.

The architecture is also suitable for future expansion to larger candidate libraries, additional environmental variables and higher-fidelity propagation models.

## 20. Repository Structure

The repository contains the main implementation stages:

```text
SIH_26058_solution/
│
├── Arduino demo/
│   └── OJAS_Arduino_Environmental_Emitter_10s.ino
│
├── datasets/
│   ├── ocean_data.csv
│   ├── OJAS_SIH26058_Combined_Ocean_State.csv
│   ├── generate_ocean_acoustic_dataset.py
│   └── SIH_2026_dataset_1.ipynb
│
├── Final prototype/
│   ├── OJAS_final_demo.m
│   ├── LFM.png
│   ├── Geometrioc NFM.png
│   └── Phase Coded.png
│
├── LUT generation/
│   ├── SIH_2026_LUT.ipynb
│   ├── OJAS_final_sensor_LUT_24.csv
│   ├── OJAS_FINAL_SENSOR_MACKENZIE_LUT_24.csv
│   ├── OJAS_final_waveform_library_24.csv
│   ├── OJAS_final_waveform_library_24_Barker.csv
│   └── OJAS_waveform_debug_Barker_FINAL.m
│
├── STM32 firmware/
│   ├── OJAS_STM32_Firmware.zip
│   └── OJAS_STM32_CubeMX_Handover.zip
│
├── OJAS_SIH2026_Report.pdf
└── Demo video.mp4            
```

## 21. Current Implementation Status

The current repository contains the following completed and reproducible stages:

- real ocean dataset ingestion,
- offline 24-candidate acoustic evaluation,
- physics/model-derived dataset generation,
- W01-W24 deployment-side LUT selection,
- MATLAB waveform synthesis and validation,
- 10-second random-ocean-row replay,
- Arduino environmental packet emission,
- STM32 firmware and CubeMX implementation materials.

## 22. Scientific Data Integrity

OJAS follows three data categories throughout the implementation:

**Supplied / recorded data:** environmental variables originating from the ocean dataset.

**Model-derived quantities:** sound speed, absorption, transmission loss, received level, noise, reverberation, processing gain, SINR, detection margin, range resolution, PSL, ISL and correlation.

**Engineering assumptions / scenario variables:** target strength, wind-noise condition, receiver noise figure, pH where unavailable, source level, mission-resolution requirement and hardware limits.

This separation is important for reproducibility and for correct interpretation of the results.

## 23. Research Basis

The methodology is based on established underwater-acoustic formulations and reference material used in the SIH proposal, including:

- Mackenzie, K. V. (1981), *Nine-term equation for sound speed in the oceans*, Journal of the Acoustical Society of America.
- Francois, R. E. and Garrison, G. R. (1982), *Sound absorption based on ocean measurements, Parts I and II*, Journal of the Acoustical Society of America.
- NOAA Southwest Fisheries Science Center, Global Ocean Sound Speed Profile Library (GOSSPL).
- NOAA technical material on seawater absorption and acoustic assessment.
- Macaulay, Chu and Ona, JASA (2020), field measurements of seawater absorption in the 38--360 kHz range.

## 24. Summary

OJAS converts environmental awareness into an adaptive sonar transmission decision. The system starts with ocean observations, computes the acoustic state, evaluates multiple waveform families over propagation and target-range scenarios, rejects infeasible candidates, ranks the remaining candidates using detection, resolution, sidelobe and energy metrics, and stores the result in a compact LUT for embedded deployment.

The core contribution is not simply generating a waveform. It is automating the decision of **which waveform should be transmitted for the present underwater environment**, while keeping the runtime system lightweight enough for an AUV payload.
