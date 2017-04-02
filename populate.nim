import tables
import nimongo.mongo, nimongo.bson
import schema


proc populate*(self:BsonSchema, db:Database, x:Bson):Bson =
  case self.kind:
  of bsDoc:
    result = newBsonDocument()
    for key, sch in self.schema:
      if sch.kind in [bsDoc, bsList] and x.contains(key):
        result[key] = self.subtype.populate(db, x[key])
      elif sch.kind == bsRef:
        let cursor = db[sch.collection].find(%*{"_id": x[key]})
        if cursor.count() > 0:
          result[key] = cursor.one()
        else:
          result[key] = "Broken Reference".toBson()
      else:
        result[key] = x[key]
  of bsList:
    if self.subtype.kind notin [bsDoc, bsList]:
      return x
    result = newBsonArray()
    for item in x:
      result.add(self.subtype.populate(db, item))
  else:
    raise newException(AssertionError, "Populate only applies to documents and lists")
