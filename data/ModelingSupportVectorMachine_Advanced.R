# =============================================================================
# PCA_SVM_Modeling_Advanced_CoffeeDefects.R
#
# Advanced leakage-free PCA + Support Vector Machine workflow for FTIR coffee
# defect classification.
# Revised for the metadata-rich spectral workbooks (7 metadata columns + FTIR variables).
#
# INPUT FILES
#   Dataset_Raw.xlsx
#   Dataset_BaselineCorrected.xlsx
#   Dataset_StandardNormalVariateCorrected.xlsx
#   Dataset_MultiplicativeScatterCorrected.xlsx
#   Dataset_FirstDerivative_1D.xlsx
#   Dataset_SecondDerivative_2D.xlsx
#   SampleDescription.xlsx
#
# METHODOLOGICAL PRINCIPLES
# 1) Biological sample grouping is respected during every train/validation split.
# 2) When Green + Roasted are analyzed jointly, paired observations from the
#    same physical coffee sample remain in the same partition.
# 3) Mean-centering, variance scaling and PCA are fitted ONLY on training data.
# 4) Validation spectra are projected using training-set PCA parameters.
# 5) All sample descriptors are metadata ONLY; only numeric wavenumber columns are predictors.
# 6) Class imbalance is handled ONLY within the training subset through inverse
#    class-frequency SVM weights; validation data retain their natural balance.
# 7) Hyperparameters can be kept fixed (original manuscript configuration) or
#    selected by grouped inner cross-validation using TRAINING data only.
# 8) SPE and Hotelling's T2 are diagnostic outputs; observations are not removed
#    automatically.
# 9) Final full-data models are saved for future use but are NOT used to estimate
#    validation performance.
# =============================================================================


# =============================================================================
# 0. REQUIRED PACKAGES
# =============================================================================

required_packages <- c("readxl", "kernlab", "pROC")

for (pkg in required_packages) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    stop(
      paste0(
        "\nPackage '", pkg, "' is required but is not installed.\n",
        "Install it with:\ninstall.packages('", pkg, "')\n"
      )
    )
  }
}

suppressPackageStartupMessages({
  library(readxl)
  library(kernlab)
  library(pROC)
})


# =============================================================================
# 1. GLOBAL SETTINGS
# =============================================================================

MASTER_SEED <- 1234

# Repeated grouped holdout
N_REPEATS_DEFAULT <- 1000

# PCA
PCA_VARIANCE_THRESHOLD_DEFAULT <- 0.95

# SVM original manuscript configuration
DEFAULT_KERNEL <- "polydot"
DEFAULT_C <- 100
DEFAULT_EPSILON <- 0.1
DEFAULT_NU <- 0.2
DEFAULT_TOL <- 0.001

# When TRUE, inverse-frequency class weights are estimated from TRAINING only.
USE_CLASS_WEIGHTS <- TRUE

# Hyperparameter tuning
DEFAULT_TUNING_MODE <- "fixed"  # "fixed" or "inner_cv"
INNER_CV_FOLDS <- 4

# Reasonable grids for nested/grouped inner CV.
# Keep grids compact because nested tuning inside repeated holdout can be costly.
C_GRID <- c(0.1, 1, 10, 100, 1000)
SIGMA_GRID <- c(0.001, 0.01, 0.1, 1)
POLY_DEGREE_GRID <- c(2, 3)
POLY_SCALE_GRID <- c(0.1, 1)
POLY_OFFSET_GRID <- c(0, 1)

OUTPUT_ROOT <- "PCA_SVM_Advanced_Results"
SKIP_COMPLETED_CONFIGURATIONS <- TRUE

# The revised SampleDescription workbook contains an explicit Coffee Lot ID.
# This is used as the biological Sample_ID for grouped train/validation splitting.
# No biological sample identifiers are inferred from row order.


# =============================================================================
# 2. DATASET DEFINITIONS
# =============================================================================

DATASETS <- list(
  Raw = list(
    file = "Dataset_Raw.xlsx",
    sheet = "Raw"
  ),
  Baseline = list(
    file = "Dataset_BaselineCorrected.xlsx",
    sheet = "Baseline"
  ),
  SNV = list(
    file = "Dataset_StandardNormalVariateCorrected.xlsx",
    sheet = "SNV"
  ),
  MSC = list(
    file = "Dataset_MultiplicativeScatterCorrected.xlsx",
    sheet = "MSC"
  ),
  D1 = list(
    file = "Dataset_FirstDerivative_1D.xlsx",
    sheet = "FirstDerivative"
  ),
  D2 = list(
    file = "Dataset_SecondDerivative_2D.xlsx",
    sheet = "SecondDerivative"
  )
)

SAMPLE_DESCRIPTION_FILE <- "SampleDescription.xlsx"
SAMPLE_DESCRIPTION_SHEET <- "Sample_description"

EXPECTED_DEFECT_TYPES <- c(
  "Defect-free",
  "Bitten",
  "Vinegar",
  "Drill bit",
  "Discolored",
  "Black"
)

DEFECT_TYPES_ONLY <- setdiff(EXPECTED_DEFECT_TYPES, "Defect-free")


# =============================================================================
# 3. GENERAL UTILITIES
# =============================================================================

sanitize_filename <- function(x) {
  x <- gsub("[^A-Za-z0-9_-]+", "_", x)
  x <- gsub("_+", "_", x)
  x <- gsub("^_|_$", "", x)
  x
}


ask_menu <- function(title, choices, default = NULL) {
  cat("\n", paste(rep("=", 78), collapse = ""), "\n", sep = "")
  cat(title, "\n")
  cat(paste(rep("=", 78), collapse = ""), "\n", sep = "")

  for (i in seq_along(choices)) {
    cat(sprintf("  %d) %s\n", i, choices[[i]]))
  }

  repeat {
    prompt <- if (is.null(default)) {
      "Select option: "
    } else {
      paste0("Select option [default ", default, "]: ")
    }

    ans <- trimws(readline(prompt))

    if (ans == "" && !is.null(default)) {
      ans <- as.character(default)
    }

    ans_num <- suppressWarnings(as.integer(ans))

    if (!is.na(ans_num) && ans_num >= 1 && ans_num <= length(choices)) {
      return(ans_num)
    }

    cat("Invalid option. Please try again.\n")
  }
}


ask_numeric <- function(prompt, default, min_value = NULL, max_value = NULL) {
  repeat {
    ans <- trimws(readline(paste0(prompt, " [default ", default, "]: ")))

    if (ans == "") {
      value <- default
    } else {
      value <- suppressWarnings(as.numeric(ans))
    }

    if (is.na(value)) {
      cat("Invalid numeric value. Please try again.\n")
      next
    }

    if (!is.null(min_value) && value < min_value) {
      cat("Value must be >= ", min_value, ".\n", sep = "")
      next
    }

    if (!is.null(max_value) && value > max_value) {
      cat("Value must be <= ", max_value, ".\n", sep = "")
      next
    }

    return(value)
  }
}


safe_write_csv <- function(x, file) {
  write.csv(x, file = file, row.names = FALSE, na = "")
}


safe_mean <- function(x) {
  if (all(is.na(x))) return(NA_real_)
  mean(x, na.rm = TRUE)
}


safe_sd <- function(x) {
  if (sum(!is.na(x)) <= 1) return(NA_real_)
  sd(x, na.rm = TRUE)
}


write_session_info <- function(output_dir) {
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  capture.output(sessionInfo(), file = file.path(output_dir, "sessionInfo.txt"))
}


# =============================================================================
# 4. READ AND VALIDATE SAMPLE METADATA
# =============================================================================

# Return the first matching column name from a set of accepted aliases.
# This keeps the script compatible with the revised metadata file while still
# accepting the earlier naming convention if needed.
find_column <- function(data, candidates, required = TRUE) {

  current_names <- trimws(names(data))
  names(data) <- current_names

  hit <- candidates[candidates %in% current_names]

  if (length(hit) > 0) {
    return(hit[1])
  }

  if (required) {
    stop(
      paste0(
        "\nRequired metadata column not found. Expected one of: ",
        paste(candidates, collapse = ", ")
      )
    )
  }

  NA_character_
}


# Resolve a workbook filename robustly. The preferred publication/repository
# filename is used first; numbered copies created by browsers/operating systems
# (e.g., Dataset_Raw(1).xlsx) are accepted as a fallback.
resolve_input_file <- function(preferred_file) {

  if (file.exists(preferred_file)) {
    return(preferred_file)
  }

  stem <- tools::file_path_sans_ext(basename(preferred_file))
  ext <- tolower(tools::file_ext(preferred_file))

  all_files <- list.files(
    path = ".",
    full.names = FALSE
  )

  all_files <- all_files[
    tolower(tools::file_ext(all_files)) == ext
  ]

  candidate_stems <- tools::file_path_sans_ext(
    basename(all_files)
  )

  prefix <- paste0(stem, "(")

  looks_numbered <- startsWith(
    candidate_stems,
    prefix
  ) & endsWith(
    candidate_stems,
    ")"
  )

  if (any(looks_numbered)) {
    numbered_files <- all_files[looks_numbered]
    numbered_stems <- candidate_stems[looks_numbered]

    inside <- substring(
      numbered_stems,
      nchar(prefix) + 1,
      nchar(numbered_stems) - 1
    )

    valid_numbered <- grepl(
      "^[0-9]+$",
      inside
    )

    candidates <- numbered_files[valid_numbered]

    if (length(candidates) > 0) {
      candidates <- sort(candidates)

      message(
        "Using numbered workbook copy '",
        candidates[1],
        "' for expected file '",
        preferred_file,
        "'."
      )

      return(candidates[1])
    }
  }

  stop(
    paste0(
      "\nInput file not found: ", preferred_file,
      "\nPlace the revised workbook in the same working directory as this script."
    )
  )
}


