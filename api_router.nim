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

proc serializeDoc(db:Database[Mongo], x:Bson):JsonNode =
  let doc = projectSchema.populate(db, x)
  return projectSchema.convertToJson(doc)

proc serializeDocs(db:Database[Mongo], x:seq[Bson]):seq[JsonNode] =
  let docs = projectSchema.populate(db, x)
  return projectSchema.convertToJson(docs)

template itemSpec():untyped =
  bson.`%*`({"_id": parseOid(rs.params["id"])})

proc getItem*(rs:var ReqState) =
  let cur = rs.db["projects"].find(itemSpec())                                   # Get query
  if cur.count() == 0: rs.notFound()                                             # 404 if no result
  let doc = cur.one()                                                            # Get doc
  # Check authorization or 404                                                   # Check auth
  var jdoc = serializeDoc(rs.db, doc)                                            # Jsonify doc
  # Remove unauthorized fields                                                   # Apply field permissions
  rs.json(wrap(jdoc))

proc getList*(rs:var ReqState) =
  var spec = newBsonDocument()
  if rs.query.hasKey("query"):                                                   # Get query
    let jspec = parseJson(rs.query["query"])
    spec = specFromJson(jspec)
  var docs = rs.db["projects"].find(spec).all()                                  # get docs
  # For item in docs: remove unauthorized docs                                   # Apply doc permissions
  var jdocs = serializeDocs(rs.db, docs)                                         # Jsonify docs
  # For item in jdocs: remove unauthorized fields                                # Apply field permissions
  rs.json(wrap(jdocs))


proc createView*(rs:var ReqState) =
  # Check permission

  var jdata:JsonNode
  try:    jdata = parseJson(rs.req.body)
  except: rs.malformedData()

  # Check other field permissions
  var doc:Bson
  try:    doc = projectSchema.mergeToBson(jdata)
  except: rs.jsonError(getCurrentExceptionMsg())

  doc["_id"] = genOid().toBson()
  discard rs.db["projects"].insert(doc)

  var jdoc = serializeDoc(rs.db, doc)
  # Remove unauthorized fields                                                   # Apply field permissions
  rs.json(wrap(jdoc))


proc updateView*(rs:var ReqState) =
  # Check overall permission

  var jdata:JsonNode
  try:    jdata = parseJson(rs.req.body)
  except: rs.malformedData()

  # Check field permissions
  let cur = rs.db["projects"].find(itemSpec())                                   # Get query
  if cur.count() == 0: rs.notFound()                                             # 404 if not found

  var doc = cur.one()                                                            # Get doc
  # Check doc permission
  try:    doc = projectSchema.mergeToBson(jdata, doc)
  except: rs.jsonError(getCurrentExceptionMsg())

  discard rs.db["projects"].update(itemSpec(), doc, false, false)

  var jdoc = serializeDoc(rs.db, doc)
  # Remove unauthorized fields                                                   # Apply field permissions
  rs.json(wrap(jdoc))



proc apiRouter*():Router =
  result = newRouter()
  result.get("/projects", getList)
  result.post("/projects", createView)
  result.get("/projects/@id", getItem)
  result.put("/projects/@id", updateView)
