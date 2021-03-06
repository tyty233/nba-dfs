rm(list=ls())
setwd("/Users/whitesi/Documents/Programming/Python/data_analyst_nd/nba-dfs")
setwd("/Users/cmt606/Documents/Ian/ME/nba-dfs")

##IMPORT PACKAGES
library(data.table)
library(dplyr)
library(dtplyr)
library(tidyr)
library(ggplot2)
source("dlin.R")
library(RColorBrewer)
library(reshape2)
library(corrplot)
source("roll_variable.R")
library(RcppRoll)
library(rms)
source("multiplot.R")
library(plyr)

##display.brewer.all() ##view all palettes with this
palette <- brewer.pal("YlGnBu", n=9)

#######################################
####### DATA IMPORT & CLEANING ########
#######################################

##read in data
player_data=read.csv("data/player_data.csv")
event_data=read.csv("data/event_data.csv")

##convert to data.tables
event_data=as.data.table(event_data)
player_data=as.data.table(player_data)

#rename and drop unnecessary columns
player_data[ ,c("X","sport") := NULL]
event_data[,X:=NULL]
setnames(player_data,old=c('X3FGA','X3FGM'),new=c('3FGA','3FGM'))

#get rid of duplicate rows in event_data
setkey(event_data,gameID)
event_data=unique(event_data)

#convert positions coded as 'F' to 'SF', 'G' to 'SG'
player_data[position=='F',position:='SF']
player_data[position=='G',position:='SG']

####################################
####### FEATURE ENGINEERING ########
####################################

##calculate fanduel points
player_data[,fd:=3*`3FGM`+2*(FGM-`3FGM`)+1*FTM+1.2*rebounds+1.5*assists+2*blocks+2*steals-1*turnovers]

##create a seaosn variable that can be used to distinguish between different seasons
player_data[,date:=as.Date(date)] ##convert string date to actual date
player_data[,date_num:=as.numeric(date)]
player_data[,season_code:=20122013]
player_data[date >= '2013-10-28' & date <= '2014-06-16', season_code:=20132014]
player_data[date >= '2014-10-28' & date <= '2015-06-16', season_code:=20142015]
player_data[date >= '2015-10-27' & date <= '2016-06-19', season_code:=20152016]

event_data = event_data %>% join(player_data[,.N,by=.(gameID,date)][,.(gameID,date)])

event_data[,date:=as.Date(date)] ##convert string date to actual date
event_data[,season_code:=20122013]
event_data[date >= '2013-10-28' & date <= '2014-06-16', season_code:=20132014]
event_data[date >= '2014-10-28' & date <= '2015-06-16', season_code:=20142015]
event_data[date >= '2015-10-27' & date <= '2016-06-19', season_code:=20152016]

# ##JOIN TABLES - FOR FUTURE USE OF EVENT_DATA
# setkey(player_data,gameID)
# setkey(event_data,gameID)
# players=player_data[event_data,nomatch=0]
# ##figure out why its size increased --get rid of dupes in event_data
# players[,player_count:=.N,by=.(gameID,player,position)][player_count>1]


##filter out players who didnt play
player_data=filter(player_data,minutes>0)

##get team info
team_data=event_data[,.(gameID,home_team,away_team)]
setkey(player_data,gameID)
setkey(team_data,gameID)
player_data=player_data[team_data,nomatch=0]

##create home/away variable
player_data[,homeaway:=1]
player_data[team==away_team,homeaway:=0]

##add rolling variables
window_size = seq(5,55,10)
player_data = player_data %>% group_by(player) %>% arrange(date) %>% roll_variable_mean(., 'fd', window_size)
player_data = player_data %>% group_by(player) %>% arrange(date) %>% roll_variable_mean(., 'minutes', window_size)
player_data = player_data %>% group_by(player) %>% arrange(date) %>% roll_variable_mean(., 'FGA', window_size)
player_data = player_data %>% group_by(player) %>% arrange(date) %>% roll_variable_mean(., 'FTA', window_size)

window_size = seq(1,3,1)
player_data = player_data %>% group_by(player) %>% arrange(date) %>% roll_variable_mean(., 'fd', window_size)
player_data = player_data %>% group_by(player) %>% arrange(date) %>% roll_variable_mean(., 'minutes', window_size)
player_data = player_data %>% group_by(player) %>% arrange(date) %>% roll_variable_mean(., 'FGA', window_size)
player_data = player_data %>% group_by(player) %>% arrange(date) %>% roll_variable_mean(., 'FTA', window_size)

