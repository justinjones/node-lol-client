

#: Represented as 9 bytes: 1 byte for C{0x00} and 8 bytes a double
#: representing the value of the number.
TYPE_NUMBER      = 0x00
#: Represented as 2 bytes: 1 byte for C{0x01} and a second, C{0x00}
#: for C{False}, C{0x01} for C{True}.
TYPE_BOOL        = 0x01
#: Represented as 3 bytes + len(String): 1 byte C{0x02}, then a UTF8 string,
#: including the top two bytes representing string length as a C{int}.
TYPE_STRING      = 0x02
#: Represented as 1 byte, C{0x03}, then pairs of UTF8 string, the key, and
#: an AMF element, ended by three bytes, C{0x00} C{0x00} C{0x09}.
TYPE_OBJECT      = 0x03
#: MovieClip does not seem to be supported by Remoting.
#: It may be used by other AMF clients such as SharedObjects.
TYPE_MOVIECLIP   = 0x04
#: 1 single byte, C{0x05} indicates null.
TYPE_NULL        = 0x05
#: 1 single byte, C{0x06} indicates null.
TYPE_UNDEFINED   = 0x06
#: When an ActionScript object refers to itself, such C{this.self = this},
#: or when objects are repeated within the same scope (for example, as the
#: two parameters of the same function called), a code of C{0x07} and an
#: C{int}, the reference number, are written.
TYPE_REFERENCE   = 0x07
#: A MixedArray is indicated by code C{0x08}, then a Long representing the
#: highest numeric index in the array, or 0 if there are none or they are
#: all negative. After that follow the elements in key : value pairs.
TYPE_MIXEDARRAY  = 0x08
#: @see: L{TYPE_OBJECT}
TYPE_OBJECTTERM  = 0x09
#: An array is indicated by C{0x0A}, then a Long for array length, then the
#: array elements themselves. Arrays are always sparse; values for
#: inexistant keys are set to null (C{0x06}) to maintain sparsity.
TYPE_ARRAY       = 0x0A
#: Date is represented as C{0x0B}, then a double, then an C{int}. The double
#: represents the number of milliseconds since 01/01/1970. The C{int} represents
#: the timezone offset in minutes between GMT. Note for the latter than values
#: greater than 720 (12 hours) are represented as M{2^16} - the value. Thus GMT+1
#: is 60 while GMT-5 is 65236.
TYPE_DATE        = 0x0B
#: LongString is reserved for strings larger then M{2^16} characters long. It
#: is represented as C{0x0C} then a LongUTF.
TYPE_LONGSTRING  = 0x0C
#: Trying to send values which don't make sense, such as prototypes, functions,
#: built-in objects, etc. will be indicated by a single C{00x0D} byte.
TYPE_UNSUPPORTED = 0x0D
#: Remoting Server -> Client only.
#: @see: L{RecordSet}
#: @see: U{RecordSet structure on OSFlash
#: <http://osflash.org/documentation/amf/recordset>}
TYPE_RECORDSET   = 0x0E
#: The XML element is indicated by C{0x0F} and followed by a LongUTF containing
#: the string representation of the XML object. The receiving gateway may which
#: to wrap this string inside a language-specific standard XML object, or simply
#: pass as a string.
TYPE_XML         = 0x0F
#: A typed object is indicated by C{0x10}, then a UTF string indicating class
#: name, and then the same structure as a normal C{0x03} Object. The receiving
#: gateway may use a mapping scheme, or send back as a vanilla object or
#: associative array.
TYPE_TYPEDOBJECT = 0x10
#: An AMF message sent from an AVM+ client such as the Flash Player 9 may break
#: out into L{AMF3<pyamf.amf3>} mode. In this case the next byte will be the
#: AMF3 type code and the data will be in AMF3 format until the decoded object
#: reaches it's logical conclusion (for example, an object has no more keys).
TYPE_AMF3        = 0x11

AMFContext = require('./context')

