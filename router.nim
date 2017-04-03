import asynchttpserver, asyncdispatch, tables, strutils, httpcore, json
import nimongo.mongo

type
  HandlerFunc = proc(state:var ReqState)
  Header = tuple[key:string, val:string]

  RouteType* = enum
    SUBROUTE, HANDLER

  RouteMethod* = enum
    ALL, GET, POST, PUT, DELETE

  RouteMatch* = ref object
    matched*: bool
    partial*: bool
    path*: string
    params*: Table[string, string]

  Route* = ref object
    rMethod: RouteMethod
    path: string

    case rType: RouteType
    of SUBROUTE:
      router: Router
    of HANDLER:
      handler: HandlerFunc

  Router* = ref object
    routes*: seq[Route]

  ReqState* = ref object
    db*: Database[Mongo]
    req*: Request
    params*: Table[string, string]
    query*: Table[string, string]
    data*: Table[string, string]
    headers*: seq[Header]
    body*: string
    code*: HttpCode
    handled*: bool



# ------------- Helper Methods -------------

proc match*(r:Route, m:HttpMethod, path:string):RouteMatch =
  new result
  result.matched = false
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

  if r.path == "*":
    result.matched = true
    return

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
  result.matched = true



# ------------- Route Methods -------------

proc newRoute*(t:RouteType, m:RouteMethod, p:string):Route =
  new result
  result.rType = t
  result.rMethod = m
  result.path = p


# ------------- State Methods -------------

proc send*(self:ReqState, msg:string) =
  self.code = Http200
  self.body = msg
  self.handled = true

proc json*(self:ReqState, doc:JsonNode) =
  self.code = Http200
  self.headers.add(("Content-Type","application/json"))
  self.body = $doc
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

proc newState*(db:Database[Mongo], req:Request):ReqState =
  result = ReqState(
    db: db,
    req: req,
    code: Http404,
    params: initTable[string, string](),
    query: initTable[string, string](),
    data: initTable[string, string](),
    headers: newSeq[Header](),
    body: "Not found"
  )

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

proc use*(self:Router, handler:HandlerFunc) =
  let r = newRoute(HANDLER, ALL, "*")
  r.handler = handler
  self.routes.add(r)

proc get*(self:Router, handler:HandlerFunc) =
  let r = newRoute(HANDLER, GET, "*")
  r.handler = handler
  self.routes.add(r)

proc post*(self:Router, handler:HandlerFunc) =
  let r = newRoute(HANDLER, POST, "*")
  r.handler = handler
  self.routes.add(r)

proc put*(self:Router, handler:HandlerFunc) =
  let r = newRoute(HANDLER, PUT, "*")
  r.handler = handler
  self.routes.add(r)

proc delete*(self:Router, handler:HandlerFunc) =
  let r = newRoute(HANDLER, DELETE, "*")
  r.handler = handler
  self.routes.add(r)

proc processState(self:Router, state:var ReqState, path:string) =
  for route in self.routes:
    let m = match(route, state.req.reqMethod, path)
    if m.matched:
      for k,v in m.params:
        state.params[k] = v
      if route.rType == SUBROUTE:
        route.router.processState(state, m.path)
      elif not m.partial:
        route.handler(state)
      if state.handled:
        break

proc processRequest*(self:Router, db:Database[Mongo], req:Request):ReqState =
  result = newState(db, req)
  self.processState(result, req.url.path)

proc serve*(self:Router, db:Database[Mongo], port=8080) =
  proc cb(req:Request){.async.} =
    let state = self.processRequest(db, req)
    await req.respond(state.code, state.body, newHttpHeaders(state.headers))

  let server = newAsyncHttpServer()
  waitFor server.serve(Port(port), cb)
