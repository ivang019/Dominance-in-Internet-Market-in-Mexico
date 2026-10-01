# =============================================================================
# DOMINANCIA MUNICIPAL SBAF - PIPELINE COMPLETO
# Metodologia: Melnik, Shy & Stenbacka (2008)
# S^D = 0.5 * (1 - gamma * (s1^2 - s2^2))
# gamma = 1 (caso base / barreras a la entrada neutras)
#
# CORRECCIONES DE DATOS aplicadas:
#   1. Se descartan filas basura (ANIO/MES en NA).
#   2. K_ENTIDAD/K_MUNICIPIO se normalizan a texto con cero a la izquierda
#      ANTES de construir K_E_M (evita municipios fantasma duplicados).
#   3. Se excluyen como "sin georreferenciacion" los codigos 99/nan/ZZ/invalido.
#   4. arrange(desc(...)) ANTES del mutate() de lider/seguidor (bug de orden).
#
# HITOS regulatorios en la grafica de tendencia:
#   - 11 jun 2013: reforma constitucional de telecomunicaciones (DOF)
#   - 6 mar 2014: declaratoria de AEP a Telmex/Telcel (P/IFT/EXT/060314/76)
#
# ESTRUCTURA DE SALIDA (todo bajo output/):
#   output/
#     dominancia_temporal_resumen.csv     <- base, cruda
#     dominancia_por_grupo_resumen.csv    <- base, cruda
#     SBAF_ACCESOS_MUNICIPIO_IHH.csv      <- base municipal, cruda
#     graficas/evolucion_dominancia.pdf
#     graficas/dominancia_por_grupo.pdf
#     tablas/SBAF_ACCESOS_MUNICIPIO_IHH.xlsx   <- version formateada para presentar
#     mapas/mapa_dominancia_categoria.pdf
#     mapas/mapa_dominancia_grupo.pdf
# =============================================================================

library(dplyr)
library(readr)
library(ggplot2)
library(lubridate)
library(openxlsx)
library(sf)
library(stringi)

# --- Parametros ---
RUTA_CSV <- "C:/Users/ivang/OneDrive/Escritorio/SBAF_1/TD_ACC_BAF_ITE_VA.csv"
RUTA_GEO <- "C:/Users/ivang/OneDrive/Escritorio/SBAF_1/Geo"
RUTA_OUTPUT <- "C:/Users/ivang/OneDrive/Escritorio/SBAF_1/output"
GAMMA <- 1

HITO_REFORMA <- as.Date("2013-06-11")
HITO_AEP     <- as.Date("2014-03-06")

# --- Helper: nombres de mes en espanol, sin depender del locale del sistema ---
MESES_ES <- c("enero", "febrero", "marzo", "abril", "mayo", "junio",
              "julio", "agosto", "septiembre", "octubre", "noviembre", "diciembre")
formato_fecha_es <- function(fechas) {
  paste0(tools::toTitleCase(MESES_ES[month(fechas)]), " ", year(fechas))
}
formato_fecha_es_eje <- function(fechas) {
  paste0(substr(MESES_ES[month(fechas)], 1, 3), " ", year(fechas))
}

# --- Crear estructura de carpetas de salida ---
dir.create(RUTA_OUTPUT, showWarnings = FALSE, recursive = TRUE)
dir.create(file.path(RUTA_OUTPUT, "graficas"), showWarnings = FALSE)
dir.create(file.path(RUTA_OUTPUT, "tablas"), showWarnings = FALSE)
dir.create(file.path(RUTA_OUTPUT, "mapas"), showWarnings = FALSE)

# =============================================================================
# LECTURA Y LIMPIEZA
# =============================================================================

Accesos_Internet <- read_csv(RUTA_CSV, locale = locale(encoding = "UTF-8"),
                             col_types = cols(K_ENTIDAD = col_character(),
                                              K_MUNICIPIO = col_character())) %>%
  mutate(across(where(is.character), ~iconv(., from = "", to = "UTF-8", sub = " ")))