read_sample_metadata <- function() {

  metadata_file <- resolve_input_file(SAMPLE_DESCRIPTION_FILE)

  meta <- as.data.frame(
    readxl::read_excel(
      metadata_file,
      sheet = SAMPLE_DESCRIPTION_SHEET
    ),
    check.names = FALSE
  )

  # Remove accidental leading/trailing spaces from Excel headers.
  names(meta) <- trimws(names(meta))

  # ---------------------------------------------------------------------------
  # Revised SampleDescription.xlsx column mapping
  # ---------------------------------------------------------------------------
  # Current workbook:
  #   V1 | Process | Defect status | Processing stage | Defect category |
  #   Within category ID | Coffee Lot ID | Observation ID |
  #   Technical replicas averaged | geographical/environmental descriptors
  #
  # Coffee Lot ID is the TRUE biological grouping variable:
  #   50 independent coffee lots -> each observed as Green and Roasted.
  # Observation ID identifies the individual sample-stage spectral observation.
  # Every deposited spectrum is already the point-by-point mean of 3 technical
  # ATR-FTIR acquisitions; technical acquisitions are NOT independent rows.
  # ---------------------------------------------------------------------------

  col_v1 <- find_column(meta, c("V1"))
  col_process <- find_column(meta, c("Process"))
  col_status <- find_column(
    meta,
    c("Defect status", "Defect_Status", "Description V1")
  )
  col_stage <- find_column(
    meta,
    c("Processing stage", "Processing_stage", "Description of process")
  )
  col_category <- find_column(
    meta,
    c("Defect category", "Defect_Category", "Type")
  )
  col_within <- find_column(
    meta,
    c("Within category ID", "Within_category_ID", "Within_Type_ID")
  )
  col_lot <- find_column(
    meta,
    c("Coffee Lot ID", "Coffee_lot_ID", "Coffee_Lot_ID", "Sample_ID")
  )
  col_observation <- find_column(
    meta,
    c("Observation ID", "Observation_ID"),
    required = FALSE
  )
  col_techrep <- find_column(
    meta,
    c(
      "Technical replicas averaged",
      "Technical replicates averaged",
      "Technical_replicates_averaged"
    ),
    required = FALSE
  )

  # Canonical internal names used throughout the modeling pipeline.
  meta$V1 <- as.numeric(meta[[col_v1]])
  meta$Process <- as.numeric(meta[[col_process]])
  meta$Defect_Status <- trimws(as.character(meta[[col_status]]))
  meta$Defect_Category <- trimws(as.character(meta[[col_category]]))
  meta$Stage <- trimws(as.character(meta[[col_stage]]))
  meta$Within_Category_ID <- as.integer(meta[[col_within]])
  meta$Coffee_Lot_ID <- trimws(as.character(meta[[col_lot]]))

  # The biological Sample_ID used for grouped splitting is explicitly the
  # Coffee Lot ID supplied in the revised metadata file.
  meta$Sample_ID <- meta$Coffee_Lot_ID

  if (!is.na(col_observation)) {
    meta$Observation_ID <- trimws(as.character(meta[[col_observation]]))
  } else {
    meta$Observation_ID <- paste0(
      "LOT_",
      sprintf("%03d", as.integer(meta$Coffee_Lot_ID)),
      "_",
      meta$Stage
    )
  }

  if (!is.na(col_techrep)) {
    meta$Technical_Replicates_Averaged <- as.integer(meta[[col_techrep]])
  } else {
    meta$Technical_Replicates_Averaged <- NA_integer_
  }

  # Optional geographical/environmental metadata are standardized for export.
  col_municipality <- find_column(
    meta,
    c("Municipality", "Municipality (Huila-Colombia)"),
    required = FALSE
  )
  col_latitude <- find_column(
    meta,
    c("Latitude"),
    required = FALSE
  )
  col_longitude <- find_column(
    meta,
    c("Longitude", "Longuitude"),
    required = FALSE
  )
  col_altitude <- find_column(
    meta,
    c("Altitude_masl", "Height (masl)"),
    required = FALSE
  )
  col_rainfall <- find_column(
    meta,
    c("Rainfall_mm", "rainfall (mm)", "Rainfall (mm)"),
    required = FALSE
  )

  if (!is.na(col_municipality)) {
    meta$Municipality <- trimws(as.character(meta[[col_municipality]]))
  }
  if (!is.na(col_latitude)) {
    meta$Latitude <- as.numeric(meta[[col_latitude]])
  }
  if (!is.na(col_longitude)) {
    meta$Longitude <- as.numeric(meta[[col_longitude]])
  }
  if (!is.na(col_altitude)) {
    meta$Altitude_masl <- as.numeric(meta[[col_altitude]])
  }
  if (!is.na(col_rainfall)) {
    meta$Rainfall_mm <- as.numeric(meta[[col_rainfall]])
  }

  # ---------------------------------------------------------------------------
  # Structural validation
  # ---------------------------------------------------------------------------

  if (anyNA(meta$V1) || !all(meta$V1 %in% c(0, 1))) {
    stop("\nV1 must contain only the binary codes 0 (defect-free) and 1 (defective).")
  }

  if (anyNA(meta$Process) || !all(meta$Process %in% c(0, 1))) {
    stop("\nProcess must contain only 0 (Green) and 1 (Roasted).")
  }

  if (!all(meta$Defect_Category %in% EXPECTED_DEFECT_TYPES)) {
    unknown <- unique(
      meta$Defect_Category[
        !meta$Defect_Category %in% EXPECTED_DEFECT_TYPES
      ]
    )

    stop(
      paste0(
        "\nUnexpected defect categories were found: ",
        paste(unknown, collapse = ", "),
        "\nExpected categories are: ",
        paste(EXPECTED_DEFECT_TYPES, collapse = ", ")
      )
    )
  }

  if (!all(meta$Stage %in% c("Green", "Roasted"))) {
    unknown_stage <- unique(
      meta$Stage[!meta$Stage %in% c("Green", "Roasted")]
    )

    stop(
      paste0(
        "\nUnexpected processing stages were found: ",
        paste(unknown_stage, collapse = ", ")
      )
    )
  }

  # Numerical codes and descriptive labels must agree.
  if (any((meta$V1 == 0) != (meta$Defect_Status == "Defect-free"))) {
    stop("\nV1 and Defect status are inconsistent in SampleDescription.xlsx.")
  }

  if (any((meta$Process == 0) != (meta$Stage == "Green"))) {
    stop("\nProcess and Processing stage are inconsistent in SampleDescription.xlsx.")
  }

  if (anyDuplicated(meta$Observation_ID)) {
    duplicated_ids <- unique(
      meta$Observation_ID[duplicated(meta$Observation_ID)]
    )
    stop(
      paste0(
        "\nObservation ID must be unique. Duplicates: ",
        paste(duplicated_ids, collapse = ", ")
      )
    )
  }

  # Each biological lot must map to one defect category/status.
  lot_category_count <- tapply(
    meta$Defect_Category,
    meta$Sample_ID,
    function(z) length(unique(z))
  )
  lot_status_count <- tapply(
    meta$Defect_Status,
    meta$Sample_ID,
    function(z) length(unique(z))
  )

  if (any(lot_category_count != 1) || any(lot_status_count != 1)) {
    stop(
      "\nAt least one Coffee Lot ID maps to more than one defect status/category."
    )
  }

  # For the present study, each independent coffee lot should have exactly one
  # Green and one Roasted representative spectrum.
  lot_stage_table <- table(meta$Sample_ID, meta$Stage)

  if (
    !all(c("Green", "Roasted") %in% colnames(lot_stage_table)) ||
    any(lot_stage_table[, "Green"] != 1) ||
    any(lot_stage_table[, "Roasted"] != 1)
  ) {
    stop(
      paste0(
        "\nEach Coffee Lot ID must contain exactly one Green and one Roasted ",
        "representative spectral observation."
      )
    )
  }

  if (
    any(!is.na(meta$Technical_Replicates_Averaged)) &&
    any(
      meta$Technical_Replicates_Averaged[
        !is.na(meta$Technical_Replicates_Averaged)
      ] != 3
    )
  ) {
    warning(
      "Technical replicas averaged is not equal to 3 for every observation."
    )
  }

  meta
}


# =============================================================================
# 5. READ AND VALIDATE SPECTRAL DATA
# =============================================================================

read_spectral_dataset <- function(dataset_key, meta) {

  cfg <- DATASETS[[dataset_key]]

  if (is.null(cfg)) {
    stop("Unknown dataset key: ", dataset_key)
  }

  spectral_file <- resolve_input_file(cfg$file)

  dat <- as.data.frame(
    readxl::read_excel(
      spectral_file,
      sheet = cfg$sheet
    ),
    check.names = FALSE
  )

  names(dat) <- trimws(names(dat))

  if (nrow(dat) != nrow(meta)) {
    stop(
      paste0(
        "\nRow mismatch between ", spectral_file,
        " (", nrow(dat), " rows) and metadata (",
        nrow(meta), " rows)."
      )
    )
  }

  # Revised spectral workbooks contain seven metadata columns before the
  # wavenumber variables. Rather than relying on fixed column positions, the
  # script identifies spectral variables from numeric wavenumber headers.
  required_spectral_metadata <- c(
    "V1",
    "Process",
    "Defect status",
    "Processing stage",
    "Defect category",
    "Within category ID",
    "Coffee Lot ID"
  )

  missing_meta <- setdiff(
    required_spectral_metadata,
    names(dat)
  )

  if (length(missing_meta) > 0) {
    stop(
      paste0(
        "\nThe revised spectral workbook ", spectral_file,
        " is missing metadata columns: ",
        paste(missing_meta, collapse = ", ")
      )
    )
  }

  # Verify row-by-row linkage between the spectral workbook and metadata file.
  same_text <- function(a, b) {
    trimws(as.character(a)) == trimws(as.character(b))
  }

  if (!all(as.numeric(dat[["V1"]]) == meta$V1)) {
    stop(paste0("\nV1 labels in ", spectral_file, " do not align with SampleDescription.xlsx."))
  }

  if (!all(as.numeric(dat[["Process"]]) == meta$Process)) {
    stop(paste0("\nProcess labels in ", spectral_file, " do not align with SampleDescription.xlsx."))
  }

  if (!all(same_text(dat[["Defect status"]], meta$Defect_Status))) {
    stop(paste0("\nDefect status in ", spectral_file, " does not align with SampleDescription.xlsx."))
  }

  if (!all(same_text(dat[["Processing stage"]], meta$Stage))) {
    stop(paste0("\nProcessing stage in ", spectral_file, " does not align with SampleDescription.xlsx."))
  }

  if (!all(same_text(dat[["Defect category"]], meta$Defect_Category))) {
    stop(paste0("\nDefect category in ", spectral_file, " does not align with SampleDescription.xlsx."))
  }

  if (!all(as.integer(dat[["Within category ID"]]) == meta$Within_Category_ID)) {
    stop(paste0("\nWithin category ID in ", spectral_file, " does not align with SampleDescription.xlsx."))
  }

  if (!all(same_text(dat[["Coffee Lot ID"]], meta$Coffee_Lot_ID))) {
    stop(paste0("\nCoffee Lot ID in ", spectral_file, " does not align with SampleDescription.xlsx."))
  }

  # Numeric column names correspond to FTIR wavenumbers.
  spectral_idx <- which(
    !is.na(
      suppressWarnings(
        as.numeric(names(dat))
      )
    )
  )

  if (length(spectral_idx) < 2) {
    stop(
      paste0(
        "\nNo valid wavenumber columns were detected in ",
        spectral_file,
        ". Spectral column headers must be numeric wavenumbers."
      )
    )
  }

  spectral <- dat[, spectral_idx, drop = FALSE]
  spectral[] <- lapply(spectral, as.numeric)

  X <- as.matrix(spectral)

  if (any(!is.finite(X))) {
    bad <- sum(!is.finite(X))
    stop(
      paste0(
        "\nThe spectral matrix in ", spectral_file,
        " contains ", bad,
        " non-finite values (NA/NaN/Inf)."
      )
    )
  }

  list(
    X = X,
    wavenumbers = colnames(spectral),
    raw_data = dat,
    source_file = spectral_file
  )
}


