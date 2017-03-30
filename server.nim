import router, api_router

proc home(req:var ReqState) =
  req.send("Hey there")

let r = newRouter()
r.add("/api", apiRouter())
r.get("/", home)

r.serve()