n0 <- nrow(Accesos_Internet)
Accesos_Internet <- Accesos_Internet %>% filter(!is.na(ANIO), !is.na(MES))
cat(sprintf("Filas basura removidas (ANIO/MES en NA): %d (%.2f%%)\n",
            n0 - nrow(Accesos_Internet), 100 * (n0 - nrow(Accesos_Internet)) / n0))

Accesos_Internet <- Accesos_Internet %>%
  mutate(
    K_ENTIDAD_NUM = suppressWarnings(as.integer(K_ENTIDAD)),
    K_MUNICIPIO_NUM = suppressWarnings(as.integer(K_MUNICIPIO))
  )

n1 <- nrow(Accesos_Internet)
Accesos_Internet <- Accesos_Internet %>%
  filter(!is.na(K_ENTIDAD_NUM), K_ENTIDAD_NUM != 99, K_ENTIDAD_NUM >= 1, K_ENTIDAD_NUM <= 32)
cat(sprintf("Filas sin georreferenciacion removidas (99/nan/ZZ/invalido): %d (%.2f%%)\n",
            n1 - nrow(Accesos_Internet), 100 * (n1 - nrow(Accesos_Internet)) / n1))

Accesos_Internet <- Accesos_Internet %>%
  mutate(
    K_ENTIDAD_PAD = sprintf("%02d", K_ENTIDAD_NUM),
    K_MUNICIPIO_PAD = sprintf("%03d", K_MUNICIPIO_NUM),
    K_E_M = paste(K_ENTIDAD_PAD, K_MUNICIPIO_PAD, sep = "-")
  )

calcular_dominancia <- function(data, group_vars) {
  data %>%
    group_by(across(all_of(group_vars))) %>%
    mutate(A_TOTAL_M = sum(A_TOTAL_E)) %>%
    ungroup() %>%
    mutate(MARKET_S = A_TOTAL_E / A_TOTAL_M * 100) %>%
    group_by(across(all_of(c(group_vars, "GRUPO")))) %>%
    summarise(MARKET_S_GRUPO = sum(MARKET_S), .groups = "drop") %>%
    group_by(across(all_of(group_vars))) %>%
    arrange(desc(MARKET_S_GRUPO), .by_group = TRUE) %>%
    mutate(
      IHH_Municipio = sum(MARKET_S_GRUPO^2),
      lider = MARKET_S_GRUPO[1] / 100,
      seguidor = ifelse(n() >= 2, MARKET_S_GRUPO[2] / 100, 0),
      S_D = 0.5 * (1 - GAMMA * (lider^2 - seguidor^2)),
      participacion_lider = lider * 100,
      dominancia = case_when(
        n() == 1 ~ "monopolio",
        lider > S_D ~ "dominancia",
        TRUE ~ "no dominancia"
      )
    ) %>%
    slice_head(n = 1) %>%
    ungroup()
}

# =============================================================================
# PARTE 1: SERIE TEMPORAL
# =============================================================================

SBAF_SERIE <- calcular_dominancia(Accesos_Internet, c("ANIO", "MES", "K_E_M"))

dominancia_temporal <- SBAF_SERIE %>%
  group_by(ANIO, MES, dominancia) %>%
  summarise(num_municipios = n(), .groups = "drop") %>%
  group_by(ANIO, MES) %>%
  mutate(porcentaje = round(100 * num_municipios / sum(num_municipios), 1)) %>%
  ungroup() %>%
  mutate(FECHA = make_date(year = ANIO, month = MES, day = 1))

dominancia_por_grupo_temporal <- SBAF_SERIE %>%
  filter(dominancia == "dominancia") %>%
  group_by(ANIO, MES, GRUPO) %>%
  summarise(num_municipios = n(), .groups = "drop") %>%
  mutate(FECHA = make_date(year = ANIO, month = MES, day = 1))

# --- Grupos relevantes fijos (definidos una sola vez, se reutilizan en
#     la grafica de barras, la comparacion de 3 cortes, y el mapa 2) ---
GRUPOS_RELEVANTES <- c("AMERICA MOVIL", "MEGACABLE-MCM", "GRUPO TELEVISA", "NETWEY", "GRUPO SALINAS")
normalizar_grupo <- function(x) toupper(stringi::stri_trans_general(x, "Latin-ASCII"))
agrupar_relevantes <- function(x) if_else(normalizar_grupo(x) %in% GRUPOS_RELEVANTES, x, "Otros")

