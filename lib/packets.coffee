uuid = require('node-uuid')

Encoder = require('namf/amf0').Encoder
Decoder = require('namf/amf0').Decoder
ASObject = require('namf/messaging').ASObject

class Packet
  constructor: (@options) ->

class ConnectPacket extends Packet
  appObject: () ->
    object =
      app: ''
      flashVer: 'WIN 10,1,85,3'
      swfUrl: 'app:/mod_ser.dat',
      tcUrl: 'rtmps://beta.lol.riotgames.com:2099',
      fpad: false,
      capabilities: 239,
      audioCodecs: 3191,
      videoCodecs: 252,
      videoFunction: 1,
      pageUrl: undefined,
      objectEncoding: 3
    return object
  
  commandObject: () ->
    object = new ASObject()
    object.name = 'flex.messaging.messages.CommandMessage'
    object.object =
      operation: 5,
      correlationId: '',
      timestamp: 0,
      clientId: null,
      timeToLive: 0,
      messageId: '9DC6600E-8F54-604F-AB39-1515B4CBE8AA', # generate uuid
      #messageId: uuid().toUpperCase()
      destination: '',
      headers: { DSMessagingVersion: 1, DSId: 'my-rtmps' },
      body: {}
    return object
    
class LoginPacket extends Packet
  constructor: () ->
    super
    console.log @options

  generate: (clientVersion) ->
    object = new ASObject()
    object.name = 'flex.messaging.messages.RemotingMessage'
    object.keys = ['operation', 'source', 'timestamp', 'clientId', 'timeToLive', 'messageId', 'destination', 'headers', 'body']
    object.object =
      operation: 'login'
      source: null
      timestamp: 0
      clientId: null
      timeToLive: 0
      messageId: uuid().toUpperCase()
      destination: 'loginService'
      headers: @generateHeaders()
      body: [@generateBody(clientVersion)]
    object.encoding = 0
    return object

  generateHeaders: () ->
    headers = new ASObject()
    headers.name = ''
    headers.object =
      DSId: @options.dsid
      DSRequestTimeout: 60
      DSEndpoint: 'my-rtmps'
    headers.encoding = 2
    return headers

  generateBody: (clientVersion = '1.48.11_11_14_04_20') ->
    body = new ASObject()
    body.name = 'com.riotgames.platform.login.AuthenticationCredentials'
    body.keys = ['oldPassword', 'password', 'authToken', 'locale', 'partnerCredentials', 'ipAddress', 'domain', 'username', 'clientVersion', 'securityAnswer']
    body.object =
      oldPassword: null,
      password: @options.password
      authToken: @options.queueToken
      #authToken: '2ca02ca5-1c75-4103-976d-20ab45f1fc79' # auth token from the login q request?
      locale: 'en_US'
      partnerCredentials: null
      ipAddress: '203.59.95.218'
      domain: 'lolclient.lol.riotgames.com'
      username: @options.username
      clientVersion: clientVersion
      securityAnswer: null
    body.encoding = 0
    return body

class AuthPacket extends Packet
  generate: () ->
    object = new ASObject()
    object.name = 'flex.messaging.messages.CommandMessage'
    object.keys = ['operation', 'correlationId', 'timestamp', 'clientId', 'timeToLive', 'messageId', 'destination', 'headers', 'body']
    object.object =
      operation: 8
      correlationId: ''
      timestamp: 0
      clientId: null
      timeToLive: 0
      messageId: uuid().toUpperCase()
      destination: 'auth'
      headers: @generateHeaders()
      body: new Buffer("#{@options.username}:#{@options.authToken}", 'utf8').toString('base64')
    object.encoding = 0
    return object

  generateHeaders: () ->
    headers = new ASObject()
    headers.name = ''
    headers.object =
      DSId: @options.dsid
      DSRequestTimeout: 60
      DSEndpoint: 'my-rtmps'
    headers.encoding = 2
    return headers