class Decoder
  endian: 'big'
  offset: 0

  constructor: (@buffer, @offset = 0) ->

  readValue: () ->
    type = @buffer.readUInt8(@offset, @endian)
    @offset += 1
    value = switch type
      when TYPE_NUMBER then @readNumber()
      when TYPE_BOOL then @readBoolean()
      when TYPE_STRING then @readString()
      when TYPE_OBJECT then @readObject()
      when TYPE_NULL then @readNull()
      when TYPE_UNDEFINED then @readUndefined()
      when TYPE_REFERENCE then @readReference()
      when TYPE_MIXEDARRAY then @readMixedArray()
      when TYPE_ARRAY then @readList()
      when TYPE_DATE then @readDate()
      when TYPE_LONGSTRING then @readLongString()
      when TYPE_UNSUPPORTED then @readNull()
      #when TYPE_XML then @readXml()
      when TYPE_TYPEDOBJECT then @readTypedObject()
      when TYPE_AMF3 then @readAMF3()
      else
        console.log 'Undefined type'
    return value

  readNumber: () ->
    number = @buffer.readDoubleBE(@offset, @endian)
    @offset += 8
    number

  readBoolean: () ->
    number = @buffer.readUInt8(@offset, @endian)
    @offset += 1
    Boolean(number)

  readString: () ->
    length = @buffer.readUInt16BE(@offset, @endian)
    @offset += 2
    str = @buffer.toString('utf-8', @offset, @offset + length)
    @offset += length
    str

  readNull: () ->
    null

  readUndefined: () ->
    undefined

  readReference: () ->
    int = @buffer.readUInt8(@offset, @endian)
    @offset += 1

  readList: () ->
    len = @buffer.readUInt32BE(@offset, @endian)
    @offset += 4
    
    (@readValue() for i in [1..len])

  readMixedArray: () ->
    len = @buffer.readUInt32BE(@offset, @endian)
    @offset += 4

    (@readValue() for i in [1..len])

  readObject: () ->
    obj = {}
    
    while key = @readString()
      obj[key] = @readValue()

    @offset += 1 # Terminated by 0x09
    obj
  
  readTypedObject: () ->
    # TODO
    klass = @readString()
    @readObject()

  readAMF3: () ->
    AMF3Decoder = require('./amf3').Decoder
    amf3 = new AMF3Decoder(@buffer, @offset)
    amf3.clear()
    value = amf3.readValue()
    @offset = amf3.offset
    return value
    

class EncoderStream
  endian: 'big'
  constructor: () ->
    @buffer = new Buffer(0)

  write: (chunk) ->
    buffer = new Buffer(@buffer.length + chunk.length)
    @buffer.copy(buffer)
    chunk.copy(buffer, @buffer.length + 1)

  writeDouble: (double) ->
    b = new Buffer(8)
    b.writeDoubleBE(num, 0)
    @write(b)

  writeUInt8: (num) ->
    b = new Buffer(1)
    b.writeUInt8(num)
    @write(b)

  writeUInt16: (num) ->
    b = new Buffer(2)
    b.writeUInt16(2)
    @write(b)


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

  writeValue: (value) ->
    switch typeOf(value)
      when null then @writeNull()
      when undefined then @writeUndefined()
      when "Number" then @writeNumber(value)
      when "String" then @writeString(value)
      when "Array" then @writeList(value)
      when "Object" then @writeObject(value)
      when "ASObject" then @writeTypedObject(value)
      when "Boolean" then @writeBoolean(value)
      else
        if klass = @getClassByName(typeOf(value))
          if klass._amf.amf3
            @writeAMF3(value)

  getBuffer: () ->
    @buffer.slice(0, @offset)

  writeType: (type) ->
    @buffer[@offset] = type
    @offset += 1

  writeNumber: (num) ->
    @writeType(TYPE_NUMBER)
    @buffer.writeDoubleBE(num, @offset)
    @offset += 8

  writeBoolean: (bool) ->
    @writeType(TYPE_BOOL)

    if bool
      @buffer.writeUInt8(1, @offset, @endian)
    else
      @buffer.writeUInt8(0, @offset, @endian)
    @offset += 1

  writeString: (str, type = true) ->
    @writeType(TYPE_STRING) if type
    len = Buffer.byteLength(str)
    @buffer.writeUInt16BE(len, @offset)
    @offset += 2

    @buffer.write(str, @offset, 'utf-8')
    @offset += len

  writeNull: () ->
    @writeType(TYPE_NULL)

  writeUndefined: () ->
    @writeType(TYPE_UNDEFINED)

  writeList: (ary) ->
    @writeType(TYPE_ARRAY)

    @buffer.writeUInt32BE(ary.length, @offset, @endian)
    @offset += 4

    @writeValue(value) for value in ary

  writeObject: (object, type = true) ->
    @writeType(TYPE_OBJECT) if type
    
    for own key, value of object
      @writeString(key, false)
      @writeValue(value)
    
    # Object end
    @writeType(0x00)
    @writeType(0x00)
    @writeType(TYPE_OBJECTTERM)

  writeTypedObject: (object) ->
    @writeType(0x10)
    @writeString(object.name, false)
    @writeObject(object.object, false)

  
  writeAMF3: (value) ->
    @writeType(TYPE_AMF3)
    
    AMF3Encoder = require('./amf3').Encoder
    amf3 = new AMF3Encoder(@buffer, @offset)
    amf3.clear()
    amf3.writeValue(value)
    @offset = amf3.offset


exports.Encoder = Encoder
exports.Decoder = Decoder
