today = ->
  weekdays = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday']
  day = (new Date).getDay()
  weekdays[day]

AMF0Encoder = (require './amf0').Encoder
AMF0Decoder = (require './amf0').Decoder

enc = new AMF0Encoder()

if today() is 'Wednesday'
  enc.writeString 'Yay its curry day!'
else
  enc.writeString 'Ah crap, its not curry day :('

# Just write some more random types
enc.writeString 'The answer to life, the universe and everything'
enc.writeNumber 42
enc.writeNull()
enc.writeUndefined()
enc.writeBoolean(true)
enc.writeBoolean(false)
enc.writeString 'All done, yo.'

console.log 'The encoded binary data:'
console.log enc.getBuffer()

logAll = (buffer) ->
  dec = new AMF0Decoder(buffer)
  while dec.offset < buffer.length
    console.log dec.readValue()

console.log "\nDecode it:"
logAll(enc.getBuffer())