##BACK TO BACK GAME VARIABLE
days_rest=player_data[,.N,by=.(team,date_num)][,.(team,date_num)][order(team,date_num)]
days_rest$date_diff=ave(days_rest$date_num, days_rest$team, FUN=function(x) c(10, diff(x)))
days_rest$b2b=ifelse(days_rest$date_diff==1,1,0)

##add opponent field
player_data[,opponent:=home_team]
player_data[team==home_team,opponent:=away_team]

##join b2b,opp_b2b
setkey(player_data,team,date_num)
setkey(days_rest,team,date_num)
player_data=player_data[days_rest[,.(team,date_num,b2b)],nomatch=0]

days_rest[,opp_b2b:=b2b][,b2b:=NULL]
setkey(player_data,opponent,date_num)
player_data=player_data[days_rest[,.(team,date_num,opp_b2b)],nomatch=0]

##one-encoding for position
player_data[, `:=` (pg = 0,sg = 0,sf = 0,pf = 0,c = 0)]
player_data[position == 'PG', pg := 1]
player_data[position == 'SG', sg := 1]
player_data[position == 'SF', sf := 1]
player_data[position == 'PF', pf := 1]
player_data[position == 'C', c := 1]

###TEAM BASED DATA
##currently the event data table has one record per game, with statistics for each team
colnames(event_data)


##calculate final scores for each game
event_data[,home_score:=sum(home_Q1,home_Q2,home_Q3,home_Q4,home_Q5,home_Q6,home_Q7,home_Q8,na.rm=TRUE),
           by=1:NROW(event_data)]
event_data[,away_score:=sum(away_Q1,away_Q2,away_Q3,away_Q4,away_Q5,away_Q6,away_Q7,away_Q8,na.rm=TRUE),
           by=1:NROW(event_data)]

##to calculate team based statistics, a data frame/table with 2 records per game -
##[cont'd] one for each team, is ideal
##the code below splits the event_data table into two tables, one for each team,
##[cont'd] standardizes the variable names, and then joins the two tables back together
team_variables= c('3FGA','3FGM','FGM','FGA','FTA','FTM',
                  'Q1','Q2','Q3','Q4','Q5','Q6','Q7',
                  'Q8','assists','blocks','fouls',
                  'points','rebounds','steals','turnovers')

away_variables= paste0('away_',team_variables)
home_variables= paste0('home_',team_variables)

##data table for the home team of each game
event_data_1=event_data[,team:=home_team][,setdiff(colnames(event_data),away_variables),with=FALSE]
##data table for hte away team of each game
event_data_2=event_data[,team:=away_team][,setdiff(colnames(event_data),home_variables),with=FALSE]

##change the column names to generic names (i.e. away_FGM --> FGM,home_FTA --> FTA)
setnames(event_data_1,old=home_variables,new=team_variables)
setnames(event_data_2,old=away_variables,new=team_variables)

##join the two tables back together
team_data=rbind(event_data_1,event_data_2)

##add date to team_data
setkey(team_data,gameID)
setkey(player_data,gameID)
team_data=team_data[player_data[,.N,by=.(gameID,date_num)][,.(gameID,date_num)],nomatch=0][order(date_num)]

##define opponent in team_data table
team_data[,opponent:=home_team]
team_data[team==home_team,opponent:=away_team]

###team total FD points
team_tot_fd=player_data[,.(team_fd=sum(fd)),by=.(gameID,team)]
setkey(team_tot_fd,gameID,team)
setkey(player_data,gameID,team)
setkey(team_data,gameID,team)
player_data=player_data[team_tot_fd,nomatch=0]
team_data=team_data[team_tot_fd,nomatch=0]
  
###opponent total FD points
team_tot_fd[,`:=` (opponent = team, team = NULL,opp_fd=team_fd,team_fd=NULL)]
setkey(team_tot_fd,gameID,opponent)
setkey(player_data,gameID,opponent)
setkey(team_data,gameID,opponent)
player_data=player_data[team_tot_fd,nomatch=0]
team_data=team_data[team_tot_fd,nomatch=0]

