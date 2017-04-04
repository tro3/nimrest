import router, tables, oids, json
import nimongo.mongo, nimongo.bson
import schema, populate, spec


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
  return json.`%*`({
    "_status": "OK",
    "_item": x
  })

proc wrap(x:seq[JsonNode]):JsonNode =
  var xs = newJArray()
  for item in x:
    xs.add(item)
  return json.`%*`({
    "_status": "OK",
    "_items": xs
  })

proc getItem*(s:var ReqState) =
  let cur = s.db["projects"].find(bson.`%*`({"_id": parseOid(s.params["id"])}))  # Get query
  if cur.count() == 0:                                                           # 404 if no result
    s.notFound()
    return
  let doc = projectSchema.populate(s.db, cur.one())                              # Get doc
  var jdoc = projectSchema.convertToJson(doc)                                    # Jsonify doc
  # Check authorization                                                          # Check auth: 404 if denied
  # Remove unauthorized fields                                                   # Apply field permissions
  s.json(wrap(jdoc))

proc getList*(s:var ReqState) =
  var spec = newBsonDocument()
  if s.query.hasKey("query"):                                                    # Get query
    let jspec = parseJson(s.query["query"])
    spec = specFromJson(jspec)
  var docs = s.db["projects"].find(spec).all()                                   # get docs
  docs = projectSchema.populate(s.db, docs)
  var jdocs = projectSchema.convertToJson(docs)                                  # Jsonify docs
  # For item in jdocs: remove unauthorized docs                                  # Apply doc permissions
  # For item in jdocs: remove unauthorized fields                                # Apply field permissions
  s.json(wrap(jdocs))

proc createView*(s:var ReqState) =
  # Check permission
  var jdata:JsonNode
  try: jdata = parseJson(s.req.body)
  except:
    s.malformedData()
    return
  # Check other field permissions
  var doc:Bson
  try: doc = projectSchema.mergeToBson(jdata)
  except ObjectConversionError:
    s.json(json.`%*`({
      "_status": "ERR",
      "_msg": getCurrentExceptionMsg()
    }))
    return
  doc["_id"] = genOid().toBson()
  discard s.db["projects"].insert(doc)
  doc = projectSchema.populate(s.db, doc)
  var jdoc = projectSchema.convertToJson(doc)
  # Remove unauthorized fields                                                   # Apply field permissions
  s.json(wrap(jdoc))


proc apiRouter*():Router =
  result = newRouter()
  result.get("/projects/@id", getItem)
