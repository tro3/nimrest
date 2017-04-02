import times, oids, tables, json
import nimongo.bson

# ------------- type: BsonType -------------------#

const timeFormat = "yyyy-MM-dd'T'HH:mm:sszzz"

type BsonTypeKind* = enum
  btBool
  btInt
  btFloat
  btString
  btTime
  btId
  btRef
  btList
  btDoc

type BsonType* = ref object
  required*: bool
  case kind*: BsonTypeKind
  of btBool:
    defaultBool*: bool
  of btInt:
    defaultInt*: int
  of btFloat:
    defaultFloat*: float
  of btString:
    defaultString*: string
  of btTime:
    defaultTime*: Time
  of btId:
    discard
  of btRef:
    collection*: string
    fields*: Table[string, BsonType]
  of btDoc:
    schema*: Table[string, BsonType]
  of btList:
    subtype*: BsonType

proc toString*(sch:BsonType):string =
  case sch.kind:
  of btBool:
    result = "bool"
  of btInt:
    result = "int"
  of btFloat:
    result = "float"
  of btString:
    result = "string"
  of btTime:
    result = "time"
  of btRef:
    result = "ref"
  of btId:
    result = "id"
  of btDoc:
    result = "doc"
  of btList:
    result = "list"

proc convertToJson*(sch:BsonType, b:Bson=nil):JsonNode =
  case sch.kind
  of btBool:
    if b == nil or b.kind != BsonKindBool:
      return newJBool(sch.defaultBool)
    else:
      return newJBool(b)
  of btInt:
    if b == nil or b.kind notin [BsonKindInt32,BsonKindInt64]:
      return newJInt(sch.defaultInt)
    else:
      return newJInt(b)
  of btFloat:
    if b == nil or b.kind != BsonKindDouble:
      return newJFloat(sch.defaultFloat)
    else:
      return newJFloat(b)
  of btString:
    if b == nil or b.kind != BsonKindStringUTF8:
      return newJString(sch.defaultString)
    else:
      return newJString(b)
  of btTime:
    if b == nil or b.kind != BsonKindTimeUTC:
      return newJString(format(sch.defaultTime.getGMTime,timeFormat))
    else:
      return newJString(format(b.getGMTime,timeFormat))
  of btId:
    if b == nil or b.kind != BsonKindOid:
      return newJNull()
    else:
      return newJString($b.toOid)
  of btRef:
    if b == nil or b.kind != BsonKindDocument:
      return newJNull()
    result = newJObject()
    for k,v in sch.fields:
      result[k] = v.convertToJson(b[k])
  of btDoc:
    let null = b == nil or b.kind != BsonKindDocument
    result = newJObject()
    for k,v in sch.schema:
      if null:  result[k] = v.convertToJson(nil)
      else:     result[k] = v.convertToJson(b[k])
  of btList:
    if b == nil or b.kind != BsonKindArray:
      return newJArray()
    result = newJArray()
    for v in b.items:
      result.add(sch.subtype.convertToJson(v))
  else:
    discard


template typecheck(exp:untyped):untyped =
  try: return exp
  except: raise newException(ObjectConversionError, "Can't convert")

template convertToBson(j, jval, b, kinds, default: untyped):untyped =
  if j != nil:                       typecheck(j.jval.toBson)
  elif b != nil and b.kind in kinds: return b
  else:                              return sch.default.toBson

proc toTime(j:JsonNode):Time = parse(j.str, timeFormat).toTime

proc toOid(j:JsonNode):Oid = parseOid(cstring(j.str))

proc mergeToBson*(sch:BsonType, j:JsonNode, b:Bson=nil):Bson =
  case sch.kind
  of btBool:   convertToBson(j, bval, b, [BsonKindBool], defaultBool)
  of btInt:    convertToBson(j, num, b, [BsonKindInt32,BsonKindInt64], defaultInt)
  of btFloat:  convertToBson(j, fnum, b, [BsonKindDouble], defaultFloat)
  of btString: convertToBson(j, str, b, [BsonKindStringUTF8], defaultString)
  of btTime:   convertToBson(j, toTime, b, [BsonKindTimeUTC], defaultTime)
  of btId:
    if j != nil:                             typecheck(j.toOid.toBson)
    elif b != nil and b.kind == BsonKindOid: return b
    else:                                    return null()
  of btRef:
    if j != nil and j.kind == JString:
      typecheck(parseOid(cstring(j.str)).toBson)
    elif j != nil and j.kind == JObject and j.hasKey("_id"):
      typecheck(parseOid(cstring(j["_id"].str)).toBson)
    elif j != nil:
      raise newException(ObjectConversionError, "Can't convert")
    elif b != nil and b.kind in [BsonKindOid,BsonKindDocument]:
      return b
    else:
      return null()
  of btDoc:
    if j != nil and j.kind != JObject:
      raise newException(ObjectConversionError, "Can't convert")
    let jnull = j == nil
    let bnull = b == nil or b.kind != BsonKindDocument
    result = newBsonDocument()
    for k,v in sch.schema:
      var jn:JsonNode
      var bn:Bson
      if jnull or not j.hasKey(k): jn = nil
      else:                        jn = j[k]
      if bnull or not b.contains(k): bn = nil
      else:                          bn = b[k]
      result[k] = v.mergeToBson(jn, bn)
  of btList:
    if j != nil and j.kind != JArray:
      raise newException(ObjectConversionError, "Can't convert")
    let jnull = j == nil
    let bnull = b == nil or b.kind != BsonKindArray
    case sch.subtype.kind:
    of btDoc:
      if jnull and bnull:
        return newBsonArray()
      elif jnull and not bnull:
        result = newBsonArray()
        for v in b.items:
          result.add(sch.subtype.mergeToBson(nil,v))
      elif not jnull:
        result = newBsonArray()
        # TODO: match by _ids if array of objects
        for i,v in j.elems:
          var bval:Bson = nil
          if not bnull and i < b.len-1:
            bval = b[i]
          result.add(sch.subtype.mergeToBson(v,bval))
    else:
      if jnull and bnull:
        return newBsonArray()
      elif jnull and not bnull:
        result = newBsonArray()
        for v in b.items:
          result.add(sch.subtype.mergeToBson(nil,v))
      elif not jnull:
        result = newBsonArray()
        for v in j.elems:
          result.add(sch.subtype.mergeToBson(v,nil))




  else:
    discard