###opponent rebounds and turnovers
opp_stats = team_data[,.(team,rebounds,turnovers)]
opp_stats[,`:=` (opponent = team, team = NULL)]

##position points summary
##calculate the total FD points for each team by position
##in some cases, teams played w/o a center. for those, use the post statistic (p_fd)
posn_sum=player_data[,.(posn_points=sum(fd)),by=.(gameID,team,position)]
posn_sum=posn_sum[,.(pg_fd=sum(ifelse(position=='PG',posn_points,0)),
                     sg_fd=sum(ifelse(position=='SG',posn_points,0)),
                     sf_fd=sum(ifelse(position=='SF',posn_points,0)),
                     pf_fd=sum(ifelse(position=='PF',posn_points,0)),
                     c_fd=sum(ifelse(position=='C',posn_points,0)),
                     g_fd=sum(ifelse(position %in% c('PG','SG','SF'),posn_points,0)),
                     p_fd=sum(ifelse(position %in% c('PF','C'),posn_points,0))),
                     by=.(gameID,team)]


##merge positional points with team_data
setkey(posn_sum,gameID,team)
setkey(team_data,gameID,team)
team_data=team_data[posn_sum,nomatch=0]

##get team opponent data
team_data_opp=team_data[,.(gameID,team,pg_fd,sg_fd,sf_fd,pf_fd,c_fd,g_fd,p_fd,team_fd)]
setnames(team_data_opp,old=c("team","pg_fd","sg_fd","sf_fd","pf_fd","c_fd","g_fd","p_fd","team_fd"),
         new=c("opponent","opp_pg_fd","opp_sg_fd","opp_sf_fd","opp_pf_fd","opp_c_fd","opp_g_fd","opp_p_fd","opp_fd"))
setkey(team_data,gameID,opponent)
setkey(team_data_opp,gameID,opponent)
team_data=team_data[team_data_opp,nomatch=0]

##rolling team statistics
##the following stat describes how many fantasy points a team has been giving up to opposing teams,
##...[cont'd] expressed as rolling averages over the last X games
team_data=team_data %>% group_by(team) %>% arrange(date_num) %>% roll_variable_mean(., 'opp_fd', window_size)
team_data=team_data %>% group_by(team) %>% arrange(date_num) %>% roll_variable_mean(., 'opp_g_fd', window_size)
team_data=team_data %>% group_by(team) %>% arrange(date_num) %>% roll_variable_mean(., 'opp_p_fd', window_size)

##join these features to player_data
##join team_data "team" on player_data "opponent"
rolling_team_variables= colnames(team_data)[grepl('fd_\\w*\\d', colnames(team_data))]
player_data=merge(player_data, team_data[,append(rolling_team_variables,c("gameID","team")),with=FALSE], 
                  by.x=c('gameID','opponent'), by.y=c('gameID','team'), all=FALSE)




##############################
######## Modelling ###########
##############################


min_variables = colnames(player_data)[grepl('minutes_\\w*\\d', colnames(player_data))]
fd_variables = colnames(player_data)[grepl('fd_\\w*\\d', colnames(player_data))]
fta_variables = colnames(player_data)[grepl('FTA_\\w*\\d', colnames(player_data))]
fga_variables = colnames(player_data)[grepl('FGA_\\w*\\d', colnames(player_data))]
pos_feature = c('pg','sg','sf','pf','c')
  
base_variables = c("fd_1","fd_2","fd_3","fd_5","fd_15","fd_25","fd_35","fd_45","fd_55")
all_variables = c(fd_variables,min_variables,fta_variables,fga_variables,
                    'b2b','opp_b2b','homeaway','starter',pos_feature)

##filter training on players with fd>0???
training = player_data[season_code != 20152016]
test = player_data[season_code == 20152016]
ytest = select(test, gameID, player, fd)

####### BASE MODEL  #########
fmla = reformulate(base_variables, response='fd')

#get model stats
mdl=lm(fmla, data = training)
mdl %>% summary

#test model on test data
ytest$mdl = predict(mdl, test)

lm(fd ~ mdl, data = ytest) %>% summary


####### MODEL 1 #########
fmla1 = reformulate(all_variables, response='fd')

#get model stats
mdl1=lm(fmla1, data = training)
mdl1 %>% summary

#test model on test data
ytest$mdl1 = predict(mdl1, test)
lm(fd ~ mdl1, data = ytest) %>% summary


