Float = require('./util').Float

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


#: The undefined type is represented by the undefined type marker. No further
#: information is encoded for this value.
TYPE_UNDEFINED = 0x00
#: The null type is represented by the null type marker. No further
#: information is encoded for this value.
TYPE_NULL = 0x01
#: The false type is represented by the false type marker and is used to
#: encode a Boolean value of C{false}. No further information is encoded for
#: this value.
TYPE_BOOL_FALSE = 0x02
#: The true type is represented by the true type marker and is used to encode
#: a Boolean value of C{true}. No further information is encoded for this
#: value.
TYPE_BOOL_TRUE = 0x03
#: In AMF 3 integers are serialized using a variable length signed 29-bit
#: integer.
#: @see: U{Parsing Integers on OSFlash (external)
#: <http://osflash.org/documentation/amf3/parsing_integers>}
TYPE_INTEGER = 0x04
#: This type is used to encode an ActionScript Number or an ActionScript
#: C{int} of value greater than or equal to 2^28 or an ActionScript uint of
#: value greater than or equal to 2^29. The encoded value is is always an 8
#: byte IEEE-754 double precision floating point value in network byte order
#: (sign bit in low memory). The AMF 3 number type is encoded in the same
#: manner as the AMF 0 L{Number<pyamf.amf0.TYPE_NUMBER>} type.
TYPE_NUMBER = 0x05
#: ActionScript String values are represented using a single string type in
#: AMF 3 - the concept of string and long string types from AMF 0 is not used.
#: Strings can be sent as a reference to a previously occurring String by
#: using an index to the implicit string reference table. Strings are encoding
#: using UTF-8 - however the header may either describe a string literal or a
#: string reference.
TYPE_STRING = 0x06
#: ActionScript 3.0 introduced a new XML type however the legacy C{XMLDocument}
#: type from ActionScript 1.0 and 2.0.is retained in the language as
#: C{flash.xml.XMLDocument}. Similar to AMF 0, the structure of an
#: C{XMLDocument} needs to be flattened into a string representation for
#: serialization. As with other strings in AMF, the content is encoded in
#: UTF-8. XMLDocuments can be sent as a reference to a previously occurring
#: C{XMLDocument} instance by using an index to the implicit object reference
#: table.
#: @see: U{OSFlash documentation (external)
#: <http://osflash.org/documentation/amf3#x07_-_xml_legacy_flashxmlxmldocument_class>}
TYPE_XML = 0x07
#: In AMF 3 an ActionScript Date is serialized as the number of
#: milliseconds elapsed since the epoch of midnight, 1st Jan 1970 in the
#: UTC time zone. Local time zone information is not sent.
TYPE_DATE = 0x08
#: ActionScript Arrays are described based on the nature of their indices,
#: i.e. their type and how they are positioned in the Array.
TYPE_ARRAY = 0x09
#: A single AMF 3 type handles ActionScript Objects and custom user classes.
TYPE_OBJECT = 0x0A
#: ActionScript 3.0 introduces a new top-level XML class that supports
#: U{E4X<http://en.wikipedia.org/wiki/E4X>} syntax.
#: For serialization purposes the XML type needs to be flattened into a
#: string representation. As with other strings in AMF, the content is
#: encoded using UTF-8.
TYPE_XMLSTRING = 0x0B
#: ActionScript 3.0 introduces the L{ByteArray} type to hold an Array
#: of bytes. AMF 3 serializes this type using a variable length encoding
#: 29-bit integer for the byte-length prefix followed by the raw bytes
#: of the L{ByteArray}.
#: @see: U{Parsing ByteArrays on OSFlash (external)
#: <http://osflash.org/documentation/amf3/parsing_byte_arrays>}
TYPE_BYTEARRAY = 0x0C

#: Reference bit.
REFERENCE_BIT = 0x01

#: The maximum value for an int that will avoid promotion to an
#: ActionScript Number when sent via AMF 3 is represented by a
#: signed 29 bit integer: 2^28 - 1.
MAX_29B_INT = 0x0FFFFFFF