# =============================================================================
# 6. CLASSIFICATION SCENARIOS
# =============================================================================

build_scenario <- function(meta, X, stage_option, scenario_name) {

  if (stage_option == "Green") {
    stage_keep <- meta$Stage == "Green"
  } else if (stage_option == "Roasted") {
    stage_keep <- meta$Stage == "Roasted"
  } else if (stage_option == "Both") {
    stage_keep <- rep(TRUE, nrow(meta))
  } else {
    stop("Unknown stage option: ", stage_option)
  }

  m <- meta[stage_keep, , drop = FALSE]
  x <- X[stage_keep, , drop = FALSE]

  if (scenario_name == "Binary_AllDefects") {

    m$Class <- ifelse(
      m$Defect_Category == "Defect-free",
      "Defect-free",
      "Defective"
    )

    m$Class <- factor(
      m$Class,
      levels = c("Defect-free", "Defective")
    )

    positive_class <- "Defective"

  } else if (grepl("^Pairwise_", scenario_name)) {

    exact_map <- setNames(
      DEFECT_TYPES_ONLY,
      gsub(" ", "_", DEFECT_TYPES_ONLY)
    )

    key <- sub("^Pairwise_", "", scenario_name)
    defect_name <- exact_map[[key]]

    if (is.null(defect_name) || is.na(defect_name)) {
      stop("Unknown pairwise scenario: ", scenario_name)
    }

    keep <- m$Defect_Category %in% c("Defect-free", defect_name)

    m <- m[keep, , drop = FALSE]
    x <- x[keep, , drop = FALSE]

    m$Class <- factor(
      m$Defect_Category,
      levels = c("Defect-free", defect_name)
    )

    positive_class <- defect_name

  } else if (scenario_name == "Multiclass_6Classes") {

    keep <- m$Defect_Category %in% EXPECTED_DEFECT_TYPES

    m <- m[keep, , drop = FALSE]
    x <- x[keep, , drop = FALSE]

    m$Class <- factor(
      m$Defect_Category,
      levels = EXPECTED_DEFECT_TYPES
    )

    positive_class <- NA_character_

  } else {
    stop("Unknown scenario: ", scenario_name)
  }

  m$Class <- droplevels(m$Class)

  # Every biological sample must map to one response class.
  group_check <- split(as.character(m$Class), m$Sample_ID)

  bad_groups <- names(group_check)[
    vapply(
      group_check,
      function(z) length(unique(z)) > 1,
      logical(1)
    )
  ]

  if (length(bad_groups) > 0) {
    stop(
      paste0(
        "\nA biological Sample_ID maps to more than one response class: ",
        paste(bad_groups, collapse = ", ")
      )
    )
  }

  list(
    meta = m,
    X = x,
    positive_class = positive_class
  )
}


# =============================================================================
# 7. GROUPED STRATIFIED HOLDOUT
# =============================================================================

grouped_stratified_split <- function(meta, train_fraction, seed) {

  set.seed(seed)

  group_df <- unique(
    data.frame(
      Sample_ID = meta$Sample_ID,
      Class = as.character(meta$Class),
      stringsAsFactors = FALSE
    )
  )

  train_ids <- character(0)

  for (cl in unique(group_df$Class)) {

    ids <- group_df$Sample_ID[group_df$Class == cl]
    n_ids <- length(ids)

    if (n_ids < 2) {
      stop(
        paste0(
          "\nClass '", cl,
          "' has fewer than two independent biological samples."
        )
      )
    }

    n_train <- floor(n_ids * train_fraction)
    n_train <- max(1, min(n_ids - 1, n_train))

    train_ids <- c(
      train_ids,
      sample(ids, size = n_train, replace = FALSE)
    )
  }

  train_index <- which(meta$Sample_ID %in% train_ids)
  valid_index <- which(!meta$Sample_ID %in% train_ids)

  overlap <- intersect(
    unique(meta$Sample_ID[train_index]),
    unique(meta$Sample_ID[valid_index])
  )

  if (length(overlap) > 0) {
    stop("\nGrouped split failure: Sample_ID leakage across partitions.")
  }

  list(
    train = train_index,
    valid = valid_index,
    train_ids = train_ids
  )
}


# =============================================================================
# 8. LEAKAGE-FREE PCA
# =============================================================================

fit_training_pca <- function(
  X_train,
  X_valid,
  pca_mode = c("variance", "fixed"),
  variance_threshold = 0.95,
  fixed_ncomp = NULL
) {

  pca_mode <- match.arg(pca_mode)

  train_sd <- apply(X_train, 2, sd)
  keep_vars <- is.finite(train_sd) & train_sd > 0

  Xtr <- X_train[, keep_vars, drop = FALSE]
  Xva <- X_valid[, keep_vars, drop = FALSE]

  if (ncol(Xtr) < 2) {
    stop("\nFewer than two usable spectral variables remain for PCA.")
  }

  # Center, scale and loadings are learned from TRAINING only.
  pca <- prcomp(
    Xtr,
    center = TRUE,
    scale. = TRUE,
    retx = TRUE
  )

  var_prop <- pca$sdev ^ 2 / sum(pca$sdev ^ 2)
  cum_var <- cumsum(var_prop)

  if (pca_mode == "variance") {
    ncomp <- which(cum_var >= variance_threshold)[1]
  } else {
    if (is.null(fixed_ncomp)) {
      stop("fixed_ncomp must be supplied when pca_mode='fixed'.")
    }
    ncomp <- as.integer(fixed_ncomp)
  }

  ncomp <- max(1, min(ncomp, ncol(pca$x)))

  train_scores <- pca$x[, seq_len(ncomp), drop = FALSE]

  # Validation observations are projected through the TRAINING PCA model.
  valid_scores_all <- predict(
    pca,
    newdata = Xva
  )

  valid_scores <- valid_scores_all[, seq_len(ncomp), drop = FALSE]

  colnames(train_scores) <- paste0("PC", seq_len(ncomp))
  colnames(valid_scores) <- paste0("PC", seq_len(ncomp))

  # ---------------------------------------------------------------------------
  # SPE and Hotelling T2
  # ---------------------------------------------------------------------------

  Xtr_scaled <- scale(
    Xtr,
    center = pca$center,
    scale = pca$scale
  )

  Xva_scaled <- scale(
    Xva,
    center = pca$center,
    scale = pca$scale
  )

  Psel <- pca$rotation[, seq_len(ncomp), drop = FALSE]

  Xtr_pred <- train_scores %*% t(Psel)
  Xva_pred <- valid_scores %*% t(Psel)

  Etr <- Xtr_scaled - Xtr_pred
  Eva <- Xva_scaled - Xva_pred

  SPE_train <- rowSums(Etr ^ 2)
  SPE_valid <- rowSums(Eva ^ 2)

  eig <- pca$sdev[seq_len(ncomp)] ^ 2
  eig[eig <= .Machine$double.eps] <- .Machine$double.eps

  T2_train <- rowSums(
    sweep(train_scores ^ 2, 2, eig, FUN = "/")
  )

  T2_valid <- rowSums(
    sweep(valid_scores ^ 2, 2, eig, FUN = "/")
  )

  limits <- list(
    SPE95 = unname(quantile(SPE_train, 0.95, na.rm = TRUE)),
    SPE99 = unname(quantile(SPE_train, 0.99, na.rm = TRUE)),
    T2_95 = unname(quantile(T2_train, 0.95, na.rm = TRUE)),
    T2_99 = unname(quantile(T2_train, 0.99, na.rm = TRUE))
  )

  list(
    pca = pca,
    keep_vars = keep_vars,
    ncomp = ncomp,
    var_prop = var_prop,
    cum_var = cum_var,
    train_scores = train_scores,
    valid_scores = valid_scores,
    diagnostics = list(
      SPE_train = SPE_train,
      SPE_valid = SPE_valid,
      T2_train = T2_train,
      T2_valid = T2_valid,
      limits = limits
    )
  )
}


# =============================================================================
# 9. CLASS WEIGHTS
# =============================================================================

calculate_class_weights <- function(y) {

  y <- droplevels(factor(y))
  counts <- table(y)

  # Inverse-frequency weights normalized to mean = 1.
  raw_weights <- sum(counts) / (length(counts) * counts)
  weights <- raw_weights / mean(raw_weights)

  # kernlab::ksvm expects class.weights as a named numeric vector.
  setNames(
    as.numeric(weights),
    names(weights)
  )
}


# =============================================================================
# 10. METRICS
# =============================================================================

cohen_kappa_from_cm <- function(cm) {

  n <- sum(cm)

  if (n == 0) return(NA_real_)

  po <- sum(diag(cm)) / n
  pe <- sum(rowSums(cm) * colSums(cm)) / (n ^ 2)

  if (abs(1 - pe) < .Machine$double.eps) {
    return(NA_real_)
  }

  (po - pe) / (1 - pe)
}


multiclass_mcc_from_cm <- function(cm) {

  s <- sum(cm)

  if (s == 0) return(NA_real_)

  c_diag <- sum(diag(cm))
  t_k <- rowSums(cm)
  p_k <- colSums(cm)

  numerator <- c_diag * s - sum(t_k * p_k)

  denominator <- sqrt(
    (s ^ 2 - sum(p_k ^ 2)) *
      (s ^ 2 - sum(t_k ^ 2))
  )

  if (!is.finite(denominator) || denominator == 0) {
    return(NA_real_)
  }

  numerator / denominator
}


safe_binary_auc <- function(y_true, prob_positive, positive_class) {

  y_true <- droplevels(factor(y_true))

  if (nlevels(y_true) != 2) return(NA_real_)

  negative_class <- setdiff(levels(y_true), positive_class)

  if (length(negative_class) != 1) return(NA_real_)

  tryCatch(
    {
      roc_obj <- pROC::roc(
        response = y_true,
        predictor = prob_positive,
        levels = c(negative_class, positive_class),
        direction = "<",
        quiet = TRUE
      )

      as.numeric(pROC::auc(roc_obj))
    },
    error = function(e) NA_real_
  )
}


safe_multiclass_auc <- function(y_true, prob_matrix) {

  tryCatch(
    {
      auc_obj <- pROC::multiclass.roc(
        response = y_true,
        predictor = prob_matrix,
        quiet = TRUE
      )

      as.numeric(auc_obj$auc)
    },
    error = function(e) NA_real_
  )
}


