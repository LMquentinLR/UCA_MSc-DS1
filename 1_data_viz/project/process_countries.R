setwd("D:/repositories/UCA_MSc-DS1/data_visualization/project")
library(readr)
library(dplyr)
library(tidyverse)
library(jsonlite)
library(geojsonR)
library(readr)

### LOADING EXTERNAL DATASETS

choro_var_albums <- c("id_artist", "genre", "publicationDate")
choro_var_artists <- c('_id',"location.country")

albums <- read_csv("wasabi_albums.csv")
albums_lite_choro <- albums %>% select(choro_var_albums)

artists <- read_csv("wasabi_artists.csv")
artists_lite_choro <- artists %>% select(choro_var_artists)

population <- read_csv("population.csv")
country_name_matcher <- read_csv("countries.csv")

### PRE-PROCESSING THE ALBUM DATASET

sift_df <- function(df, filter_string, name, save=FALSE) {
  new_df <- df %>% mutate(genre = tolower(genre)) %>% 
    filter(grepl(paste(filter_string, collapse="|"), genre)) %>% 
    select(genre) %>% distinct(genre)
  if (save == TRUE) { write.table(new_df, file=paste(name, ".txt"), quote=F) }
  return(new_df$genre)
}

rock_lst <- c("rock")
metal_lst <- c("metal")
punk_lst <- c("punk")
country_folk_lst <- c("country", "folk", "blues", "gospel")
hip_hop_rap_lst <- c("hip","hop","pop","rap", "reggae", "americana")
jazz_lst <- c("jazz")
electro_lst <- c("electro","dubstep","drum and bass", "synth", "ebm", "tech")

rock_genres <- sift_df(albums_lite_choro, rock_lst, "rock")
metal_genres <- sift_df(albums_lite_choro, metal_lst, "metal")
punk_genres <- sift_df(albums_lite_choro, punk_lst, "punk")
country_folk_genres <- sift_df(albums_lite_choro, country_folk_lst, "countr_folk")
hihop_pop_genres <- sift_df(albums_lite_choro, hip_hop_rap_lst, "hip-hop_pop")
jazz_genres <- sift_df(albums_lite_choro, jazz_lst, "jazz")
electro_genres <- sift_df(albums_lite_choro, electro_lst, "electro")

kept_genres <- c(rock_genres, metal_genres, punk_genres, country_folk_genres, 
                 hihop_pop_genres, jazz_genres, electro_genres, electro_genres)

# 1. Drops all entries that are of a genre we are not interested in
# 2. Create a new column genre_family that contains generic genre name of the album
# 3. Drops the genre column
# 4. Remove all instances older than 1950 and creates a column referencing the 
# decade of the album
# 5. Drops the publicationDate column 
# 6. Removes duplicates
df_album <- as_tibble(albums_lite_choro) %>% 
  filter (tolower(genre) %in% kept_genres) %>% 
  mutate(genre_family = case_when(tolower(genre)%in%rock_genres~"rock",
                                  tolower(genre)%in%metal_genres~"metal",
                                  tolower(genre)%in%punk_genres~"punk",
                                  tolower(genre)%in%country_folk_genres~"countryfolk",
                                  tolower(genre)%in%hihop_pop_genres~"hiphop",
                                  tolower(genre)%in%jazz_genres~"jazz",
                                  tolower(genre)%in%electro_genres~"electro")) %>% 
  select(-c(genre)) %>%
  filter(publicationDate >= 1960) %>% 
  mutate(decade = case_when((publicationDate>=1960 & publicationDate<1970)~1960,
                            (publicationDate>=1970 & publicationDate<1980)~1970,
                            (publicationDate>=1980 & publicationDate<1990)~1980,
                            (publicationDate>=1990 & publicationDate<2000)~1990,
                            (publicationDate>=2000)~2000)) %>%
  select(-c(publicationDate)) %>% distinct()

### PRE-PROCESSING THE ARTIST DATASET

# 1. Removes duplicates
# 2. Renames the _id column to id_artists
artists_lite_choro <- as_tibble(artists_lite_choro) %>% distinct() %>%
  rename("id_artist"="_id")

### PRE-PROCESSING THE POPULATION DATASET

pop_df <- population %>% 
  mutate(decade = case_when((Year>=1960 & Year<1970)~1960,
                            (Year>=1970 & Year<1980)~1970, 
                            (Year>=1980 & Year<1990)~1980, 
                            (Year>=1990 & Year<2000)~1990, 
                            (Year>=2000)~2000)) %>% 
  select(-c("Country Code", "Year"))
