hexy = require('hexy')

assert = require('assert')

AMF0Decoder = require('namf/amf0').Decoder
AMF0Encoder = require('namf/amf0').Encoder

class RTMPHeader
  @FULL: 0x00
  @MESSAGE: 0x40
  @TIME: 0x80
  @SEPARATOR: 0xC0
  @MASK: 0xC0

  constructor: (options) ->
    for own key, val of options
      @[key] = val

    @channel = 0 unless @channel
    @time = 0 unless @time
    @streamId = 0 unless @streamId

    @hdrdata = []
    if @channel < 64
      @hdrdata.push(@channel)
    else if @channel < (64+256)
      @hdrdata.push(0x00)
      @hdrdata.push(@channel - 64)
    else
      @hdrdata.push(0x01)
      @hdrdata.push( ((@channel - 64) % 256) + ((@channel - 64) / 256) )

  toBytes: (control) ->
    data = []
    data.push(@hdrdata[0] | control)
    data.push.apply(data, @hdrdata.slice(1))

    if control != RTMPHeader.SEPARATOR
      # time
      if @time < 0xFFFFFF
        pack = new Buffer(4)
        pack.writeUInt32BE(@time, 0)
        data.push(pack[1], pack[2], pack[3])
      else
        data.push(0xFF, 0xFF, 0xFF)

      if control != RTMPHeader.TIME
        # size
        pack = new Buffer(4)
        pack.writeUInt32BE(@size & 0xFFFFFFFF, 0)
        data.push(pack[1], pack[2], pack[3])
        
        # type
        data.push(@type)

        if control != RTMPHeader.MESSAGE
          pack = new Buffer(4)
          pack.writeUInt32LE(@streamId & 0xFFFFFFFF, 0)
          data.push(pack[0], pack[1], pack[2], pack[3])

    if @time >= 0xFFFFFF
      pack = new Buffer(4)
      pack.writeUInt32BE(@time & 0xFFFFFFFF, 0)
      data.push(pack[0], pack[1], pack[2], pack[3])

    return new Buffer(data)