calculate_metrics <- function(
  y_true,
  y_pred,
  prob_matrix = NULL,
  positive_class = NA_character_
) {

  lvls <- levels(y_true)

  y_true <- factor(y_true, levels = lvls)
  y_pred <- factor(y_pred, levels = lvls)

  cm <- table(True = y_true, Predicted = y_pred)

  n <- sum(cm)
  accuracy <- if (n > 0) sum(diag(cm)) / n else NA_real_
  kappa <- cohen_kappa_from_cm(cm)

  class_metrics <- lapply(seq_along(lvls), function(k) {

    tp <- cm[k, k]
    fn <- sum(cm[k, ]) - tp
    fp <- sum(cm[, k]) - tp
    tn <- sum(cm) - tp - fn - fp

    sensitivity <- if ((tp + fn) > 0) tp / (tp + fn) else NA_real_
    specificity <- if ((tn + fp) > 0) tn / (tn + fp) else NA_real_
    precision <- if ((tp + fp) > 0) tp / (tp + fp) else NA_real_
    recall <- sensitivity

    f1 <- if (
      is.finite(precision) &&
      is.finite(recall) &&
      (precision + recall) > 0
    ) {
      2 * precision * recall / (precision + recall)
    } else {
      NA_real_
    }

    data.frame(
      Class = lvls[k],
      Sensitivity = sensitivity,
      Specificity = specificity,
      Precision = precision,
      Recall = recall,
      F1 = f1,
      stringsAsFactors = FALSE
    )
  })

  class_metrics <- do.call(rbind, class_metrics)

  out <- list(
    confusion = cm,
    class_metrics = class_metrics,
    Accuracy = accuracy,
    Kappa = kappa,
    Sensitivity = safe_mean(class_metrics$Sensitivity),
    Specificity = safe_mean(class_metrics$Specificity),
    Precision = safe_mean(class_metrics$Precision),
    Recall = safe_mean(class_metrics$Recall),
    F1 = safe_mean(class_metrics$F1),
    BalancedAccuracy = safe_mean(class_metrics$Sensitivity),
    MCC = multiclass_mcc_from_cm(cm),
    AUC = NA_real_
  )

  if (!is.null(prob_matrix)) {

    if (length(lvls) == 2 && !is.na(positive_class)) {

      if (positive_class %in% colnames(prob_matrix)) {
        out$AUC <- safe_binary_auc(
          y_true,
          prob_matrix[, positive_class],
          positive_class
        )
      }

      pos_row <- class_metrics[
        class_metrics$Class == positive_class,
        ,
        drop = FALSE
      ]

      if (nrow(pos_row) == 1) {
        out$Sensitivity <- pos_row$Sensitivity
        out$Specificity <- pos_row$Specificity
        out$Precision <- pos_row$Precision
        out$Recall <- pos_row$Recall
        out$F1 <- pos_row$F1
      }

    } else if (length(lvls) > 2) {

      out$AUC <- safe_multiclass_auc(
        y_true,
        prob_matrix
      )
    }
  }

  out
}


# =============================================================================
# 11. GROUPED INNER CROSS-VALIDATION FOR OPTIONAL HYPERPARAMETER TUNING
# =============================================================================

make_grouped_folds <- function(meta_train, k = 4, seed = 1234) {

  set.seed(seed)

  group_df <- unique(
    data.frame(
      Sample_ID = meta_train$Sample_ID,
      Class = as.character(meta_train$Class),
      stringsAsFactors = FALSE
    )
  )

  group_df$Fold <- NA_integer_

  for (cl in unique(group_df$Class)) {

    idx <- which(group_df$Class == cl)
    shuffled <- sample(idx)

    fold_assignments <- rep(seq_len(k), length.out = length(shuffled))
    group_df$Fold[shuffled] <- fold_assignments
  }

  group_df
}


build_svm_grid <- function(kernel_name) {

  if (kernel_name == "vanilladot") {

    expand.grid(
      C = C_GRID,
      Sigma = NA_real_,
      Degree = NA_real_,
      Scale = NA_real_,
      Offset = NA_real_,
      stringsAsFactors = FALSE
    )

  } else if (kernel_name == "rbfdot") {

    expand.grid(
      C = C_GRID,
      Sigma = SIGMA_GRID,
      Degree = NA_real_,
      Scale = NA_real_,
      Offset = NA_real_,
      stringsAsFactors = FALSE
    )

  } else if (kernel_name == "polydot") {

    expand.grid(
      C = C_GRID,
      Sigma = NA_real_,
      Degree = POLY_DEGREE_GRID,
      Scale = POLY_SCALE_GRID,
      Offset = POLY_OFFSET_GRID,
      stringsAsFactors = FALSE
    )

  } else {
    stop("Unsupported kernel for tuning: ", kernel_name)
  }
}


fit_ksvm_model <- function(
  X,
  y,
  kernel_name,
  C_value,
  class_weights = NULL,
  sigma = NA_real_,
  degree = NA_real_,
  scale_value = NA_real_,
  offset = NA_real_,
  prob_model = TRUE
) {

  y <- droplevels(factor(y))

  if (kernel_name == "vanilladot") {

    kpar_value <- "automatic"

  } else if (kernel_name == "rbfdot") {

    if (is.na(sigma)) {
      kpar_value <- "automatic"
    } else {
      kpar_value <- list(sigma = sigma)
    }

  } else if (kernel_name == "polydot") {

    if (
      is.na(degree) ||
      is.na(scale_value) ||
      is.na(offset)
    ) {
      kpar_value <- "automatic"
    } else {
      kpar_value <- list(
        degree = degree,
        scale = scale_value,
        offset = offset
      )
    }

  } else {
    stop("Unsupported kernel: ", kernel_name)
  }

  # IMPORTANT FOR MULTICLASS + CLASS WEIGHTS:
  # kernlab::ksvm can fail when prob.model = TRUE in weighted multiclass C-svc,
  # because probability calibration internally refits pairwise classifiers while
  # passing the full multiclass weight vector. Therefore probability fitting is
  # disabled only for weighted multiclass models. Binary models retain
  # probability estimates and AUC calculation.
  effective_prob_model <- isTRUE(prob_model)
  if (nlevels(y) > 2 && USE_CLASS_WEIGHTS && !is.null(class_weights)) {
    effective_prob_model <- FALSE
  }

  args <- list(
    x = as.matrix(X),
    y = y,
    type = "C-svc",
    kernel = kernel_name,
    C = C_value,
    kpar = kpar_value,
    scaled = FALSE,
    tol = DEFAULT_TOL,
    prob.model = effective_prob_model,
    cross = 0
  )

  if (USE_CLASS_WEIGHTS && !is.null(class_weights)) {
    args$class.weights <- class_weights
  }

  do.call(kernlab::ksvm, args)
}


safe_predict_probabilities <- function(model, X, class_levels) {

  probs <- tryCatch(
    {
      p <- predict(
        model,
        as.matrix(X),
        type = "probabilities"
      )

      p <- as.matrix(p)

      if (is.null(colnames(p))) {
        colnames(p) <- class_levels[seq_len(ncol(p))]
      }

      # Reorder/add missing class columns if necessary.
      out <- matrix(
        NA_real_,
        nrow = nrow(p),
        ncol = length(class_levels),
        dimnames = list(NULL, class_levels)
      )

      common <- intersect(class_levels, colnames(p))
      out[, common] <- p[, common, drop = FALSE]

      out
    },
    error = function(e) NULL
  )

  probs
}


evaluate_tuning_candidate <- function(
  X_train,
  meta_train,
  fold_map,
  kernel_name,
  candidate,
  positive_class
) {

  fold_scores <- numeric(0)

  for (fold_i in sort(unique(fold_map$Fold))) {

    valid_ids <- fold_map$Sample_ID[fold_map$Fold == fold_i]

    inner_valid_idx <- which(meta_train$Sample_ID %in% valid_ids)
    inner_train_idx <- which(!meta_train$Sample_ID %in% valid_ids)

    if (
      length(inner_train_idx) == 0 ||
      length(inner_valid_idx) == 0
    ) {
      next
    }

    y_inner_train <- droplevels(meta_train$Class[inner_train_idx])
    y_inner_valid <- factor(
      meta_train$Class[inner_valid_idx],
      levels = levels(meta_train$Class)
    )

    if (nlevels(y_inner_train) < 2) {
      next
    }

    # PCA is fitted again inside each inner training fold.
    inner_pca <- fit_training_pca(
      X_train = X_train[inner_train_idx, , drop = FALSE],
      X_valid = X_train[inner_valid_idx, , drop = FALSE],
      pca_mode = "variance",
      variance_threshold = PCA_VARIANCE_THRESHOLD_DEFAULT
    )

    weights <- if (USE_CLASS_WEIGHTS) {
      calculate_class_weights(y_inner_train)
    } else {
      NULL
    }

    model <- tryCatch(
      fit_ksvm_model(
        X = inner_pca$train_scores,
        y = y_inner_train,
        kernel_name = kernel_name,
        C_value = candidate$C,
        class_weights = weights,
        sigma = candidate$Sigma,
        degree = candidate$Degree,
        scale_value = candidate$Scale,
        offset = candidate$Offset,
        prob_model = FALSE
      ),
      error = function(e) NULL
    )

    if (is.null(model)) {
      next
    }

    pred <- tryCatch(
      predict(
        model,
        as.matrix(inner_pca$valid_scores),
        type = "response"
      ),
      error = function(e) NULL
    )

    if (is.null(pred)) {
      next
    }

    pred <- factor(pred, levels = levels(meta_train$Class))

    cm <- table(
      True = y_inner_valid,
      Predicted = pred
    )

    # Balanced accuracy = macro sensitivity.
    recalls <- vapply(
      seq_len(nrow(cm)),
      function(k) {
        denom <- sum(cm[k, ])
        if (denom == 0) return(NA_real_)
        cm[k, k] / denom
      },
      numeric(1)
    )

    fold_scores <- c(
      fold_scores,
      mean(recalls, na.rm = TRUE)
    )
  }

  if (length(fold_scores) == 0) {
    return(NA_real_)
  }

  mean(fold_scores, na.rm = TRUE)
}


