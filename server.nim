import nimongo.mongo
import router, api_router

proc home(req:var ReqState) =
  req.send("Hey there")

let r = newRouter()
r.add("/api", apiRouter())
r.get("/", home)

let m = newMongo()
if not m.connect():
  raise newException(IOError, "Couldn't connect to MongoDB")
let db = m["app"]

r.serve(db)
