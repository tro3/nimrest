import times, oids, tables, json
import nimongo.bson

# ------------- type: BsonSchema -------------------#

const timeFormat = "yyyy-MM-dd'T'HH:mm:sszzz"

type BsonSchemaKind* = enum
  bsBool
  bsInt
  bsFloat
  bsString
  bsTime
  bsId
  bsRef
  bsList
  bsDoc

type BsonSchema* = ref object
  required*: bool
  case kind*: BsonSchemaKind
  of bsBool:
    defaultBool*: bool
  of bsInt:
    defaultInt*: int
  of bsFloat:
    defaultFloat*: float
  of bsString:
    defaultString*: string
  of bsTime:
    defaultTime*: Time
  of bsId:
    discard
  of bsRef:
    collection*: string
    fields*: Table[string, BsonSchema]
  of bsDoc:
    schema*: Table[string, BsonSchema]
  of bsList:
    subtype*: BsonSchema

proc toString*(sch:BsonSchema):string =
  case sch.kind:
  of bsBool:
    result = "bool"
  of bsInt:
    result = "int"
  of bsFloat:
    result = "float"
  of bsString:
    result = "string"
  of bsTime:
    result = "time"
  of bsRef:
    result = "ref"
  of bsId:
    result = "id"
  of bsDoc:
    result = "doc"
  of bsList:
    result = "list"

proc convertToJson*(sch:BsonSchema, b:Bson=nil):JsonNode =
  case sch.kind
  of bsBool:
    if b == nil or b.kind != BsonKindBool:
      return newJBool(sch.defaultBool)
    else:
      return newJBool(b)
  of bsInt:
    if b == nil or b.kind notin [BsonKindInt32,BsonKindInt64]:
      return newJInt(sch.defaultInt)
    else:
      return newJInt(b)
  of bsFloat:
    if b == nil or b.kind != BsonKindDouble:
      return newJFloat(sch.defaultFloat)
    else:
      return newJFloat(b)
  of bsString:
    if b == nil or b.kind != BsonKindStringUTF8:
      return newJString(sch.defaultString)
    else:
      return newJString(b)
  of bsTime:
    if b == nil or b.kind != BsonKindTimeUTC:
      return newJString(format(sch.defaultTime.getGMTime,timeFormat))
    else:
      return newJString(format(b.getGMTime,timeFormat))
  of bsId:
    if b == nil or b.kind != BsonKindOid:
      return newJNull()
    else:
      return newJString($b.toOid)
  of bsRef:
    if b == nil or b.kind != BsonKindDocument:
      return newJNull()
    result = newJObject()
    for k,v in sch.fields:
      result[k] = v.convertToJson(b[k])
  of bsDoc:
    let null = b == nil or b.kind != BsonKindDocument
    result = newJObject()
    for k,v in sch.schema:
      if null:  result[k] = v.convertToJson(nil)
      else:     result[k] = v.convertToJson(b[k])
  of bsList:
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

proc mergeToBson*(sch:BsonSchema, j:JsonNode, b:Bson=nil):Bson =
  case sch.kind
  of bsBool:
    if j != nil: typecheck(j.bval.toBson)
    elif b != nil and b.kind == BsonKindBool:
      return b
    else:
      return sch.defaultBool.toBson
  of bsInt:
    if j != nil: typecheck(j.num.toBson)
    elif b != nil and b.kind in [BsonKindInt32,BsonKindInt64]:
      return b
    else:
      return sch.defaultInt.toBson
  of bsFloat:
    if j != nil: typecheck(j.fnum.toBson)
    elif b != nil and b.kind == BsonKindDouble:
      return b
    else:
      return sch.defaultFloat.toBson
  of bsString:
    if j != nil: typecheck(j.str.toBson)
    elif b != nil and b.kind == BsonKindStringUTF8:
      return b
    else:
      return sch.defaultString.toBson
  of bsTime:
    if j != nil: typecheck(parse(j.str, timeFormat).toTime.toBson)
    elif b != nil and b.kind == BsonKindTimeUTC:
      return b
    else:
      return sch.defaultTime.toBson
  of bsId:
    if j != nil: typecheck(parseOid(cstring(j.str)).toBson)
    elif b != nil and b.kind == BsonKindOid:
      return b
    else:
      return null()
  of bsRef:
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
  of bsDoc:
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
  of bsList:
    if j != nil and j.kind != JArray:
      raise newException(ObjectConversionError, "Can't convert")
    let jnull = j == nil
    let bnull = b == nil or b.kind != BsonKindArray
    case sch.subtype.kind:
    of bsDoc:
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
