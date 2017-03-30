import router, tables, json

var dbEntry = %* {
  "_id": "2",
  "name": "Manhattan project",
  "subdoc": {
    "auth": true
  }
}

proc get(s:var ReqState) =
  s.json($dbEntry)


proc apiRouter*():Router =
  result = newRouter()
  result.get("/projects/@id", get)