tune_svm_grouped_inner_cv <- function(
  X_train,
  meta_train,
  kernel_name,
  positive_class,
  seed
) {

  # The number of folds cannot exceed the smallest number of biological samples
  # in a training class.
  group_df <- unique(
    meta_train[, c("Sample_ID", "Class"), drop = FALSE]
  )

  class_group_counts <- table(group_df$Class)

  k <- min(
    INNER_CV_FOLDS,
    min(class_group_counts)
  )

  if (k < 2) {
    stop(
      "\nInsufficient biological samples for grouped inner cross-validation."
    )
  }

  fold_map <- make_grouped_folds(
    meta_train = meta_train,
    k = k,
    seed = seed
  )

  grid <- build_svm_grid(kernel_name)
  grid$InnerCV_BalancedAccuracy <- NA_real_

  for (j in seq_len(nrow(grid))) {

    grid$InnerCV_BalancedAccuracy[j] <- evaluate_tuning_candidate(
      X_train = X_train,
      meta_train = meta_train,
      fold_map = fold_map,
      kernel_name = kernel_name,
      candidate = grid[j, , drop = FALSE],
      positive_class = positive_class
    )
  }

  if (all(is.na(grid$InnerCV_BalancedAccuracy))) {
    stop("\nAll inner-CV hyperparameter candidates failed.")
  }

  best_idx <- which.max(grid$InnerCV_BalancedAccuracy)

  list(
    best = grid[best_idx, , drop = FALSE],
    grid = grid,
    folds = k
  )
}


# =============================================================================
# 12. DIAGNOSTIC OUTPUTS
# =============================================================================

save_first_iteration_diagnostics <- function(
  config_dir,
  iteration,
  meta_train,
  meta_valid,
  pca_fit,
  wavenumbers
) {

  if (iteration != 1) return(invisible(NULL))

  ncomp <- pca_fit$ncomp

  pca_variance <- data.frame(
    PC = paste0("PC", seq_along(pca_fit$var_prop)),
    Variance = pca_fit$var_prop,
    CumulativeVariance = pca_fit$cum_var
  )

  safe_write_csv(
    pca_variance,
    file.path(config_dir, "PCA_ExplainedVariance_Repeat001.csv")
  )

  retained_wavenumbers <- wavenumbers[pca_fit$keep_vars]

  loadings <- as.data.frame(
    pca_fit$pca$rotation[, seq_len(ncomp), drop = FALSE],
    check.names = FALSE
  )

  loadings <- cbind(
    Wavenumber = retained_wavenumbers,
    loadings
  )

  safe_write_csv(
    loadings,
    file.path(config_dir, "PCA_Loadings_Repeat001.csv")
  )

  train_scores_df <- data.frame(
    Partition = "Training",
    Sample_ID = meta_train$Sample_ID,
    Observation_ID = meta_train$Observation_ID,
    Stage = meta_train$Stage,
    Class = as.character(meta_train$Class),
    pca_fit$train_scores,
    check.names = FALSE
  )

  valid_scores_df <- data.frame(
    Partition = "Validation",
    Sample_ID = meta_valid$Sample_ID,
    Observation_ID = meta_valid$Observation_ID,
    Stage = meta_valid$Stage,
    Class = as.character(meta_valid$Class),
    pca_fit$valid_scores,
    check.names = FALSE
  )

  all_scores <- rbind(
    train_scores_df,
    valid_scores_df
  )

  safe_write_csv(
    all_scores,
    file.path(config_dir, "PCA_Scores_Repeat001.csv")
  )

  diag_train <- data.frame(
    Partition = "Training",
    Sample_ID = meta_train$Sample_ID,
    Observation_ID = meta_train$Observation_ID,
    Stage = meta_train$Stage,
    Class = as.character(meta_train$Class),
    SPE = pca_fit$diagnostics$SPE_train,
    T2 = pca_fit$diagnostics$T2_train
  )

  diag_valid <- data.frame(
    Partition = "Validation",
    Sample_ID = meta_valid$Sample_ID,
    Observation_ID = meta_valid$Observation_ID,
    Stage = meta_valid$Stage,
    Class = as.character(meta_valid$Class),
    SPE = pca_fit$diagnostics$SPE_valid,
    T2 = pca_fit$diagnostics$T2_valid
  )

  diagnostics <- rbind(
    diag_train,
    diag_valid
  )

  lim <- pca_fit$diagnostics$limits

  diagnostics$SPE_Above95 <- diagnostics$SPE > lim$SPE95
  diagnostics$SPE_Above99 <- diagnostics$SPE > lim$SPE99
  diagnostics$T2_Above95 <- diagnostics$T2 > lim$T2_95
  diagnostics$T2_Above99 <- diagnostics$T2 > lim$T2_99

  safe_write_csv(
    diagnostics,
    file.path(config_dir, "PCA_SPE_T2_Diagnostics_Repeat001.csv")
  )

  safe_write_csv(
    data.frame(
      Statistic = c("SPE95", "SPE99", "T2_95", "T2_99"),
      Limit = c(
        lim$SPE95,
        lim$SPE99,
        lim$T2_95,
        lim$T2_99
      )
    ),
    file.path(config_dir, "PCA_ControlLimits_Repeat001.csv")
  )

  if (ncomp >= 2) {

    png(
      file.path(config_dir, "PCA_ScorePlot_PC1_PC2_Repeat001.png"),
      width = 1800,
      height = 1400,
      res = 180
    )

    classes <- factor(all_scores$Class)
    class_colors <- seq_len(nlevels(classes))
    pch_values <- ifelse(
      all_scores$Partition == "Training",
      16,
      1
    )

    plot(
      all_scores$PC1,
      all_scores$PC2,
      col = class_colors,
      pch = pch_values,
      xlab = "PC1 score",
      ylab = "PC2 score",
      main = "Leakage-free PCA: training fit + validation projection"
    )

    legend(
      "topright",
      legend = levels(classes),
      col = seq_len(nlevels(classes)),
      pch = 16,
      bty = "n",
      cex = 0.8
    )

    legend(
      "bottomright",
      legend = c("Training", "Validation"),
      pch = c(16, 1),
      bty = "n",
      cex = 0.8
    )

    dev.off()
  }

  png(
    file.path(config_dir, "PCA_SPE_Diagnostic_Repeat001.png"),
    width = 1800,
    height = 1100,
    res = 180
  )

  plot(
    seq_len(nrow(diagnostics)),
    diagnostics$SPE,
    pch = ifelse(
      diagnostics$Partition == "Training",
      16,
      1
    ),
    xlab = "Observations",
    ylab = "Squared Prediction Error (SPE)",
    main = "PCA SPE diagnostic"
  )

  abline(h = lim$SPE95, lty = 2)
  abline(h = lim$SPE99, lty = 3)

  legend(
    "topright",
    legend = c("95% training limit", "99% training limit"),
    lty = c(2, 3),
    bty = "n"
  )

  dev.off()

  png(
    file.path(config_dir, "PCA_T2_Diagnostic_Repeat001.png"),
    width = 1800,
    height = 1100,
    res = 180
  )

  plot(
    seq_len(nrow(diagnostics)),
    diagnostics$T2,
    pch = ifelse(
      diagnostics$Partition == "Training",
      16,
      1
    ),
    xlab = "Observations",
    ylab = expression(Hotelling~T^2),
    main = expression(PCA~Hotelling~T^2~diagnostic)
  )

  abline(h = lim$T2_95, lty = 2)
  abline(h = lim$T2_99, lty = 3)

  legend(
    "topright",
    legend = c("95% training limit", "99% training limit"),
    lty = c(2, 3),
    bty = "n"
  )

  dev.off()

  invisible(NULL)
}


# =============================================================================
# 13. CONFUSION MATRIX ACCUMULATION
# =============================================================================

initialize_cm_accumulator <- function(levels_class) {

  n <- length(levels_class)

  list(
    sum = matrix(
      0,
      nrow = n,
      ncol = n,
      dimnames = list(
        True = levels_class,
        Predicted = levels_class
      )
    ),
    sumsq = matrix(
      0,
      nrow = n,
      ncol = n,
      dimnames = list(
        True = levels_class,
        Predicted = levels_class
      )
    )
  )
}


update_cm_accumulator <- function(acc, cm) {
  acc$sum <- acc$sum + cm
  acc$sumsq <- acc$sumsq + cm ^ 2
  acc
}


finalize_cm_accumulator <- function(acc, n_repeats) {

  mean_cm <- acc$sum / n_repeats

  if (n_repeats > 1) {

    var_cm <- (
      acc$sumsq -
        (acc$sum ^ 2) / n_repeats
    ) / (n_repeats - 1)

    var_cm[var_cm < 0 & abs(var_cm) < 1e-12] <- 0

    sd_cm <- sqrt(var_cm)

  } else {

    sd_cm <- matrix(
      NA_real_,
      nrow = nrow(mean_cm),
      ncol = ncol(mean_cm),
      dimnames = dimnames(mean_cm)
    )
  }

  list(
    mean = mean_cm,
    sd = sd_cm
  )
}


cm_to_data_frame <- function(cm) {

  out <- as.data.frame.matrix(cm)
  out <- cbind(
    True_Class = rownames(out),
    out
  )

  rownames(out) <- NULL

  out
}


# =============================================================================
# 14. SVM SETTINGS
# =============================================================================

choose_kernel <- function() {

  choices <- c(
    "Polynomial kernel (polydot) - original manuscript",
    "Radial basis function kernel (rbfdot)",
    "Linear kernel (vanilladot)"
  )

  opt <- ask_menu(
    "STEP 6 - Select SVM kernel",
    choices,
    default = 1
  )

  c(
    "polydot",
    "rbfdot",
    "vanilladot"
  )[opt]
}


choose_tuning_mode <- function() {

  choices <- c(
    "Fixed hyperparameters (C = 100; original manuscript configuration)",
    "Grouped inner cross-validation within training data"
  )

  opt <- ask_menu(
    "STEP 7 - Hyperparameter strategy",
    choices,
    default = 1
  )

  if (opt == 1) {
    "fixed"
  } else {
    "inner_cv"
  }
}


# =============================================================================
# 15. FIT FINAL FULL-DATA MODEL
# =============================================================================

