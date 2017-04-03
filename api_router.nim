import router, tables, oids, json
import nimongo.mongo, nimongo.bson
import schema, populate

# var dbEntry = %* {
#   "_id": "2",
#   "name": "Manhattan project",
#   "subdoc": {
#     "auth": true
#   }
# }

let userSchema = BsonType(
  kind: btDoc,
  schema: {
    "_id": BsonType(
      kind: btId
    ),
    "name": BsonType(
      kind: btString
    ),
  }.toTable
)

let projectSchema = BsonType(
  kind: btDoc,
  schema: {
    "_id": BsonType(
      kind: btId
    ),
    "name": BsonType(
      kind: btString
    ),
    "owner": BsonType(
      kind: btRef,
      collection: "users",
      fields: userSchema.schema
    ),
  }.toTable
)

proc wrap(x:JsonNode):JsonNode =
  result = json.`%*`({
    "_status": "OK",
    "_item": x
  })

proc getItem*(s:var ReqState) =
  let cur = s.db["projects"].find(bson.`%*`({"_id": parseOid(s.params["id"])}))
  if cur.count() == 0:
    s.notFound()
  else:
    var doc = cur.one()
    doc = projectSchema.populate(s.db, doc)
    s.json(wrap(projectSchema.convertToJson(doc)))


proc apiRouter*():Router =
  result = newRouter()
  result.get("/projects/@id", getItem)
