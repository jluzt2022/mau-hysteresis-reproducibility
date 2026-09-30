# mau-hysteresis-reproducibility

Reproducibility code for the manuscript:

**Tabo, Z., Jacobs, S. R., and Breuer, L.**  
*Hysteresis metrics reveal land-use-dependent stormflow constituent dynamics in tropical Afromontane catchments*

## Overview

This repository contains the R code used to reproduce the publication-specific analyses, tables, and figures for a six-year high-frequency hydrochemical study of three tropical Afromontane headwater catchments in the South-West Mau Forest Complex, Kenya:

- **NF** — Natural forest
- **SHA** — Smallholder agriculture
- **TTP** — Tea and tree plantation

The study evaluates storm-event responses of nitrate (NO3-N), dissolved organic carbon (DOC), electrical conductivity (EC), and total suspended solids (TSS), including chemical-status classification, hysteresis metrics, flushing behaviour, and multivariate response clustering.

## Reproducibility design

The code has two explicitly separated modes.

### 1. Public reproducibility mode — default

The default mode reproduces the publication analyses from processed and derived datasets archived separately in Zenodo.

```r
RUN_RAW_DATA_PIPELINE <- FALSE
