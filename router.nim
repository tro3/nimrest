import asynchttpserver, asyncdispatch, tables, strutils, httpcore

type
  HandlerFunc = proc(state:var ReqState)
  Header = tuple[key:string, val:string]

  RouteType = enum
    SUBROUTE, HANDLER

  RouteMethod = enum
    ALL, GET, POST, PUT, DELETE

  RouteMatch = ref object
    match: bool
    partial: bool
    path: string
    params: Table[string, string]

  Route = ref object
    rMethod: RouteMethod
    path: string

    case rType: RouteType
    of SUBROUTE:
      router: Router
    of HANDLER:
      handler: HandlerFunc

  Router* = ref object
    routes: seq[Route]

  ReqState* = ref object
    req*: Request
    params*: Table[string, string]
    query*: Table[string, string]
    headers*: seq[Header]
    body*: string
    code: HttpCode
    handled: bool



# ------------- Helper Methods -------------

proc match(r:Route, m:HttpMethod, path:string):RouteMatch =
  new result
  result.match = false
  result.partial = false
  result.params = initTable[string,string]()

  case r.rMethod:
  of GET:
    if m notin [HttpGET]: return
  of POST:
    if m notin [HttpPOST]: return
  of PUT:
    if m notin [HttpPUT, HttpPATCH]: return
  of DELETE:
    if m notin [HttpDELETE]: return
  of ALL:
    discard

  let rdirs = r.path.strip(chars={'/'}).split('/')
  let pdirs = path.strip(chars={'/'}).split('/')
  if len(rdirs) > len(pdirs):
    return
  if len(rdirs) < len(pdirs):
    result.partial = true

  for ind, dir in rdirs:
    if dir[0] == '@':
      result.params[dir[1..len(dir)]] = pdirs[ind]
    elif ind < len(pdirs)-1 and pdirs[ind] != dir:
      return
  result.path = "/" & pdirs[len(rdirs)..len(pdirs)-1].join("/")
  result.match = true



# ------------- Route Methods -------------

proc newRoute(t:RouteType, m:RouteMethod, p:string):Route =
  new result
  result.rType = t
  result.rMethod = m
  result.path = p


# ------------- State Methods -------------

proc send*(self:ReqState, msg:string) =
  self.code = Http200
  self.body = msg
  self.handled = true

proc json*(self:ReqState, msg:string) =
  self.code = Http200
  self.headers.add(("Content-Type","application/json"))
  self.body = msg
  self.handled = true

proc notFound*(self:ReqState) =
  self.code = Http404
  self.body = "Not Found"
  self.handled = true

proc unauthorized*(self:ReqState) =
  self.code = Http403
  self.body = "Unauthorized"
  self.handled = true



# ------------- Router Methods -------------

proc newRouter*():Router =
  new result
  result.routes = newSeq[Route]()

proc add*(self:Router, path:string, router:Router) =
  let r = newRoute(SUBROUTE, ALL, path)
  r.router = router
  self.routes.add(r)

proc use*(self:Router, path:string, handler:HandlerFunc) =
  let r = newRoute(HANDLER, ALL, path)
  r.handler = handler
  self.routes.add(r)

proc get*(self:Router, path:string, handler:HandlerFunc) =
  let r = newRoute(HANDLER, GET, path)
  r.handler = handler
  self.routes.add(r)

proc post*(self:Router, path:string, handler:HandlerFunc) =
  let r = newRoute(HANDLER, POST, path)
  r.handler = handler
  self.routes.add(r)

proc put*(self:Router, path:string, handler:HandlerFunc) =
  let r = newRoute(HANDLER, PUT, path)
  r.handler = handler
  self.routes.add(r)

proc delete*(self:Router, path:string, handler:HandlerFunc) =
  let r = newRoute(HANDLER, DELETE, path)
  r.handler = handler
  self.routes.add(r)

proc processState(self:Router, state:var ReqState, path:string) =
  for route in self.routes:
    let m = match(route, state.req.reqMethod, path)
    if m.match:
      for k,v in m.params:
        state.params[k] = v
      if route.rType == SUBROUTE:
        route.router.processState(state, m.path)
      elif not m.partial:
        route.handler(state)
      if state.handled:
        break

proc processRequest(self:Router, req:Request):ReqState =
  result = ReqState(
    req: req,
    code: Http404,
    params: initTable[string, string](),
    query: initTable[string, string](),
    headers: newSeq[Header](),
    body: "Not found"
  )
  self.processState(result, req.url.path)

proc serve*(self:Router, port=8080) =
  proc cb(req:Request){.async.} =
    let state = self.processRequest(req)
    await req.respond(state.code, state.body, newHttpHeaders(state.headers))

  let server = newAsyncHttpServer()
  waitFor server.serve(Port(port), cb)



# ------------- Unit Tests -------------

when isMainModule:

  import unittest, uri

  suite "helpers":
    test "match full":
      let r = newRoute(SUBROUTE, ALL, "/api/@collection/@id")
      let m = match(r, HttpGet, "/api/projects/12")
      check(m.match)
      check(m.params["collection"] == "projects")
      check(m.params["id"] == "12")
      check(m.path == "/")
      check(m.partial == false)
    test "match partial":
      let r = newRoute(SUBROUTE, ALL, "/api/@collection")
      let m = match(r, HttpGet, "/api/projects/12")
      check(m.match)
      check(m.params["collection"] == "projects")
      check(m.path == "/12")
      check(m.partial == true)
    test "nonmatch longer":
      let r = newRoute(SUBROUTE, ALL, "/api/@collection")
      let m = match(r, HttpGet, "/api")
      check(not m.match)
    test "match root":
      let r = newRoute(SUBROUTE, ALL, "/")
      let m = match(r, HttpGet, "/")
      check(m.match)
      check(m.partial == false)
    test "match root 2":
      let r = newRoute(SUBROUTE, ALL, "/")
      let m = match(r, HttpGet, "")
      check(m.match)
      check(m.partial == false)
    test "match method":
      let r = newRoute(SUBROUTE, POST, "/")
      let m = match(r, HttpGet, "/")
      check(not m.match)
      let m2 = match(r, HttpPost, "/")
      check(m2.match)
      check(m.partial == false)

  suite "router":
    setup:
      var r = newRouter()

    test "router/add":
      let r2 = newRouter()
      r.add("/api", r2)
      check(len(r.routes) == 1)

    test "router/use":
      proc get(s:var ReqState) = discard
      r.use("/api", get)
      check(len(r.routes) == 1)

    test "state processing":
      proc t1(s:var ReqState) =
        s.body &= s.params["id"]
      proc t2(s:var ReqState) =
        s.body = "Hello "
      proc t3(s:var ReqState) =
        s.body = "Goodbye "

      let r2 = newRouter()
      r2.use("/projects/@id", t1)

      r.get("/", t2)
      r.post("/", t3)
      r.add("/api", r2)

      let req = Request(
        reqMethod: HttpGet,
        url: Uri(
          path: "/api/projects/34"
        )
      )
      let s = r.processRequest(req)
      check(s.body == "Hello 34")

      let req2 = Request(
        reqMethod: HttpPost,
        url: Uri(
          path: "/api/projects/34"
        )
      )
      let s2 = r.processRequest(req2)
      check(s2.body == "Goodbye 34")