######  MODEL 2 #########

mdl2 = Glm(fmla1,data = training)

vars_kept = fastbw(mdl2, k.aic = 1.5)$names.kept

mdl2 = lm(reformulate(vars_kept, response = 'fd'), data = training)

mdl2 %>% summary

#test model on test data
ytest$mdl2 = predict(mdl2, test)
lm(fd ~ mdl2, data = ytest) %>% summary


##############################
##### UNIVARIATE PLOTS #######
##############################

glimpse(player_data)
##comment on data

ggplot(player_data,aes(fd)) + geom_histogram(binwidth = 1) + theme_dlin() +
  labs(title = 'NBA Fanduel Points Histogram')

summary(player_data$fd)

###comments - you can get -ive points. the distribution is positively skewed

ggplot(player_data[position %in% c('PG','SG','SF','PF','C'),],aes(position)) + geom_bar() + theme_dlin() +
  labs(title = 'NBA Positions Histogram')

##comments - less centers compared to other positions
##number of players at each position per team per game
player_data[position %in% c('PG','SG','SF','PF','C'),][,.(avg_per_game=.N/(NROW(event_data) *2)),by = position]


# How many games go to OT?
dat = melt(event_data[ , `:=` (Regular = sum(ifelse(is.na(home_Q4),0,1)), Single_OT = sum(ifelse(is.na(home_Q5),0,1)),
                          Double_OT = sum(ifelse(is.na(home_Q6),0,1)), Triple_OT = sum(ifelse(is.na(home_Q7),0,1)),
                          Quad_OT = sum(ifelse(is.na(home_Q8),0,1)))][,.(Regular,Single_OT,Double_OT,Triple_OT,Quad_OT)][0:1])

colnames(dat) = c("Game_Length", "count")

dat$fraction = dat$count / sum(dat$count)
dat = dat[order(dat$fraction), ]
dat$ymax = cumsum(dat$fraction)
dat$ymin = c(0, head(dat$ymax, n=-1))
dat$percentage = round(dat$count / sum(dat$count)* 100,2)

ggplot(dat, aes(fill=Game_Length, ymax=ymax, ymin=ymin, xmax=4, xmin=3)) +
  geom_rect(colour="grey30") +
  coord_polar(theta="y") +
  xlim(c(0, 4)) +
  theme_dlin() +
  theme(panel.grid=element_blank()) +
  theme(axis.text=element_blank()) +
  theme(axis.ticks=element_blank()) +
  labs(title="Fraction of NBA Games in OT: 2012-2015")

dat[,.(Game_Length,percentage)]

###minutes played 

##facet grid one of the rolling variable features to show its similar to the un-rolled feature 
p1 = ggplot(player_data,aes(minutes_5)) + geom_histogram(binwidth = 1) + theme_dlin() +
  labs(title = 'NBA Rolling Minutes Played Histogram')

p2 = ggplot(player_data,aes(minutes_15)) + geom_histogram(binwidth = 1) + theme_dlin()

p3 = ggplot(player_data,aes(minutes_25)) + geom_histogram(binwidth = 1) + theme_dlin()

multiplot(p1, p2, p3, cols=1)




##multiple variable distribution plots
##code from http://stackoverflow.com/questions/13035834/plot-every-column-in-a-data-frame-as-a-histogram-on-one-page-using-ggplotcoz

cols = c("3FGM","FGM","FTM","rebounds","assists","blocks","steals","turnovers","fouls")

pg = melt(player_data[position == 'PG', cols, with=FALSE])
ggplot(pg,aes(x = value)) + theme_dlin() + facet_wrap(~variable,scales = "free_x") + geom_histogram(binwidth = 0.5) +
        labs(title = 'Point Guards')

sg = melt(player_data[position == 'SG', cols, with=FALSE])
ggplot(sg,aes(x = value)) + theme_dlin() + facet_wrap(~variable,scales = "free_x") + geom_histogram(binwidth = 0.5) +
  labs(title = 'Shooting Guards')

sf = melt(player_data[position == 'SF', cols, with=FALSE])
ggplot(sf,aes(x = value)) + theme_dlin() + facet_wrap(~variable,scales = "free_x") + geom_histogram(binwidth = 0.5) +
  labs(title = 'Small Forwards')

