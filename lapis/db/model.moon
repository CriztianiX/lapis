
db = require "lapis.db"
db.set_logger require "lapis.logging"

import underscore, escape_pattern from require "lapis.util"
import insert, concat from table

class Model
  @timestamp: false
  @primary_key: "id"

  @primary_keys: =>
    if type(@primary_key) == "table"
      unpack @primary_key
    else
      @primary_key

  @encode_key = (...) =>
    if type(@primary_key) == "table"
      { k, select i, ... for i, k in ipairs @primary_key }
    else
      { [@primary_key]: ... }

  @table_name = =>
    name = underscore @__name
    @table_name = -> name
    name

  @load: (tbl) =>
    setmetatable tbl, @__base

  @load_all: (tbls) =>
    [@load t for t in *tbls]

  @select: (query, ...) =>
    query = db.interpolate_query query, ...
    tbl_name = db.escape_identifier @table_name!
    if res = db.select "* from #{tbl_name} #{query}"
      @load_all res

  -- include references to this model in a list of records based on a foreign
  -- key
  @include_in: (other_records, foreign_key) =>
    if type(@primary_key) == "table"
      error "model must have singular primary key to include"

    include_ids = for record in *other_records
      with id = record[foreign_key]
        continue unless id

    if next include_ids
      flat_ids = concat [db.escape_literal id for id in *include_ids], ", "
      primary = db.escape_identifier @primary_key
      tbl_name = db.escape_identifier @table_name!

      if res = db.select "* from #{tbl_name} where #{primary} in (#{flat_ids})"
        records = {}
        for t in *res
          records[t[@primary_key]] = @load t
        field_name = foreign_key\match "^(.*)_#{escape_pattern(@primary_key)}$"

        for other in *other_records
          other[field_name] = records[other[foreign_key]]

    other_records

  -- find by primary key, or by table of conds
  @find: (...) =>
    cond = if "table" == type select 1, ...
      db.encode_assigns (...), nil, "and"
    else
      db.encode_assigns @encode_key(...), nil, "and"

    table_name = db.escape_identifier @table_name!

    if result = unpack db.select "* from #{table_name} where #{cond} limit 1"
      @load result

  -- create from table of values, return loaded object
  @create: (values) =>
    values._timestamp = true if @timestamp
    res = db.insert @table_name!, values, @primary_keys!
    if res
      if res.resultset
        for k,v in pairs res.resultset[1]
          values[k] = v
      @load values

  @check_unique_constraint: (name, value) =>
    cond = db.encode_assigns { [name]: value }
    table_name = db.escape_identifier @table_name!
    res = unpack db.select "COUNT(*) as c from #{table_name} where #{cond}"
    res.c > 0

  delete: =>
    cond = { key, @[key] for key in *{@@primary_keys!} }
    db.delete @@table_name!, cond

{ :Model }