fit_final_model <- function(
  X,
  meta,
  pca_mode,
  variance_threshold,
  fixed_ncomp,
  kernel_name,
  tuning_mode
) {

  train_sd <- apply(X, 2, sd)
  keep_vars <- is.finite(train_sd) & train_sd > 0

  X_use <- X[, keep_vars, drop = FALSE]

  pca <- prcomp(
    X_use,
    center = TRUE,
    scale. = TRUE,
    retx = TRUE
  )

  var_prop <- pca$sdev ^ 2 / sum(pca$sdev ^ 2)
  cum_var <- cumsum(var_prop)

  if (pca_mode == "variance") {
    ncomp <- which(cum_var >= variance_threshold)[1]
  } else {
    ncomp <- fixed_ncomp
  }

  ncomp <- max(
    1,
    min(ncomp, ncol(pca$x))
  )

  scores <- pca$x[, seq_len(ncomp), drop = FALSE]
  colnames(scores) <- paste0("PC", seq_len(ncomp))

  weights <- if (USE_CLASS_WEIGHTS) {
    calculate_class_weights(meta$Class)
  } else {
    NULL
  }

  if (tuning_mode == "fixed") {

    best <- data.frame(
      C = DEFAULT_C,
      Sigma = NA_real_,
      Degree = NA_real_,
      Scale = NA_real_,
      Offset = NA_real_
    )

  } else {

    tuning <- tune_svm_grouped_inner_cv(
      X_train = X,
      meta_train = meta,
      kernel_name = kernel_name,
      positive_class = NA_character_,
      seed = MASTER_SEED + 999999
    )

    best <- tuning$best
  }

  svm <- fit_ksvm_model(
    X = scores,
    y = meta$Class,
    kernel_name = kernel_name,
    C_value = best$C,
    class_weights = weights,
    sigma = best$Sigma,
    degree = best$Degree,
    scale_value = best$Scale,
    offset = best$Offset,
    prob_model = TRUE
  )

  list(
    pca = pca,
    ncomp = ncomp,
    keep_vars = keep_vars,
    svm = svm,
    class_levels = levels(meta$Class),
    class_weights = weights,
    kernel = kernel_name,
    tuning_mode = tuning_mode,
    hyperparameters = best,
    spectral_variable_names = colnames(X),
    retained_variable_names = colnames(X)[keep_vars],
    pca_variance = var_prop,
    pca_cumulative_variance = cum_var
  )
}


# =============================================================================
# 16. ONE COMPLETE CONFIGURATION
# =============================================================================

run_configuration <- function(
  dataset_key,
  spectral_obj,
  meta,
  stage_option,
  scenario_name,
  train_fraction,
  n_repeats,
  pca_mode,
  variance_threshold,
  fixed_ncomp,
  kernel_name,
  tuning_mode
) {

  scenario <- build_scenario(
    meta = meta,
    X = spectral_obj$X,
    stage_option = stage_option,
    scenario_name = scenario_name
  )

  m <- scenario$meta
  X <- scenario$X
  positive_class <- scenario$positive_class

  class_levels <- levels(m$Class)

  partition_label <- paste0(
    round(train_fraction * 100),
    "_",
    round((1 - train_fraction) * 100)
  )

  config_id <- paste(
    dataset_key,
    stage_option,
    scenario_name,
    partition_label,
    kernel_name,
    tuning_mode,
    sep = "__"
  )

  config_dir <- file.path(
    OUTPUT_ROOT,
    sanitize_filename(config_id)
  )

  dir.create(
    config_dir,
    recursive = TRUE,
    showWarnings = FALSE
  )

  cat("\n")
  cat("--------------------------------------------------------------------------\n")
  cat("CONFIGURATION\n")
  cat("--------------------------------------------------------------------------\n")
  cat("Preprocessing :", dataset_key, "\n")
  cat("Stage         :", stage_option, "\n")
  cat("Scenario      :", scenario_name, "\n")
  cat("Partition     :", partition_label, "\n")
  cat("Kernel        :", kernel_name, "\n")
  cat("Tuning        :", tuning_mode, "\n")
  cat("Observations  :", nrow(m), "\n")
  cat("Bio. samples  :", length(unique(m$Sample_ID)), "\n")
  cat("Classes       :", paste(class_levels, collapse = " | "), "\n")
  cat("Repeats       :", n_repeats, "\n")

  # ---------------------------------------------------------------------------
  # Class distributions
  # ---------------------------------------------------------------------------

  obs_dist <- as.data.frame(table(m$Class))
  names(obs_dist) <- c("Class", "Observation_Count")

  bio_df <- unique(
    m[, c("Sample_ID", "Class"), drop = FALSE]
  )

  bio_dist <- as.data.frame(table(bio_df$Class))
  names(bio_dist) <- c("Class", "Biological_Sample_Count")

  class_distribution <- merge(
    obs_dist,
    bio_dist,
    by = "Class",
    all = TRUE
  )

  safe_write_csv(
    class_distribution,
    file.path(config_dir, "Class_Distribution.csv")
  )

  # ---------------------------------------------------------------------------
  # Repeated holdout
  # ---------------------------------------------------------------------------

  iteration_results <- vector(
    "list",
    n_repeats
  )

  cm_train_acc <- initialize_cm_accumulator(class_levels)
  cm_valid_acc <- initialize_cm_accumulator(class_levels)

  for (i in seq_len(n_repeats)) {

    split_seed <- MASTER_SEED + i

    sp <- grouped_stratified_split(
      meta = m,
      train_fraction = train_fraction,
      seed = split_seed
    )

    train_idx <- sp$train
    valid_idx <- sp$valid

    X_train <- X[train_idx, , drop = FALSE]
    X_valid <- X[valid_idx, , drop = FALSE]

    meta_train <- m[train_idx, , drop = FALSE]
    meta_valid <- m[valid_idx, , drop = FALSE]

    # -------------------------------------------------------------------------
    # LEAKAGE-FREE PCA
    # -------------------------------------------------------------------------

    pca_fit <- fit_training_pca(
      X_train = X_train,
      X_valid = X_valid,
      pca_mode = pca_mode,
      variance_threshold = variance_threshold,
      fixed_ncomp = fixed_ncomp
    )

    save_first_iteration_diagnostics(
      config_dir = config_dir,
      iteration = i,
      meta_train = meta_train,
      meta_valid = meta_valid,
      pca_fit = pca_fit,
      wavenumbers = spectral_obj$wavenumbers
    )

    # -------------------------------------------------------------------------
    # Training-only class weights
    # -------------------------------------------------------------------------

    class_weights <- if (USE_CLASS_WEIGHTS) {
      calculate_class_weights(meta_train$Class)
    } else {
      NULL
    }

    # -------------------------------------------------------------------------
    # Hyperparameters
    # -------------------------------------------------------------------------

    tuning_score <- NA_real_
    inner_cv_folds_used <- NA_integer_

    if (tuning_mode == "fixed") {

      best <- data.frame(
        C = DEFAULT_C,
        Sigma = NA_real_,
        Degree = NA_real_,
        Scale = NA_real_,
        Offset = NA_real_,
        InnerCV_BalancedAccuracy = NA_real_
      )

    } else {

      tuning <- tune_svm_grouped_inner_cv(
        X_train = X_train,
        meta_train = meta_train,
        kernel_name = kernel_name,
        positive_class = positive_class,
        seed = MASTER_SEED + 50000 + i
      )

      best <- tuning$best
      tuning_score <- best$InnerCV_BalancedAccuracy
      inner_cv_folds_used <- tuning$folds

      if (i == 1) {
        safe_write_csv(
          tuning$grid,
          file.path(
            config_dir,
            "SVM_HyperparameterGrid_Repeat001.csv"
          )
        )
      }
    }

    # -------------------------------------------------------------------------
    # SVM
    # -------------------------------------------------------------------------

    set.seed(MASTER_SEED + 100000 + i)

    svm <- fit_ksvm_model(
      X = pca_fit$train_scores,
      y = meta_train$Class,
      kernel_name = kernel_name,
      C_value = best$C,
      class_weights = class_weights,
      sigma = best$Sigma,
      degree = best$Degree,
      scale_value = best$Scale,
      offset = best$Offset,
      prob_model = TRUE
    )

    pred_train <- predict(
      svm,
      as.matrix(pca_fit$train_scores),
      type = "response"
    )

    pred_valid <- predict(
      svm,
      as.matrix(pca_fit$valid_scores),
      type = "response"
    )

    pred_train <- factor(
      pred_train,
      levels = class_levels
    )

    pred_valid <- factor(
      pred_valid,
      levels = class_levels
    )

    prob_train <- safe_predict_probabilities(
      svm,
      pca_fit$train_scores,
      class_levels
    )

    prob_valid <- safe_predict_probabilities(
      svm,
      pca_fit$valid_scores,
      class_levels
    )

    met_train <- calculate_metrics(
      y_true = meta_train$Class,
      y_pred = pred_train,
      prob_matrix = prob_train,
      positive_class = positive_class
    )

    met_valid <- calculate_metrics(
      y_true = meta_valid$Class,
      y_pred = pred_valid,
      prob_matrix = prob_valid,
      positive_class = positive_class
    )

    cm_train_acc <- update_cm_accumulator(
      cm_train_acc,
      met_train$confusion
    )

    cm_valid_acc <- update_cm_accumulator(
      cm_valid_acc,
      met_valid$confusion
    )

    iteration_results[[i]] <- data.frame(
      Iteration = i,
      N_Training_Observations = length(train_idx),
      N_Validation_Observations = length(valid_idx),
      N_Training_BiologicalSamples = length(unique(meta_train$Sample_ID)),
      N_Validation_BiologicalSamples = length(unique(meta_valid$Sample_ID)),

      PCA_NComp = pca_fit$ncomp,
      PCA_CumulativeVariance = pca_fit$cum_var[pca_fit$ncomp],

      SVM_Kernel = kernel_name,
      SVM_Tuning = tuning_mode,
      SVM_C = best$C,
      SVM_Sigma = best$Sigma,
      SVM_Degree = best$Degree,
      SVM_Scale = best$Scale,
      SVM_Offset = best$Offset,
      InnerCV_Folds = inner_cv_folds_used,
      InnerCV_BalancedAccuracy = tuning_score,

      Train_Accuracy = met_train$Accuracy,
      Train_BalancedAccuracy = met_train$BalancedAccuracy,
      Train_Kappa = met_train$Kappa,
      Train_Sensitivity = met_train$Sensitivity,
      Train_Specificity = met_train$Specificity,
      Train_Precision = met_train$Precision,
      Train_Recall = met_train$Recall,
      Train_F1 = met_train$F1,
      Train_AUC = met_train$AUC,
      Train_MCC = met_train$MCC,

      Validation_Accuracy = met_valid$Accuracy,
      Validation_BalancedAccuracy = met_valid$BalancedAccuracy,
      Validation_Kappa = met_valid$Kappa,
      Validation_Sensitivity = met_valid$Sensitivity,
      Validation_Specificity = met_valid$Specificity,
      Validation_Precision = met_valid$Precision,
      Validation_Recall = met_valid$Recall,
      Validation_F1 = met_valid$F1,
      Validation_AUC = met_valid$AUC,
      Validation_MCC = met_valid$MCC,

      Accuracy_Gap = met_train$Accuracy - met_valid$Accuracy,

      stringsAsFactors = FALSE
    )

    if (i == 1) {

      # Class weights
      if (!is.null(class_weights)) {
        weights_df <- data.frame(
          Class = names(class_weights),
          Weight = unlist(class_weights),
          stringsAsFactors = FALSE
        )

        safe_write_csv(
          weights_df,
          file.path(config_dir, "SVM_ClassWeights_Repeat001.csv")
        )
      }

      # First-repeat predictions
      first_train_predictions <- data.frame(
        Partition = "Training",
        Sample_ID = meta_train$Sample_ID,
        Observation_ID = meta_train$Observation_ID,
        Stage = meta_train$Stage,
        True_Class = as.character(meta_train$Class),
        Predicted_Class = as.character(pred_train),
        stringsAsFactors = FALSE
      )

      first_valid_predictions <- data.frame(
        Partition = "Validation",
        Sample_ID = meta_valid$Sample_ID,
        Observation_ID = meta_valid$Observation_ID,
        Stage = meta_valid$Stage,
        True_Class = as.character(meta_valid$Class),
        Predicted_Class = as.character(pred_valid),
        stringsAsFactors = FALSE
      )

      safe_write_csv(
        rbind(
          first_train_predictions,
          first_valid_predictions
        ),
        file.path(config_dir, "Predictions_Repeat001.csv")
      )
    }

    if (
      i == 1 ||
      i %% 50 == 0 ||
      i == n_repeats
    ) {

      cat(
        sprintf(
          "\r  Repeat %d/%d | Validation Acc = %.3f | Kappa = %.3f | PCs = %d | C = %g",
          i,
          n_repeats,
          met_valid$Accuracy,
          met_valid$Kappa,
          pca_fit$ncomp,
          best$C
        )
      )

      flush.console()
    }
  }

  cat("\n")

  iteration_df <- do.call(
    rbind,
    iteration_results
  )

  safe_write_csv(
    iteration_df,
    file.path(config_dir, "Iteration_Metrics.csv")
  )

  # ---------------------------------------------------------------------------
  # Confusion matrices
  # ---------------------------------------------------------------------------

  cm_train_final <- finalize_cm_accumulator(
    cm_train_acc,
    n_repeats
  )

  cm_valid_final <- finalize_cm_accumulator(
    cm_valid_acc,
    n_repeats
  )

  safe_write_csv(
    cm_to_data_frame(cm_train_final$mean),
    file.path(config_dir, "Confusion_Training_Mean.csv")
  )

  safe_write_csv(
    cm_to_data_frame(cm_train_final$sd),
    file.path(config_dir, "Confusion_Training_SD.csv")
  )

  safe_write_csv(
    cm_to_data_frame(cm_valid_final$mean),
    file.path(config_dir, "Confusion_Validation_Mean.csv")
  )

  safe_write_csv(
    cm_to_data_frame(cm_valid_final$sd),
    file.path(config_dir, "Confusion_Validation_SD.csv")
  )

  # ---------------------------------------------------------------------------
  # Metrics summary
  # ---------------------------------------------------------------------------

  numeric_cols <- names(iteration_df)[
    vapply(iteration_df, is.numeric, logical(1))
  ]

  summary_metrics <- do.call(
    rbind,
    lapply(
      numeric_cols,
      function(v) {
        data.frame(
          Metric = v,
          Mean = safe_mean(iteration_df[[v]]),
          SD = safe_sd(iteration_df[[v]]),
          stringsAsFactors = FALSE
        )
      }
    )
  )

  safe_write_csv(
    summary_metrics,
    file.path(config_dir, "Metrics_Summary.csv")
  )

  # ---------------------------------------------------------------------------
  # Final full-data model
  # ---------------------------------------------------------------------------

  final_model <- fit_final_model(
    X = X,
    meta = m,
    pca_mode = pca_mode,
    variance_threshold = variance_threshold,
    fixed_ncomp = fixed_ncomp,
    kernel_name = kernel_name,
    tuning_mode = tuning_mode
  )

  saveRDS(
    final_model,
    file = file.path(config_dir, "Final_PCA_SVM_Model.rds")
  )

  final_loadings <- as.data.frame(
    final_model$pca$rotation[
      ,
      seq_len(final_model$ncomp),
      drop = FALSE
    ],
    check.names = FALSE
  )

  final_loadings <- cbind(
    Wavenumber = spectral_obj$wavenumbers[final_model$keep_vars],
    final_loadings
  )

  safe_write_csv(
    final_loadings,
    file.path(config_dir, "Final_PCA_Loadings.csv")
  )

  final_var <- data.frame(
    PC = paste0("PC", seq_along(final_model$pca_variance)),
    Variance = final_model$pca_variance,
    CumulativeVariance = final_model$pca_cumulative_variance
  )

  safe_write_csv(
    final_var,
    file.path(config_dir, "Final_PCA_ExplainedVariance.csv")
  )

  safe_write_csv(
    final_model$hyperparameters,
    file.path(config_dir, "Final_SVM_Hyperparameters.csv")
  )

  # ---------------------------------------------------------------------------
  # One-line checkpoint
  # ---------------------------------------------------------------------------

  get_mean <- function(col) safe_mean(iteration_df[[col]])
  get_sd <- function(col) safe_sd(iteration_df[[col]])

  class_distribution_text <- paste(
    paste0(
      class_distribution$Class,
      "=",
      class_distribution$Biological_Sample_Count
    ),
    collapse = ";"
  )

  summary_row <- data.frame(
    Config_ID = config_id,
    Preprocessing = dataset_key,
    Stage = stage_option,
    Scenario = scenario_name,
    Train_Fraction = train_fraction,
    Validation_Fraction = 1 - train_fraction,
    N_Repeats = n_repeats,
    N_Observations = nrow(m),
    N_Biological_Samples = length(unique(m$Sample_ID)),
    Biological_Class_Distribution = class_distribution_text,

    PCA_Mode = pca_mode,
    PCA_TargetVariance = ifelse(
      pca_mode == "variance",
      variance_threshold,
      NA_real_
    ),
    PCA_FixedNComp = ifelse(
      pca_mode == "fixed",
      fixed_ncomp,
      NA_real_
    ),
    PCA_NComp_Mean = get_mean("PCA_NComp"),
    PCA_NComp_SD = get_sd("PCA_NComp"),
    PCA_CumulativeVariance_Mean = get_mean("PCA_CumulativeVariance"),

    SVM_Kernel = kernel_name,
    SVM_Tuning = tuning_mode,
    SVM_ClassWeights = USE_CLASS_WEIGHTS,

    SVM_C_Mean = get_mean("SVM_C"),
    SVM_Sigma_Mean = get_mean("SVM_Sigma"),
    SVM_Degree_Mean = get_mean("SVM_Degree"),
    SVM_Scale_Mean = get_mean("SVM_Scale"),
    SVM_Offset_Mean = get_mean("SVM_Offset"),

    Train_Accuracy_Mean = get_mean("Train_Accuracy"),
    Train_Accuracy_SD = get_sd("Train_Accuracy"),
    Train_Kappa_Mean = get_mean("Train_Kappa"),
    Train_Kappa_SD = get_sd("Train_Kappa"),
    Train_Sensitivity_Mean = get_mean("Train_Sensitivity"),
    Train_Sensitivity_SD = get_sd("Train_Sensitivity"),
    Train_Specificity_Mean = get_mean("Train_Specificity"),
    Train_Specificity_SD = get_sd("Train_Specificity"),
    Train_F1_Mean = get_mean("Train_F1"),
    Train_F1_SD = get_sd("Train_F1"),
    Train_AUC_Mean = get_mean("Train_AUC"),
    Train_AUC_SD = get_sd("Train_AUC"),
    Train_MCC_Mean = get_mean("Train_MCC"),
    Train_MCC_SD = get_sd("Train_MCC"),

    Validation_Accuracy_Mean = get_mean("Validation_Accuracy"),
    Validation_Accuracy_SD = get_sd("Validation_Accuracy"),
    Validation_BalancedAccuracy_Mean = get_mean("Validation_BalancedAccuracy"),
    Validation_BalancedAccuracy_SD = get_sd("Validation_BalancedAccuracy"),
    Validation_Kappa_Mean = get_mean("Validation_Kappa"),
    Validation_Kappa_SD = get_sd("Validation_Kappa"),
    Validation_Sensitivity_Mean = get_mean("Validation_Sensitivity"),
    Validation_Sensitivity_SD = get_sd("Validation_Sensitivity"),
    Validation_Specificity_Mean = get_mean("Validation_Specificity"),
    Validation_Specificity_SD = get_sd("Validation_Specificity"),
    Validation_Precision_Mean = get_mean("Validation_Precision"),
    Validation_Precision_SD = get_sd("Validation_Precision"),
    Validation_F1_Mean = get_mean("Validation_F1"),
    Validation_F1_SD = get_sd("Validation_F1"),
    Validation_AUC_Mean = get_mean("Validation_AUC"),
    Validation_AUC_SD = get_sd("Validation_AUC"),
    Validation_MCC_Mean = get_mean("Validation_MCC"),
    Validation_MCC_SD = get_sd("Validation_MCC"),
    Accuracy_Gap_Mean = get_mean("Accuracy_Gap"),
    Accuracy_Gap_SD = get_sd("Accuracy_Gap"),

    stringsAsFactors = FALSE
  )

  summary_row
}