pf = melt(player_data[position == 'PF', cols, with=FALSE])
ggplot(pf,aes(x = value)) + theme_dlin() + facet_wrap(~variable,scales = "free_x") + geom_histogram(binwidth = 0.5) +
  labs(title = 'Power Forwards')

c = melt(player_data[position == 'C', cols, with=FALSE])
ggplot(c,aes(x = value)) + theme_dlin() + facet_wrap(~variable,scales = "free_x") + geom_histogram(binwidth = 0.5) +
  labs(title = 'Center')

##box plot of fd points by position 

##new feature variables
##b2b,opp_b2b,team_fd, rolling variables

summary(player_data$minutes_5)
##comment on na's

summary(player_data$b2b)


##############################
##### UNIVARIATE ANALYSIS ####
##############################

# What is the structure of your dataset?
# What is/are the main feature(s) of interest in your dataset?
# What other features in the dataset do you think will help support your investigation into your feature(s) of interest?
# Did you create any new variables from existing variables in the dataset?
# --> could look at distrbn of home/away for sanity check
# Of the features you investigated, were there any unusual distributions? Did you perform any operations on the data to tidy, adjust, or change the form of the data? If so, why did you do this?


##############################
###### BIVARIATE PLOTS #######
##############################

##depth at position
team_depth = player_data[, .(pos_depth=.N - 1) ,by=.(gameID,team,position)][order(gameID,team,position)]
player_data = player_data %>% inner_join(team_depth)

##minutes
ggplot(player_data,aes(x = minutes, y = fd)) + geom_point(colour=palette[5]) + theme_dlin() +
  labs(title = 'NBA Fanduel Points versus minutes', x = 'minutes', y = 'fanduel points') +
  geom_smooth(method = "lm", se = FALSE,colour='black') + 
  geom_text(aes(label = paste("R^2: ",mean(r2$r2),sep="")),parse=T,x=20,y=20)

##labelled R2s on plot
d<-data.frame(cat = sample(c("a","b","c"),100,replace=T), xval=seq_len(100), yval = rnorm(100))
r2<-ddply(player_data,.(position),function(x) summary(lm(x$fd ~ x$minutes))$r.squared)
names(r2)<-c("position","r2")
g<-ggplot(d, aes(x = xval, y = yval, group = cat))+geom_point(aes(color=cat))
g<-g+geom_smooth(method="lm",aes(color=cat),se=F)
g+geom_text(data=r2,aes(color=cat, label = paste("R^2: ", r2,sep="")),parse=T,x=100,y=c(1,1.25,1.5), show_guide=F)


##minutes vs depth at pos
ggplot(player_data,aes(x = pos_depth, y = minutes)) + geom_point(colour=palette[5]) + theme_dlin() +
  labs(title = 'NBA Fanduel Points versus minutes', x = 'pos_depth', y = 'minutes') +
  geom_smooth(method = "lm", se = FALSE,colour='black')

##INSPECT pos_depth > 5
View(player_data[pos_depth > 5]) ##-->duplicate player records
##get all dupes
View(player_data[,.(count=.N),by=.(gameID,team,player)][count>1,.(gameID,player)])
nrow(player_data[,.(count=.N),by=.(gameID,team,player)][count>1,.(gameID,player)])

##define player efficiency as fd points per minute
player_data[,eff := fd/minutes]

ggplot(player_data,aes(x = eff, y = fd)) + geom_point(colour=palette[5]) + theme_dlin() +
  labs(title = 'NBA Fanduel Points versus minutes', x = 'minutes', y = 'fanduel points')

##examine some outliers
View(player_data[eff>3,.(gameID,player,minutes,fd,`3FGM`,FGM,FTM,rebounds,assists,blocks,steals,turnovers)][0:10])
#--> all players played <3 minutes

##filter and re-plot
ggplot(player_data[minutes>5,],aes(x = eff, y = fd)) + geom_point(colour=palette[5]) + theme_dlin() +
  labs(title = 'NBA Fanduel Points versus minutes', x = 'FD Points Per Minute (Efficiency)', y = 'fanduel points') +
  geom_smooth(method = "lm", se = FALSE,colour='black')

##starter
ggplot(player_data,aes(x = starter, y = fd)) + geom_point(colour=palette[5]) + theme_dlin() +
  labs(title = 'NBA Fanduel Points - Effect of Starting', x = 'starter (binary)', y = 'fanduel points') +
  geom_smooth(method = "lm", se = FALSE,colour='black')


