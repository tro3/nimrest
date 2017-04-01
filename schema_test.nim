import unittest, times, tables, oids
import json except `%*`
import nimongo.bson
import schema


const timeFormat = "yyyy-MM-dd'T'HH:mm:sszzz"

suite "bson conversion to json":
  setup:
    let sch = BsonSchema(
      kind: bsDoc,
      schema: {
        "bool": BsonSchema(
          kind: bsBool,
          defaultBool: false
        ),
        "int": BsonSchema(
          kind: bsInt,
          defaultInt: 5
        ),
        "float": BsonSchema(
          kind: bsFloat,
          defaultFloat: 5.5
        ),
        "string": BsonSchema(
          kind: bsString,
          defaultString: "dflt"
        ),
        "time": BsonSchema(
          kind: bsTime,
          defaultTime: parse("2015-01-01T00:00:00+00:00", timeFormat).toTime
        ),
        "id": BsonSchema(
          kind: bsId,
        ),
        "intlist": BsonSchema(
          kind: bsList,
          subtype: BsonSchema(
            kind: bsInt,
            defaultInt: 0,
          ),
        ),
        "objlist": BsonSchema(
          kind: bsList,
          subtype: BsonSchema(
            kind: bsDoc,
            schema: {
              "name": BsonSchema(
                kind: bsString,
                defaultString: "Bob",
              ),
            }.toTable,
          ),
        ),
        "ref": BsonSchema(
          kind: bsRef,
          fields: {
            "name": BsonSchema(
              kind: bsString,
              defaultString: "Bob",
            ),
          }.toTable,
        ),
      }.toTable,
    )

  test "values":
    let b = %*{
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
    }
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

  test "default values":
    let j = sch.convertToJson(nil)
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

  test "error values":
    let b = %*{
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
    }
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
