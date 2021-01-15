# Aim: generate scenarios of change associated with new developments

library(tidyverse)
library(sf)

# set-up and parameters ---------------------------------------------------

household_size = 2.3 # mean UK household size at 2011 census
max_length = 20000 # maximum length of desire lines in m
site_name = "great-kneighton"   # which site to look at (can change)
min_flow_routes = 5 # threshold above which OD pairs are included
region_buffer_dist = 2000
# input data --------------------------------------------------------------

centroids_msoa = pct::get_centroids_ew() 
centroids_msoa = sf::st_transform(centroids_msoa, 4326)
zones_msoa_national = pct::get_pct(national = TRUE, geography = "msoa", layer = "z")

od = pct::get_od()
u = "https://github.com/cyipt/actdev/releases/download/0.1.1/all-sites.geojson"
sites = sf::st_read(u)

#1) get 2011 MSOA populations
# u2 = "https://www.ons.gov.uk/file?uri=%2fpeoplepopulationandcommunity%2fpopulationandmigration%2fpopulationestimates%2fdatasets%2fmiddlesuperoutputareamidyearpopulationestimates%2fmid2011/mid2011msoaunformattedfile.xls"
# piggyback::pb_upload("data/mid2011msoaunformattedfile.xls")
# piggyback::pb_download("https://github.com/cyipt/actdev/releases/download/0.1.1/data.2fmid2011msoaunformattedfile.xls")
msoa_pops = readxl::read_xls(path = "data/mid2011msoaunformattedfile.xls", sheet = "Mid-2011 Persons", )
msoa_pops = msoa_pops %>% 
  select(geo_code1 = Code, msoa_population = "All Ages")

#2) estimated site population = number of homes when complete * household_size constant
site_dwellings = read_csv("data/site-populations.csv")
site_pops = site_dwellings %>% 
  mutate(site_population = dwellings_when_complete * household_size)

# select site of interest
site = sites[sites$site_name == site_name, ]
sf::write_sf(site, "data-small/chapelford/site-boundary.geojson")

zones_touching_site = zones_msoa_national[site, , op = sf::st_intersects]


# Route from site centroid (rather than MSOA centroid) --------------------
# this could be changed to route from a random selection of homes within the site, to better represent the accessibility of the site as a whole
site_centroid = site %>% 
  st_transform(27700) %>% 
  st_centroid() %>% 
  st_transform(4326)

zone_data = zones_touching_site %>% 
  st_drop_geometry() %>%
  mutate(site_name = site$site_name)
site_c = right_join(site_centroid, zone_data) %>%
  select(geo_code, site_name)

# Generate desire lines ---------------------------------------------------
# Adapted to work when the site lies within 2 or more MSOAs
# For MSOA data from wu03ew_v2, downloaded using `get_od()`, geo_code1 is always the home and geo_code2 is the workplace. So we don't need to add in OD pairs where geo_code2 lies within the site
od_site = od %>% 
  filter(geo_code1 %in% zones_touching_site$geo_code) %>% 
  filter(geo_code2 %in% centroids_msoa$msoa11cd) %>% 
  filter(geo_code1 != geo_code2) # note: not accounting for intrazonal flows. But where the site lies within 2 or more MSOAs, flows from one to the other of these will still be included.
# intra-zonal flows could be added later, using more detailed od-workplace zone data. Or we could simply route from the site centroid to the MSOA centroid.

desire_lines_site = od::od_to_sf(x = od_site, z = site_c, zd = centroids_msoa)
desire_lines_site = desire_lines_site %>% 
  mutate(site_name = site_name)


# Adjust flows to represent site population, not MSOA population(s) -------
# for both MSOAs and development sites, these are entire populations, not commuter populations



#3) divide proportionately (accounting for multiple msoas where relevant)
desire_lines_site = inner_join(desire_lines_site, msoa_pops)
desire_lines_site = inner_join(desire_lines_site, site_pops)
site_population = unique(desire_lines_site$site_population)
unique_msoa_pops = desire_lines_site %>% 
  st_drop_geometry() %>% 
  select(geo_code1, msoa_population) %>%
  distinct()
sum_msoa_pops = sum(unique_msoa_pops$msoa_population)
desire_lines_site = desire_lines_site %>% 
  mutate(sum_msoa_pops = sum_msoa_pops)