pop_df <- data.frame(pop_df)
pop_df <- aggregate(pop_df, by=list(pop_df$decade,
                                    pop_df$Country.Name), FUN=mean)
pop_df <- pop_df %>% select(-c("Country.Name", "Group.1")) %>%
  rename("country"="Group.2") %>% mutate(country = tolower(country))

## CREATING THE JOINT DATA FRAME

# 1. Merges artist_lite_choro and df_album on the id_artist column
# 2. rename location.country column to country
# 3. replace NA with world
# 4. lower case all country names and replaces the country names with formatted ones
joined_df <- merge(x=df_album, y=artists_lite_choro, by="id_artist") %>% 
  rename("country"="location.country") %>% mutate(country = replace_na(country, "world")) %>% 
  mutate(country = tolower(country)) %>% subset(country !="world")

standardize_country_names <- function(df, source_df) {
  df <- df %>% add_column(cleaned_country = NA)
  for (i in 1:nrow(df)) {
    for (j in 1:nrow(source_df)) {
      if (tolower(df$country[i])==tolower(source_df$country_raw[j])) {
        df$cleaned_country[i]=source_df$preprocessed_country[j]
      }
    }
  }
  df <- df %>% select(-c(country)) %>% rename("country"="cleaned_country")
  return(df)
}

joined_df <- standardize_country_names(joined_df, country_name_matcher)
pop_df <- standardize_country_names(pop_df, country_name_matcher)

joined_df <- joined_df %>% select(-c(id_artist))

joined_df$count <- 1

joined_df <- joined_df %>% group_by(decade, country, genre_family) %>% 
  summarise(count = n())

joined_df <- merge(joined_df, pop_df, by=c("country","decade")) %>% 
  rename("population"="Value")

# Removes superfluous data frame
rm(albums)
rm(artists)
rm(albums_lite_choro)
rm(df_album)
rm(artists_lite_choro)

