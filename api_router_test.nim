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
      "name": "Brooklyn",
      "owner": parseOid("012345670123456701234567"),
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
    check(s.body == "Not found")


suite "getList":

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
      "name": "Brooklyn",
      "owner": parseOid("012345670123456701234567"),
    }))
    let users = db["users"]
    let projects = db["projects"]

  teardown:
    discard projects.drop()
    discard users.drop()

  test "basic find":
    var s = newState(db, Request())
    getList(s)
    check(s.code == Http200)
    check(s.body == $j({
      "_status": "OK",
      "_items": [{
        "owner": {
          "_id": "012345670123456701234567",
          "name": "Fred"
        },
        "_id": "012345670123456701234568",
        "name": "Manhatthan",
      },{
        "owner": {
          "_id": "012345670123456701234567",
          "name": "Fred"
        },
        "_id": "012345670123456701234569",
        "name": "Brooklyn",
      }]
    }))

  test "query find":
    var s = newState(db, Request())
    s.query["query"] = """{"name":"Brooklyn"}"""
    getList(s)
    check(s.code == Http200)
    check(s.body == $j({
      "_status": "OK",
      "_items": [{
        "owner": {
          "_id": "012345670123456701234567",
          "name": "Fred"
        },
        "_id": "012345670123456701234569",
        "name": "Brooklyn",
      }]
    }))

  test "not found":
    var s = newState(db, Request())
    s.query["query"] = """{"name":"Fred"}"""
    getList(s)
    check(s.code == Http200)
    check(s.body == $j({
      "_status": "OK",
      "_items": []
    }))


suite "createView":

  setup:
    let conn = newMongo()
    if not conn.connect():
      raise newException(IOError, "No mongo connection")
    let db = conn["test"]
    db["users"].insert(b({
      "_id": parseOid("012345670123456701234567"),
      "name": "Fred",
    }))
    let users = db["users"]
    let projects = db["projects"]

  teardown:
    discard projects.drop()
    discard users.drop()

  test "basic create":
    let req = Request(
      body: """{
      "owner": {
        "_id": "012345670123456701234567",
        "name": "Fred"
      },
      "_id": "012345670123456701234568",
      "name": "Manhattan"
      }"""
    )
    var s = newState(db, req)
    createView(s)
    check(s.code == Http200)
    let body = parseJson(s.body)
    check(body["_status"].str == "OK")
    check(body["_item"]["_id"].str != "012345670123456701234568")
    check(body["_item"]["owner"]["_id"].str == "012345670123456701234567")
    check(body["_item"]["name"].str == "Manhattan")
    let cur = db["projects"].find(bson.`%*`({}))
    check(cur.count() == 1)
    let doc = cur.one()
    check(doc["_id"].kind != BsonKindNull)
    check(doc["_id"].toOid != parseOid("012345670123456701234568"))
    check(doc["owner"].toOid == parseOid("012345670123456701234567"))
    check(doc["name"].toString == "Manhattan")

  test "field errors":
    let req = Request(
      body: """{
      "owner": {
        "_id": "012345670123456701234567",
        "name": "Fred"
      },
      "_id": "012345670123456701234568",
      "name": 123
      }"""
    )
    var s = newState(db, req)
    createView(s)
    check(s.code == Http200)
    let body = parseJson(s.body)
    check(body["_status"].str == "ERR")
    check(body["_msg"].str == "Can't convert 123 to string")
    let cur = db["projects"].find(bson.`%*`({}))
    check(cur.count() == 0)


suite "updateView":

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
    let users = db["users"]
    let projects = db["projects"]

  teardown:
    discard projects.drop()
    discard users.drop()

  test "basic update":
    let req = Request(
      body: """{
      "owner": {
        "_id": "012345670123456701234567",
        "name": "Fred"
      },
      "_id": "012345670123456701234568",
      "name": "Manhattan 2"
      }"""
    )
    var s = newState(db, req)
    s.params["id"] = "012345670123456701234568"
    updateView(s)
    check(s.code == Http200)
    let body = parseJson(s.body)
    check(body["_status"].str == "OK")
    check(body["_item"]["_id"].str == "012345670123456701234568")
    check(body["_item"]["owner"]["_id"].str == "012345670123456701234567")
    check(body["_item"]["name"].str == "Manhattan 2")
    let cur = db["projects"].find(bson.`%*`({}))
    check(cur.count() == 1)
    let doc = cur.one()
    check(doc["_id"].toOid == parseOid("012345670123456701234568"))
    check(doc["owner"].toOid == parseOid("012345670123456701234567"))
    check(doc["name"].toString == "Manhattan 2")

  test "field errors":
    let req = Request(
      body: """{
      "owner": {
        "_id": "012345670123456701234567",
        "name": "Fred"
      },
      "_id": "012345670123456701234568",
      "name": 123
      }"""
    )
    var s = newState(db, req)
    s.params["id"] = "012345670123456701234568"
    updateView(s)
    check(s.code == Http200)
    let body = parseJson(s.body)
    check(body["_status"].str == "ERR")
    check(body["_msg"].str == "Can't convert 123 to string")
    let cur = db["projects"].find(bson.`%*`({}))
    check(cur.count() == 1)
