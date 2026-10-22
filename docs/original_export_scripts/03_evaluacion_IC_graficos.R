source("00_config.R")
z <- readRDS(file.path(carpeta,"datos","datos_y_folds.rds"))
s <- readRDS(file.path(carpeta,"modelos","seleccion.rds"))
stopifnot(identical(z$cfg,cfg),identical(s$firma,z$firma))
entrenamiento <- z$entrenamiento; prueba <- z$prueba
predicciones <- list(); ajustes <- list()
for (nombre in modelos) {
  wf <- finalize_workflow(s$workflows[[nombre]],s$mejores[[nombre]])
  set.seed(cfg$semilla_ajuste)
  ajustes[[nombre]] <- fit(wf,data = entrenamiento)
  predicciones[[nombre]] <- prueba %>% select(fila_id,bloque,celda_id,BAND,DISTANCIA,Perdida) %>%
    bind_cols(predict(ajustes[[nombre]],new_data = prueba)) %>%
    mutate(Modelo = nombre, residuo = Perdida - .pred, error_absoluto = abs(residuo))
  saveRDS(ajustes[[nombre]],file.path(carpeta,"modelos",paste0("fit_final_",nombre,".rds")))
}
pred <- bind_rows(predicciones)
stopifnot(all(is.finite(pred$.pred)),!anyDuplicated(pred[c("fila_id","Modelo")]))
guardar_csv(pred,"08_predicciones_prueba.csv")
saveRDS(pred,file.path(carpeta,"datos","predicciones.rds"))
metricas_test <- imap_dfr(predicciones,function(d,nombre) {
  val <- metricas_vector(d$Perdida,d$.pred)
  tibble(Modelo = nombre,.metric = names(val),.estimate = unname(val))
})
guardar_csv(metricas_test,"09_metricas_prueba.csv")
# Bootstrap espacial PAREADO: remuestrear bloques de prueba completos, con reemplazo.
# En cada réplica todos los modelos reciben exactamente las mismas filas y multiplicidades.
# IC percentil 2.5%-97.5%, condicional a los modelos ya ajustados; NO se reentrena aquí.
ancha <- pred %>% select(fila_id,bloque,Perdida,Modelo,.pred) %>%
  pivot_wider(names_from = Modelo,values_from = .pred)
stopifnot(nrow(ancha) == nrow(prueba), !anyNA(ancha))
indices <- split(seq_len(nrow(ancha)),ancha$bloque)
G <- length(indices)
if (G < 2) stop("Se necesitan varios bloques de prueba para bootstrap espacial.")
if (G < 20) message("Pocos bloques de prueba (",G,"): IC aproximados; registrar esta limitación en el informe.")
set.seed(cfg$semilla_boot)
boot <- map_dfr(seq_len(cfg$B),function(b) {
  ib <- unlist(indices[sample.int(G,G,replace = TRUE)],use.names = FALSE)
  map_dfr(modelos,function(nombre) {
    v <- metricas_vector(ancha$Perdida[ib],ancha[[nombre]][ib])
    tibble(replica = b,Modelo = nombre,.metric = names(v),valor = unname(v))
  })
})
saveRDS(boot,file.path(carpeta,"datos","bootstrap_metricas.rds"))
IC_modelos <- boot %>% group_by(Modelo,.metric) %>% summarise(
  replicas_validas = sum(is.finite(valor)),
  IC95_inferior = quantile(valor,.025,na.rm = TRUE),
  IC95_superior = quantile(valor,.975,na.rm = TRUE),.groups = "drop") %>%
  left_join(metricas_test,by = c("Modelo",".metric")) %>% mutate(n_bloques = G)
guardar_csv(IC_modelos,"10_IC95_metricas_por_modelo.csv")
# Positivo = mejora del candidato frente a referencia, para TODAS las métricas.
# RMSE/MAE: referencia - candidato; R²: candidato - referencia.
pares <- tribble(~Referencia,~Candidato,
 "base","orientacion", "base","geometria", "base","completo",
 "orientacion","completo", "geometria","completo", "orientacion","geometria")
dif_boot <- pmap_dfr(pares,function(Referencia,Candidato) {
  a <- boot %>% filter(Modelo == Referencia) %>% select(replica,.metric,ref = valor)
  b <- boot %>% filter(Modelo == Candidato) %>% select(replica,.metric,cand = valor)
  inner_join(a,b,by = c("replica",".metric")) %>% mutate(
    Referencia = Referencia,Candidato = Candidato,
    mejora = if_else(.metric %in% c("rmse","mae"),ref-cand,cand-ref))
})
dif_puntual <- pmap_dfr(pares,function(Referencia,Candidato) {
  a <- metricas_test %>% filter(Modelo == Referencia) %>% select(.metric,ref = .estimate)
  b <- metricas_test %>% filter(Modelo == Candidato) %>% select(.metric,cand = .estimate)
  inner_join(a,b,by = ".metric") %>% mutate(Referencia = Referencia,Candidato = Candidato,
    mejora = if_else(.metric %in% c("rmse","mae"),ref-cand,cand-ref)) %>%
    select(Referencia,Candidato,.metric,mejora)
})
IC_mejora <- dif_boot %>% group_by(Referencia,Candidato,.metric) %>% summarise(
  replicas_validas = sum(is.finite(mejora)),
  IC95_inferior = quantile(mejora,.025,na.rm = TRUE),
  IC95_superior = quantile(mejora,.975,na.rm = TRUE),.groups = "drop") %>%
  left_join(dif_puntual,by = c("Referencia","Candidato",".metric")) %>%
  mutate(n_bloques = G, interpretacion = case_when(
    IC95_inferior > 0 ~ "IC favorece al candidato",
    IC95_superior < 0 ~ "IC favorece a la referencia",
    TRUE ~ "IC incluye cero: resultado inconcluso"))