# --- Version para GRAFICAR: solo los 5 grupos relevantes, resto en "Otros" ---
# (la base CSV completa, sin agrupar, se conserva intacta para quien la quiera cruda)
dominancia_por_grupo_grafica <- dominancia_por_grupo_temporal %>%
  mutate(GRUPO_AGRUPADO = agrupar_relevantes(GRUPO)) %>%
  group_by(ANIO, MES, FECHA, GRUPO_AGRUPADO) %>%
  summarise(num_municipios = sum(num_municipios), .groups = "drop")

p1 <- ggplot(dominancia_temporal, aes(x = FECHA, y = porcentaje, color = dominancia)) +
  geom_vline(xintercept = as.numeric(HITO_REFORMA), linetype = "dashed", color = "grey40") +
  geom_vline(xintercept = as.numeric(HITO_AEP), linetype = "dashed", color = "grey40") +
  annotate("text", x = HITO_REFORMA, y = 5, label = "Reforma 2013", angle = 90,
           vjust = -0.5, hjust = 0, size = 3, color = "grey30") +
  annotate("text", x = HITO_AEP, y = 5, label = "AEP 2014", angle = 90,
           vjust = -0.5, hjust = 0, size = 3, color = "grey30") +
  geom_line(linewidth = 0.6) +
  geom_point(size = 1.5) +
  labs(title = "Evoluci\u00f3n de la dominancia en municipios",
       x = "Fecha", y = "Porcentaje de municipios", color = "Tipo de dominancia") +
  scale_x_date(labels = formato_fecha_es_eje, date_breaks = "6 months") +
  theme_minimal(base_size = 13) +
  theme(axis.text.x = element_text(angle = 45, hjust = 1))

# --- Misma grafica, pero en numero de municipios en vez de porcentaje ---
p1_num <- ggplot(dominancia_temporal, aes(x = FECHA, y = num_municipios, color = dominancia)) +
  geom_vline(xintercept = as.numeric(HITO_REFORMA), linetype = "dashed", color = "grey40") +
  geom_vline(xintercept = as.numeric(HITO_AEP), linetype = "dashed", color = "grey40") +
  annotate("text", x = HITO_REFORMA, y = 5, label = "Reforma 2013", angle = 90,
           vjust = -0.5, hjust = 0, size = 3, color = "grey30") +
  annotate("text", x = HITO_AEP, y = 5, label = "AEP 2014", angle = 90,
           vjust = -0.5, hjust = 0, size = 3, color = "grey30") +
  geom_line(linewidth = 0.6) +
  geom_point(size = 1.5) +
  labs(title = "Evoluci\u00f3n de la dominancia en municipios",
       x = "Fecha", y = "N\u00famero de municipios", color = "Tipo de dominancia") +
  scale_x_date(labels = formato_fecha_es_eje, date_breaks = "6 months") +
  theme_minimal(base_size = 13) +
  theme(axis.text.x = element_text(angle = 45, hjust = 1))

p2 <- ggplot(dominancia_por_grupo_grafica,
             aes(x = FECHA, y = num_municipios,
                 fill = forcats::fct_relevel(GRUPO_AGRUPADO, "Otros", after = Inf))) +
  geom_col() +
  labs(title = "Municipios dominados por grupo econ\u00f3mico",
       x = "Fecha", y = "N\u00famero de municipios", fill = "Grupo econ\u00f3mico") +
  scale_x_date(labels = formato_fecha_es_eje, date_breaks = "6 months") +
  theme_minimal(base_size = 13) +
  theme(axis.text.x = element_text(angle = 45, hjust = 1))

# --- Comparacion de 3 cortes (primero / intermedio / ultimo) SOLO para
#     grupos relevantes fijos; todo lo demas se excluye por completo
#     (sin bucket "Otros" aqui, a diferencia de p2) ---
periodos_disponibles <- dominancia_por_grupo_temporal %>%
  distinct(ANIO, MES, FECHA) %>%
  arrange(FECHA) %>%
  mutate(PERIODO = ANIO * 100 + MES)

