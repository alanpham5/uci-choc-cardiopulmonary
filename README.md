# Cardiopulmonary Simulation Models
This project implements a combined cardiopulmonary simulation framework. The repository includes:

- A lung/ventilator model (via Modelo_Respiratorio.slx) plus patient-specific parameterization routines, for simulating respiratory mechanics, pressures, flows, and lung volume over time for cohorts (real or synthetic).

- A cardiovascular model (via CardioVascularSystem.slx inside a dedicated project) plus scripts to map patient (or synthetic healthy) data into the model, run heartbeat simulations (~2 beats), and extract key metrics (e.g. stroke volume, cardiac output, aortic pressure) or full time-series for further analysis or plotting.
This allows systematic simulation and comparison of both respiratory and cardiac behavior across different patient populations, under controlled ventilator or physiological conditions.

# Lung Model Simulation Scripts

This repository contains scripts and model files for running lung and ventilator simulations using patient data from `choc-data-all.csv`. The simulations use the **Modelo_Respiratorio** Simulink model and produce plots, metrics, and raw time-series outputs.

---

## Model Components

| File | Description |
|------|-------------|
| `Modelo_Respiratorio.slx` / `Modelo_Respiratorio.slxc` | Simulink lung and ventilator model (compiled and uncompiled). Used in all simulations. |
| `Ventiladorcito.fig` | GUI for setting ventilator parameters. |
| `choc-data-all.csv` | De-identified patient dataset provided by CHOC. |

---

## Scripts Overview

| Script | Purpose | Input | Output | Notes |
|--------|---------|--------|--------|--------|
| `runLung_singleSimulation.m` | Loads a single patient’s data and runs the lung model simulation. | `choc-data-all.csv` | On-screen model plots, `patientX_allPlots_labeled.png`, `patientX_lungVolume.png` | Set `patientIndex` on line 5. |
| `runLung_allPatients.m` | Runs the model for all patients and extracts summary metrics. | `choc-data-all.csv` | `patient_lung_sim_results.csv` | Run as-is. |
| `runLung_allHealthy.m` | Samples healthy cohort and processes all healthy patients. | `choc-data-all.csv` | `healthy_patient_lung_sim_results.csv` | Run as-is. |
| `runLung_rawDataExtract.m` | Extracts raw simulation time-series for all patients. | `choc-data-all.csv` | `patient_time_series_data/all_patients_<metric>_timeseries.csv` | Prompts for metric index in console. |
| `runLung_rawDataExtractHealthy.m` | Extracts raw simulation time-series for healthy patients. | `healthy_patient_lung_sim_results.csv` | `healthy_patient_time_series_data/healthy_patients_<metric>_timeseries.csv` | Prompts for metric index in console. |
| `runLung_compareOne.m` | Compares a pectus patient vs. healthy cohort using plots. | `choc-data-all.csv`, `healthy_patient_lung_sim_results.csv` | `Transpulmonary_Pressure_*`, `Alveolar_Flow_*`, `Lung_Volume_*` plot files | Set `patientIndex` on line 12. |

# Heart Model Simulation Scripts

This section describes the Simscape cardiovascular (heart + circulation) model and the scripts used to run patient-specific and healthy-baseline simulations.

---

## Model Components

| File | Description |
|------|-------------|
| `CardioVascularSystem.slx` / `CardioVascularSystem.slxc` | Simscape cardiovascular model (compiled and uncompiled). Used in all heart simulations. |
| `HeartModel.prj` | MATLAB Project file that configures paths and dependencies so the model loads and runs reliably. |

---

## Scripts Overview

| Script | Purpose | Input | Output | Notes |
|--------|---------|--------|--------|--------|
| `runHeart_onePatient.m` | Loads one patient record, maps CHOC variables to heart model parameters, simulates ~2 beats, and displays pressures/flows. Prints SV, CO, AoP SBP/DBP in console. | `choc-data-all.csv` | Model plots; console summary metrics | Set `patientIndex` near the top. |
| `runHeart_allPatients.m` | Runs all patients through the heart model. Each iteration resets to healthy defaults, applies parameter mapping, simulates ~2 beats, extracts last-beat metrics (SV/CO + AoP/LVP/LVOF stats), and writes results to CSV. | `choc-data-all.csv` | `heart_sim_results.csv` | Run as-is. |
| `runHeart_allPatients_extractAll.m` | Same as above but also exports selected raw time-series signals for each patient into a combined CSV. | `choc-data-all-temp.csv` | `heart_sim_results.csv`, `all_patients_timeseries_extract.csv` | Run as-is; edit `want = {...}` to change extracted signals. |
| `runHeart_allHealthy.m` | Generates a synthetic healthy cohort, runs simulations, extracts summary metrics, and exports selected raw signals. | Generated internally (`healthy-data-all-temp.csv`) | `healthy-data-all-temp.csv`, `healthy_heart_sim_results_w_upd_vars.csv`, `healthy_timeseries_extract_w_upd_vars.csv` | Update `numPatients` if needed; edit `want = {...}` to change extracted signals. |
| `runHeart_compareOne.m` | Compares a healthy baseline vs. a selected patient (by Pt Key). Runs two matched simulations and overlays pressures/flows/volumes. Prints Pt Key and row. | `choc-data-all_clean.csv` or `choc-data-all.csv` | On-screen comparison plots | Set `ptKeyValue` near the top. |

---

## Requirements
- MATLAB (2022a or newer recommended)
- Simulink & Simscape

## References
- Gil, J. (n.d.). Simulation of respiratory mechanics on Simulink with GUI. MATLAB Central File Exchange. The MathWorks Inc. https://www.mathworks.com/matlabcentral/fileexchange/75335-simulation￾of-respiratory-mechanics-on-simulink-with-gui
- Khan, M. A. N. (n.d.). Cardiovascular system in Simscape with ECMO machine. MATLAB Central File Exchange. The MathWorks Inc. https://www.mathworks.com/matlabcentral/fileexchange/125310-
cardiovascular-system-in-simscape-with-ecmo-machine