##corrplot - general
M=cor(player_data[,.(fd,minutes,starter,homeaway,fouls,FGA,pos_depth)])
corrplot.mixed(M,lower="number",upper='circle')

##corrplot - rolling variables
M2=cor(player_data[is.na(fd_1) == FALSE & is.na(fd_2) == FALSE & is.na(fd_3) == FALSE &
                     is.na(fd_5) == FALSE & is.na(fd_15) == FALSE & is.na(fd_25) == FALSE & 
                     is.na(fd_35) == FALSE & is.na(fd_55) == FALSE,
                   .(fd,fd_1,fd_2,fd_3,fd_5,fd_15,fd_25,fd_35,fd_55)])

corrplot.mixed(M2,lower="number",upper='circle')

M3=cor(player_data[is.na(minutes_1) == FALSE & is.na(minutes_2) == FALSE & is.na(minutes_3) == FALSE &
                     is.na(minutes_5) == FALSE & is.na(minutes_15) == FALSE & is.na(minutes_25) == FALSE & 
                     is.na(minutes_35) == FALSE & is.na(minutes_55) == FALSE,
                   .(fd,minutes_1,minutes_2,minutes_3,minutes_5,minutes_15,minutes_25,minutes_35,minutes_55)])

corrplot.mixed(M3,lower="number",upper='circle')


##homeaway
ggplot(player_data,aes(x = homeaway, y = fd)) + geom_point(colour=palette[5]) + theme_dlin() +
  labs(title = 'NBA Fanduel Points - Effect of Playing at Home', x = 'home or away (binary)', y = 'fanduel points') +
  geom_smooth(method = "lm", se = FALSE,colour='black')

##b2b 
ggplot(player_data,aes(x = b2b, y = fd)) + geom_point(colour=palette[5]) + theme_dlin() +
  labs(title = 'NBA Fanduel Points - Effect of Playing at Home', x = 'back-to-back game (binary)', y = 'fanduel points') +
  geom_smooth(method = "lm", se = FALSE,colour='black')


##minutes played by position
ggplot(player_data,aes(factor(position),minutes)) + geom_boxplot() + theme_dlin() +
  labs(title = 'NBA Minutes Played By Position')

##points scored by position (revisited)
ggplot(player_data,aes(factor(position),fd)) + geom_boxplot() + theme_dlin() +
  labs(title = 'NBA Fanduel Points By Position')

##points scored by team
ggplot(player_data[season_code==20152016,.N,by=.(gameID,team,team_fd)],aes(reorder(factor(team),-team_fd,median),team_fd)) + geom_boxplot() + theme_dlin() +
  labs(title = 'NBA Fanduel Points By Team for the 2015-2016 Season',x='team',y='team total fanduel points') + 
  theme(axis.text.x = element_text(angle = 90, hjust = 1))

##points allowed by team
ggplot(team_data[season_code==20122013,.N,by=.(gameID,team,opp_fd)],aes(reorder(factor(team),-opp_fd,median),opp_fd)) + geom_boxplot() + theme_dlin() +
  labs(title = 'FD Points Allowed by Team for the 2015-2016 Season',x='team',y='team total allowed fanduel points') + 
  theme(axis.text.x = element_text(angle = 90, hjust = 1))

##STACKING
##player point correlations
C1 = cor(player_data[,.(fd,team_fd,opp_fd)])
C2 = cor(team_data[,.(pg_fd,sg_fd,sf_fd,pf_fd,c_fd,team_fd,opp_fd)])
C3 = cor(team_data[,.(pg_fd,sg_fd,sf_fd,pf_fd,c_fd,
                      opp_pg_fd,opp_sg_fd,opp_sf_fd,opp_pf_fd,opp_c_fd)])
C4 = cor(team_data[,.(g_fd,p_fd,opp_g_fd,opp_p_fd)])

corrplot.mixed(C3,lower="number",upper='circle',col=col2(10))
##do correlation among starters??
dcast(player_data[gameID=='20121030-boston-celtics-at-miami-heat' & starter ==1,
                  .(team,fd,position)],team ~ position,fun.aggregate = min, value.var = team)