create_json <- function(df) {
  
  entry <- list(rock=list(sixties=list(count=0,population=0),
                               seventies=list(count=0,population=0),
                               eighties=list(count=0,population=0),
                               nineties=list(count=0,population=0),
                               twothousands=list(count=0,population=0)),
                     metal=list(sixties=list(count=0,population=0),
                                seventies=list(count=0,population=0),
                                eighties=list(count=0,population=0),
                                nineties=list(count=0,population=0),
                                twothousands=list(count=0,population=0)),
                     punk=list(sixties=list(count=0,population=0),
                               seventies=list(count=0,population=0),
                               eighties=list(count=0,population=0),
                               nineties=list(count=0,population=0),
                               twothousands=list(count=0,population=0)),
                     country=list(sixties=list(count=0,population=0),
                                  seventies=list(count=0,population=0),
                                  eighties=list(count=0,population=0),
                                  nineties=list(count=0,population=0),
                                  twothousands=list(count=0,population=0)),
                     hip=list(sixties=list(count=0,population=0),
                              seventies=list(count=0,population=0),
                              eighties=list(count=0,population=0),
                              nineties=list(count=0,population=0),
                              twothousands=list(count=0,population=0)),
                     jazz=list(sixties=list(count=0,population=0),
                               seventies=list(count=0,population=0),
                               eighties=list(count=0,population=0),
                               nineties=list(count=0,population=0),
                               twothousands=list(count=0,population=0)),
                     electro=list(sixties=list(count=0,population=0),
                                  seventies=list(count=0,population=0),
                                  eighties=list(count=0,population=0),
                                  nineties=list(count=0,population=0),
                                  twothousands=list(count=0,population=0)
  ))
  
  processed_countries <- c("nullcountry")
  entries <- list(entry)
  country_list <- df$country %>% unique()
  for (country in country_list) {
    new_entry <- entry
    for (country_index in 1:nrow(df)) {
      if (df$country[country_index]==country) {
        if (df$genre_family[country_index]=="rock") {
          if (df$decade[country_index]==1960) {
            new_entry$rock$sixties$count = df$count[country_index]
            new_entry$rock$sixties$population = df$population[country_index]
          } else if (df$decade[country_index]==1970) {
            new_entry$rock$seventies$count = df$count[country_index]
            new_entry$rock$seventies$population = df$population[country_index]
          } else if (df$decade[country_index]==1980) {
            new_entry$rock$eighties$count = df$count[country_index]
            new_entry$rock$eighties$population = df$population[country_index]
          } else if (df$decade[country_index]==1990) {
            new_entry$rock$nineties$count = df$count[country_index]
            new_entry$rock$nineties$population = df$population[country_index]
          } else if (df$decade[country_index]==2000) {
            new_entry$rock$twothousands$count = df$count[country_index]
            new_entry$rock$twothousands$population = df$population[country_index]
          } 
        } else if (df$genre_family[country_index]=="metal") {
          if (df$decade[country_index]==1960) {
            new_entry$metal$sixties$count = df$count[country_index]
            new_entry$metal$sixties$population = df$population[country_index]
          } else if (df$decade[country_index]==1970) {
            new_entry$metal$seventies$count = df$count[country_index]
            new_entry$metal$seventies$population = df$population[country_index]
          } else if (df$decade[country_index]==1980) {
            new_entry$metal$eighties$count = df$count[country_index]
            new_entry$metal$eighties$population = df$population[country_index]
          } else if (df$decade[country_index]==1990) {
            new_entry$metal$nineties$count = df$count[country_index]
            new_entry$metal$nineties$population = df$population[country_index]
          } else if (df$decade[country_index]==2000) {
            new_entry$metal$twothousands$count = df$count[country_index]
            new_entry$metal$twothousands$population = df$population[country_index]
          }  
        } else if (df$genre_family[country_index]=="punk") {
          if (df$decade[country_index]==1960) {
            new_entry$punk$sixties$count = df$count[country_index]
            new_entry$punk$sixties$population = df$population[country_index]
          } else if (df$decade[country_index]==1970) {
            new_entry$punk$seventies$count = df$count[country_index]
            new_entry$punk$seventies$population = df$population[country_index]
          } else if (df$decade[country_index]==1980) {
            new_entry$punk$eighties$count = df$count[country_index]
            new_entry$punk$eighties$population = df$population[country_index]
          } else if (df$decade[country_index]==1990) {
            new_entry$punk$nineties$count = df$count[country_index]
            new_entry$punk$nineties$population = df$population[country_index]
          } else if (df$decade[country_index]==2000) {
            new_entry$punk$twothousands$count = df$count[country_index]
            new_entry$punk$twothousands$population = df$population[country_index]
          } 
        } else if (df$genre_family[country_index]=="countryfolk") {
          if (df$decade[country_index]==1960) {
            new_entry$country$sixties$count = df$count[country_index]
            new_entry$country$sixties$population = df$population[country_index]
          } else if (df$decade[country_index]==1970) {
            new_entry$country$seventies$count = df$count[country_index]
            new_entry$country$seventies$population = df$population[country_index]
          } else if (df$decade[country_index]==1980) {
            new_entry$country$eighties$count = df$count[country_index]
            new_entry$country$eighties$population = df$population[country_index]
          } else if (df$decade[country_index]==1990) {
            new_entry$country$nineties$count = df$count[country_index]
            new_entry$country$nineties$population = df$population[country_index]
          } else if (df$decade[country_index]==2000) {
            new_entry$country$twothousands$count = df$count[country_index]
            new_entry$country$twothousands$population = df$population[country_index]
          } 
        } else if (df$genre_family[country_index]=="hiphop") {
          if (df$decade[country_index]==1960) {
            new_entry$hip$sixties$count = df$count[country_index]
            new_entry$hip$sixties$population = df$population[country_index]
          } else if (df$decade[country_index]==1970) {
            new_entry$hip$seventies$count = df$count[country_index]
            new_entry$hip$seventies$population = df$population[country_index]
          } else if (df$decade[country_index]==1980) {
            new_entry$hip$eighties$count = df$count[country_index]
            new_entry$hip$eighties$population = df$population[country_index]
          } else if (df$decade[country_index]==1990) {
            new_entry$hip$nineties$count = df$count[country_index]
            new_entry$hip$nineties$population = df$population[country_index]
          } else if (df$decade[country_index]==2000) {
            new_entry$hip$twothousands$count = df$count[country_index]
            new_entry$hip$twothousands$population = df$population[country_index]
          } 
        } else if (df$genre_family[country_index]=="jazz") {
          if (df$decade[country_index]==1960) {
            new_entry$jazz$sixties$count = df$count[country_index]
            new_entry$jazz$sixties$population = df$population[country_index]
          } else if (df$decade[country_index]==1970) {
            new_entry$jazz$seventies$count = df$count[country_index]
            new_entry$jazz$seventies$population = df$population[country_index]
          } else if (df$decade[country_index]==1980) {
            new_entry$jazz$eighties$count = df$count[country_index]
            new_entry$jazz$eighties$population = df$population[country_index]
          } else if (df$decade[country_index]==1990) {
            new_entry$jazz$nineties$count = df$count[country_index]
            new_entry$jazz$nineties$population = df$population[country_index]
          } else if (df$decade[country_index]==2000) {
            new_entry$jazz$twothousands$count = df$count[country_index]
            new_entry$jazz$twothousands$population = df$population[country_index]
          } 
        } else if (df$genre_family[country_index]=="electro") {
          if (df$decade[country_index]==1960) {
            new_entry$electro$sixties$count = df$count[country_index]
            new_entry$electro$sixties$population = df$population[country_index]
          } else if (df$decade[country_index]==1970) {
            new_entry$electro$seventies$count = df$count[country_index]
            new_entry$electro$seventies$population = df$population[country_index]
          } else if (df$decade[country_index]==1980) {
            new_entry$electro$eighties$count = df$count[country_index]
            new_entry$electro$eighties$population = df$population[country_index]
          } else if (df$decade[country_index]==1990) {
            new_entry$electro$nineties$count = df$count[country_index]
            new_entry$electro$nineties$population = df$population[country_index]
          } else if (df$decade[country_index]==2000) {
            new_entry$electro$twothousands$count = df$count[country_index]
            new_entry$electro$twothousands$population = df$population[country_index]
          } 
        }
      }
    }
    final_entry <- list(country, new_entry)
    names(final_entry) <- c("name", "data")
    write(toJSON(final_entry, pretty = TRUE, auto_unbox = TRUE), 
          paste("./data/", toString(country),".txt",sep=""))
  }
}

