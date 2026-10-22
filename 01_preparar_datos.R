source("00_config.R")
if (!file.exists(archivo_excel)) stop("Copiar el Excel original a: ", archivo_excel)
# Este lector usa las posiciones del Excel original de 46 columnas.
# C/D = coordenadas del receptor; E/F NO son esas coordenadas.
cab <- names(readxl::read_excel(archivo_excel, n_max = 0))
if (length(cab) != 46L) stop("El Excel no tiene 46 columnas. Revisar el lector.")
if (!grepl("lon", cab[3], ignore.case = TRUE) ||
    !grepl("lat", cab[4], ignore.case = TRUE))
  stop("Verificar: columna C longitud y D latitud del receptor.")
tipos <- rep("skip", 46)
tipos[c(3, 4, 7:13, 25, 35)] <- "numeric"
tipos[c(2, 14)] <- "text"
data <- readxl::read_excel(archivo_excel, col_types = tipos)
names(data)[1:3] <- c("celda_id", "Longitud", "Latitud")
requeridas <- c("Altura Site", "Azimut Site", "Tilt Mec site", "Tilt Elect Site",
                "DISTANCIA", "Altura Recep", "ansm sitio", "BAND", "Level", "Height")
if (length(setdiff(requeridas, names(data)))) stop("Revisar nombres: ",
  paste(setdiff(requeridas, names(data)), collapse = ", "))
data <- data %>% mutate(fila_id = row_number() + 1L,
                         BAND = toupper(trimws(BAND)),
                         celda_id = na_if(trimws(celda_id), ""))
num <- names(data)[vapply(data, is.numeric, logical(1))]
data <- data %>% mutate(across(all_of(num), ~replace(.x, !is.finite(.x), NA_real_)))
registro <- tibble(paso = "Lectura original", n = nrow(data))
filtrar <- function(d, condicion, descripcion) {
  salida <- d[which(condicion), , drop = FALSE]
  registro <<- bind_rows(registro, tibble(paso = descripcion, n = nrow(salida)))
  salida
}
data <- filtrar(data, !is.na(data$Level) & !is.na(data$DISTANCIA), "Level y distancia disponibles")
data <- filtrar(data, data$DISTANCIA >= 15 & data$DISTANCIA < 3000, "15 <= distancia < 3000 m")
data <- filtrar(data, data$Level > -150, "Level > -150 dBm")
data <- filtrar(data, !is.na(data$Longitud) & !is.na(data$Latitud) &
  abs(data$Longitud) <= 180 & abs(data$Latitud) <= 90, "Coordenadas receptor disponibles y validas")
guardar_csv(registro %>% mutate(excluidos_paso = lag(n) - n), "00_flujo_muestra.csv")
if (!nrow(data)) stop("No quedaron observaciones.")
if (any(is.na(data$BAND)) || any(!data$BAND %in% c("L2", "L28", "L4")))
  stop("Hay BAND faltantes o desconocidas; resolver antes de continuar.")
# La altura del receptor sobre el vehículo se conoce: 1.5 m.
if (any(abs(data$`Altura Recep` - 1.5) > 1e-6, na.rm = TRUE))
  stop("Altura Recep no es siempre 1.5 m: revisar el supuesto de drive test.")
data <- data %>% mutate(`Altura Recep` = coalesce(`Altura Recep`, 1.5),
  Perdida = cfg$potencia_referencia_dbm - Level,
  Perdida_categorica = case_when(Level >= -80 ~ "Bueno", Level >= -100 ~ "Moderado", TRUE ~ "Malo"))
guardar_csv(tibble(variable = requeridas,
  n_faltantes = vapply(data[requeridas],function(x) sum(is.na(x)),integer(1))),
  "00_faltantes_predictores.csv")
# Congelar entrada, configuración, versiones y scripts: no mezclar corridas diferentes.
versiones <- vapply(paquetes, function(x) as.character(packageVersion(x)), character(1))
scripts <- c("00_config.R", "01_preparar_datos.R", "02_tuning.R", "03_evaluacion_IC_graficos.R")
firma <- digest::digest(list(cfg, tools::md5sum(archivo_excel), versiones, tools::md5sum(scripts)))
manifest_path <- file.path(carpeta, "datos", "manifest.rds")
if (file.exists(manifest_path) && !identical(readRDS(manifest_path)$firma, firma))
  stop("Cambió entrada/configuración/scripts/paquetes. Usar otro id_ejecucion para conservar resultados.")
# UTM en metros; detener si el área abarca varias zonas o hemisferios.
zonas <- floor((data$Longitud + 180)/6) + 1
if (length(unique(zonas)) != 1 || (min(data$Latitud) < 0 && max(data$Latitud) >= 0))
  stop("Área amplia: elegir una proyección métrica adecuada antes de crear bloques.")
epsg <- if (median(data$Latitud) >= 0) 32600 + unique(zonas) else 32700 + unique(zonas)
puntos <- st_as_sf(data, coords = c("Longitud", "Latitud"), crs = 4326, remove = FALSE) %>% st_transform(epsg)
xy <- st_coordinates(puntos)
data <- data %>% mutate(Este_m = xy[,1], Norte_m = xy[,2],
  bloque = paste(floor(Este_m/cfg$bloque_m), floor(Norte_m/cfg$bloque_m), sep = "_"))