# # creating a new set of columns for converted flows
# desire_lines_pops = desire_lines_site %>% 
#   mutate(across(all:other, .fns = list(converted = ~ ./ sum_msoa_pops * site_population)))

# keeping converted flows in the same columns
desire_lines_pops = desire_lines_site %>% 
  mutate(across(all:other, .fns = ~ ./ sum_msoa_pops * site_population))

# todo: add empirical data on 'new homes' effect (residents of new homes are more likely to drive than residents of older homes)
# could also adjust the base walking and cycling mode shares in response to the difference between journey distance from the site centroid as compared to journey distance from the MSOA centroid (eg in Cambridge, the MSOA centroid is a fair bit closer to the city centre than the site centroid, which could explain why such a high proportion of commuters are shown walking to work in the city centre)  

# For sites with 2 or more origin MSOAs, combine flows to avoid having multiple desire lines to the same destination MSOA
desire_lines_combined = desire_lines_pops %>% 
  group_by(geo_code2) %>% 
  summarise(
    geo_code1 = geo_code1[1], # do we even need this?
    across(all:other, sum)
  )

desire_lines_combined$length = stplanr::geo_length(desire_lines_combined)

desire_lines_combined = desire_lines_combined %>% 
  mutate(pwalk_commute_base = foot/all) %>% 
  mutate(pcycle_commute_base = bicycle/all) %>% 
  mutate(pdrive_commute_base = car_driver/all) %>% 
  mutate(gradient = 0)

desire_lines_combined = desire_lines_combined %>% 
  select(geo_code1, geo_code2, all:other, length, gradient, pwalk_commute_base:pdrive_commute_base)

desire_lines_rounded = desire_lines_combined %>% 
  mutate(across(where(is.numeric), round, 6))
readr::write_csv(desire_lines_rounded, "all-census-od.csv")

desire_lines_20km = desire_lines_rounded %>% 
  filter(length <= max_length)
sf::write_sf(desire_lines_20km, "data-small/chapelford/desire-lines-large.geojson")

desire_lines_5 = desire_lines_rounded %>% 
  filter(all >= min_flow_routes)

# Get region of interest from desire lines --------------------------------
min_flow_map = site_population / 80
desire_lines_large = desire_lines_combined %>% 
  filter(all >= min_flow_map)

convex_hull = sf::st_convex_hull(sf::st_union(desire_lines_large))
study_area = stplanr::geo_buffer(convex_hull, dist = region_buffer_dist)


zones_touching_study_area = zones_msoa_national[study_area, , op = sf::st_intersects]


dir.create("data-small/chapelford")
sf::write_sf(study_area, "data-small/chapelford/small-study-area.geojson")

# Add scenarios of change -------------------------------------------------

desire_lines_small = desire_lines_combined[study_area, , op = sf::st_within]
# todo: add PT

#####move this to earlier in the script
# todo: add route data
desire_lines_combined = desire_lines_combined %>% 
  mutate(pcycle_commute_godutch = pct::uptake_pct_godutch_2020(distance = length, gradient = gradient)) %>% 
  mutate(pwalk_commute_godutch = case_when(
    length <= 2000 ~ pwalk_commute_base + 0.1, # 10% shift walking
    TRUE ~ pwalk_commute_base 
  )
  )  

# todo: estimate which proportion of the new walkers/cyclists in the go dutch scenarios would switch from driving, and which proportion would switch from other modes
desire_lines_scenario = desire_lines_combined %>% 
  mutate(bicycle_commute_godutch = all * pcycle_commute_godutch) %>% 
  mutate(walk_commute_godutch = all * pwalk_commute_godutch) %>% 
  mutate(car_commute_godutch = case_when(
    car_driver + (bicycle - bicycle_commute_godutch) + (foot - walk_commute_godutch) >= 0 ~ 
      car_driver + (bicycle - bicycle_commute_godutch) + (foot - walk_commute_godutch),
    TRUE ~ 0)
  ) %>% 
  mutate(pdrive_commute_godutch = car_commute_godutch / all)
##########

sf::write_sf(desire_lines_scenario, "data-small/chapelford/small-desire-lines.geojson")


