import unittest, asynchttpserver, tables, oids, httpcore, times, json
import nimongo.mongo, nimongo.bson
import api_router, router, schema

template j(x:untyped):untyped = json.`%*`(x)
template b(x:untyped):untyped = bson.`%*`(x)


suite "getItem":

  setup:
    let conn = newMongo()
    if not conn.connect():
      raise newException(IOError, "No mongo connection")
    let db = conn["test"]
    db["users"].insert(b({
      "_id": parseOid("012345670123456701234567"),
      "name": "Fred",
    }))
    db["projects"].insert(b({
      "_id": parseOid("012345670123456701234568"),
      "name": "Manhatthan",
      "owner": parseOid("012345670123456701234567"),
    }))
    db["projects"].insert(b({
      "_id": parseOid("012345670123456701234569"),
      "name": "Manhatthan",
      "owner": parseOid("01234567012345670123456a"),
    }))
    let users = db["users"]
    let projects = db["projects"]

  teardown:
    discard projects.drop()
    discard users.drop()

  test "basic find":
    var s = newState(db, Request())
    s.params["id"] = "012345670123456701234568"
    getItem(s)
    check(s.code == Http200)
    check(s.body == $j({
      "_status": "OK",
      "_item": {
        "owner": {
        "_id": "012345670123456701234567",
        "name": "Fred"
        },
        "_id": "012345670123456701234568",
        "name": "Manhatthan",
      }
    }))

  test "not found":
    var s = newState(db, Request())
    s.params["id"] = "01234567012345670123456b"
    getItem(s)
    check(s.code == Http404)
    check(s.body == "Not Found")
