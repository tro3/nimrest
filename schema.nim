import times, oids, tables
import json except `%*`
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
    if b == nil or b.kind notin [
      BsonKind.BsonKindInt32,
      BsonKind.BsonKindInt64
    ]: return newJInt(sch.defaultInt)
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