class RTMPProtocol
  @PING_SIZE: 1536
  @DEFAULT_CHUNK_SIZE: 128
  @PROTOCOL_CHANNEL_ID: 2
  @READ_WIN_SIZE: 125000
  @WRITE_WIN_SIZE: 1073741824

  constructor: (@stream) ->
    @lastReadHeaders = {}
    @lastWriteHeaders = {}
    @incompletePackets = {}
    @readChunkSize = @writeChunkSize = RTMPProtocol.DEFAULT_CHUNK_SIZE
    @readWinSize = RTMPProtocol.READ_WIN_SIZE
    @writeWinSize = RTMPProtocol.WRITE_WIN_SIZE
    @readWinSize0 = @writeWinSize0 = 0
    @nextChannelId = RTMPProtocol.PROTOCOL_CHANNEL_ID + 1
    @bytesRead = 0

    @socket.on 'data', (data) =>
      @bytesRead += data.length
  
  # override in subclass
  messageReceived: (msg) ->
    # Do nothing
  
  protocolMessage: (msg) ->
    # Do nothing
  
  parse: () ->
    @parseMessages()

  writeMessage: (msg) ->
    @stream.write(msg)

  parseMessages: (data) ->
    CHANNEL_MASK = 0x3F
    
    offset = 0
    msg = null
    
    while offset < data.length
      hdrsize = data[offset]
      offset += 1

      channel = hdrsize & CHANNEL_MASK
      if channel is 0 # we need one more byte
        channel = 64 + data[offset]
        offset += 1
      else if channel is 1 # we need two more bytes
        channel = 64 + data[offset] + 256 * data[offset+1]
        offset += 2

      hdrtype = hdrsize & RTMPHeader.MASK
      
      header = null
      if hdrtype is RTMPHeader.FULL or @lastReadHeaders[channel] is undefined
        header = new RTMPHeader({channel: channel})
        @lastReadHeaders[channel] = header
      else
        header = @lastReadHeaders[channel]

      if hdrtype < RTMPHeader.SEPARATOR
        timestampData = new Buffer(4)
        timestampData[0] = 0x00
        data.copy(timestampData, 1, offset, offset+3)
        offset += 3

        timestamp = timestampData.readUInt32BE(0)
        header.time = timestamp

      if hdrtype < RTMPHeader.TIME
        sizeData = new Buffer(4)
        sizeData[0] = 0x00
        data.copy(sizeData, 1, offset, offset+3)
        offset += 3

        header.size = sizeData.readUInt32BE(0)

        header.type = data[offset]
        offset += 1

      if hdrtype < RTMPHeader.MESSAGE
        header.streamId = data.readUInt32LE(offset, offset+4)
        offset += 4

      if header.time is 0xFFFFFF
        header.extendedTime = data.readUInt32BE(offset, offset+4)
        offset += 4
      else
        header.extendedTime = null
      
      if hdrtype is RTMPHeader.FULL
        header.currentTime = header.extendedTime or header.time
        header.hdrtype = hdrtype
      else if hdrtype is RTMPHeader.MESSAGE or hdrtype is RTMPHeader.TIME
        header.hdrtype = hdrtype
      oldData = @incompletePackets[channel]
      count = Math.min(header.size - (oldData?.length or 0), @readChunkSize)
      newData = data.slice(offset, offset+count)
      offset += count
      
      if oldData
        packetData = new Buffer(oldData.length + newData.length)
        oldData.copy(packetData)
        newData.copy(packetData, oldData.length)
      else
        packetData = newData

      # Check if we need to send Ack
      if @readWinSize is not null
        if @bytesRead > (@readWinSize0 + @readWinSize)
          @readWinSize0 = @bytesRead
          ack = new RTMPMessage()
          size = new Buffer(4)
          size.writeUInt32BE(@readWinSize0, 0)
          ack.type = RTMPMessage.ACK
          ack.data = size
          #console.log 'WRITING ACK ======================================================='
          @writeMessage(ack)
      
      if packetData.length < header.size # we dont have all data
        @incompletePackets[channel] = packetData
      else # we have all data
        if hdrtype is RTMPHeader.MESSAGE or hdrtype is RTMPHeader.TIME
          header.currentTime = (header.currentTime or 0) + (header.extendedTime or header.time)
        else if hdrtype is RTMPHeader.SEPARATOR
          if header.hdrtype is RTMPHeader.MESSAGE or header.hdrtype is RTMPHeader.TIME
            header.currentTime = (header.currentTime or 0) + (header.extendedTime or header.time)
        if packetData.length is header.size
          if @incompletePackets[channel]
            delete @incompletePackets[channel]
        else
          # ??? setup incomplete data?
        hdr = new RTMPHeader({channel: header.channel, time: header.currentTime, size: header.size, type: header.type, streamId: header.streamId})
        msg = new RTMPMessage(hdr, packetData)
    return msg