guardar_csv(IC_mejora,"11_IC95_diferencias_pareadas.csv")
saveRDS(dif_boot,file.path(carpeta,"datos","bootstrap_diferencias.rds"))
# IC marginales exploratorios: no equivalen a seis comparaciones simultáneas al 95%.
# Estadísticos de error por frecuencia y por tramos de distancia: descriptivos.
pred <- pred %>% mutate(Frecuencia = recode(BAND,L2 = "1900 MHz",L28 = "700 MHz",L4 = "2100 MHz"),
  Tramo_distancia = cut(DISTANCIA,breaks = c(15,250,500,1000,1500,2000,3000),
    include.lowest = TRUE,right = FALSE))
por_grupo <- function(d,columnas) {
  d %>% group_by(across(all_of(columnas))) %>% summarise(n = n(),n_bloques = n_distinct(bloque),
    rmse = sqrt(mean(residuo^2)),mae = mean(error_absoluto),sesgo = mean(residuo),
    p50_error_abs = quantile(error_absoluto,.50),p90_error_abs = quantile(error_absoluto,.90),
    p95_error_abs = quantile(error_absoluto,.95),.groups = "drop")
}
err_dist <- por_grupo(pred,c("Modelo","Tramo_distancia"))
err_frec <- por_grupo(pred,c("Modelo","Frecuencia"))
guardar_csv(err_dist,"12_error_por_distancia.csv")
guardar_csv(err_frec,"13_error_por_frecuencia.csv")
guardar_csv(por_grupo(pred,"Modelo"),"14_percentiles_y_sesgo.csv")
# Figuras en inglés para el artículo.
pred <- pred %>% mutate(Modelo = factor(Modelo,levels = modelos,labels = unname(etiquetas)))
tema <- theme_bw(base_size = 11)
guardar_plot(ggplot(pred,aes(Perdida,.pred)) + geom_point(alpha = .15,size = .5) +
  geom_abline(slope = 1,intercept = 0,color = "red") + facet_wrap(~Modelo) + coord_equal() + tema +
  labs(x = "Observed path loss (dB)",y = "Predicted path loss (dB)"),"01_observado_estimado.png")
guardar_plot(ggplot(pred,aes(.pred,residuo)) + geom_point(alpha = .15,size = .5) +
  geom_hline(yintercept = 0,color = "red") + facet_wrap(~Modelo) + tema +
  labs(x = "Predicted path loss (dB)",y = "Residual: observed - predicted (dB)"),"02_residuos_estimados.png")
guardar_plot(ggplot(pred,aes(residuo,color = Modelo)) + geom_density() + tema +
  labs(x = "Residual (dB)",y = "Density",color = "Model"),"03_distribucion_residuos.png")
guardar_plot(ggplot(pred,aes(error_absoluto,color = Modelo)) + stat_ecdf() + tema +
  labs(x = "Absolute error (dB)",y = "Cumulative proportion",color = "Model"),"04_error_acumulado.png")
guardar_plot(ggplot(pred,aes(DISTANCIA,residuo)) + geom_point(alpha = .1,size = .4) +
  geom_hline(yintercept = 0,color = "red") + facet_wrap(~Modelo) + tema +
  labs(x = "Distance (m)",y = "Residual (dB)"),"05_residuos_distancia.png")
guardar_plot(ggplot(err_dist,aes(Tramo_distancia,rmse,color = Modelo,group = Modelo)) +
  geom_line() + geom_point() + tema + theme(axis.text.x = element_text(angle = 35,hjust = 1)) +
  labs(x = "Distance interval (m)",y = "RMSE (dB)",color = "Model"),"06_rmse_distancia.png")
guardar_plot(ggplot(pred,aes(Frecuencia,error_absoluto,fill = Modelo)) +
  geom_boxplot(outlier.shape = NA) + tema +
  labs(x = "Frequency",y = "Absolute error (dB)",fill = "Model"),"08_error_frecuencia.png")
guardar_plot(IC_mejora %>% mutate(Comparacion = paste(Candidato,"vs",Referencia)) %>%
  ggplot(aes(Comparacion,mejora,ymin = IC95_inferior,ymax = IC95_superior)) +
  geom_pointrange() + geom_hline(yintercept = 0,linetype = 2) + coord_flip() +
  facet_wrap(~.metric,scales = "free_x") + tema +
  labs(x = NULL,y = "Paired improvement and marginal 95% CI"),"09_IC_diferencias.png",12,8)
# Diferencia individual de error absoluto frente a Base; positivo favorece al candidato.
errores <- predicciones$base %>% select(fila_id,base_abs = error_absoluto)
pareados <- bind_rows(predicciones[-1]) %>% left_join(errores,by = "fila_id") %>%
  mutate(mejora_error_abs = base_abs-error_absoluto)
guardar_csv(pareados,"15_errores_pareados_base.csv")
guardar_plot(ggplot(pareados,aes(Modelo,mejora_error_abs,fill = Modelo)) +
  geom_boxplot(outlier.shape = NA) + geom_hline(yintercept = 0,linetype = 2) + tema +
  labs(x = "Candidate model",y = "Base absolute error - candidate absolute error (dB)"),"10_errores_pareados.png")
print(metricas_test); print(IC_mejora,width = Inf)
message("Evaluación terminada. No seleccionar nuevas variantes usando los resultados de prueba.")
