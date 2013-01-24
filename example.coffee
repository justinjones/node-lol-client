LolClient = require('./lol-client')
util = require('util')

# Config stuff
options =
  region: 'na' # Lol Client region, one of 'na', 'euw' or 'eune'
  username: 'your_leagueoflegends_username' # must be lowercase!
  password: 'your_leagueoflegends_password'
  version: '1.74.13_01_14_16_57' # Lol Client version - must be "current" or it wont work. This is correct as at 24/01/2013

summoner = {
  name: 'HotshotGG', # summoners name
  acctId: 434582, # returned from getSummonerByName and getSummonerById
  summonerId: 407750 # returned from getSummonerByName
  teamId: "TEAM-a1ebba15-986f-488a-ae2f-e081b2886ba4" # teamIds can be gotten from getTeamsForSummoner
}

client = new LolClient(options)

# Listen for a successful connection event
client.on 'connection', ->
  console.log 'Connected'
  
  # Now do stuff!
  client.getSummonerByName summoner.name, (err, result) ->
    console.log util.inspect(result, false, null, true)

  client.getSummonerStats summoner.acctId, (err, result) ->
    console.log util.inspect(result, false, null, true)

  client.getMatchHistory summoner.acctId, (err, result) ->
    console.log util.inspect(result, false, null, true)

  client.getAggregatedStats summoner.acctId, (err, result) ->
    console.log util.inspect(result, false, null, true)

  client.getTeamsForSummoner summoner.summonerId, (err, result) ->
    console.log util.inspect(result, false, null, true)

  client.getTeamById summoner.teamId, (err, result) ->
    console.log util.inspect(result, false, null, true)
    
  client.getSummonerData summoner.acctId, (err, result) ->
    console.log util.inspect(result, false, null, true)

client.connect() # Perform connection