class RTMPClient extends RTMPProtocol
  constructor: (@socket) ->
    @_nextCallId = 1
    @_callbacks = {}
    @_timeouts = {}
    @streams = {}
    @objectEncoding = 0
    @lastReadHeaders = {}
    @lastWriteHeaders = {}
    @incompletePackets = {}
    @readChunkSize = @writeChunkSize = RTMPProtocol.DEFAULT_CHUNK_SIZE
    @readWinSize = RTMPProtocol.READ_WIN_SIZE
    @readWinSize = 1700000
    @writeWinSize = RTMPProtocol.WRITE_WIN_SIZE
    @readWinSize0 = @writeWinSize0 = 0
    @nextChannelId = RTMPProtocol.PROTOCOL_CHANNEL_ID + 1
    @bytesRead = 0
    
    if @socket
      @socket.on 'data', (data) =>
        @bytesRead += data.length

  # Client sends VC1 (0x03) - RMTP version
  # Client sends C1 (4 byte time + 4 byte 0x00 + 1528 random bytes)
  # Server sends VS1 (0x03) - RTMP version
  # Server sends S1, same format as C1 above
  # Server sends S2, copy of C1
  # Client sends C2, copy of S1
  handshake: (cb) ->
    handshake1 = new Buffer(1537)
    handshake1[0] = 0x03

    clientResponse = null
    
    # Listener which handles VS1/S1
    handleHandshake1 = (data) =>
      @socket.removeListener('data', handleHandshake1)

      if data.length isnt 1537 and data.length isnt 3073
        cb(new Error('Handshake response was incorrect size.'))
      if data.length is 1537
        clientResponse = data.slice(1) # Data to send back with C2
        @socket.addListener('data', handleHandshake2)
      if data.length is 3073
        clientResponse = data.slice(1, 1537) # Data to send back with C2
        handleHandshake2(data.slice(1537)) # Forward data to S2 handler
    
    # Listener which handles S2
    handleHandshake2 = (data) =>
      @socket.removeListener('data', handleHandshake2)
      if data.length isnt 1536
        cb(new Error('Handshake response was incorrect size.'))
      else
        # Write C2 and callback
        @socket.write(clientResponse)
        #@socket.addListener 'data', @parseMessages
        @socket.on 'data', @parseData
        cb(null)

    # Add listener and write VC1/C1
    @socket.addListener('data', handleHandshake1)
    @socket.write(handshake1)
  
  parseData: (data) =>
    extraData = null

    if @partialMessage
      
      totalSize = @partialMessage.header.size + Math.floor(@partialMessage.header.size / 128)

      if Math.floor(@partialMessage.header.size / 128) is (@partialMessage.header.size / 128)
        totalSize -= 1

      totalSize += @partialMessage.header.hdrsize

      dataNeeded = totalSize - @partialMessage.data.length

      newData = null
      if dataNeeded < data.length
        newData = data.slice(0, dataNeeded)
        extraData = data.slice(newData.length)
      else
        newData = data

      buf = new Buffer(@partialMessage.data.length + newData.length)
      @partialMessage.data.copy(buf, 0)
      newData.copy(buf, @partialMessage.data.length)

      @partialMessage.data = buf
      
      if @partialMessage.data.length >= totalSize
        @parseFullData(@partialMessage.header, @partialMessage.data)
        @partialMessage = null

        if extraData
          @parseData(extraData)

        
    else
      CHANNEL_MASK = 0x3F

      offset = 0
      header = null

      hdrsize = data[offset]
      offset += 1

      channel = hdrsize & CHANNEL_MASK
      if channel is 0 # we need one more byte
        channel = 64 + data[offset]
        offset += 1
      else if channel is 1 # we need two more bytes
        channel = 64 + data[offset] + 256 * data[offset+1]
        offset += 2

      hdrtype = hdrsize & RTMPHeader.MASK
      
      if hdrtype is RTMPHeader.FULL or @lastReadHeaders[channel] is undefined
        header = new RTMPHeader({channel: channel})
        @lastReadHeaders[channel] = header
      else
        header = @lastReadHeaders[channel]
      
      if hdrtype < RTMPHeader.SEPARATOR
        timestampData = new Buffer(4)
        timestampData[0] = 0x00
        data.copy(timestampData, 1, offset, offset+3)
        offset += 3

        timestamp = timestampData.readUInt32BE(0)
        header.time = timestamp

      if hdrtype < RTMPHeader.TIME
        sizeData = new Buffer(4)
        sizeData[0] = 0x00
        data.copy(sizeData, 1, offset, offset+3)
        offset += 3

        header.size = sizeData.readUInt32BE(0)

        header.type = data[offset]
        offset += 1

      if hdrtype < RTMPHeader.MESSAGE
        header.streamId = data.readUInt32LE(offset, offset+4)
        offset += 4

      if header.time is 0xFFFFFF
        header.extendedTime = data.readUInt32BE(offset, offset+4)
        offset += 4
      else
        header.extendedTime = null
      
      if hdrtype is RTMPHeader.FULL
        header.currentTime = header.extendedTime or header.time
        header.hdrtype = hdrtype
      else if hdrtype is RTMPHeader.MESSAGE or hdrtype is RTMPHeader.TIME
        header.hdrtype = hdrtype

      @partialMessage = {header: header}

      totalSize = @partialMessage.header.size + Math.floor(@partialMessage.header.size / 128)

      if Math.floor(@partialMessage.header.size / 128) is (@partialMessage.header.size / 128)
        totalSize -= 1

      totalSize += offset

      @partialMessage.header.hdrsize = offset

      dataNeeded = Math.min(totalSize, data.length)
      
      if data.length > dataNeeded
        @partialMessage.data = data.slice(0, dataNeeded)
        extraData = data.slice(@partialMessage.data.length)
      else
        @partialMessage.data = data

      if @partialMessage.data.length >= totalSize
        @parseFullData(@partialMessage.header, @partialMessage.data)
        @partialMessage = null

        if extraData
          @parseData(extraData)


  
  parseFullData: (header, data) =>
    data = data.slice(header.hdrsize)
    offset = 0
    chunkMarkers = 0
    packetData = null
    while offset < data.length and offset < (header.size + chunkMarkers)
      if packetData
        offset += 1 # skip chunk marker
        chunkMarkers += 1

      count = Math.min((header.size + chunkMarkers) - offset, @readChunkSize)
      newData = data.slice(offset, offset+count)
      offset += count
      
      if packetData
        buf = new Buffer(packetData.length + newData.length)
        packetData.copy(buf)
        newData.copy(buf, packetData.length)
        packetData = buf
      else
        packetData = newData
    
    hdr = new RTMPHeader({channel: header.channel, time: header.currentTime, size: header.size, type: header.type, streamId: header.streamId})
    msg = new RTMPMessage(hdr, packetData)
    @messageReceived(msg)

  parseMessages: (data) =>
    CHANNEL_MASK = 0x3F

    offset = 0
    msg = null
    parseHeader = true

    while offset < data.length
      oldOffset = offset
      hdrsize = data[offset]
      offset += 1

      channel = hdrsize & CHANNEL_MASK
      if channel is 0 # we need one more byte
        channel = 64 + data[offset]
        offset += 1
      else if channel is 1 # we need two more bytes
        channel = 64 + data[offset] + 256 * data[offset+1]
        offset += 2

      hdrtype = hdrsize & RTMPHeader.MASK
      
      header = null
      
      if hdrtype is RTMPHeader.FULL and (channel is 2 or channel is 3)# or @lastReadHeaders[channel] is undefined
        header = new RTMPHeader({channel: channel})
        @lastReadHeaders[channel] = header
      else if @lastReadHeaders['3']
        header = @lastReadHeaders['3']
        #offset = oldOffset
        parseHeader = false
      else
        header = @lastReadHeaders[channel]
      
      if parseHeader
        if hdrtype < RTMPHeader.SEPARATOR
          timestampData = new Buffer(4)
          timestampData[0] = 0x00
          data.copy(timestampData, 1, offset, offset+3)
          offset += 3

          timestamp = timestampData.readUInt32BE(0)
          header.time = timestamp

        if hdrtype < RTMPHeader.TIME
          sizeData = new Buffer(4)
          sizeData[0] = 0x00
          data.copy(sizeData, 1, offset, offset+3)
          offset += 3

          header.size = sizeData.readUInt32BE(0)

          header.type = data[offset]
          offset += 1

        if hdrtype < RTMPHeader.MESSAGE
          header.streamId = data.readUInt32LE(offset, offset+4)
          offset += 4

        if header.time is 0xFFFFFF
          header.extendedTime = data.readUInt32BE(offset, offset+4)
          offset += 4
        else
          header.extendedTime = null
        
        if hdrtype is RTMPHeader.FULL
          header.currentTime = header.extendedTime or header.time
          header.hdrtype = hdrtype
        else if hdrtype is RTMPHeader.MESSAGE or hdrtype is RTMPHeader.TIME
          header.hdrtype = hdrtype

      oldData = @incompletePackets['3']
      count = Math.min(header.size - (oldData?.length or 0), @readChunkSize, data.length - offset)
      
      newData = data.slice(offset, offset+count)
      offset += count
      
      if oldData
        packetData = new Buffer(oldData.length + newData.length)
        oldData.copy(packetData)
        newData.copy(packetData, oldData.length)
      else
        packetData = newData
      
      if @bytesRead > (@readWinSize0 + @readWinSize)
        @readWinSize0 = @bytesRead
        ack = new RTMPMessage()
        size = new Buffer(4)
        size.writeUInt32BE(@readWinSize0, 0)
        ack.type = RTMPMessage.ACK
        ack.data = size
        ack.size = ack.data.length
        @writeMessage(ack)
      
      if packetData.length < header.size # we dont have all data
        @incompletePackets['3'] = packetData
        @incompletePackets[channel] = packetData
      else # we have all data
        if hdrtype is RTMPHeader.MESSAGE or hdrtype is RTMPHeader.TIME
          header.currentTime = (header.currentTime or 0) + (header.extendedTime or header.time)
        else if hdrtype is RTMPHeader.SEPARATOR
          if header.hdrtype is RTMPHeader.MESSAGE or header.hdrtype is RTMPHeader.TIME
            header.currentTime = (header.currentTime or 0) + (header.extendedTime or header.time)
        if packetData.length is header.size
          if @incompletePackets[channel]
            delete @incompletePackets[channel]
          if @incompletePackets['3']
            delete @incompletePackets['3']
        else
          # ??? setup incomplete data?
        hdr = new RTMPHeader({channel: header.channel, time: header.currentTime, size: header.size, type: header.type, streamId: header.streamId})
        msg = new RTMPMessage(hdr, packetData)
        @messageReceived(msg)
        return msg
        if msg.type is RTMPMessage.ACK
          console.log hexy.hexy(data)
  
  send: (cmd, cb) ->
    [cmd.id, cmd.type] = [@_nextCallId, (@objectEncoding == 0 and RTMPMessage.RPC or RTMPMessage.RPC3)]
    callId = @_nextCallId
    @_nextCallId += 1

    @_callbacks[callId] = cb
    closeSocket = () =>
      console.log 'Timeout reached, closing socket.'
      if !@broken
        @broken = true
        @socket.destroySoon()
      for key, timeout of @_timeouts
        clearTimeout timeout
    timeoutId = setTimeout closeSocket, 10000
    @_timeouts[callId] = timeoutId

    @writeMessage(cmd.toMessage())

  writeMessage: (message) ->
    header = null
    control = null
    if @lastWriteHeaders[message.streamId]
      header = @lastWriteHeaders[message.streamId]
    else
      if @nextChannelId <= RTMPProtocol.PROTOCOL_CHANNEL_ID
        @nextChannelId = RTMPProtocol.PROTOCOL_CHANNEL_ID + 1
      header = new RTMPHeader(channel: @nextChannelId)
      @nextChannelId += 1

    if message.type < RTMPMessage.AUDIO
      header = new RTMPHeader(channel: RTMPProtocol.PROTOCOL_CHANNEL_ID, type: RTMPMessage.MESSAGE)
    
    if header.streamId isnt message.streamId or header.time is 0 or message.time <= header.time
      [header.streamId, header.type, header.size, header.time, header.delta] = [message.streamId, message.type, message.size, message.time, message.time]
      control = RTMPHeader.FULL
    else if header.size isnt message.size or header.type isnt message.type
      [header.type, header.size, header.time, header.delta] = [message.type, message.size, message.time, message.time] # message.time-header.time???
      control = RTMPHeader.MESSAGE
    else
      [header.time, header.delta] = [message.time, message.time] # message.time-header.time????
      control = RTMPHeader.TIME

    
    hdrOptions =
      channel: header.channel
      size: header.size
      type: header.type
      streamId: header.streamId
    if control is RTMPHeader.MESSAGE or control is RTMPHeader.TIME
      hdrOptions['time'] = header.delta
    else
      hdrOptions['time'] = header.time
    hdr = new RTMPHeader(hdrOptions)

    data = new Buffer(0)
    offset = 0
    while offset < message.data.length
      hdrData = hdr.toBytes(control)
      count = Math.min(@writeChunkSize, message.data.length - offset)
      sliceData = message.data.slice(offset, offset+count)
      offset += count

      newData = new Buffer(data.length + hdrData.length + sliceData.length)
      data.copy(newData, 0)
      hdrData.copy(newData, data.length)
      sliceData.copy(newData, data.length + hdrData.length)
      
      data = newData

      control = RTMPHeader.SEPARATOR
    if message.type < RTMPMessage.AUDIO
      hexy = require('hexy')
      console.log hexy.hexy(data)
    @socket.write(data) if @socket.writable

  messageReceived: (msg) ->
    if (msg.type is RTMPMessage.RPC or msg.type is RTMPMessage.RPC3) and msg.streamId == 0
      cmd = RTMPCommand.fromMessage(msg)
      if cmd.name is '_error'
        @socket.destroySoon()
      if cb = @_callbacks[cmd.id]
        clearTimeout @_timeouts[cmd.id]
        delete @_timeouts[cmd.id]
        if cmd.name is '_error'
          cb(cmd)
        else
          cb(null, cmd)
        delete @_callbacks[cmd.id]
    else if msg.type is RTMPMessage.ACK
      console.log 'Got ack'
      @writeWinSize0 = msg.data.readUInt32BE(0)
    else if msg.type is RTMPMessage.WIN_ACK_SIZE
      console.log msg
      #@readWinSize = msg.data.readUInt32BE(0)
      #@readWinSize0 = @bytesRead
    else
      console.log 'UNKNOWN MSG?', msg
      #else if @streams[msg.streamId] != -1
      #stream = @streams[@streams[msg.streamId]]

