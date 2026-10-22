# Ejecutar después de 03. TreeSHAP nativo, exacto respecto al modelo ajustado.
source("00_config.R")
z <- readRDS(file.path(carpeta,"datos","datos_y_folds.rds"))
stopifnot(identical(cfg,z$cfg))
resumenes <- list()
for (nombre in modelos) {
  ajuste <- readRDS(file.path(carpeta,"modelos",paste0("fit_final_",nombre,".rds")))
  rec <- workflows::extract_recipe(ajuste,estimated = TRUE)
  x <- recipes::bake(rec,new_data = z$prueba,all_predictors()) %>% as.matrix()
  motor <- workflows::extract_fit_engine(ajuste)
  contrib <- predict(motor,newdata = x,predcontrib = TRUE,approxcontrib = FALSE)
  if (!is.matrix(contrib) || ncol(contrib) != ncol(x)+1L)
    stop("Formato de SHAP inesperado; revisar versión xgboost.")
  p <- predict(ajuste,new_data = z$prueba)$.pred
  discrepancia <- max(abs(rowSums(contrib)-p))
  if (discrepancia > .01) stop("No se verificó aditividad SHAP: ",nombre)
  valores <- contrib[,seq_len(ncol(x)),drop = FALSE]
  colnames(valores) <- colnames(x)
  imp <- tibble(Modelo = nombre,Variable = colnames(x),
                SHAP_abs_medio_db = colMeans(abs(valores))) %>%
    mutate(porcentaje = 100*SHAP_abs_medio_db/sum(SHAP_abs_medio_db),
           error_max_aditividad_db = discrepancia)
  resumenes[[nombre]] <- imp
  saveRDS(list(fila_id = z$prueba$fila_id,SHAP = valores,
    bias = contrib[,ncol(contrib)],x = x),file.path(carpeta,"shap",paste0("SHAP_",nombre,".rds")))
  g <- imp %>% ggplot(aes(reorder(Variable,SHAP_abs_medio_db),SHAP_abs_medio_db)) +
    geom_col(fill = "steelblue") + coord_flip() + theme_bw() +
    labs(x = NULL,y = "Mean absolute SHAP value (dB)",title = etiquetas[[nombre]])
  ggsave(file.path(carpeta,"shap",paste0("SHAP_importance_",nombre,".png")),g,
         width = 9,height = 6,dpi = 300,bg = "white")
}
readr::write_csv(bind_rows(resumenes),file.path(carpeta,"shap","SHAP_importance_global.csv"))
# SHAP describe atribuciones del modelo: no prueba causalidad ni mejora fuera de muestra.
