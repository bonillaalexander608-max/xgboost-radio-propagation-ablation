# Run from the project root before the analysis.
packages <- c("tidyverse", "tidymodels", "readxl", "sf", "xgboost", "digest")
missing <- packages[!vapply(packages, requireNamespace, logical(1), quietly = TRUE)]
if (length(missing)) install.packages(missing, repos = "https://cloud.r-project.org")
message("Dependencies installed. See reports/reference/sessionInfo.txt for recorded versions.")
