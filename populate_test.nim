import unittest, oids, tables
import nimongo.mongo, nimongo.bson
import populate, schema

suite "populate":

  setup:
    let conn = newMongo()
    if not conn.connect():
      raise newException(IOError, "No mongo connection")
    let db = conn["test"]
    db["users"].insert(%*{
      "_id": parseOid("012345670123456701234567"),
      "name": "Fred",
    })
    db["projects"].insert(%*{
      "_id": parseOid("012345670123456701234568"),
      "name": "Manhatthan",
      "owner": parseOid("012345670123456701234567"),
    })
    let users = db["users"]
    let projects = db["projects"]

    let schUser = BsonSchema(
      kind: bsDoc,
      schema: {
        "_id": BsonSchema(
          kind: bsId
        ),
        "name": BsonSchema(
          kind: bsString
        ),
      }.toTable
    )
    let schProject = BsonSchema(
      kind: bsDoc,
      schema: {
        "_id": BsonSchema(
          kind: bsId
        ),
        "name": BsonSchema(
          kind: bsString
        ),
        "owner": BsonSchema(
          kind: bsRef,
          collection: "users",
          fields: schUser.schema
        ),
      }.toTable
    )

  teardown:
    discard projects.drop()
    discard users.drop()

  test "basics":
    var proj = projects.find(%*{}).one()
    proj = schProject.populate(db, proj)
    check(proj["owner"]["name"].toString() == "Fred")