fecha_primera <- periodos_disponibles$FECHA[1]
fecha_ultima  <- periodos_disponibles$FECHA[nrow(periodos_disponibles)]
fecha_intermedia <- periodos_disponibles$FECHA[
  which.min(abs(as.numeric(periodos_disponibles$FECHA) -
                  mean(c(as.numeric(fecha_primera), as.numeric(fecha_ultima)))))
]

cat(sprintf("Cortes elegidos -> primero: %s | intermedio: %s | ultimo: %s\n",
            fecha_primera, fecha_intermedia, fecha_ultima))

comparacion_cortes <- dominancia_por_grupo_temporal %>%
  filter(FECHA %in% c(fecha_primera, fecha_intermedia, fecha_ultima)) %>%
  filter(normalizar_grupo(GRUPO) %in% GRUPOS_RELEVANTES) %>%
  mutate(CORTE_LABEL = factor(formato_fecha_es(FECHA),
                              levels = formato_fecha_es(c(fecha_primera, fecha_intermedia, fecha_ultima))))

# eje X = fecha del corte, color = grupo (como se pidio)
p3 <- ggplot(comparacion_cortes, aes(x = CORTE_LABEL, y = num_municipios, fill = GRUPO)) +
  geom_col(position = "dodge") +
  labs(title = "Municipios dominados por grupo: 3 cortes temporales",
       x = NULL, y = "N\u00famero de municipios", fill = "Grupo") +
  theme_minimal(base_size = 13) +
  theme(axis.text.x = element_text(angle = 0, hjust = 0.5))

# --- Bases (CSV crudo, directo en output/) ---
write_excel_csv(dominancia_temporal, file.path(RUTA_OUTPUT, "dominancia_temporal_resumen.csv"))
write_excel_csv(dominancia_por_grupo_temporal, file.path(RUTA_OUTPUT, "dominancia_por_grupo_resumen.csv"))

# --- Graficas (PDF, en output/graficas/) ---
# evolucion_dominancia.pdf: 2 paginas, misma info en % (pagina 1) y en numero de municipios (pagina 2)
cairo_pdf(file.path(RUTA_OUTPUT, "graficas", "evolucion_dominancia.pdf"), width = 10, height = 6, onefile = TRUE)
print(p1)
print(p1_num)
dev.off()
ggsave(file.path(RUTA_OUTPUT, "graficas", "dominancia_por_grupo.pdf"), p2, width = 10, height = 6, device = cairo_pdf)
ggsave(file.path(RUTA_OUTPUT, "graficas", "comparacion_3_cortes.pdf"), p3, width = 10, height = 6, device = cairo_pdf)

# =============================================================================
# PARTE 2: CORTE MAS RECIENTE
# =============================================================================

periodo_max <- Accesos_Internet %>%
  mutate(PERIODO = ANIO * 100 + MES) %>%
  summarise(max_periodo = max(PERIODO, na.rm = TRUE)) %>%
  pull(max_periodo)
ANIO_CORTE <- periodo_max %/% 100
MES_CORTE  <- periodo_max %% 100
cat(sprintf("Corte mas reciente detectado: %d-%02d\n", ANIO_CORTE, MES_CORTE))

SBAF_ACCESOS <- Accesos_Internet %>%
  filter(ANIO == ANIO_CORTE, MES == MES_CORTE) %>%
  {calcular_dominancia(., c("K_E_M"))} %>%
  mutate(
    CVE_ENT = sub("-.*", "", K_E_M),
    CVE_MUN = sub(".*-", "", K_E_M)
  )

# --- Base municipal (CSV crudo, directo en output/) ---
write_excel_csv(SBAF_ACCESOS, file.path(RUTA_OUTPUT, "SBAF_ACCESOS_MUNICIPIO_IHH.csv"))

