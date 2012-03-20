typeOf = (object) ->
   return null if object is null
   return undefined if object is undefined
   funcNameRegex = /function (.{1,})\(/
   results = (funcNameRegex).exec((object).constructor.toString())
   if results && results.length > 1
     return results[1]
   else
     return ''

ObjectEncoding =
  #: Property list encoding.
  #: The remaining integer-data represents the number of class members that
  #: exist. The property names are read as string-data. The values are then
  #: read as AMF3-data.
  STATIC: 0x00

  #: Externalizable object.
  #: What follows is the value of the "inner" object, including type code.
  #: This value appears for objects that implement IExternalizable, such as
  #: L{ArrayCollection} and L{ObjectProxy}.
  EXTERNAL: 0x01

  #: Name-value encoding.
  #: The property names and values are encoded as string-data followed by
  #: AMF3-data until there is an empty string property name. If there is a
  #: class-def reference there are no property names and the number of values
  #: is equal to the number of properties in the class-def.
  DYNAMIC: 0x02

  #: Proxy object.
  PROXY: 0x03



DESTINATION_CLIENT_ID_HEADER = "DSDstClientId"
#: Each message pushed from the server will contain this header identifying
#: the client that will receive the message.
DESTINATION_CLIENT_ID_HEADER = "DSDstClientId"
#: Messages are tagged with the endpoint id for the channel they are sent
#: over.
ENDPOINT_HEADER = "DSEndpoint"
#: Messages that need to set remote credentials for a destination carry the
#: C{Base64} encoded credentials in this header.
REMOTE_CREDENTIALS_HEADER = "DSRemoteCredentials"
#: The request timeout value is set on outbound messages by services or
#: channels and the value controls how long the responder will wait for an
#: acknowledgement, result or fault response for the message before timing
#: out the request.
REQUEST_TIMEOUT_HEADER = "DSRequestTimeout"

SMALL_ATTRIBUTE_FLAGS = [0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40]

SMALL_ATTRIBUTES =
  0x01: 'body'
  0x02: 'clientId'
  0x04: 'destination'
  0x08: 'headers'
  0x10: 'messageId'
  0x20: 'timestamp'
  0x40: 'timeToLive'

SMALL_UUID_FLAGS = [0x01, 0x02]

SMALL_UUIDS =
  0x01: 'clientId'
  0x02: 'messageId'

SMALL_FLAG_MORE = 0x80

readFlags = (decoder) ->
  flags = []
  done = false

  until done
    byte = decoder.getByte()

    if (byte & SMALL_FLAG_MORE) is 0
      done = true
    else
      byte = byte ^ SMALL_FLAG_MORE

    flags.push(byte)

  return flags

class ASObject
  amf3: true
  name: null
  alias: null
  external: false
  encoding: ObjectEncoding.STATIC

  constructor: (@name) ->
    @keys = []
    @object = {}

  _readKeys: (decoder, ref) ->
    length = ref >> 4
    if length is 0
      @keys = []
    else
      @keys = (decoder.readString() for i in [1..length])

  _readamf: (decoder) ->
    obj = new ASObject(@name)
    obj.encoding = @encoding

    if obj.encoding is ObjectEncoding.STATIC
      obj.keys = @keys
      for key in @keys
        obj.object[key] = decoder.readValue()
    else
      key = decoder.readString()
      while key
        obj.object[key] = decoder.readValue()
        key = decoder.readString()
    obj

  _writeamf: (encoder) ->
    if @encoding is ObjectEncoding.STATIC
      #encoder.writeString(key, false) for key in @keys
      for key in @keys
        encoder.writeValue(@object[key])
    else
      for key, value of @object
        encoder.writeString(key, false)
        encoder.writeValue(value)
      encoder.writeType(0x01)

ASObject._amf =
  amf3: true
  name: null
  alias: null
  external: false
  encoding: ObjectEncoding.STATIC

class ArrayCollection
  amf3: true
  name: 'ArrayCollection'
  alias: 'flex.messaging.io.ArrayCollection'
  external: true
  encoding: ObjectEncoding.EXTERNAL

  constructor: () ->
    @data = []
  
  _readamf: (decoder) ->
    obj = new ArrayCollection()
    obj.data = decoder.readValue()
    return obj

  _writeamf: (encoder) ->
    encoder.writeArray(@data)

ArrayCollection._amf =
  amf3: true
  name: 'ArrayCollection'
  alias: 'flex.messaging.io.ArrayCollection'
  external: true
  encoding: ObjectEncoding.EXTERNAL

class AbstractMessage
  amf3: true
  dynamic: false
  external: true
  encoding: ObjectEncoding.EXTERNAL

  constructor: (options = {}) ->
    @body = options.body || null
    @clientId = options.clientId || null
    @destination = options.destination || null
    @headers = options.headers || null
    @messageId = options.messageId || null
    @timestamp = options.timestamp || null
    @timeToLive = options.timeToLive || null
  
  decodeSmallAttribute: (attr, decoder) ->
    obj = decoder.readValue()

    return obj

  encodeSmallAttribute: (attr, encoder) ->
    obj = @[attr]

    unless obj
      return obj
    
    if attr in ['timestamp', 'timeToLive']
      return obj

    if attr in ['messageId', 'clientId']
      return null
    return obj

  _readamf: (decoder) ->
    flags = readFlags(decoder)

    if flags.length > 2
      throw 'Too many flags'

    idx = 0
    for byte in flags
      if idx is 0
        for flag in SMALL_ATTRIBUTE_FLAGS
          if flag & byte
            attr = SMALL_ATTRIBUTES[flag]
            @[attr] = decoder.readValue()
      if idx is 1
        for flag in SMALL_UUID_FLAGS
          if flag & byte
            attr = SMALL_UUIDS[flag]
            @[attr] = decoder.readValue()
      idx += 1

  _writeamf: (encoder) ->
    flagAttrs = []
    uuidAttrs = []
    byte = 0

    for flag in SMALL_ATTRIBUTE_FLAGS
      value = @encodeSmallAttribute(SMALL_ATTRIBUTES[flag])
      
      if value
        byte = byte | flag
        flagAttrs.push(value)

    flags = byte
    byte = 0

    for flag in SMALL_UUID_FLAGS
      attr = SMALL_UUIDS[flag]
      value = @[attr]

      unless value
        continue

      byte = byte | flag
      uuidAttrs.push(value)
    
    unless byte
      encoder.writeType(flags)
    else
      encoder.writeType(flags | SMALL_FLAG_MORE)
      encoder.writeType(byte)
    
    for attr in flagAttrs
      encoder.writeValue(attr)
    encoder.writeValue(attr) for attr in uuidAttrs

AbstractMessage._amf =
  amf3: true
  dynamic: false
  external: true
  encoding: ObjectEncoding.EXTERNAL


class AsyncMessage extends AbstractMessage
  amf3: true
  alias: 'DSA'
  external: true
  encoding: ObjectEncoding.EXTERNAL

  constructor: () ->
    super

  _readamf: (decoder) ->
    super

    flags = readFlags(decoder)

    if flags.length > 1
      throw 'Too many flags'
    
    byte = flags[0]
    if byte & 0x01
      @correlationId = decoder.readValue()
    if byte & 0x02
      # TODO: uuid
      @correlationId = decoder.readValue()

  _writeamf: (encoder) ->
    super

    if typeOf(@correlationId) is "Buffer"
      encoder.writeType(0x02)
      encoder.writeByteArray(@correlationId)
    else
      encoder.writeType(0x01)
      encoder.writeValue(@correlationId)

AsyncMessage._amf =
  amf3: true
  alias: 'DSA'
  external: true
  encoding: ObjectEncoding.EXTERNAL

class AcknowledgeMessage extends AsyncMessage
  amf3: true
  alias: 'DSK'
  external: true
  encoding: ObjectEncoding.EXTERNAL
  name: 'AcknowledgeMessage'

  constructor: () ->
    super

  _readamf: (decoder) ->
    super

    flags = readFlags(decoder)

    if flags.length > 1
      throw 'Too many flags'

    return @

  _writeamf: (encoder) ->
    super
    encoder.writeType(0x00)

AcknowledgeMessage._amf =
  amf3: true
  alias: 'DSK'
  external: true
  encoding: ObjectEncoding.EXTERNAL
  name: 'AcknowledgeMessage'

exports.AbstractMessage = AbstractMessage
exports.AcknowledgeMessage = AcknowledgeMessage
exports.ASObject = ASObject
exports.ArrayCollection = ArrayCollection
