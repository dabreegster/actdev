# Mode split summary by distance ------------------------------------------	

library(tidyverse)
library(ggplot2)
library(sf)

if(!exists("site_name")) site_name = "northwick-park"

path = file.path("data-small", site_name)
all_od = read_csv(file.path(path, "all-census-od.csv"))
desire_lines = sf::read_sf(file.path(path, "desire-lines-many.geojson"))

# colourscheme
cols = c("#457b9d", "#90be6d", "#ffd166", "#fe5f55")

# create combined infographic ---------------------------------------------

get_distance_bands = function(x, distance_band = c(0, zonebuilder::zb_100_triangular_numbers[2:5], 20, 30, 10000)) {
  distance_labels = paste0(distance_band[-length(distance_band)], "-", distance_band[-1])
  distance_labels = gsub(pattern = "-10000", replacement = "+", distance_labels)
  cut(x = x, breaks = distance_band * 1000, labels = distance_labels)
}

all_od_new = all_od %>% 
  rename(all = all, walk = foot, cycle = bicycle, drive = car_driver, trimode = trimode_base) %>% 
  select(geo_code2, all, trimode, walk, cycle, drive, length) %>% 
  mutate(across(all:length, as.numeric))

# disaggregated desire lines inside the study area
desire_lines_disag = desire_lines %>% 
  rename(all = all_base, trimode = trimode_base) %>% 
  mutate(distance_band = get_distance_bands(x = length)) %>% 
  group_by(distance_band, .drop = FALSE) %>% 
  filter(purpose == "commute") %>% 
  select(geo_code2, all, trimode, walk_base, cycle_base, drive_base, walk_godutch, cycle_godutch, drive_godutch, length) %>% 
  sf::st_drop_geometry()

# get desire lines outside the study area
all_dist_outside = all_od_new %>% 
  filter(! geo_code2 %in% desire_lines_disag$geo_code2)

# join the lines inside and outside the study area for the two scenarios separately
desire_disag_base = desire_lines_disag %>%
  select(-c(walk_godutch:drive_godutch)) %>% 
  rename(walk = walk_base, cycle = cycle_base, drive = drive_base)

desire_disag_scenario = desire_lines_disag %>%
  select(-c(walk_base:drive_base)) %>% 
  rename(walk = walk_godutch, cycle = cycle_godutch, drive = drive_godutch)

desire_all_base = bind_rows(desire_disag_base, all_dist_outside)

desire_all_scenario = bind_rows(desire_disag_scenario, all_dist_outside)

# Baseline scenario

mode_split_base = desire_all_base %>%
  mutate(distance_band = get_distance_bands(x = length)) %>% 
  group_by(distance_band, .drop = FALSE) %>% 
  summarise(across(all:drive, sum)) %>% 
  mutate(other = all - trimode)

all_dist = mode_split_base %>% 
  pivot_longer(cols = c(walk, cycle, drive, other))

all_dist$name = factor(all_dist$name, levels = c("walk", "cycle", "other", "drive"))

g1 = ggplot(all_dist, aes(fill = name, y = value, x = distance_band)) +
  geom_bar(position = "stack", stat = "identity") +
  scale_fill_manual(values = cols) +
  labs(y = "", x = "Distance band (km)", fill = "") +
  theme_minimal()

# Go Active scenario

mode_split_scenario = desire_all_scenario %>%
  mutate(distance_band = get_distance_bands(x = length)) %>% 
  group_by(distance_band, .drop = FALSE) %>% 
  summarise(across(all:drive, sum)) %>% 
  mutate(other = all - trimode)

all_dist_scenario = mode_split_scenario %>% 
  pivot_longer(cols = c(walk, cycle, drive, other))

all_dist_scenario$name = factor(all_dist_scenario$name, levels = c("walk", "cycle", "other", "drive"))

g2 = ggplot(all_dist_scenario, aes(fill = name, y = value, x = distance_band)) +
  geom_bar(position = "stack", stat = "identity") +
  scale_fill_manual(values = cols) +
  labs(y = "", x = "Distance band (km)", fill = "") +
  theme_minimal()

# library(patchwork)
# infographic = g1 + g2

dsn = file.path("data-small", site_name, "mode-split-base.png")
ggsave(filename = dsn, width = 4, height = 3, dpi = 100, plot = g1)
# magick::image_read(dsn) # sanity check, looking good!

