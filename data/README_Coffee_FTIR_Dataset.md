# Mid-infrared spectral dataset and machine learning tools for defect detection in green and roasted coffee

## Repository information

This repository contains mid-infrared (ATR-FTIR) spectral data for defect-free and defective coffee samples evaluated at two processing stages (green and roasted), together with metadata and R-based machine-learning workflows for classification using latent-variable representations.

**Repository:** Mendeley Data  
**Dataset record:** https://data.mendeley.com/datasets/dtd2fggpyp  
**Repository version:** Version 5  
**Version-specific DOI:** https://data.mendeley.com/datasets/dtd2fggpyp/5  

**License:** CC BY 4.0

The spectral preprocessing procedures used to generate the deposited preprocessed datasets were implemented using the R-based framework available at:

**Collazos-Escobar et al. (2026). _R Codes for Preprocessing FT-NIR, FTIR, and Raman Spectral Data and Machine Learning Tools for Predictive and Classification Model Calibration_. Mendeley Data, Version 2. DOI: 10.17632/gcf9cz6hsr.2.**  
https://data.mendeley.com/datasets/gcf9cz6hsr/2

The present repository contains the resulting raw and preprocessed spectral datasets and the R scripts used for the subsequent machine-learning analyses. The SVM and Random Forest scripts therefore use the already generated spectral datasets as input; they do not recalculate the baseline, SNV, MSC, D1, or D2 transformations.

---

## 1. Experimental design and biological samples

The dataset contains **50 independent biological coffee lots**:

- 25 defect-free coffee lots.
- 5 independent lots classified as bitten.
- 5 independent lots classified as vinegar.
- 5 independent lots classified as drill bit.
- 5 independent lots classified as discolored.
- 5 independent lots classified as black.

Each biological coffee lot was evaluated at **two processing stages**:

1. Green coffee.
2. Roasted coffee.

Therefore, the dataset contains **100 sample-stage spectral observations**: 50 green observations and 50 roasted observations.

For each sample-stage observation, three technical ATR-FTIR acquisitions were obtained and averaged point by point before inclusion in the deposited spectral datasets. Technical replicate acquisitions are therefore not treated as independent observations.

---

## 2. Sample identification and Green–Roasted correspondence

### Coffee Lot ID

`Coffee Lot ID` is the **biological sample identifier** and is the variable used to identify each independent coffee lot across processing stages.

The same `Coffee Lot ID` is retained for the green and roasted observations originating from the same biological coffee lot. Thus, the green and roasted spectra sharing a `Coffee Lot ID` are **paired observations of the same biological sample**, not independent biological replicates.

For example:

| Coffee Lot ID | Observation ID | Processing stage | Interpretation |
|---|---|---|---|
| 1 | LOT_001_Green | Green | Green observation from biological coffee lot 1 |
| 1 | LOT_001_Roasted | Roasted | Roasted observation from the same biological coffee lot 1 |
| 26 | LOT_026_Green | Green | Green observation from biological coffee lot 26 |
| 26 | LOT_026_Roasted | Roasted | Roasted observation from the same biological coffee lot 26 |

`Observation ID` is the unique identifier for an individual sample-stage observation and follows the structure:

`LOT_###_Green` or `LOT_###_Roasted`

where `###` corresponds to the `Coffee Lot ID`.

`Within category ID` is a local sequential identifier within each defect category and **must not be used as the biological grouping variable**.

### Grouping during model validation

For analyses combining green and roasted observations, model partitioning is performed using `Coffee Lot ID`. Consequently, both observations originating from the same biological coffee lot are always assigned to the **same training or validation subset**. This prevents information leakage between paired green and roasted observations.

Biological sample identity is never inferred from spreadsheet row order.

---

## 3. Sample metadata

The file `SampleDescription.xlsx` contains the complete sample-level metadata.

