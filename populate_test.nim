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
    db["projects"].insert(%*{
      "_id": parseOid("012345670123456701234569"),
      "name": "Manhatthan",
      "owner": parseOid("01234567012345670123456a"),
    })
    let users = db["users"]
    let projects = db["projects"]

    let schUser = BsonType(
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
    let schProject = BsonType(
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
          fields: schUser.schema
        ),
      }.toTable
    )

  teardown:
    discard projects.drop()
    discard users.drop()

  test "basic":
    var proj = projects.find(%*{"_id": parseOid("012345670123456701234568")}).one()
    proj = schProject.populate(db, proj)
    check(proj["owner"]["name"].toString() == "Fred")

  test "broken reference":
    var proj = projects.find(%*{"_id": parseOid("012345670123456701234569")}).one()
    proj = schProject.populate(db, proj)
    check(proj["owner"].toString() == "Broken Reference")
