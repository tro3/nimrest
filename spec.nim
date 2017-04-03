import json
import nimongo.bson

proc specFromJson*(x:JsonNode):Bson =
  case x.kind
  of JNull:   return null()
  of JBool:   return toBson(x.bval)
  of JInt:    return toBson(x.num)
  of JFloat:  return toBson(x.fnum)
  of JString: return toBson(x.str)
  of JObject:
    result = newBsonDocument()
    for k,v in x:
      result[k] = specFromJson(x[k])
  of JArray:
    result = newBsonArray()
    for v in x:
      result.add(specFromJson(v))