# =============================================================================
# 17. CHECKPOINTS
# =============================================================================

summary_file_path <- function() {
  file.path(
    OUTPUT_ROOT,
    "Model_Summary.csv"
  )
}


load_existing_summary <- function() {

  f <- summary_file_path()

  if (file.exists(f)) {
    read.csv(
      f,
      stringsAsFactors = FALSE,
      check.names = FALSE
    )
  } else {
    NULL
  }
}


append_checkpoint <- function(summary_row) {

  f <- summary_file_path()

  if (!file.exists(f)) {

    safe_write_csv(
      summary_row,
      f
    )

  } else {

    old <- read.csv(
      f,
      stringsAsFactors = FALSE,
      check.names = FALSE
    )

    old <- old[
      old$Config_ID != summary_row$Config_ID,
      ,
      drop = FALSE
    ]

    all_cols <- union(
      names(old),
      names(summary_row)
    )

    for (nm in setdiff(all_cols, names(old))) {
      old[[nm]] <- NA
    }

    for (nm in setdiff(all_cols, names(summary_row))) {
      summary_row[[nm]] <- NA
    }

    old <- old[, all_cols, drop = FALSE]
    summary_row <- summary_row[, all_cols, drop = FALSE]

    safe_write_csv(
      rbind(
        old,
        summary_row
      ),
      f
    )
  }
}


is_completed <- function(config_id) {

  if (!SKIP_COMPLETED_CONFIGURATIONS) {
    return(FALSE)
  }

  existing <- load_existing_summary()

  if (
    is.null(existing) ||
    !"Config_ID" %in% names(existing)
  ) {
    return(FALSE)
  }

  config_id %in% existing$Config_ID
}


# =============================================================================
# 18. USER MENUS
# =============================================================================