dsn = file.path("data-small", site_name, "mode-split-goactive.png")
ggsave(filename = dsn, width = 4, height = 3, dpi = 100, plot = g2)

# experimental: output plot as html
# p1 = plotly::ggplotly(g1)
# dsn = file.path("data-small", site_name, "mode-split-base.html")
# htmlwidgets::saveWidget(p1, dsn)

# Create single mode split summary csv
sum_total = sum(mode_split_base$all)

mode_split_all = mode_split_base %>% 
  mutate(
    across(all:other, round, 0),
    proportion_in_distance_band = round(100 * all / sum_total),
    walk_goactive = round(mode_split_scenario$walk),
    cycle_goactive = round(mode_split_scenario$cycle),
    drive_goactive = round(mode_split_scenario$drive),
    other_goactive = round(mode_split_scenario$other),
    percent_walk_base = round(100 * walk / all),	
    percent_cycle_base = round(100 * cycle / all),	
    percent_drive_base = round(100 * drive / all),
    percent_other_base = round(100 * other / all),
    percent_walk_goactive = round(100 * walk_goactive / all),	
    percent_cycle_goactive = round(100 * cycle_goactive / all),	
    percent_drive_goactive = round(100 * drive_goactive / all),
    percent_other_goactive = round(100 * other_goactive / all)
  ) %>% 
  rename(
    walk_base = walk,
    cycle_base = cycle,
    drive_base = drive,
    other_base = other
  ) %>% 
  select(distance_band, proportion_in_distance_band, everything())

dsn = file.path("data-small", site_name, "mode-split.csv")	
file.remove(dsn)
readr::write_csv(mode_split_all, file = dsn)

# Update aggregate mode-split data for new site

#baseline scenario
mode_share_site_path_baseline = file.path("data-small/mode-share-sites-baseline.csv")
mode_share_sites_baseline = read.csv(mode_share_site_path_baseline)

if (new_site) {
  new_mode_share = data.frame(site_name,sum(mode_split_all$walk_base),sum(mode_split_all$cycle_base),sum(mode_split_all$drive_base),sum(mode_split_all$other_base))
  names(new_mode_share) <- c("site_name","walk_base","cycle_base","drive_base","other_base")
  mode_share_sites_baseline = rbind(mode_share_sites_baseline,new_mode_share)
} else {
  mode_share_sites_baseline$walk_base[mode_share_sites_baseline$site_name == site_name] = sum(mode_split_all$walk_base)
  mode_share_sites_baseline$cycle_base[mode_share_sites_baseline$site_name == site_name] = sum(mode_split_all$cycle_base)
  mode_share_sites_baseline$drive_base[mode_share_sites_baseline$site_name == site_name] = sum(mode_split_all$drive_base)
  mode_share_sites_baseline$other_base[mode_share_sites_baseline$site_name == site_name] = sum(mode_split_all$other_base)
}
mode_share_sites_baseline = arrange(mode_share_sites_baseline,site_name)
file.remove(mode_share_site_path_baseline)
readr::write_csv(mode_share_sites_baseline, mode_share_site_path_baseline)

#go active scenario
mode_share_site_path_goactive = file.path("data-small/mode-share-sites-goactive.csv")
mode_share_sites_goactive = read.csv(mode_share_site_path_goactive)
if (new_site) {
  new_mode_share_active = data.frame(site_name, sum(mode_split_all$walk_goactive),sum(mode_split_all$cycle_goactive),sum(mode_split_all$drive_goactive),sum(mode_split_all$other_goactive))
  names(new_mode_share_active) <- c("site_name","walk_active","cycle_active","drive_active","other_active")
  mode_share_sites_goactive = rbind(mode_share_sites_goactive,new_mode_share_active)
} else {
  mode_share_sites_goactive$walk_active[mode_share_sites_goactive$site_name == site_name] = sum(mode_split_all$walk_goactive)
  mode_share_sites_goactive$cycle_active[mode_share_sites_goactive$site_name == site_name] = sum(mode_split_all$cycle_goactive)
  mode_share_sites_goactive$drive_active[mode_share_sites_goactive$site_name == site_name] = sum(mode_split_all$drive_goactive)
  mode_share_sites_goactive$other_active[mode_share_sites_goactive$site_name == site_name] = sum(mode_split_all$other_goactive)
}
mode_share_sites_goactive = arrange(mode_share_sites_goactive,site_name)

file.remove(mode_share_site_path_goactive)
readr::write_csv(mode_share_sites_goactive,mode_share_site_path_goactive)