class HeartbeatPacket extends Packet
  counter: 1
  generate: () ->
    object = new ASObject()
    object.name = 'flex.messaging.messages.RemotingMessage'
    object.keys = ['operation', 'source', 'timestamp', 'clientId', 'timeToLive', 'messageId', 'destination', 'headers', 'body']
    object.object =
      operation: 'performLCDSHeartBeat'
      source: null
      timestamp: 0
      clientId: null
      timeToLive: 0
      messageId: uuid().toUpperCase()
      destination: 'loginService'
      headers: @generateHeaders()
      body: [@options.acctId, @options.authToken, @counter, new Date().toString()[0..-7]]
    object.encoding = 0
    @counter += 1
    return object

  generateHeaders: () ->
    headers = new ASObject()
    headers.name = ''
    headers.object =
      DSId: @options.dsid
      DSRequestTimeout: 60
      DSEndpoint: 'my-rtmps'
    headers.encoding = 2
    return headers


class LookupPacket extends Packet
  generate: (name) ->
    object = new ASObject()
    object.name = 'flex.messaging.messages.RemotingMessage'
    object.keys = ['source', 'operation', 'timestamp', 'messageId', 'clientId', 'timeToLive', 'body', 'destination', 'headers']
    object.object =
      operation: 'getSummonerByName'
      source: null
      timestamp: 0
      clientId: null
      timeToLive: 0
      messageId: uuid().toUpperCase()
      destination: 'summonerService'
      headers: @generateHeaders()
      body: [name]
    object.encoding = 0
    return object

  generateHeaders: () ->
    headers = new ASObject()
    headers.name = ''
    headers.object =
      DSId: @options.dsid
      DSRequestTimeout: 60
      DSEndpoint: 'my-rtmps'
    headers.encoding = 2
    return headers

class GetSummonerDataPacket extends Packet
  generate: (acctId) ->
    object = new ASObject()
    object.name = 'flex.messaging.messages.RemotingMessage'
    object.keys = ['source', 'operation', 'timestamp', 'messageId', 'clientId', 'timeToLive', 'body', 'destination', 'headers']
    object.object =
      operation: 'getAllPublicSummonerDataByAccount'
      source: null
      timestamp: 0
      clientId: null
      timeToLive: 0
      #messageId: 'FE149B94-2373-9F75-3EDE-1515B4A47763' # generate a uuid
      messageId: uuid().toUpperCase()
      destination: 'summonerService'
      headers: @generateHeaders()
      body: [acctId]
    object.encoding = 0
    return object

  generateHeaders: () ->
    headers = new ASObject()
    headers.name = ''
    headers.object =
      DSId: @options.dsid
      DSRequestTimeout: 60
      DSEndpoint: 'my-rtmps'
    headers.encoding = 2
    return headers

class AggregatedStatsPacket extends Packet
  generate: (acctId) ->
    object = new ASObject()
    object.name = 'flex.messaging.messages.RemotingMessage'
    object.keys = ['source', 'operation', 'timestamp', 'messageId', 'clientId', 'timeToLive', 'body', 'destination', 'headers']
    object.object =
      operation: 'getAggregatedStats'
      source: null
      timestamp: 0
      clientId: null
      timeToLive: 0
      #messageId: 'FE149B94-2373-9F75-3EDE-1515B4A47763' # generate a uuid
      messageId: uuid().toUpperCase()
      destination: 'playerStatsService'
      headers: @generateHeaders()
      body: [acctId, 'CLASSIC', 'CURRENT']
    object.encoding = 0
    return object

  generateHeaders: () ->
    headers = new ASObject()
    headers.name = ''
    headers.object =
      #DSId: 'B676FABB-A938-8A67-F7DF-9D922DE0CF4A' # ds id from connect request
      DSId: @options.dsid
      DSRequestTimeout: 60
      DSEndpoint: 'my-rtmps'
    headers.encoding = 2
    return headers

class PlayerStatsPacket extends Packet
  generate: (acctId) ->
    object = new ASObject()
    object.name = 'flex.messaging.messages.RemotingMessage'
    object.keys = ['source', 'operation', 'timestamp', 'messageId', 'clientId', 'timeToLive', 'body', 'destination', 'headers']
    object.object =
      operation: 'retrievePlayerStatsByAccountId'
      source: null
      timestamp: 0
      clientId: null
      timeToLive: 0
      #messageId: 'FE149B94-2373-9F75-3EDE-1515B4A47763' # generate a uuid
      messageId: uuid().toUpperCase()
      destination: 'playerStatsService'
      headers: @generateHeaders()
      body: [acctId, 'CURRENT']
    object.encoding = 0
    return object

  generateHeaders: () ->
    headers = new ASObject()
    headers.name = ''
    headers.object =
      #DSId: 'B676FABB-A938-8A67-F7DF-9D922DE0CF4A' # ds id from connect request
      DSId: @options.dsid
      DSRequestTimeout: 60
      DSEndpoint: 'my-rtmps'
    headers.encoding = 2
    return headers

