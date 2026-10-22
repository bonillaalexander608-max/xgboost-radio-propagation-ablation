source("00_config.R")
z <- readRDS(file.path(carpeta, "datos", "datos_y_folds.rds"))
if (!identical(cfg,z$cfg)) stop("Configuración distinta. Volver a 01 con otro id_ejecucion.")
entrenamiento <- z$entrenamiento; folds_comparacion <- z$folds_comparacion
base_raw <- c("Altura Site", "ansm sitio", "Altura Recep", "Height", "DISTANCIA", "BAND")
orient_raw <- c("Azimut Site", "Tilt Mec site", "Tilt Elect Site")
# Mismos donantes base para TODOS los modelos. La orientación no imputa variables base.
# Altura Recep es constante conocida y no se usa como donante.
donantes <- setdiff(base_raw,"Altura Recep")
crear_receta <- function(nombre) {
  usa_ori <- nombre %in% c("orientacion", "completo")
  usa_geo <- nombre %in% c("geometria", "completo")
  cols <- c(base_raw, if (usa_ori) orient_raw)
  formula <- reformulate(sprintf("`%s`", cols), response = "Perdida")
  rec <- recipe(formula, data = entrenamiento) %>%
    step_impute_knn(all_numeric_predictors(), neighbors = cfg$vecinos_knn,
                   impute_with = all_of(donantes)) %>%
    step_mutate(Altura_Torre = `Altura Site` + `ansm sitio`,
                Altura_receptor = `Altura Recep` + Height,
                Frecuencia = factor(BAND, levels = c("L2", "L28", "L4")),
                Distancia_km = DISTANCIA/1000)
  if (usa_ori) rec <- rec %>%
    step_mutate(Azimut_cos = cos(`Azimut Site`*pi/180),
                Azimut_sen = sin(`Azimut Site`*pi/180))
  if (usa_geo) rec <- rec %>%
    step_mutate(Angulo_elevacion = atan2(Altura_Torre - Altura_receptor, DISTANCIA),
                Razon_altura_distancia = (Altura_Torre - Altura_receptor)/DISTANCIA)
  rec <- rec %>% step_log(Distancia_km, base = 10) %>% step_rm(all_of(base_raw))
  if (usa_ori) rec <- rec %>% step_rm(`Azimut Site`)
  rec %>% step_dummy(all_nominal_predictors()) %>% step_zv(all_predictors()) %>%
    step_normalize(all_numeric_predictors())
}
xgb_spec <- boost_tree(trees = tune(), min_n = tune(), tree_depth = tune(),
  learn_rate = tune(), loss_reduction = tune(), sample_size = tune()) %>%
  set_engine("xgboost", nthread = 1, verbosity = 0) %>% set_mode("regression")
# Rejilla común, idéntico presupuesto y selección exclusivamente por RMSE de CV.
set.seed(cfg$semilla_grid)
rejilla <- dials::grid_space_filling(
  x = list(
    trees = dials::trees(range = c(500L, 1800L)),
    min_n = dials::min_n(range = c(5L, 30L)),
    tree_depth = dials::tree_depth(range = c(2L, 8L)),
    learn_rate = dials::learn_rate(range = c(-3, -1)),
    loss_reduction = dials::loss_reduction(range = c(-5, 1)),
    sample_size = dials::sample_prop(range = c(0.65, 1))
  ),
  size = cfg$n_config
)
print(rejilla)
write_csv(rejilla, file.path(carpeta,"tablas","05_rejilla_tuning.csv"))
saveRDS(rejilla,file.path(carpeta,"datos","rejilla.rds"))
# Secuencial para no saturar RAM. Los ajustes se guardan al terminar CADA modelo.
# No hay checkpoint de cada fold: interrumpir un modelo obliga a repetir ese modelo.
# Prueba de preparación antes del primer entrenamiento largo.
for (nombre in modelos) {
  r <- prep(crear_receta(nombre), training = analysis(folds_comparacion$splits[[1]]))
  b <- bake(r,new_data = assessment(folds_comparacion$splits[[1]]),all_predictors())
  if (!all(vapply(b,function(x) is.numeric(x) && all(is.finite(x)),logical(1))))
    stop("Preprocesamiento incompleto o valores no finitos: ",nombre)
}
resultados <- list(); mejores <- list(); workflows <- list()
for (nombre in modelos) {
  wf <- workflow() %>% add_recipe(crear_receta(nombre)) %>% add_model(xgb_spec)
  workflows[[nombre]] <- wf
  ruta <- file.path(carpeta,"modelos",paste0("tuning_",nombre,".rds"))
  firma_modelo <- digest::digest(list(z$firma, nombre, rejilla))
  if (file.exists(ruta)) {
    anterior <- readRDS(ruta)
    if (!identical(anterior$firma,firma_modelo)) stop("Checkpoint incompatible: ",ruta)
    resultados[[nombre]] <- anterior$resultado
    message("Se recuperó el tuning completo de ",nombre)
  } else {
    message("Tuning de ",nombre,": ",cfg$v*cfg$repeats," resamples x ",nrow(rejilla)," configuraciones")
    set.seed(cfg$semilla_ajuste)
    resultados[[nombre]] <- tune_grid(wf, resamples = folds_comparacion, grid = rejilla,
      metrics = metric_set(rmse,mae,rsq),
      control = control_grid(save_pred = FALSE, verbose = TRUE, allow_par = FALSE))
    saveRDS(list(firma = firma_modelo, resultado = resultados[[nombre]]),ruta)
  }
  notas <- collect_notes(resultados[[nombre]])
  guardar_csv(notas,paste0("notas_tuning_",nombre,".csv"))
  guardar_csv(collect_metrics(resultados[[nombre]]),paste0("cv_",nombre,".csv"))
  # Impedir selección sobre un candidato con folds fallidos.
  met <- collect_metrics(resultados[[nombre]]) %>% filter(.metric == "rmse")
  if (any(met$n != nrow(folds_comparacion)) || any(!is.finite(met$mean)))
    stop("Hay candidatos con fallos. Revisar notas antes de seleccionar: ",nombre)
  mejores[[nombre]] <- select_best(resultados[[nombre]], metric = "rmse")
}
mejores_tabla <- bind_rows(mejores,.id = "Modelo")
guardar_csv(mejores_tabla,"06_mejores_hiperparametros.csv")
saveRDS(list(workflows = workflows, mejores = mejores, firma = z$firma),
        file.path(carpeta,"modelos","seleccion.rds"))
cv <- imap_dfr(resultados,~collect_metrics(.x) %>% mutate(Modelo = .y))
guardar_csv(cv,"07_resultados_cv.csv")
guardar_plot(cv %>% filter(.metric == "rmse") %>%
  ggplot(aes(tree_depth,mean,color = learn_rate)) + geom_point() +
  facet_wrap(~Modelo) + theme_bw() + labs(x = "Tree depth", y = "Spatial CV RMSE (dB)", color = "Learning rate"),
  "07_tuning_results.png")
print(mejores_tabla)
message("Tuning terminado. Continuar con 03_evaluacion_IC_graficos.R.")
