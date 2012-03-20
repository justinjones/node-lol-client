
https = require('https')

performQueueRequest = (host, username, password, cb) ->
  options =
    host: host
    port: 443
    path: '/login-queue/rest/queue/authenticate'
    method: 'POST'

  data = "payload=user%3D#{username}%2Cpassword%3D#{password}"

  req = https.request options, (res) ->
    res.on 'data', (d) ->
      data = JSON.parse(d.toString('utf-8'))
      cb(null, data)
  
  req.on 'error', (err) ->
    cb(err)

  req.end(data)

module.exports = performQueueRequest