pts <- function(d) st_as_sf(d, coords = c("Este_m", "Norte_m"), crs = epsg, remove = FALSE)
quitar_buffer <- function(a, b) {
  cerca <- lengths(st_is_within_distance(pts(a), pts(b), dist = cfg$buffer_m)) > 0
  a[!cerca, , drop = FALSE]
}
min_dist <- function(a, b) {
  pa <- pts(a); pb <- pts(b)
  j <- st_nearest_feature(pa, pb)
  min(as.numeric(st_distance(pa, pb[j, ], by_element = TRUE)))
}
set.seed(cfg$semilla_split)
bloques <- sort(unique(data$bloque))
if (length(bloques) < cfg$v + 2) stop("Muy pocos bloques para este diseño.")
bloques_prueba <- sample(bloques, ceiling(length(bloques)*cfg$prop_bloques_prueba))
prueba <- data %>% filter(bloque %in% bloques_prueba)
entrenamiento_pre <- data %>% filter(!bloque %in% bloques_prueba)
entrenamiento <- quitar_buffer(entrenamiento_pre, prueba)
if (n_distinct(entrenamiento$bloque) < cfg$v) stop("Insuficientes bloques de entrenamiento.")
data <- data %>% mutate(Conjunto = case_when(fila_id %in% prueba$fila_id ~ "Test",
  fila_id %in% entrenamiento$fila_id ~ "Training", TRUE ~ "Buffer excluded"))
set.seed(cfg$semilla_folds)
folds_originales <- group_vfold_cv(entrenamiento, group = bloque, v = cfg$v,
                                  repeats = cfg$repeats, balance = "observations")
splits <- vector("list", nrow(folds_originales)); auditorias <- vector("list", length(splits))
for (i in seq_along(splits)) {
  s <- folds_originales$splits[[i]]
  a_pre <- analysis(s); b <- assessment(s); a <- quitar_buffer(a_pre, b)
  if (nrow(a) < 10 || nrow(b) < 2) stop("Fold insuficiente tras buffer: ", i)
  splits[[i]] <- make_splits(list(analysis = match(a$fila_id, entrenamiento$fila_id),
    assessment = match(b$fila_id, entrenamiento$fila_id)), data = entrenamiento)
  auditorias[[i]] <- tibble(resample = i, n_analisis = nrow(a), n_validacion = nrow(b),
    excluidos_buffer = nrow(a_pre)-nrow(a), distancia_min_m = min_dist(a,b),
    bloques_compartidos = length(intersect(a$bloque,b$bloque)),
    celdas_compartidas = length(intersect(na.omit(a$celda_id),na.omit(b$celda_id))))
}
ids <- paste(folds_originales$id, folds_originales$id2, sep = "_")
folds_comparacion <- manual_rset(splits, ids)
auditoria <- bind_rows(auditorias)
stopifnot(all(auditoria$bloques_compartidos == 0),
          all(auditoria$distancia_min_m > cfg$buffer_m))
guardar_csv(auditoria, "01_auditoria_folds.csv")
guardar_csv(tibble(n_entrenamiento = nrow(entrenamiento), n_prueba = nrow(prueba),
  n_buffer = nrow(entrenamiento_pre)-nrow(entrenamiento),
  porcentaje_prueba_filas = 100*nrow(prueba)/nrow(data),
  bloques_train = n_distinct(entrenamiento$bloque), bloques_test = n_distinct(prueba$bloque),
  distancia_min_m = min_dist(entrenamiento,prueba),
  celdas_compartidas = length(intersect(na.omit(entrenamiento$celda_id),na.omit(prueba$celda_id)))),
  "02_particion.csv")
guardar_csv(data %>% count(Conjunto, BAND, name = "n"), "03_muestra_por_frecuencia.csv")
guardar_csv(data %>% count(Conjunto, celda_id, name = "n"), "04_muestra_por_celda.csv")
guardar_plot(ggplot(data, aes(Este_m/1000, Norte_m/1000, color = Conjunto)) +
  geom_point(size = .5, alpha = .5) + coord_equal() + theme_bw() +
  labs(x = "Easting (km)", y = "Northing (km)", color = "Partition"), "00_spatial_partition.png")
saveRDS(list(data = data, entrenamiento = entrenamiento, prueba = prueba,
             folds_comparacion = folds_comparacion, firma = firma, cfg = cfg, epsg = epsg),
        file.path(carpeta, "datos", "datos_y_folds.rds"))
saveRDS(list(firma = firma, cfg = cfg, versiones = versiones, epsg = epsg,
  md5_excel = tools::md5sum(archivo_excel)), manifest_path)
writeLines(capture.output(sessionInfo()), file.path(carpeta, "sessionInfo.txt"))
print(registro); print(readr::read_csv(file.path(carpeta,"tablas","02_particion.csv"), show_col_types = FALSE))
message("Preparación terminada. Revisar mapa y auditorías antes de lanzar 02_tuning.R.")