##effect of high scoring games
player_data = player_data %>% inner_join(event_data[,.(gameID,home_score,away_score)])
player_data[,team_score := home_score]
player_data[team == away_team, team_score := away_score]

player_data[, score_bucket := 1]
player_data[team_score > 75, score_bucket := 2]
player_data[team_score > 100, score_bucket := 3]
player_data[team_score > 125, score_bucket := 4]

ggplot(player_data[,.(mean_fd = mean(fd)),by = score_bucket],aes(x = score_bucket, y = mean_fd)) + 
  geom_point(colour=palette[5]) + theme_dlin() +
  labs(title = 'NBA Fanduel Points - Effect of High Scoring Games', x = 'score bucket', y = 'average fanduel points') +
  geom_smooth(method = "lm", se = FALSE,colour='black')


##############################
##### MULTIVARIATE PLOTS #####
##############################

##points allowed by team over seasons
ggplot(team_data[,.(mean_opp_fd = mean(opp_fd)),by=.(season_code,team)],
       aes(factor(team),mean_opp_fd,colour=factor(season_code),shape=factor(season_code))) + geom_point() + 
  theme_dlin() + facet_grid(season_code~.) +
  labs(title = 'FD Points Allowed by Team',x='team',y='average fanduel points') + 
  theme(axis.text.x = element_text(angle = 90, hjust = 1))

team_data[,.(mean_opp_fd = mean(opp_fd)),by=.(season_code,team)][order(season_code,mean_opp_fd)]

##points scored by team over seasons
ggplot(team_data[,.(mean_team_fd = mean(team_fd)),by=.(season_code,team)],
       aes(factor(team),mean_team_fd,colour=factor(season_code),shape=factor(season_code))) + geom_point() + 
  theme_dlin() + facet_grid(season_code~.) +
  labs(title = 'FD Points Scored by Team',x='team',y='average fanduel points') + 
  theme(axis.text.x = element_text(angle = 90, hjust = 1))

team_data[,.(mean_team_fd = mean(team_fd)),by=.(season_code,team)][order(season_code,mean_team_fd)]

##points allowed by team to each position, do one coloured dot for each position
pa_pos = team_data[season_code==20122013,.(opp_pg_fd = mean(opp_pg_fd), opp_sg_fd = mean(opp_sg_fd),
                                  opp_sf_fd = mean(opp_sf_fd),opp_pf_fd = mean(opp_pf_fd),opp_c_fd = mean(opp_c_fd)),
          by = .(season_code,team)]

pa_pos = melt(pa_pos,id.vars = c('season_code','team'))

ggplot(pa_pos[season_code==20122013,],aes(factor(team),value,colour=factor(variable),shape=factor(variable))) + geom_point() + theme_dlin() +
  labs(title = 'NBA Fanduel Points Allowed by Team for the 2015-2016 Season',x='team',y='team mean total allowed fanduel points') + 
  theme(axis.text.x = element_text(angle = 90, hjust = 1))

##lebrons points against certain teams
lebron = player_data[player == 'LeBron James',.(mean_fd = mean(fd), count = .N), by = .(opponent,season_code)]

ggplot(lebron,aes(reorder(factor(opponent),-mean_fd),mean_fd,colour=factor(season_code),shape=factor(season_code))) + geom_point() + 
  theme_dlin() + facet_grid(season_code~.) +
  labs(title = 'LeBron James Average Fanduel Points Against Each Team',x='team',y='average fanduel points') + 
  theme(axis.text.x = element_text(angle = 90, hjust = 1))


##USEFUL Funcs
summary(player_data)
summary(player_data)
dim(player_data) ##dim[1]=nrows, dim[2]=ncolumns


###FEATURES TO ADD
##try and quantify injuries as lost shot attempts that will become available!
##defensive efficiency statistic (points allowed, FGA allowed, points allowed to each posn)
##usage rate
##points per minute
##weak rebounding teams? (especially important for centers..opp_rebounds allowed feature)
##teams with lots of turnovers??
##starter is resting/injured.

##trailing turnovers
##trailing points (actual basketball points)

##MODELLING
##look at your notes file, and look at DFN site for other ideas
##two models: guards and centers 


##OTHER IDEAS
##explore covariance...versus teammates, versus opponents
##PLOT FD VS OT!!
##plot FD vs high scoring games
##plot distributino of FD points allowed by team vs. average (facet grid with season!)
##

