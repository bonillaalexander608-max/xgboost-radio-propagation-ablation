# Methodology and confidence intervals

For observations $y_i$ and predictions $\hat y_i$:

$$\operatorname{RMSE}=\sqrt{n^{-1}\sum_i(y_i-\hat y_i)^2},\qquad
\operatorname{MAE}=n^{-1}\sum_i|y_i-\hat y_i|.$$

$$R^2_{\mathrm{corr}}=\operatorname{cor}(y,\hat y)^2,\qquad
R^2_{\mathrm{pred}}=1-\frac{\sum_i(y_i-\hat y_i)^2}{\sum_i(y_i-\bar y)^2}.$$

Squared correlation is the exported `rsq`. Predictive R² can be negative.

## Engineered representations

Let $h_T$ be `Altura Site + ansm sitio`, $h_R$ be `Altura Recep + Height`, and $d$ be `DISTANCIA` in metres. The model uses $\log_{10}(d/1000)$ and BAND as a categorical feature. Geometry adds $\theta=\operatorname{atan2}(h_T-h_R,d)$ in radians and $(h_T-h_R)/d$. Orientation adds separate supplied tilts and $\sin(a\pi/180)$, $\cos(a\pi/180)$ for absolute azimuth $a$ in degrees. The elevation-angle interpretation assumes horizontal distance; the spreadsheet definition remains to be confirmed. Raw azimuth imputation does not respect circular topology and is a limitation when missing.

## Paired block bootstrap

There are $G=11$ held-out blocks. For each of $B=2000$ replicates, sample $G$ block indices uniformly with replacement and concatenate all observations from those blocks, including repeats. Every model receives identical observations and multiplicities in that replicate. Recalculate each metric from the pooled sampled rows: this is not an unweighted average of block-specific metrics.

For reference R and candidate C, improvements are

$$\Delta_{\mathrm{error}}=M_R-M_C,\qquad
\Delta_{R^2}=R_C^2-R_R^2.$$

Positive always favours the candidate. The reported point estimate is calculated on the original test set, not the mean bootstrap improvement. The marginal percentile interval is

$$\mathrm{CI}_{95\%}=[Q_{0.025}(\Delta^*),Q_{0.975}(\Delta^*)].$$

Model-level intervals apply the same quantiles to each model's metric replicates. Invalid R² replicas are omitted and valid counts are exported. Test predictions and fitted models are held fixed: this quantifies conditional test-block uncertainty, not the full training/model-selection process.

The theoretical rationale is cluster resampling: retain within-block dependence while treating blocks as the resampling units. Its adequacy requires representative, sufficiently independent blocks and enough units for approximation. Eleven blocks and possible between-block dependence limit coverage accuracy. A 100 m buffer does not guarantee these conditions. Intervals are exploratory and marginal, without family-wise multiplicity adjustment. An interval including zero is inconclusive, not evidence of equivalence. Comparing separate model intervals is not a substitute for the paired difference interval.

## SHAP

The optional script requests native XGBoost prediction contributions with `predcontrib = TRUE` and `approxcontrib = FALSE`. It verifies that feature contributions plus bias reproduce predictions within 0.01 dB. Global importance is the mean absolute contribution over held-out observations, in target dB units. These are model attribution summaries; correlated or transformed predictors can share attribution. They do not prove causality or predictive improvement.

## Implementation references

- [Grouped resampling](https://rsample.tidymodels.org/reference/group_vfold_cv.html)
- [KNN imputation recipes](https://recipes.tidymodels.org/reference/step_impute_knn.html)
- [Grid tuning](https://tune.tidymodels.org/reference/tune_grid.html)

The formulas describe the supplied implementation. The repository does not claim exact finite-sample coverage for this spatial design.
