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
      name: "name",
      required: true,
      kind: btString
    ),
    "cost": BsonType(
      name: "cost",
      kind: btInt,
      defaultInt: 100
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

proc getItem*(rs:var ReqState) =
  let cur = rs.db["projects"].find(bson.`%*`({"_id": parseOid(rs.params["id"])}))  # Get query
  if cur.count() == 0:                                                           # 404 if no result
    rs.notFound()
    return
  let doc = projectSchema.populate(rs.db, cur.one())                              # Get doc
  var jdoc = projectSchema.convertToJson(doc)                                    # Jsonify doc
  # Check authorization                                                          # Check auth: 404 if denied
  # Remove unauthorized fields                                                   # Apply field permissions
  rs.json(wrap(jdoc))

proc getList*(rs:var ReqState) =
  var spec = newBsonDocument()
  if rs.query.hasKey("query"):                                                    # Get query
    let jspec = parseJson(rs.query["query"])
    spec = specFromJson(jspec)
  var docs = rs.db["projects"].find(spec).all()                                   # get docs
  docs = projectSchema.populate(rs.db, docs)
  var jdocs = projectSchema.convertToJson(docs)                                  # Jsonify docs
  # For item in jdocs: remove unauthorized docs                                  # Apply doc permissions
  # For item in jdocs: remove unauthorized fields                                # Apply field permissions
  rs.json(wrap(jdocs))


proc createView*(rs:var ReqState) =
  # Check permission

  var jdata:JsonNode
  try: jdata = parseJson(rs.req.body)
  except: rs.malformedData()

  # Check other field permissions
  var doc:Bson
  try: doc = projectSchema.mergeToBson(jdata)
  except ObjectConversionError: rs.jsonError(getCurrentExceptionMsg())

  doc["_id"] = genOid().toBson()
  discard rs.db["projects"].insert(doc)

  doc = projectSchema.populate(rs.db, doc)
  var jdoc = projectSchema.convertToJson(doc)
  # Remove unauthorized fields                                                   # Apply field permissions
  rs.json(wrap(jdoc))


proc updateView*(rs:var ReqState) =
  # Check permission

  var jdata:JsonNode
  try: jdata = parseJson(rs.req.body)
  except: rs.malformedData()

  # Check other field permissions
  let spec = bson.`%*`({"_id": parseOid(rs.params["id"])})
  let cur = rs.db["projects"].find(spec)                                          # Get query
  if cur.count() == 0: rs.notFound()

  var doc:Bson
  try: doc = projectSchema.mergeToBson(jdata, cur.one())                         # Get doc
  except ObjectConversionError: rs.jsonError(getCurrentExceptionMsg())

  discard rs.db["projects"].update(spec, doc, false, false)

  doc = projectSchema.populate(rs.db, doc)
  var jdoc = projectSchema.convertToJson(doc)

  # Remove unauthorized fields                                                   # Apply field permissions
  rs.json(wrap(jdoc))



proc apiRouter*():Router =
  result = newRouter()
  result.get("/projects", getList)
  result.post("/projects", createView)
  result.get("/projects/@id", getItem)
  result.put("/projects/@id", updateView)