#: The minimum that can be represented by a signed 29 bit integer.
MIN_29B_INT = -0x10000000

AMFContext = require('./context')
ASObject = require('./messaging').ASObject

class ClassDefinition
  initialize: (@alias) ->
    @reference = null

class Decoder extends AMFContext
  endian: 'big'
  offset: 0

  constructor: (@buffer, @offset = 0) ->
    @referenceStrings = []

  readValue: () ->
    type = @buffer.readUInt8(@offset, @endian)
    @offset += 1
    value = switch type
      when TYPE_UNDEFINED then @readUndefined()
      when TYPE_NULL then @readNull()
      when TYPE_BOOL_FALSE then @readBoolFalse()
      when TYPE_BOOL_TRUE then @readBoolTrue()
      when TYPE_INTEGER then @readInteger()
      when TYPE_NUMBER then @readNumber()
      when TYPE_STRING then @readString()
      when TYPE_XML then @readXML()
      when TYPE_DATE then @readDate()
      when TYPE_ARRAY then @readArray()
      when TYPE_OBJECT then @readObject()
      when TYPE_XMLSTRING then @readXMLString()
      when TYPE_BYTEARRAY then @readByteArray()
      else
        console.log 'Unknown type'
        #process.exit()
    return value

  getByte: () ->
    byte = @buffer[@offset]
    @offset += 1
    return byte

  readUndefined: () ->
    undefined

  readNull: () ->
    null

  readBoolFalse: () ->
    false

  readBoolTrue: () ->
    true

  readNumber: () ->
    number = @buffer.readDoubleBE(@offset, @endian)
    @offset += 8
    new Float(number)

  readInteger: (signed = true) ->
    @_decodeInt(signed)

  readString: () ->
    [length, isReference] = @_readLength()
    if isReference
      str = @getStringFromReference(length)
      return str

    if length is 0
      return ''

    str = @buffer.toString('utf8', @offset, @offset + length)
    @offset += length

    @addString(str)

    return str

  readDate: () ->
    ref = @readInteger(false)

    if ref & 1
      u = @readNumber()
      d = new Date(u)
      @addObject(d)
      return d
    else
      idx = ref >> 1
      return @getObjectFromReference(idx)

  readArray: () ->
    length = @readInteger(false)
    # TODO: check for reference
    if (length & REFERENCE_BIT) is 0
      return @getObjectFromReference(length >> 1)
    length = length >> 1
    key = @readString()
    if length is  0
      return []
    if key is '' or key is null
      object = (@readValue() for i in [1..length])
      @addObject(object)
      return object
    else
      object = {}
      while key
        object[key] = @readValue()
        key = @readString()
      
      for i in [1..length]
        object[i] = @readValue()
      
      @addObject(object)
      return object

  readObject: () ->
    ref = @readInteger(false)
    object = null

    if (ref & REFERENCE_BIT) is 0
      return @getObjectFromReference(ref >> 1)
    
    if (ref & 1)

      if (ref & 2)
        
        if (ref & 4)
          ref = ref >> 1
          klass = @_getClassDefinition(ref)
          object = klass._readamf(@)
        else
          name = @readString()

          encodingRef = ref >> 1
          encodingRef = encodingRef >> 1
          thing = new ASObject(name)
          thing.encoding = (encodingRef & 0x03)

          if thing.encoding is ObjectEncoding.STATIC
            thing._readKeys(@, ref)
          @addClass(name, thing)
          object = thing._readamf(@)
      else
        idx = ref >> 2
        classData = @getClassFromReference(idx)
        klass = classData.klass
        #object = new klass.constructor()
        #object.keys = klass.keys
        object = klass._readamf(@)

      @addObject(object)
    else
      idx = ref >> 1
      return @getObjectFromReference(idx)
    return object

  readByteArray: () ->
    ref = @readInteger(false)
    if ref & 1
      length = ref >> 1
      data = @buffer.slice(@offset, @offset+length)
      @offset += length
      @addObject(data)
      return data
    else
      idx = ref >> 1
      return @getObjectFromReference(idx)

  _readLength: () ->
    x = @readInteger(false)
    return [x >> 1, (x & REFERENCE_BIT) == 0]
  
  _getClassDefinition: (ref) ->
    isRef = (ref & REFERENCE_BIT) is 0
    ref = ref >> 1
    if isRef
      return @getClassFromReference(ref)
    name = @readString()

    if name is 'DSK'
      AcknowledgeMessage = require('./messaging').AcknowledgeMessage
      thing = new AcknowledgeMessage()
    else if name is 'flex.messaging.io.ArrayCollection'
      ArrayCollection = require('./messaging').ArrayCollection
      thing = new ArrayCollection()
    else if name is 'flex.messaging.messages.RemotingMessage'
    else
      process.exit()
    
    @addClass(name, thing)
    return thing

  _decodeInt: (signed = false) ->
    n = result = 0
    b = @buffer[@offset]
    @offset += 1

    while (b & 0x80) != 0 and (n < 3)
      result = (result << 7) | (b & 0x7F)

      b = @buffer[@offset]
      @offset += 1

      n += 1

    if n < 3
      result = (result << 7) | b
    else
      result = (result << 8) | b

      if result & 0x10000000 != 0
        if signed
          result -= 0x20000000
        else
          result = result << 1
          result += 1
    
    return result

