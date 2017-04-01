import unittest, uri, httpcore, tables, asynchttpserver
import router

suite "route helpers":
  test "match full":
    let r = newRoute(SUBROUTE, ALL, "/api/@collection/@id")
    let m = match(r, HttpGet, "/api/projects/12")
    check(m.matched)
    check(m.params["collection"] == "projects")
    check(m.params["id"] == "12")
    check(m.path == "/")
    check(m.partial == false)
  test "match partial":
    let r = newRoute(SUBROUTE, ALL, "/api/@collection")
    let m = match(r, HttpGet, "/api/projects/12")
    check(m.matched)
    check(m.params["collection"] == "projects")
    check(m.path == "/12")
    check(m.partial == true)
  test "nonmatch longer":
    let r = newRoute(SUBROUTE, ALL, "/api/@collection")
    let m = match(r, HttpGet, "/api")
    check(not m.matched)
  test "match root":
    let r = newRoute(SUBROUTE, ALL, "/")
    let m = match(r, HttpGet, "/")
    check(m.matched)
    check(m.partial == false)
  test "match root 2":
    let r = newRoute(SUBROUTE, ALL, "/")
    let m = match(r, HttpGet, "")
    check(m.matched)
    check(m.partial == false)
  test "match method":
    let r = newRoute(SUBROUTE, POST, "/")
    let m = match(r, HttpGet, "/")
    check(not m.matched)
    let m2 = match(r, HttpPost, "/")
    check(m2.matched)
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

  test "router state processing":
    proc t1(s:var ReqState) =
      s.send(s.data["pre"] & s.params["id"])
    proc t2(s:var ReqState) =
      s.data["pre"] = "Hello "
    proc t3(s:var ReqState) =
      s.data["pre"] = "Goodbye "

    let r2 = newRouter()
    r2.use("/projects/@id", t1)

    r.get(t2)
    r.post(t3)
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
