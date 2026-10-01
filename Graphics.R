# =============================================================================
# FIGURAS EN INGLES PARA EL README (sin titulo; los pies van en el README)
# Lee las tablas que ya genero Dominancia.R y guarda 5 PNG en SBAF_1/git2.
# =============================================================================

library(dplyr)
library(readr)
library(ggplot2)
library(lubridate)
library(sf)
library(stringi)

# --- Rutas ---
BASE            <- "C:/Users/ivang/OneDrive/Escritorio/SBAF_1"
RUTA_RESULTADOS <- file.path(BASE, "output")   # CSV que genero Dominancia.R
RUTA_GEO        <- file.path(BASE, "Geo")
RUTA_SALIDA     <- file.path(BASE, "git2")
dir.create(RUTA_SALIDA, showWarnings = FALSE, recursive = TRUE)

HITO_REFORMA <- as.Date("2013-06-11")
HITO_AEP     <- as.Date("2014-03-06")

# --- Etiquetas en ingles (no dependen del idioma del sistema) ---
fecha_eje <- function(x) paste(month.abb[month(x)], year(x))

DOM_NIVELES <- c("dominancia", "monopolio", "no dominancia")
DOM_ETIQ    <- c("Dominance", "Monopoly", "No dominance")
DOM_COLORES <- c("Dominance" = "#B2182B", "Monopoly" = "#67001F",
                 "No dominance" = "#2166AC", "No data" = "grey90")

GRUPOS_REL   <- c("AMERICA MOVIL", "MEGACABLE-MCM", "GRUPO TELEVISA", "NETWEY", "GRUPO SALINAS")
GRUPOS_ETIQ  <- c("Am\u00e9rica M\u00f3vil", "Megacable", "Grupo Televisa", "Netwey", "Grupo Salinas")
NIV_GRUPOS   <- c(GRUPOS_ETIQ, "Others")
normalizar   <- function(x) toupper(stringi::stri_trans_general(x, "Latin-ASCII"))
etiqueta_grupo <- function(x) {
  i <- match(normalizar(x), GRUPOS_REL)
  ifelse(is.na(i), "Others", GRUPOS_ETIQ[i])
}

guardar <- function(p, nombre, w, h) {
  ggsave(file.path(RUTA_SALIDA, nombre), p, width = w, height = h, dpi = 200, bg = "white")
}

# --- Datos ---
temporal <- read_csv(file.path(RUTA_RESULTADOS, "dominancia_temporal_resumen.csv"),
                     show_col_types = FALSE) %>%
  mutate(FECHA = as.Date(FECHA),
         tipo  = factor(dominancia, levels = DOM_NIVELES, labels = DOM_ETIQ))

por_grupo <- read_csv(file.path(RUTA_RESULTADOS, "dominancia_por_grupo_resumen.csv"),
                      show_col_types = FALSE) %>%
  mutate(FECHA = as.Date(FECHA))

# =============================================================================
# FIGURA 1: evolucion del tipo de dominancia (% de municipios)
# =============================================================================
fig1 <- ggplot(temporal, aes(x = FECHA, y = porcentaje, color = tipo)) +
  geom_vline(xintercept = as.numeric(HITO_REFORMA), linetype = "dashed", color = "grey40") +
  geom_vline(xintercept = as.numeric(HITO_AEP),     linetype = "dashed", color = "grey40") +
  annotate("text", x = HITO_REFORMA, y = 5, label = "Reform 2013", angle = 90,
           vjust = -0.5, hjust = 0, size = 3, color = "grey30") +
  annotate("text", x = HITO_AEP, y = 5, label = "PEA 2014", angle = 90,
           vjust = -0.5, hjust = 0, size = 3, color = "grey30") +
  geom_line(linewidth = 0.6) +
  geom_point(size = 1.5) +
  labs(x = "Date", y = "Share of municipalities (%)", color = "Dominance type") +
  scale_x_date(labels = fecha_eje, date_breaks = "6 months") +
  theme_minimal(base_size = 13) +
  theme(axis.text.x = element_text(angle = 45, hjust = 1))

guardar(fig1, "fig1_dominance_evolution.png", 10, 6)

# =============================================================================
# FIGURA 2: municipios dominados por grupo (5 grupos + Others)
# =============================================================================
datos_fig2 <- por_grupo %>%
  mutate(grupo = factor(etiqueta_grupo(GRUPO), levels = NIV_GRUPOS)) %>%
  group_by(FECHA, grupo) %>%
  summarise(num_municipios = sum(num_municipios), .groups = "drop")

