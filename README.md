# mau-hysteresis-reproducibility

Reproducibility materials for the manuscript:

**Tabo, Z., Jacobs, S. R., and Breuer, L.**  
*Hysteresis metrics reveal land-use-dependent stormflow constituent dynamics in tropical Afromontane catchments*

## Overview

This repository contains the R code used to reproduce the analyses, tables, and figures for a six-year high-frequency hydrochemical study of three tropical Afromontane headwater catchments in the South-West Mau Forest Complex, Kenya:

- **NF** — Natural forest
- **SHA** — Smallholder agriculture
- **TTP** — Tea and tree plantation

The study evaluates storm-event responses of nitrate (NO3-N), dissolved organic carbon (DOC), electrical conductivity (EC), and total suspended solids (TSS), including event detection, chemical-status classification, hysteresis metrics, flushing behaviour, and multivariate response clustering.

## Study period

The reproducibility dataset covers:

**1 January 2015 to 31 December 2020**

at **10-minute temporal resolution**.

## Repository structure

mau-hysteresis-reproducibility/
├── README.md
├── CITATION.cff
├── DATA_DICTIONARY.csv
├── LICENSE
├── .gitignore
└── code/
    └── mau_hysteresis_reproducibility.R
```

The corresponding cleaned 10-minute dataset is archived in Zenodo as:

`data_final.csv`

Zenodo dataset DOI:

https://doi.org/10.5281/zenodo.23078064

## Reproducibility workflow

The analysis starts directly from the cleaned 10-minute monitoring dataset used in the manuscript.

The R script performs:

- import and physical quality control of the monitoring data;
- rainfall and discharge event detection;
- construction of the accepted storm-event register;
- water-quality response screening;
- calculation of pre-event concentration baselines;
- chemical-status classification;
- Lloyd hysteresis index calculation;
- normalized loop-area calculation;
- flushing-index calculation;
- C-Q loop classification;
- multivariate response clustering;
- statistical analyses;
- generation of manuscript and supplementary tables;
- generation of manuscript and supplementary figures;
- publication-output auditing.

## Running the analysis

1. Download or clone this GitHub repository.

2. Download `data_final.csv` from Zenodo:

   https://doi.org/10.5281/zenodo.23078064

3. Place `data_final.csv` in the project directory.

A simple working structure is:

```text
project/
├── data_final.csv
└── code/
    └── mau_hysteresis_reproducibility.R
```

4. Set the R working directory to the project folder containing `data_final.csv`.

5. Run:

```r
source("code/mau_hysteresis_reproducibility.R")
```

The script searches the project directory recursively for `data_final.csv`.

## Output structure

Running the script creates:

```text
Mau_Hysteresis_Reproducibility/
├── 00_Core_Analysis/
├── 01_Main_Article/
├── 02_Supplementary_Information/
└── 03_Reproducibility/
```

These folders contain the event-level analysis outputs, manuscript figures and tables, supplementary figures and tables, and reproducibility audit files.

## Analytical populations

The manuscript analysis contains:

| Population | n |
|---|---:|
| Accepted rainfall-runoff events | 695 |
| Classifiable event-constituent combinations | 2506 |
| Responsive combinations | 1472 |
| Geometry-resolved combinations | 1323 |
| Clustering-eligible combinations | 1319 |

These counts provide key reproducibility checks for the workflow.

## Software requirements

The analysis uses R and the following principal packages:

- zoo
- xts
- lubridate
- dplyr
- tidyr
- purrr
- tibble
- ggplot2
- scales
- png
- stringr
- patchwork
- cowplot
- cluster
- mgcv

Users should install any missing packages before running the script.

## Data availability

The cleaned 10-minute hydro-meteorological and hydrochemical dataset used in this study for the period 2015–2020 is publicly archived in Zenodo:

https://doi.org/10.5281/zenodo.23078064

The broader monitoring archive outside the manuscript study period is not included in this release.

## Code availability

The reproducibility code is maintained in this GitHub repository:

https://github.com/jluzt2022/mau-hysteresis-reproducibility

## License

The code is distributed under the MIT License.

The associated Zenodo dataset is distributed under the Creative Commons Attribution 4.0 International license (CC BY 4.0).

## Citation

When using these materials, please cite the associated manuscript and dataset.

### Dataset

Tabo, Z., Jacobs, S. R., and Breuer, L. (2026).  
*10-minute hydro-meteorological and hydrochemical data for storm-event hysteresis analysis in South-West Mau, Kenya (2015–2020)* (Version 1.0.0) [Data set]. Zenodo.  
https://doi.org/10.5281/zenodo.23078064

### Code

Tabo, Z., Jacobs, S. R., and Breuer, L. (2026).  
*mau-hysteresis-reproducibility*. GitHub repository.  
https://github.com/jluzt2022/mau-hysteresis-reproducibility



