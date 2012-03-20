typeOf = (object) ->
   return null if object is null
   return undefined if object is undefined
   funcNameRegex = /function (.{1,})\(/
   results = (funcNameRegex).exec((object).constructor.toString())
   if results && results.length > 1
     return results[1]
   else
     return ''

class AMFContext
  clear: () ->
    @_objectReferences = []
    @_classReferences = []
    @_stringReferences = []

  _objectReferences: []
  _classReferences: []
  _registeredClasses: []
  _stringReferences: []

  getObjectFromReference: (ref) ->
    @_objectReferences[ref]

  getObjectReference: (object) ->
    @_objectReferences.indexOf(object)

  getClassFromReference: (ref) ->
    found = @_classReferences[ref]
    return found if found
    return -1

  getClassReference: (name) ->
    found = @_classReferences.filter (data) ->
      data.name == name
    if found.length > 0
      return @_classReferences.indexOf(found[0])
    return -1

  addObject: (object) ->
    @_objectReferences.push object

  addClass: (name, klass) ->
    ref = @_classReferences.length
    obj = {name: name, klass: klass, reference: ref}
    @_classReferences.push obj

  addString: (string) ->
    @_stringReferences.push string

  getStringReference: (string) ->
    @_stringReferences.indexOf(string)
  
  getStringFromReference: (ref) ->
    @_stringReferences[ref]

  findClass: (name) ->
    found = @_registeredClasses.filter (klass) ->
      klass.name is name
    if found.length > 0
      return found[0]
    else
      return false

  registerClass: (klass) ->
    @_registeredClasses.push({
      name: klass._amf.name
      alias: klass._amf.alias or klass._amf.name
      klass: klass
    })
    console.log @_registeredClasses

  getClassByName: (name) ->
    if name is 'ArrayCollection'
      return require('./messaging').ArrayCollection
    else if name is 'AcknowledgeMessage'
      return require('./messaging').AcknowledgeMessage
    else if name is 'ASObject'
      return require('./messaging').ASObject

  getClassByAlias: (alias) ->

  getClassByObject: (object) ->
    getClassByName(typeOf(object))

module.exports = exports = AMFContext