| Variable | Description |
|---|---|
| `V1` | Binary defect code: 0 = defect-free; 1 = defective |
| `Process` | Processing-stage code: 0 = green; 1 = roasted |
| `Defect status` | Defect-free or defective |
| `Processing stage` | Green or Roasted |
| `Defect category` | Defect-free, Bitten, Vinegar, Drill bit, Discolored, or Black |
| `Within category ID` | Sequential identifier within the corresponding defect category |
| `Coffee Lot ID` | Biological coffee-lot identifier; primary grouping variable |
| `Observation ID` | Unique stage-specific observation identifier |
| `Technical replicas averaged` | Number of technical ATR-FTIR acquisitions averaged per deposited spectrum |
| `Municipality (Huila-Colombia)` | Municipality of sample origin |
| `Latitude` | Geographic latitude |
| `Longitude` | Geographic longitude |
| `Height (masl)` | Altitude in metres above sea level |
| `rainfall (mm)` | Rainfall descriptor |

---

## 4. Repository files

### Metadata and initial characterization

- `SampleDescription.xlsx`  
  Complete metadata for the 100 sample-stage observations, including biological `Coffee Lot ID`, stage-specific `Observation ID`, defect category, processing stage, number of technical replicates averaged, and geographical/environmental descriptors.

- `Initial_Characterization.xlsx`  
  Initial characterization of green and roasted coffee groups, including moisture content and water activity.

### Spectral datasets

- `Dataset_Raw.xlsx` — raw ATR-FTIR spectra.
- `Dataset_BaselineCorrected.xlsx` — baseline-corrected spectra.
- `Dataset_StandardNormalVariateCorrected.xlsx` — SNV-transformed spectra.
- `Dataset_MultiplicativeScatterCorrected.xlsx` — MSC-transformed spectra.
- `Dataset_FirstDerivative_1D.xlsx` — Savitzky–Golay first-derivative spectra.
- `Dataset_SecondDerivative_2D.xlsx` — Savitzky–Golay second-derivative spectra.

The final spectral workbooks contain the same 100 sample-stage observations and the same spectral grid. The first seven columns contain core sample metadata:

`V1`, `Process`, `Defect status`, `Processing stage`, `Defect category`, `Within category ID`, and `Coffee Lot ID`.

These columns are followed by the FTIR variables identified by numeric wavenumber headers.

The spectral range is approximately **650–4000 cm⁻¹**. In the deposited final workbooks, the common spectral grid contains **900 wavenumber variables** from 648.556784 to 3999.433499 cm⁻¹.

### Machine-learning scripts

- `ModelingSupportVectorMachine_Advanced.R`  
  Leakage-free PCA + Support Vector Machine workflow.

- `ModelingRandomForest_Advanced.R`  
  Leakage-free PCA + Random Forest workflow.

Both scripts read `SampleDescription.xlsx` and the selected spectral workbook and verify the consistency of the sample metadata before model fitting.

---

## 5. Spectral preprocessing

Spectral preprocessing was carried out in **R 4.4.3 (2025-02-28)** using the following packages:

- `ChemoSpec` 6.3.1
- `mdatools` 0.16.0
- `baseline` 1.3-8
- `R.utils` 2.13.0

The preprocessing settings used to generate the deposited datasets were as follows.

### Baseline correction

Baseline correction was performed using the modified polynomial fitting algorithm (`modpolyfit`) implemented through `ChemoSpec::baselineSpectra()`.

Parameters:

- `int = FALSE`
- `retC = TRUE`
- polynomial degree: `degree = 4`
- convergence tolerance: `tol = 0.001`
- maximum iterations: `rep = 100`

### Standard Normal Variate (SNV)

SNV was applied independently to each spectrum by centering the spectral intensities using the spectrum-specific mean and scaling by the corresponding standard deviation.

### Multiplicative Scatter Correction (MSC)

MSC was calculated using the mean spectrum of the baseline-corrected dataset as the reference spectrum. The reference was calculated automatically by `mdatools::prep.msc()` using `mspectrum = NULL`.

### Savitzky–Golay derivatives

First- and second-order derivatives were calculated using the Savitzky–Golay implementation in `mdatools`.

Parameters:

- spectral window: `width = 9`
- polynomial order: `porder = 3`
- derivative order: first derivative (D1) or second derivative (D2)

Spectral edge points were handled internally by the implementation, and no spectral variables were intentionally removed as a consequence of derivative preprocessing.

For the original preprocessing framework and accompanying R implementation, see:

