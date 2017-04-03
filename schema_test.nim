import unittest, times, tables, oids, json
import nimongo.bson
import schema


const timeFormat = "yyyy-MM-dd'T'HH:mm:sszzz"

suite "bson/json conversion":
  setup:
    let sch = BsonType(
      kind: btDoc,
      schema: {
        "bool": BsonType(
          kind: btBool,
          defaultBool: false
        ),
        "int": BsonType(
          kind: btInt,
          defaultInt: 5
        ),
        "float": BsonType(
          kind: btFloat,
          defaultFloat: 5.5
        ),
        "string": BsonType(
          kind: btString,
          defaultString: "dflt"
        ),
        "time": BsonType(
          kind: btTime,
          defaultTime: parse("2015-01-01T00:00:00+00:00", timeFormat).toTime
        ),
        "id": BsonType(
          kind: btId,
        ),
        "intlist": BsonType(
          kind: btList,
          subtype: BsonType(
            kind: btInt,
            defaultInt: 0,
          ),
        ),
        "objlist": BsonType(
          kind: btList,
          subtype: BsonType(
            kind: btDoc,
            schema: {
              "name": BsonType(
                kind: btString,
                defaultString: "Bob",
              ),
            }.toTable,
          ),
        ),
        "ref": BsonType(
          kind: btRef,
          fields: {
            "name": BsonType(
              kind: btString,
              defaultString: "Bob",
            ),
          }.toTable,
        ),
      }.toTable,
    )

  test "bson->json values":
    let b = bson.`%*`({
      "bool":true,
      "int":2,
      "float":2.2,
      "string":"Bob",
      "id": parseOid(cstring("123456781234567812345678")),
      "time": parse("2017-01-01T00:00:00+00:00",timeFormat).toTime,
      "intlist": @[1,2,3],
      "objlist": [{"name":"Fred"}],
      "ref": {
        "_id": "123456781234567812345679",
        "name": "George",
        "age": 22,
      },
      "extra": "",
    })
    let j = sch.convertToJson(b)
    check(j["bool"].bval == true)
    check(j["int"].num == 2)
    check(j["float"].fnum == 2.2)
    check(j["string"].str == "Bob")
    check(j["time"].str == "2017-01-01T00:00:00+00:00")
    check(j["id"].str == "123456781234567812345678")
    check(j["intlist"].elems[0].num == 1)
    check(j["intlist"].elems[2].num == 3)
    check(j["objlist"].elems[0]["name"].str == "Fred")
    check(j["ref"].fields["name"].str == "George")
    check(j["ref"].hasKey("age") == false)
    check(j.hasKey("extra") == false)

  test "bson->json default values":
    let j = sch.convertToJson()
    check(j["bool"].bval == false)
    check(j["int"].num == 5)
    check(j["float"].fnum == 5.5)
    check(j["string"].str == "dflt")
    check(j["time"].str == "2015-01-01T00:00:00+00:00")
    check(j["id"].kind == JNull)
    check(len(j["intlist"]) == 0)
    check(len(j["objlist"]) == 0)
    check(j["ref"].kind == JNull)
    check(j.hasKey("extra") == false)

  test "bson->json error values":
    let b = bson.`%*`({
      "bool":10.2,
      "int":"a",
      "float":"b",
      "string":5,
      "id": 28,
      "time": "hello",
      "intlist": "howdy",
      "objlist": "yo",
      "ref": "oy",
      "extra": "",
    })
    let j = sch.convertToJson(b)
    check(j["bool"].bval == false)
    check(j["int"].num == 5)
    check(j["float"].fnum == 5.5)
    check(j["string"].str == "dflt")
    check(j["time"].str == "2015-01-01T00:00:00+00:00")
    check(j["id"].kind == JNull)
    check(len(j["intlist"]) == 0)
    check(len(j["objlist"]) == 0)
    check(j["ref"].kind == JNull)
    check(j.hasKey("extra") == false)

  test "json->bson values":
    let j = json.`%*`({
      "bool":true,
      "int":2,
      "float":2.2,
      "string":"Bob",
      "time": "2017-01-01T00:00:00+00:00",
      "id": "123456781234567812345678",
      "intlist": @[1,2,3],
      "objlist": [{"name":"Fred"}],
      "ref": {
        "_id": "123456781234567812345679",
        "name": "George",
        "age": 22,
      },
      "extra": "",
    })
    let b = sch.mergeToBson(j)
    check(b["bool"].toBool == true)
    check(b["int"].toInt == 2)
    check(b["float"].toFloat64 == 2.2)
    check(b["string"].toString == "Bob")
    check(b["time"].toTime == parse("2017-01-01T00:00:00+00:00",timeFormat).toTime)
    check(b["id"].toOid == parseOid(cstring("123456781234567812345678")))
    check(b["ref"].toOid == parseOid(cstring("123456781234567812345679")))
    check(b["intlist"][0].toInt == 1)
    check(b["intlist"][2].toInt == 3)
    check(b["objlist"][0]["name"].toString == "Fred")
    check(b.contains("extra") == false)

  test "json->bson pass-through values":
    let j:JsonNode = nil
    let bi = bson.`%*`({
      "bool":true,
      "int":2,
      "float":2.2,
      "string":"Bob",
      "time": parse("2017-01-01T00:00:00+00:00",timeFormat).toTime,
      "id": parseOid(cstring("123456781234567812345678")),
      "intlist": @[1,2,3],
      "objlist": [{"name":"Fred"}],
      "ref": parseOid(cstring("123456781234567812345679")),
      "extra": "",
    })
    let b = sch.mergeToBson(j, bi)
    check(b["bool"].toBool == true)
    check(b["int"].toInt == 2)
    check(b["float"].toFloat64 == 2.2)
    check(b["string"].toString == "Bob")
    check(b["time"].toTime == parse("2017-01-01T00:00:00+00:00",timeFormat).toTime)
    check(b["id"].toOid == parseOid(cstring("123456781234567812345678")))
    check(b["ref"].toOid == parseOid(cstring("123456781234567812345679")))
    check(b["intlist"][0].toInt == 1)
    check(b["intlist"][2].toInt == 3)
    check(b["objlist"][0]["name"].toString == "Fred")
    check(b.contains("extra") == false)

  test "json->bson prototype values":
    let j:JsonNode = nil
    let bi = bson.`%*`({})
    let b = sch.mergeToBson(j, bi)
    check(b["bool"].toBool == false)
    check(b["int"].toInt == 5)
    check(b["float"].toFloat64 == 5.5)
    check(b["string"].toString == "dflt")
    check(b["time"].toTime == parse("2015-01-01T00:00:00+00:00",timeFormat).toTime)
    check(b["id"].kind == BsonKindNull)
    check(b["ref"].kind == BsonKindNull)
    check(b["intlist"].len == 0)
    check(b["objlist"].len == 0)

  test "json->bson error values":
    let js = @[
      json.`%*`({"bool":10.2}),
      json.`%*`({"int":"a"}),
      json.`%*`({"float":"b"}),
      json.`%*`({"string":5}),
      json.`%*`({"id": 28}),
      json.`%*`({"time": "hello"}),
      json.`%*`({"intlist": "howdy"}),
      json.`%*`({"objlist": "yo"}),
      json.`%*`({"ref": 12}),
    ]
    for j in js:
      expect ObjectConversionError:
        discard sch.mergeToBson(j)
        echo "not thrown"
