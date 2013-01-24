tls = require('tls')
loginQueue = require('./lib/login-queue')
lolPackets = require('./lib/packets')
rtmp = require('namf/rtmp')

RTMPClient = rtmp.RTMPClient
RTMPCommand = rtmp.RTMPCommand

EventEmitter = require('events').EventEmitter

class LolClient extends EventEmitter
  _rtmpHosts: {
    'na': 'prod.na1.lol.riotgames.com'
    'euw': 'prod.eu.lol.riotgames.com'
    'eune': 'prod.eun1.lol.riotgames.com'
  }
  
  _loginQueueHosts: {
    'na': 'lq.na1.lol.riotgames.com'
    'euw': 'lq.eu.lol.riotgames.com'
    'eune': 'lq.eun1.lol.riotgames.com'
  }
    
  constructor: (@options) ->
    if @options.region
      @options.host = @_rtmpHosts[@options.region]
      @options.lqHost = @_loginQueueHosts[@options.region]
    else
      @options.host = @options.host
      @options.lqHost = @option.lqHost
    @options.port = @options.port || 2099

    @options.username = @options.username
    @options.password = @options.password
    @options.version = @options.version || '1.55.12_02_27_22_54'
    @options.debug = @options.debug || false

    console.log @options if @options.debug

  connect: (cb) ->
    @checkLoginQueue (err, token) =>
      console.log err if err
      #return cb(err) if err
      @sslConnect (err, stream) =>
        #return cb(err) if err
        console.log 'stream connected'
        @stream = stream

        @setupRTMP()

  checkLoginQueue: (cb) ->
    console.log 'Checking Login Queue' if @options.debug
    loginQueue @options.lqHost, @options.username, @options.password, (err, response) =>
      if err
        console.log 'Login Queue Failed' if @options.debug
        console.log err if err and @options.debug
        return checkLoginQueue(cb)
      else
        if !response.token
          cb(new Error('Login Queue Response had no token'))
        else
          console.log 'Login Queue Response', response if @options.debug
          @options.queueToken = response.token
          cb(null, @options.queueToken)

  sslConnect: (cb) ->
    console.log 'Connecting to SSL' if @options.debug

    stream = tls.connect @options.port, @options.host, () =>
      cb(null, stream)

    stream.on 'error', () =>
      stream.destroySoon()


  setupRTMP: () ->
    console.log 'Setting up RTMP Client' if @options.debug
    @rtmp = new RTMPClient(@stream)
    console.log 'Handshaking RTMP' if @options.debug
    @rtmp.handshake (err) =>
      if err
        @stream.destroy()
      else
        @performNetConnect()

  performNetConnect: () ->
    console.log 'Performing RTMP NetConnect' if @options.debug
    ConnectPacket = lolPackets.ConnectPacket
    pkt = new ConnectPacket(@options)
    cmd = new RTMPCommand(0x14, 'connect', null, pkt.appObject(), [false, 'nil', '', pkt.commandObject()])
    @rtmp.send cmd, (err, result) =>
      if err
        console.log 'NetConnect failed' if @options.debug
        @stream.destroy()
      else
        console.log 'NetConnect success' if @options.debug
        @performLogin(result)

  performLogin: (result) =>
    console.log 'Performing RTMP Login...' if @options.debug
    LoginPacket = lolPackets.LoginPacket
    @options.dsid = result.args[0].id
    
    # Client version
    cmd = new RTMPCommand(0x11, null, null, null, [new LoginPacket(@options).generate(@options.version)])
    @rtmp.send cmd, (err, result) =>
      if err
        console.log 'RTMP Login failed' if @options.debug
        @stream.destroy()
      else
        @performAuth(result)

  performAuth: (result) =>
    console.log 'Performing RTMP Auth..' if @options.debug
    AuthPacket = lolPackets.AuthPacket
    
    @options.authToken = result.args[0].body.object.token
    cmd = new RTMPCommand(0x11, null, null, null, [new AuthPacket(@options).generate()])
    @rtmp.send cmd, (err, result) =>
      if err
        console.log 'RTMP Auth failed' if @options.debug
      else
        console.log 'Connect Process Completed' if @options.debug
        @emit 'connection'
  
  getSummonerByName: (name, cb) =>
    console.log "Finding player by name: #{name}" if @options.debug
    LookupPacket = lolPackets.LookupPacket
    cmd = new RTMPCommand(0x11, null, null, null, [new LookupPacket(@options).generate(name)])
    @rtmp.send cmd, (err, result) =>
      return cb(err) if err
      return cb(err, null) unless result?.args?[0]?.body?
      return cb(err, result.args[0].body)

  getSummonerStats: (acctId, cb) =>
    console.log "Fetching Summoner Stats for #{acctId}" if @options.debug
    PlayerStatsPacket = lolPackets.PlayerStatsPacket
    cmd = new RTMPCommand(0x11, null, null, null, [new PlayerStatsPacket(@options).generate(Number(acctId))])
    @rtmp.send cmd, (err, result) =>
      return cb(err) if err
      return cb(err, null) unless result?.args?[0]?.body?
      return cb(err, result.args[0].body)

  getMatchHistory: (acctId, cb) =>
    console.log "Fetching recent games for #{acctId}" if @options.debug
    RecentGames = lolPackets.RecentGames
    cmd = new RTMPCommand(0x11, null, null, null, [new RecentGames(@options).generate(Number(acctId))])
    @rtmp.send cmd, (err, result) =>
      return cb(err) if err
      return cb(err, null) unless result?.args?[0]?.body?
      return cb(err, result.args[0].body)

  getAggregatedStats: (acctId, cb) =>
    AggregatedStatsPacket = lolPackets.AggregatedStatsPacket
    cmd = new RTMPCommand(0x11, null, null, null, [new AggregatedStatsPacket(@options).generate(Number(acctId))])
    @rtmp.send cmd, (err, result) =>
      return cb(err) if err
      return cb(err, null) unless result?.args?[0]?.body?
      return cb(err, result.args[0].body)
  
  getTeamsForSummoner: (summonerId, cb) =>
    GetTeamForSummoner = lolPackets.GetTeamForSummoner
    cmd = new RTMPCommand(0x11, null, null, null, [new GetTeamForSummoner(@options).generate(Number(summonerId))])
    @rtmp.send cmd, (err, result) =>
      cb(err) if err
      cb(err, null) unless result?.args?[0]?.body?
      cb(err, result.args[0].body)

  getTeamById: (teamId, cb) =>
    GetTeamById = lolPackets.GetTeamById
    cmd = new RTMPCommand(0x11, null, null, null, [new GetTeamById(@options).generate(teamId)])
    @rtmp.send cmd, (err, result) =>
      return cb(err) if err
      return cb(err, null) unless result?.args?[0]?.body
      return cb(err, result.args[0].body)

  getSummonerData: (acctId, cb) =>
    GetSummonerDataPacket = lolPackets.GetSummonerDataPacket
    cmd = new RTMPCommand(0x11, null, null, null, [new GetSummonerDataPacket(@options).generate(acctId)])
    @rtmp.send cmd, (err, result) =>
      return cb(err) if err
      return cb(err, null) unless result?.args?[0]?.body
      return cb(err, result.args[0].body)


module.exports = LolClient