fig2 <- ggplot(datos_fig2, aes(x = FECHA, y = num_municipios, fill = grupo)) +
  geom_col() +
  labs(x = "Date", y = "Number of municipalities", fill = "Economic group") +
  scale_x_date(labels = fecha_eje, date_breaks = "6 months") +
  theme_minimal(base_size = 13) +
  theme(axis.text.x = element_text(angle = 45, hjust = 1))

guardar(fig2, "fig2_municipalities_by_group.png", 10, 6)

# =============================================================================
# FIGURA 3: tres cortes (primero, intermedio, ultimo), solo los 5 grupos
# =============================================================================
periodos <- sort(unique(por_grupo$FECHA))
f_primera <- periodos[1]
f_ultima  <- periodos[length(periodos)]
f_media   <- periodos[which.min(abs(as.numeric(periodos) -
                                      mean(c(as.numeric(f_primera), as.numeric(f_ultima)))))]
cortes <- c(f_primera, f_media, f_ultima)

datos_fig3 <- por_grupo %>%
  filter(FECHA %in% cortes, normalizar(GRUPO) %in% GRUPOS_REL) %>%
  mutate(grupo = factor(etiqueta_grupo(GRUPO), levels = GRUPOS_ETIQ),
         corte = factor(fecha_eje(FECHA), levels = fecha_eje(cortes)))

fig3 <- ggplot(datos_fig3, aes(x = corte, y = num_municipios, fill = grupo)) +
  geom_col(position = "dodge") +
  labs(x = NULL, y = "Number of municipalities", fill = "Economic group") +
  theme_minimal(base_size = 13)

guardar(fig3, "fig3_municipalities_by_group_three_cuts.png", 10, 6)

# =============================================================================
# MAPAS: corte mas reciente
# =============================================================================
FECHA_CORTE <- max(temporal$FECHA)
sufijo <- paste0(tolower(month.abb[month(FECHA_CORTE)]), year(FECHA_CORTE))   # ej. dec2025

municipal <- read_csv(file.path(RUTA_RESULTADOS, "SBAF_ACCESOS_MUNICIPIO_IHH.csv"),
                      col_types = cols(CVE_ENT = col_character(), CVE_MUN = col_character(),
                                       .default = col_guess()),
                      show_col_types = FALSE)

mun_sf <- st_read(file.path(RUTA_GEO, "00mun.shp"),
                  options = "ENCODING=WINDOWS-1252", quiet = TRUE)
mapa_datos <- mun_sf %>% left_join(municipal, by = c("CVE_ENT", "CVE_MUN"))

mapa_datos <- mapa_datos %>%
  mutate(
    tipo_map  = factor(coalesce(DOM_ETIQ[match(dominancia, DOM_NIVELES)], "No data"),
                       levels = c(DOM_ETIQ, "No data")),
    grupo_map = factor(if_else(is.na(GRUPO), "No data", etiqueta_grupo(GRUPO)),
                       levels = c(NIV_GRUPOS, "No data"))
  )

# --- Mapa 1: tipo de dominancia ---
map1 <- ggplot(mapa_datos) +
  geom_sf(aes(fill = tipo_map), color = NA) +
  scale_fill_manual(values = DOM_COLORES, name = "Dominance type", drop = FALSE) +
  theme_void(base_size = 13) +
  theme(legend.position = "right")

guardar(map1, paste0("map1_dominance_type_", sufijo, ".png"), 10, 8)

# --- Mapa 2: grupo dominante ---
colores_grupos <- c(setNames(viridisLite::viridis(length(NIV_GRUPOS), option = "turbo"), NIV_GRUPOS),
                    "No data" = "grey90")

map2 <- ggplot(mapa_datos) +
  geom_sf(aes(fill = grupo_map), color = NA) +
  scale_fill_manual(values = colores_grupos, name = "Dominant group", drop = FALSE) +
  theme_void(base_size = 13) +
  theme(legend.position = "right")

guardar(map2, paste0("map2_dominant_group_", sufijo, ".png"), 10, 8)

cat("\nListo. Archivos guardados en:", RUTA_SALIDA, "\n")
print(list.files(RUTA_SALIDA))