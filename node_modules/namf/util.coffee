typeOf = (object) ->
   return null if object is null
   return undefined if object is undefined
   funcNameRegex = /function (.{1,})\(/
   results = (funcNameRegex).exec((object).constructor.toString())
   if results && results.length > 1
     return results[1]
   else
     return ''

class Float extends Number
  constructor: (num) ->
    @value = Number(num)

  valueOf: () ->
    @value

exports.typeOf = typeOf
exports.Float = Float
