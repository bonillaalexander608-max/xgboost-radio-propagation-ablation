# Abrir este proyecto como directorio de trabajo en RStudio.
# Editar estas opciones ANTES de ejecutar 01; para otro experimento cambiar id_ejecucion.
archivo_excel <- file.path("datos_entrada", "data _31025.xlsx")
id_ejecucion <- "Ablacion_Orientacion_Geometria_v1"
cfg <- list(version_script = "1.0", bloque_m = 1000, buffer_m = 100,
            prop_bloques_prueba = 0.20, v = 10L, repeats = 5L,
            n_config = 40L, B = 2000L, semilla_split = 123L,
            semilla_folds = 42L, semilla_grid = 2026L,
            semilla_ajuste = 2027L, semilla_boot = 2028L,
            potencia_referencia_dbm = 43, vecinos_knn = 5L,
            # Completar documentalmente: 43 - Level no es una ecuación radioeléctrica completa.
            unidad_distancia = "metros")
paquetes <- c("tidyverse", "tidymodels", "readxl", "sf", "xgboost", "digest")
faltan <- paquetes[!vapply(paquetes, requireNamespace, logical(1), quietly = TRUE)]
if (length(faltan)) stop("Instalar primero: install.packages(c(",
  paste(sprintf('"%s"', faltan), collapse = ", "), "))")
suppressPackageStartupMessages({library(tidyverse); library(tidymodels); library(sf)})
carpeta <- file.path("resultados", id_ejecucion)
for (s in c("datos", "modelos", "tablas", "graficos", "shap"))
  dir.create(file.path(carpeta, s), recursive = TRUE, showWarnings = FALSE)
guardar_csv <- function(x, nombre) readr::write_csv(x, file.path(carpeta, "tablas", nombre))
guardar_plot <- function(x, nombre, ancho = 10, alto = 6) {
  ggplot2::ggsave(file.path(carpeta, "graficos", nombre), x,
                 width = ancho, height = alto, dpi = 300, bg = "white")
}
modelos <- c("base", "orientacion", "geometria", "completo")
etiquetas <- c(base = "Base", orientacion = "Base + orientation",
               geometria = "Base + geometry", completo = "Complete")
# Métricas calculadas sin depender de convenciones implícitas de R².
metricas_vector <- function(y, pred) {
  e <- y - pred
  r2corr <- if (length(y) > 1 && sd(y) > 0 && sd(pred) > 0) cor(y, pred)^2 else NA_real_
  den <- sum((y - mean(y))^2)
  c(rmse = sqrt(mean(e^2)), mae = mean(abs(e)), rsq = r2corr,
    r2_predictivo = if (den > 0) 1 - sum(e^2)/den else NA_real_)
}
# Se registra también R² predictivo, distinto del rsq = cor(y,pred)^2 usado antes.