create_json(joined_df)
merge_files(INPUT_FOLDER = "./data/", CONCAT_DELIMITER=",",
            OUTPUT_FILE = "music-data.txt")

file <- paste("[",read_file("music-data.txt"),"]",sep="")
write(file, "music-data.txt")
  
# Removes superfluous data frame
rm(albums)
rm(artists)
rm(albums_lite_choro)
rm(df_album)
rm(artists_lite_choro)

genre_df <- joined_df %>% select(-c(population))
genre_df <- aggregate(genre_df$count, 
                       by=list(genre_df$decade, genre_df$genre_family), 
                       FUN=sum)
genre_df <- genre_df %>% rename("decade"="Group.1", 
                                  "genre"="Group.2")

create_genre_json <- function(df) {
  
  entry <- list(rock=list(sixties=0,seventies=0,eighties=0,nineties=0,twothousands=0),
                metal=list(sixties=0,seventies=0,eighties=0,nineties=0,twothousands=0),
                punk=list(sixties=0,seventies=0,eighties=0,nineties=0,twothousands=0),
                country=list(sixties=0,seventies=0,eighties=0,nineties=0,twothousands=0),
                hip=list(sixties=0,seventies=0,eighties=0,nineties=0,twothousands=0),
                jazz=list(sixties=0,seventies=0,eighties=0,nineties=0,twothousands=0),
                electro=list(sixties=0,seventies=0,eighties=0,nineties=0,twothousands=0)
                )
  
  for (line in 1:nrow(df)) {
    if (df$decade[line]==1960){
      if (df$genre[line]=="rock"){
        entry$rock$sixties = entry$rock$sixties + df$x[line]
      } else if (df$genre[line]=="metal"){
        entry$metal$sixties = entry$metal$sixties + df$x[line]
      } else if (df$genre[line]=="punk"){
        entry$punk$sixties = entry$punk$sixties + df$x[line]
      } else if (df$genre[line]=="countryfolk"){
        entry$country$sixties = entry$country$sixties + df$x[line]
      } else if (df$genre[line]=="hiphop"){
        entry$hip$sixties = entry$hip$sixties + df$x[line]
      } else if (df$genre[line]=="jazz"){
        entry$jazz$sixties = entry$jazz$sixties + df$x[line]
      } else if (df$genre[line]=="electro"){
        entry$electro$sixties = entry$electro$sixties + df$x[line]
      }
    } else if (df$decade[line]==1970){
      if (df$genre[line]=="rock"){
        entry$rock$seventies = entry$rock$seventies + df$x[line]
      } else if (df$genre[line]=="metal"){
        entry$metal$seventies = entry$metal$seventies + df$x[line]
      } else if (df$genre[line]=="punk"){
        entry$punk$seventies = entry$punk$seventies + df$x[line]
      } else if (df$genre[line]=="countryfolk"){
        entry$country$seventies = entry$country$seventies + df$x[line]
      } else if (df$genre[line]=="hiphop"){
        entry$hip$seventies = entry$hip$seventies + df$x[line]
      } else if (df$genre[line]=="jazz"){
        entry$jazz$seventies = entry$jazz$seventies + df$x[line]
      } else if (df$genre[line]=="electro"){
        entry$electro$seventies = entry$electro$seventies + df$x[line]
      }
    } else if (df$decade[line]==1980){
      if (df$genre[line]=="rock"){
        entry$rock$eighties = entry$rock$eighties + df$x[line]
      } else if (df$genre[line]=="metal"){
        entry$metal$eighties = entry$metal$eighties + df$x[line]
      } else if (df$genre[line]=="punk"){
        entry$punk$eighties = entry$punk$eighties + df$x[line]
      } else if (df$genre[line]=="countryfolk"){
        entry$country$eighties = entry$country$eighties + df$x[line]
      } else if (df$genre[line]=="hiphop"){
        entry$hip$eighties = entry$hip$eighties + df$x[line]
      } else if (df$genre[line]=="jazz"){
        entry$jazz$eighties = entry$jazz$eighties + df$x[line]
      } else if (df$genre[line]=="electro"){
        entry$electro$eighties = entry$electro$eighties + df$x[line]
      }
    } else if (df$decade[line]==1990){
      if (df$genre[line]=="rock"){
        entry$rock$nineties = entry$rock$nineties + df$x[line]
      } else if (df$genre[line]=="metal"){
        entry$metal$nineties = entry$metal$nineties + df$x[line]
      } else if (df$genre[line]=="punk"){
        entry$punk$nineties = entry$punk$nineties + df$x[line]
      } else if (df$genre[line]=="countryfolk"){
        entry$country$nineties = entry$country$nineties + df$x[line]
      } else if (df$genre[line]=="hiphop"){
        entry$hip$nineties = entry$hip$nineties + df$x[line]
      } else if (df$genre[line]=="jazz"){
        entry$jazz$nineties = entry$jazz$nineties + df$x[line]
      } else if (df$genre[line]=="electro"){
        entry$electro$nineties = entry$electro$nineties + df$x[line]
      }
    } else if (df$decade[line]==2000){
      if (df$genre[line]=="rock"){
        entry$rock$twothousands = entry$rock$twothousands + df$x[line]
      } else if (df$genre[line]=="metal"){
        entry$metal$twothousands = entry$metal$twothousands + df$x[line]
      } else if (df$genre[line]=="punk"){
        entry$punk$twothousands = entry$punk$twothousands + df$x[line]
      } else if (df$genre[line]=="countryfolk"){
        entry$country$twothousands = entry$country$twothousands + df$x[line]
      } else if (df$genre[line]=="hiphop"){
        entry$hip$twothousands = entry$hip$twothousands + df$x[line]
      } else if (df$genre[line]=="jazz"){
        entry$jazz$twothousands = entry$jazz$twothousands + df$x[line]
      } else if (df$genre[line]=="electro"){
        entry$electro$twothousands = entry$electro$twothousands + df$x[line]
      }
    }
  }
  write(toJSON(entry),#, pretty = TRUE, auto_unbox = TRUE), 
        paste("./genre-summary.txt",sep=""))
}

create_genre_json(genre_df)

file <- paste("[",read_file("genre-summary.txt"),"]",sep="")
file <- str_replace(file, '\"rock\":', '{\"name\":\"rock\", \"data\":')
file <- str_replace(file, '\"metal\":', '{\"name\":\"metal\", \"data\":')
file <- str_replace(file, '\"punk\":', '{\"name\":\"punk\", \"data\":')
file <- str_replace(file, '\"country\":', '{\"name\":\"country\", \"data\":')
file <- str_replace(file, '\"hip\":', '{\"name\":\"hip\", \"data\":')
file <- str_replace(file, '\"jazz\":', '{\"name\":\"jazz\", \"data\":')
file <- str_replace(file, '\"electro\":', '{\"name\":\"electro\", \"data\":')
file <- str_replace_all(file, "\\},", "\\}\\},")
file <- str_replace(file, '\\[\\{\\{','\\[\\{')
write(file, "genre-summary.txt")