# --- Tabla formateada para presentar (Excel, en output/tablas/) ---
wb <- createWorkbook()
addWorksheet(wb, "Dominancia municipal")
writeData(wb, "Dominancia municipal", SBAF_ACCESOS, headerStyle = createStyle(textDecoration = "bold", fgFill = "#D9E1F2"))
setColWidths(wb, "Dominancia municipal", cols = 1:ncol(SBAF_ACCESOS), widths = "auto")
freezePane(wb, "Dominancia municipal", firstRow = TRUE)
pct_cols <- which(names(SBAF_ACCESOS) %in% c("MARKET_S_GRUPO", "lider", "seguidor", "S_D", "participacion_lider"))
addStyle(wb, "Dominancia municipal", style = createStyle(numFmt = "0.00"),
         rows = 2:(nrow(SBAF_ACCESOS) + 1), cols = pct_cols, gridExpand = TRUE)
saveWorkbook(wb, file.path(RUTA_OUTPUT, "tablas", "SBAF_ACCESOS_MUNICIPIO_IHH.xlsx"), overwrite = TRUE)

# =============================================================================
# PARTE 3: MAPAS (dominancia por categoria + grupo dominante)
# =============================================================================

mun_sf <- st_read(file.path(RUTA_GEO, "00mun.shp"), options = "ENCODING=WINDOWS-1252", quiet = TRUE)
mapa_datos <- mun_sf %>% left_join(SBAF_ACCESOS, by = c("CVE_ENT" = "CVE_ENT", "CVE_MUN" = "CVE_MUN"))

n_sin_match <- sum(is.na(mapa_datos$dominancia))
cat(sprintf("Municipios sin dato de dominancia cruzado: %d de %d\n", n_sin_match, nrow(mapa_datos)))

FECHA_CORTE <- make_date(year = ANIO_CORTE, month = MES_CORTE, day = 1)

mapa1 <- ggplot(mapa_datos) +
  geom_sf(aes(fill = dominancia), color = NA) +
  scale_fill_manual(
    values = c("dominancia" = "#B2182B", "no dominancia" = "#2166AC", "monopolio" = "#67001F"),
    na.value = "grey90", name = "Tipo de dominancia"
  ) +
  labs(title = paste0("Dominancia de mercado SBAF por municipio (", formato_fecha_es(FECHA_CORTE), ")")) +
  theme_void(base_size = 13) +
  theme(legend.position = "right")

mapa_datos <- mapa_datos %>%
  mutate(GRUPO_AGRUPADO = if_else(is.na(GRUPO), NA_character_, agrupar_relevantes(GRUPO)))

mapa2 <- ggplot(mapa_datos) +
  geom_sf(aes(fill = forcats::fct_relevel(GRUPO_AGRUPADO, "Otros", after = Inf)), color = NA) +
  scale_fill_viridis_d(na.value = "grey90", name = "Grupo dominante", option = "turbo") +
  labs(title = paste0("Grupo econ\u00f3mico dominante por municipio (", formato_fecha_es(FECHA_CORTE), ")")) +
  theme_void(base_size = 13) +
  theme(legend.position = "right")

ggsave(file.path(RUTA_OUTPUT, "mapas", "mapa_dominancia_categoria.pdf"), mapa1, width = 10, height = 8, device = cairo_pdf)
ggsave(file.path(RUTA_OUTPUT, "mapas", "mapa_dominancia_grupo.pdf"), mapa2, width = 10, height = 8, device = cairo_pdf)

# =============================================================================
cat("\nListo. Estructura generada en:", RUTA_OUTPUT, "\n")
cat(" - dominancia_temporal_resumen.csv\n")
cat(" - dominancia_por_grupo_resumen.csv\n")
cat(" - SBAF_ACCESOS_MUNICIPIO_IHH.csv\n")
cat(" - graficas/evolucion_dominancia.pdf\n")
cat(" - graficas/dominancia_por_grupo.pdf\n")
cat(" - tablas/SBAF_ACCESOS_MUNICIPIO_IHH.xlsx\n")
cat(" - mapas/mapa_dominancia_categoria.pdf\n")
cat(" - mapas/mapa_dominancia_grupo.pdf\n")