typeOf = (object) ->
   return null if object is null
   return undefined if object is undefined
   funcNameRegex = /function (.{1,})\(/
   results = (funcNameRegex).exec((object).constructor.toString())
   if results && results.length > 1
     return results[1]
   else
     return ''


class Encoder extends AMFContext
  endian: 'big'
  offset: 0
  buffers: []

  constructor: (@buffer, @offset = 0) ->
    @buffer = new Buffer(10485760) unless @buffer

  getBuffer: () ->
    @buffer.slice(0, @offset)

  writeValue: (value) ->
    switch typeOf(value)
      when null then @writeNull()
      when undefined then @writeUndefined()
      when "Float" then @writeNumber(value.value)
      when "Number" then @writeInteger(value)
      when "String" then @writeString(value)
      when "Array" then @writeArray(value)
      when "Object" then @writeObject(value)
      when "Boolean" then @writeBoolean(value)
      when "Buffer" then @writeByteArray(value)
      when "Date" then @writeDate(value)
      else
        @writeObject(value)

  writeType: (type) ->
    @buffer[@offset] = type
    @offset += 1

  writeBoolean: (bool) ->
    if bool
      @writeType(TYPE_BOOL_TRUE)
    else
      @writeType(TYPE_BOOL_FALSE)

  writeUndefined: () ->
    @writeType(TYPE_UNDEFINED)

  writeNull: () ->
    @writeType(TYPE_NULL)

  writeNumber: (num, writeType = true) ->
    @writeType(TYPE_NUMBER) if writeType
    @buffer.writeDoubleBE(num, @offset, @endian)
    @offset += 8

  writeInteger: (num, writeType = true) ->
    if num < MIN_29B_INT or num > MAX_29B_INT
      @writeNumber(num, writeType)
    else
      @writeType(TYPE_INTEGER) if writeType
      for byte in @_encodeInteger(num)
        @buffer[@offset] = byte
        @offset += 1

  writeString: (str, writeType = true) ->
    @writeType(TYPE_STRING) if writeType

    len = Buffer.byteLength(str)

    if len is 0
      @writeType(REFERENCE_BIT)
      return
    
    ref = @getStringReference(str)
    if ref != -1
      @writeInteger(ref << 1, false)
      return

    @addString str

    flag = (len << 1) | REFERENCE_BIT
    
    @writeInteger(flag, false)
    @buffer.write(str, @offset, 'utf8')
    @offset += len
    
  writeArray: (ary, isProxy = false) ->
    @writeType(TYPE_ARRAY)
    
    ref = @getObjectReference(ary)
    if ref != -1
      @writeInteger(ref << 1, false)
      return

    @addObject(ary)

    flag = (ary.length << 1) | REFERENCE_BIT
    
    @writeInteger(flag, false)

    @buffer[@offset] = 0x01
    @offset += 1
    
    @writeValue(value) for value in ary

  writeDict: (object, isProxy = false) ->
    @writeType(TYPE_ARRAY)

    ref = @getObjectReference(object)
    if ref != -1
      @writeInteger(ref << 1)
      return
    
    @addObject(object)

    intKeys = []
    strKeys = []

    for own key, value of object
      if Number(key) isnt NaN and Math.floor(Number(key)) is Number(key)
        intKeys.push(key)
      else
        strKeys.push(key.toString())

    for int in intKeys
      if intKeys.length < int <= 0
        # treat as string
        strKeys.push(int.toString())
        intKeys = intKeys.filter (item) ->
          item isnt int

    intKeys.sort()

    flag = (intKeys.length << 1) | REFERENCE_BIT
    @writeInteger(flag, false)

    for key in strKeys
      @writeString(key, false)
      @writeValue(object[key])

    @writeType(0x01)

    for int in intKeys
      @writeValue(object[int])

  writeObject: (object, isProxy = false) ->
    @writeType(TYPE_OBJECT)

    # TODO: reference stuff
    ref = @getObjectReference(object)
    if ref != -1
      @writeInteger(ref << 1)
      return

    className = object.alias or object.name

    @addObject(object)
    idx = @getClassReference(className)
    classRef = false

    unless idx is -1
      classRef = true
      classData = @getClassFromReference(idx)
      definition = classData.klass
    else
      classData = @findClass(typeOf(object))

      if classData
        definition = classData.klass
      else
        definition = require('./messaging').ASObject
        definition.name = object.name
      @addClass(className, definition)
      classData = @_classReferences[@_classReferences.length-1]
    
    if classRef
      @writeInteger(classData.reference, false)
      # TODO: Write reference
    else
      ref = 0
      if object.encoding != ObjectEncoding.EXTERNAL
        ref += object.keys.length << 4

      finalRef = (ref | (object.encoding << 2) | (REFERENCE_BIT << 1) | REFERENCE_BIT)
      
      @writeInteger(finalRef, false)
      
      classData.reference = ((classData.reference << 2) | REFERENCE_BIT)
    unless classRef
      @writeString(className, false)

      if object.encoding != ObjectEncoding.EXTERNAL
        @writeString(key, false) for key in object.keys
      
    object._writeamf(@)

    
  writeDate: (date) ->
    @writeType(TYPE_DATE)
    ref = @getObjectReference(date)

    if ref != -1
      @writeInteger(ref << 1, false)
      return

    @addObject(date)

    @writeType(REFERENCE_BIT)
    if date.getTime
      @writeNumber(date.getTime(), false)
    else
      @writeNumber(date, false)

  writeByteArray: (buffer) ->
    @writeType(TYPE_BYTEARRAY)

    ref = @getObjectReference(buffer)
    if ref != -1
      @writeInteger(ref << 1, false)
      return

    @addObject(buffer)

    @writeInteger((buffer.length << 1) | REFERENCE_BIT, false)
    buffer.copy(@buffer, @offset)
    @offset += buffer.length

  _encodeInteger: (num) ->
    if num < 0
      num += 0x20000000
    
    bytes = []
    realValue = null

    if num > 0x1fffff
      realValue = num
      num = num >> 1
      bytes.push(0x80 | ((num >> 21) & 0xff))

    if num > 0x3fff
      bytes.push(0x80 | ((num >> 14) & 0xff))

    if num > 0x7f
      bytes.push(0x80 | ((num >> 7) & 0xff))

    if realValue is not null
      num = realValue

    if num > 0x1fffff
      bytes.push(num & 0xff)
    else
      bytes.push(num & 0x7f)

    #ENCODED_INT_CACHE[num] = bytes

    return bytes


exports.ObjectEncoding = ObjectEncoding
exports.Decoder = Decoder
exports.Encoder = Encoder

