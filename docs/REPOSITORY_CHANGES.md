# Repository preparation

- The raw workbook is copied byte for byte; its name is standardized to the path in `00_config.R`.
- Preparation now sources `00_config.R` instead of opening `file.choose()`. This also fixes fresh-session execution of step 01 and the runner.
- The latest separately uploaded tuning script is used, including its explicit `dials::grid_space_filling(x = list(...))` call.
- Figure filenames use English; existing figure pixels and all reference numerical outputs are unchanged. Existing feature names/model IDs inside some plots remain the original identifiers.
- New runs use `Ablacion_Orientacion_Geometria_github_v1`; reference exports are under `reports/reference`. Script changes alter execution signatures; original tuning checkpoints are not included or reusable as new-run checkpoints.
- The original scripts bundled in the results ZIP are preserved under `docs/original_export_scripts` for provenance. These archival files include the earlier grid call and are not the runnable entry points.
- No article, R history, personal continuation notes, or fitted-model binaries are included.
- No full R run or tuning was performed during packaging. Four metric definitions were independently recalculated from all exported test predictions, and paired point differences and fold audits were checked. Bootstrap endpoints are preserved from the supplied exports, not regenerated here.
- Dependency versions are recorded in the reference `sessionInfo.txt`. No unverified `renv.lock` is supplied; installing current packages alone does not guarantee identical stochastic results.