choose_preprocessing <- function() {

  choices <- c(
    "Raw spectrum",
    "Baseline-corrected",
    "Standard Normal Variate (SNV)",
    "Multiplicative Scatter Correction (MSC)",
    "First derivative (D1)",
    "Second derivative (D2)",
    "ALL preprocessing approaches"
  )

  opt <- ask_menu(
    "STEP 1 - Select spectral preprocessing approach",
    choices,
    default = 1
  )

  if (opt == 7) {
    names(DATASETS)
  } else {
    names(DATASETS)[opt]
  }
}


choose_stage <- function() {

  choices <- c(
    "Green only",
    "Roasted only",
    "Green + Roasted together",
    "ALL stage configurations"
  )

  opt <- ask_menu(
    "STEP 2 - Select coffee processing stage",
    choices,
    default = 1
  )

  if (opt == 4) {
    c("Green", "Roasted", "Both")
  } else {
    c("Green", "Roasted", "Both")[opt]
  }
}


choose_classification_scenarios <- function() {

  choices <- c(
    "Binary: Defect-free vs ALL defects pooled",
    "Binary: Defect-free vs ONE selected defect",
    "Binary: Defect-free vs EACH defect (5 models)",
    "Multiclass: Defect-free + 5 individual defect categories",
    "ALL classification scenarios"
  )

  opt <- ask_menu(
    "STEP 3 - Select classification objective",
    choices,
    default = 1
  )

  pairwise_all <- paste0(
    "Pairwise_",
    gsub(" ", "_", DEFECT_TYPES_ONLY)
  )

  if (opt == 1) {
    return("Binary_AllDefects")
  }

  if (opt == 2) {

    defect_opt <- ask_menu(
      "Select the defect category",
      DEFECT_TYPES_ONLY,
      default = 1
    )

    return(
      paste0(
        "Pairwise_",
        gsub(
          " ",
          "_",
          DEFECT_TYPES_ONLY[defect_opt]
        )
      )
    )
  }

  if (opt == 3) {
    return(pairwise_all)
  }

  if (opt == 4) {
    return("Multiclass_6Classes")
  }

  c(
    "Binary_AllDefects",
    pairwise_all,
    "Multiclass_6Classes"
  )
}


choose_partitions <- function() {

  choices <- c(
    "70% training / 30% validation",
    "75% training / 25% validation",
    "80% training / 20% validation",
    "ALL three partitions"
  )

  opt <- ask_menu(
    "STEP 4 - Select grouped repeated-holdout partition",
    choices,
    default = 2
  )

  fractions <- c(
    0.70,
    0.75,
    0.80
  )

  if (opt == 4) {
    fractions
  } else {
    fractions[opt]
  }
}


choose_pca_settings <- function() {

  choices <- c(
    "Automatic number of PCs based on cumulative explained variance",
    "Fixed number of PCs"
  )

  opt <- ask_menu(
    "STEP 5 - Select PCA dimensionality rule",
    choices,
    default = 1
  )

  if (opt == 1) {

    threshold <- ask_numeric(
      "Cumulative explained variance threshold (0-1)",
      default = PCA_VARIANCE_THRESHOLD_DEFAULT,
      min_value = 0.50,
      max_value = 0.9999
    )

    list(
      mode = "variance",
      threshold = threshold,
      fixed_ncomp = NULL
    )

  } else {

    fixed <- ask_numeric(
      "Fixed number of principal components",
      default = 10,
      min_value = 1
    )

    list(
      mode = "fixed",
      threshold = NA_real_,
      fixed_ncomp = as.integer(fixed)
    )
  }
}


# =============================================================================
# 19. MAIN
# =============================================================================

main <- function() {

  cat("\n")
  cat("==========================================================================\n")
  cat(" ADVANCED PCA + SUPPORT VECTOR MACHINE MODELING PIPELINE\n")
  cat(" Coffee defect classification | leakage-free grouped validation\n")
  cat("==========================================================================\n")

  dir.create(
    OUTPUT_ROOT,
    recursive = TRUE,
    showWarnings = FALSE
  )

  write_session_info(OUTPUT_ROOT)

  meta <- read_sample_metadata()

  traceability_cols <- intersect(
    c(
      "Sample_ID",
      "Coffee_Lot_ID",
      "Observation_ID",
      "V1",
      "Process",
      "Defect_Status",
      "Defect_Category",
      "Stage",
      "Within_Category_ID",
      "Technical_Replicates_Averaged",
      "Municipality",
      "Latitude",
      "Longitude",
      "Altitude_masl",
      "Rainfall_mm"
    ),
    names(meta)
  )

  safe_write_csv(
    meta[, traceability_cols, drop = FALSE],
    file.path(
      OUTPUT_ROOT,
      "Sample_Traceability_Map.csv"
    )
  )

  cat("\nDataset metadata detected:\n")
  cat("  Spectral observations :", nrow(meta), "\n")
  cat("  Independent coffee lots:", length(unique(meta$Sample_ID)), "\n")
  cat("  Green observations    :", sum(meta$Stage == "Green"), "\n")
  cat("  Roasted observations  :", sum(meta$Stage == "Roasted"), "\n")
  cat("\nDefect-category counts by stage:\n")
  print(
    table(
      meta$Defect_Category,
      meta$Stage
    )
  )

  preprocessing_options <- choose_preprocessing()
  stage_options <- choose_stage()
  scenario_options <- choose_classification_scenarios()
  train_fractions <- choose_partitions()
  pca_settings <- choose_pca_settings()
  kernel_name <- choose_kernel()
  tuning_mode <- choose_tuning_mode()

  n_repeats <- as.integer(
    ask_numeric(
      "STEP 8 - Number of repeated grouped holdout iterations",
      default = N_REPEATS_DEFAULT,
      min_value = 1
    )
  )

  total_configs <- (
    length(preprocessing_options) *
      length(stage_options) *
      length(scenario_options) *
      length(train_fractions)
  )

  total_outer_fits <- total_configs * n_repeats

  cat("\n")
  cat("==========================================================================\n")
  cat(" RUN PLAN\n")
  cat("==========================================================================\n")
  cat("Preprocessing approaches :", length(preprocessing_options), "\n")
  cat("Stage configurations     :", length(stage_options), "\n")
  cat("Classification scenarios:", length(scenario_options), "\n")
  cat("Partitions               :", length(train_fractions), "\n")
  cat("Kernel                   :", kernel_name, "\n")
  cat("Hyperparameter strategy  :", tuning_mode, "\n")
  cat("Total configurations     :", total_configs, "\n")
  cat("Outer SVM fits           :", format(total_outer_fits, big.mark = ","), "\n")
  cat("==========================================================================\n")

  if (
    tuning_mode == "inner_cv" &&
    total_outer_fits > 5000
  ) {

    cat(
      "\nWARNING: Nested/grouped inner CV inside thousands of repeated holdouts ",
      "is computationally expensive.\n",
      "For exploratory runs, use 50-200 outer repeats first.\n",
      sep = ""
    )
  }

  if (total_outer_fits > 50000) {

    cat(
      "\nWARNING: This is a very large batch.\n",
      "Consider testing with fewer repeats first.\n",
      sep = ""
    )

    confirmation <- toupper(
      trimws(
        readline(
          "Type YES to continue, or anything else to stop: "
        )
      )
    )

    if (confirmation != "YES") {
      stop("\nRun stopped by user before model fitting.")
    }
  }

  capture.output(
    {
      cat("MASTER_SEED =", MASTER_SEED, "\n")
      cat("N_REPEATS =", n_repeats, "\n")
      cat("PREPROCESSING =", paste(preprocessing_options, collapse = ", "), "\n")
      cat("STAGES =", paste(stage_options, collapse = ", "), "\n")
      cat("SCENARIOS =", paste(scenario_options, collapse = ", "), "\n")
      cat("TRAIN_FRACTIONS =", paste(train_fractions, collapse = ", "), "\n")
      cat("PCA_MODE =", pca_settings$mode, "\n")
      cat("PCA_THRESHOLD =", pca_settings$threshold, "\n")
      cat("PCA_FIXED_NCOMP =", pca_settings$fixed_ncomp, "\n")
      cat("SVM_KERNEL =", kernel_name, "\n")
      cat("SVM_TUNING_MODE =", tuning_mode, "\n")
      cat("DEFAULT_C =", DEFAULT_C, "\n")
      cat("USE_CLASS_WEIGHTS =", USE_CLASS_WEIGHTS, "\n")
      cat("INNER_CV_FOLDS =", INNER_CV_FOLDS, "\n")
    },
    file = file.path(
      OUTPUT_ROOT,
      "Run_Settings.txt"
    )
  )

  for (dataset_key in preprocessing_options) {

    cat(
      "\nLoading spectral dataset:",
      dataset_key,
      "...\n"
    )

    spectral_obj <- read_spectral_dataset(
      dataset_key,
      meta
    )

    cat(
      "  Predictor variables:",
      ncol(spectral_obj$X),
      "\n"
    )

    for (stage_option in stage_options) {
      for (scenario_name in scenario_options) {
        for (train_fraction in train_fractions) {

          partition_label <- paste0(
            round(train_fraction * 100),
            "_",
            round((1 - train_fraction) * 100)
          )

          config_id <- paste(
            dataset_key,
            stage_option,
            scenario_name,
            partition_label,
            kernel_name,
            tuning_mode,
            sep = "__"
          )

          if (is_completed(config_id)) {

            cat(
              "\nSkipping completed configuration:",
              config_id,
              "\n"
            )

            next
          }

          summary_row <- run_configuration(
            dataset_key = dataset_key,
            spectral_obj = spectral_obj,
            meta = meta,
            stage_option = stage_option,
            scenario_name = scenario_name,
            train_fraction = train_fraction,
            n_repeats = n_repeats,
            pca_mode = pca_settings$mode,
            variance_threshold = ifelse(
              pca_settings$mode == "variance",
              pca_settings$threshold,
              PCA_VARIANCE_THRESHOLD_DEFAULT
            ),
            fixed_ncomp = pca_settings$fixed_ncomp,
            kernel_name = kernel_name,
            tuning_mode = tuning_mode
          )

          append_checkpoint(summary_row)

          cat(
            "Completed and checkpointed:",
            config_id,
            "\n"
          )
        }
      }
    }
  }

  cat("\n")
  cat("==========================================================================\n")
  cat(" ALL REQUESTED MODELS COMPLETED\n")
  cat("==========================================================================\n")
  cat("Results folder :", OUTPUT_ROOT, "\n")
  cat("Main summary   :", summary_file_path(), "\n")
  cat("Session info   :", file.path(OUTPUT_ROOT, "sessionInfo.txt"), "\n")
  cat("Traceability   :", file.path(OUTPUT_ROOT, "Sample_Traceability_Map.csv"), "\n")
  cat("==========================================================================\n")
}


# =============================================================================
# 20. RUN
# =============================================================================

main()