class RecentGames extends Packet
  generate: (acctId) ->
    object = new ASObject()
    object.name = 'flex.messaging.messages.RemotingMessage'
    object.keys = ['source', 'operation', 'timestamp', 'messageId', 'clientId', 'timeToLive', 'body', 'destination', 'headers']
    object.object =
      operation: 'getRecentGames'
      source: null
      timestamp: 0
      clientId: null
      timeToLive: 0
      #messageId: 'FE149B94-2373-9F75-3EDE-1515B4A47763' # generate a uuid
      messageId: uuid().toUpperCase()
      destination: 'playerStatsService'
      headers: @generateHeaders()
      body: [acctId]
    object.encoding = 0
    return object

  generateHeaders: () ->
    headers = new ASObject()
    headers.name = ''
    headers.object =
      DSId: @options.dsid
      DSRequestTimeout: 60
      DSEndpoint: 'my-rtmps'
    headers.encoding = 2
    return headers

class GetTeamForSummoner extends Packet
  generate: (summonerId) ->
    object = new ASObject()
    object.name = 'flex.messaging.messages.RemotingMessage'
    object.keys = ['source', 'operation', 'timestamp', 'messageId', 'clientId', 'timeToLive', 'body', 'destination', 'headers']
    object.object =
      operation: 'findPlayer'
      source: null
      timestamp: 0
      clientId: null
      timeToLive: 0
      #messageId: 'FE149B94-2373-9F75-3EDE-1515B4A47763' # generate a uuid
      messageId: uuid().toUpperCase()
      destination: 'summonerTeamService'
      headers: @generateHeaders()
      body: [summonerId]
    object.encoding = 0
    return object

  generateHeaders: () ->
    headers = new ASObject()
    headers.name = ''
    headers.object =
      DSId: @options.dsid
      DSRequestTimeout: 60
      DSEndpoint: 'my-rtmps'
    headers.encoding = 2
    return headers

class GetTeamById extends Packet
  generate: (teamId) ->
    object = new ASObject()
    object.name = 'flex.messaging.messages.RemotingMessage'
    object.keys = ['source', 'operation', 'timestamp', 'messageId', 'clientId', 'timeToLive', 'body', 'destination', 'headers']
    object.object =
      operation: 'findTeamById'
      source: null
      timestamp: 0
      clientId: null
      timeToLive: 0
      #messageId: 'FE149B94-2373-9F75-3EDE-1515B4A47763' # generate a uuid
      messageId: uuid().toUpperCase()
      destination: 'summonerTeamService'
      headers: @generateHeaders()
      body: [@generateBody(teamId)]
    object.encoding = 0
    return object

  generateBody: (teamId) ->
    body = new ASObject()
    body.name = 'com.riotgames.team.TeamId'
    body.keys = ['dataVersion', 'fullId', 'futureData']
    body.object =
      dataVersion: null
      fullId: teamId
      futureData: null
    body.encoding = 0
    return body

  generateHeaders: () ->
    headers = new ASObject()
    headers.name = ''
    headers.object =
      DSId: @options.dsid
      DSRequestTimeout: 60
      DSEndpoint: 'my-rtmps'
    headers.encoding = 2
    return headers

exports.ConnectPacket = ConnectPacket
exports.LoginPacket = LoginPacket
exports.AuthPacket = AuthPacket
exports.HeartbeatPacket = HeartbeatPacket
exports.LookupPacket = LookupPacket
exports.GetSummonerDataPacket = GetSummonerDataPacket
exports.AggregatedStatsPacket = AggregatedStatsPacket
exports.PlayerStatsPacket = PlayerStatsPacket
exports.RecentGames = RecentGames
exports.GetTeamForSummoner = GetTeamForSummoner
exports.GetTeamById = GetTeamById