class RTMPCommand
  constructor: (@type, @name, @id, @data, @args = []) ->
  
  @fromMessage: (message) ->
    if [RTMPMessage.RPC, RTMPMessage.RPC3, RTMPMessage.DATA, RTMPMessage.DATA3].indexOf(message.type) is -1
      throw "Not a valid message type for a command."

    if message.data.length is 0
      throw "Zero length message data."
    data = null
    if message.type is RTMPMessage.RPC3 or message.type is RTMPMessage.DATA3
      data = message.data.slice(1)
    else
      data = message.data

    cmd = new RTMPCommand()
    cmd.type = message.type
    decoder = new AMF0Decoder(data)

    cmd.name = decoder.readValue() # first field is command name

    if message.type is RTMPMessage.RPC or message.type is RTMPMessage.RPC3
      # second field is id
      cmd.id = decoder.readValue()
      cmd.data = decoder.readValue()
    else
      cmd.id = 0
    cmd.args = []

    if cmd.name is '_error'
      console.log cmd
      console.log hexy.hexy(data)
      return cmd

    while decoder.offset < decoder.buffer.length
      cmd.args.push(decoder.readValue())

    return cmd

  toMessage: () ->
    msg = new RTMPMessage()
    msg.type = @type

    encoder = new AMF0Encoder()
    encoder.writeValue(@name)
    if msg.type is RTMPMessage.RPC or msg.type is RTMPMessage.RPC3
      encoder.writeValue(@id)
      encoder.writeValue(@data or null)
    if msg.type is RTMPMessage.RPC
      encoder.writeValue(arg) for arg in @args
    else if msg.type is RTMPMessage.RPC3
      encoder.writeAMF3(arg) for arg in @args

    out = encoder.getBuffer()
    if msg.type is RTMPMessage.RPC3
      buffer = new Buffer(out.length + 1)
      buffer[0] = 0x00
      out.copy(buffer, 1)
    else
      buffer = out
    msg.data = buffer
    msg.size = buffer.length
    return msg


class RTMPMessage
  # message types: RPC3, DATA3,and SHAREDOBJECT3 are used with AMF3
  [@CHUNK_SIZE,  @ABORT,  @ACK,  @USER_CONTROL,  @WIN_ACK_SIZE, @SET_PEER_BW, @AUDIO, @VIDEO, @DATA3, @SHAREDOBJ3, @RPC3, @DATA, @SHAREDOBJ, @RPC] = \
  [0x01,         0x02,    0x03,  0x04,           0x05,          0x06,         0x08,   0x09,   0x0F,   0x10,        0x11,  0x12,  0x13,       0x14]

  constructor: (@header, @data) ->
    @header = new RTMPHeader() unless @header
    @type = @header.type if @header.type
    @size = @header.size if @header.size
    @streamId = @header.streamId if @header.streamId
    @streamId = 0 unless @streamId
    @time = @header.time if @header.time

exports.RTMPClient = RTMPClient
exports.RTMPCommand = RTMPCommand