https://data.mendeley.com/datasets/gcf9cz6hsr/2  
DOI: 10.17632/gcf9cz6hsr.2

---

## 6. Machine-learning workflow

The deposited scripts implement PCA-based latent-variable machine-learning workflows.

### Common methodological rules

Both modeling scripts:

- use numeric wavenumber columns only as predictor variables;
- treat sample descriptors as metadata only;
- use `Coffee Lot ID` as the biological grouping variable;
- perform train/validation partitioning before scaling and PCA;
- fit centering, scaling, and PCA using the training subset only;
- project validation observations using the PCA model fitted on the training subset;
- keep paired Green and Roasted observations from the same `Coffee Lot ID` in the same partition when both stages are analyzed together;
- use PCA diagnostics such as SPE and Hotelling's T² for diagnostic purposes only, without automatically deleting observations;
- save final models fitted to the complete selected dataset separately from the models used to estimate validation performance.

### Available processing-stage configurations

- Green only.
- Roasted only.
- Green + Roasted together.

### Available classification scenarios

- Defect-free vs all defects pooled.
- Defect-free vs one selected defect.
- Defect-free vs each individual defect.
- Six-class multiclass classification: Defect-free + five defect categories.

### Repeated grouped holdout

Available train/validation partitions are:

- 70% / 30%
- 75% / 25% — default
- 80% / 20%

The default number of repeated grouped holdout iterations is **1000**.

### PCA

The default rule retains the number of principal components required to explain **95% of the cumulative variance**. A fixed number of PCs may also be selected interactively.

PCA centering, scaling, and loadings are estimated from training observations only.

### Support Vector Machine

The SVM workflow uses the `kernlab` package.

Default configuration:

- kernel: polynomial (`polydot`)
- `C = 100`
- inverse-frequency class weights calculated from training observations only
- optional grouped inner cross-validation for hyperparameter tuning

Alternative radial-basis (`rbfdot`) and linear (`vanilladot`) kernels can also be selected.

### Random Forest

The RF workflow uses the `randomForest` package.

Default configuration:

- number of trees: `ntree = 550`
- balanced bootstrap sampling is applied within the training subset
- validation observations retain their natural class distribution

---

## 7. Reproducibility instructions

1. Download all repository files into the same working directory.
2. Open R or RStudio and set that directory as the working directory.
3. Install the packages required by the selected modeling script if they are not already available.
4. Run either:
   - `ModelingSupportVectorMachine_Advanced.R`, or
   - `ModelingRandomForest_Advanced.R`.
5. Select the desired preprocessing dataset, processing stage, classification scenario, train/validation partition, and PCA configuration through the interactive menu.
6. For SVM, additionally select the kernel and hyperparameter strategy.
7. The scripts create dedicated results directories and record the selected run settings and R session information to support reproducibility.

Because the scripts use explicit `Coffee Lot ID` values for biological grouping, the original spreadsheet row order should not be used to define sample independence.

---

## 8. Important interpretation note

The 50 `Coffee Lot ID` values represent the independent biological units of the study. The 100 deposited stage-specific spectra should therefore not be interpreted as 100 independent biological samples when Green and Roasted observations are analyzed jointly.

For binary classification with all defect categories pooled, the biological dataset contains 25 defect-free lots and 25 defective lots.

For six-class classification, the dataset contains 25 defect-free biological lots and five independent biological lots for each individual defect category. Multiclass analyses should therefore be interpreted as exploratory and require validation using larger independent datasets and external validation samples before defect-specific generalization is established.

---

## 9. Citation and versioning

Users should cite the **latest version of this Mendeley Data repository** used in their analysis.

When Version 5 is published, replace the placeholder at the beginning of this README with the final Version 5 DOI assigned by Mendeley Data.

The spectral preprocessing framework should be cited separately when relevant:

Collazos-Escobar, G. A., Bahamón Monje, A. F., & Gutierrez Guzman, N. (2026). _R Codes for Preprocessing FT-NIR, FTIR, and Raman Spectral Data and Machine Learning Tools for Predictive and Classification Model Calibration_. Mendeley Data, Version 2. https://doi.org/10.17632/gcf9cz6hsr.2
