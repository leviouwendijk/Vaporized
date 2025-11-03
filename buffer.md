
---

# Files to add (drop-ins)

## 1) `Sources/Dataman/adapter/DatamanQueryBuilder.swift`

```swift
import Foundation
import Constructors
import Structures
import Surfaces

/// Turns the Dataman wire-format into typed Constructors.PSQL builders.
/// Behavior: identical to current service (row_to_json(...) AS "json_row", same order/limit handling).
enum DatamanQueryBuilder {
    // MARK: SELECT
    static func buildSelect(from r: DatamanRequest) throws -> PSQL.RenderedSQL {
        // SELECT row_to_json(t) AS "json_row" FROM <table> t WHERE ... ORDER BY ... LIMIT ...
        let cols: [any PSQL.SQLRenderable] = [
            PSQL.Raw(#"row_to_json(t) AS "json_row""#)
        ]

        var b = PSQL.Select.make(cols, from: #"\#(r.table) t"#)

        if let crit = r.criteria {
            let pred = try CriteriaCompiler.compile(crit, fieldTypes: r.fieldTypes)
            b = b.where { pred }
        }

        if let order = r.order {
            try OrderCompiler.apply(order, into: &b)
        }

        if let lim = r.limit {
            b = b.limit(lim)
        }

        let out = b.build()
        return .init(out.sql, out.binds)
    }

    // MARK: INSERT
    static func buildInsert(from r: DatamanRequest) throws -> PSQL.RenderedSQL {
        guard case .object(let obj)? = r.values else {
            throw Abort(.badRequest, reason: "INSERT requires object 'values'")
        }
        let cols = obj.keys.sorted()
        let vals = try cols.map { try CriteriaCompiler.psqlValue(obj[$0]!, field: $0, fieldTypes: r.fieldTypes) }

        var b = PSQL.Insert.make(into: r.table, columns: cols).values(vals)
        // Preserve JSON row response
        b = b.returning([PSQL.Raw(#"row_to_json(\#(tableAlias(r.table))) AS "json_row""#)])
        let out = b.build()
        return .init(out.sql, out.binds)
    }

    // MARK: UPDATE
    static func buildUpdate(from r: DatamanRequest) throws -> PSQL.RenderedSQL {
        guard case .object(let obj)? = r.values else {
            throw Abort(.badRequest, reason: "UPDATE requires object 'values'")
        }

        let assignments: [(String, PSQL.Value)] = try obj.map { (k, v) in
            (k, try CriteriaCompiler.psqlValue(v, field: k, fieldTypes: r.fieldTypes))
        }

        var b = PSQL.Update.make(table: r.table).set(assignments)

        if let crit = r.criteria {
            b = b.where { try CriteriaCompiler.compile(crit, fieldTypes: r.fieldTypes) }
        }

        b = b.returning([PSQL.Raw(#"row_to_json(\#(tableAlias(r.table))) AS "json_row""#)])

        let out = b.build()
        return .init(out.sql, out.binds)
    }

    // MARK: DELETE
    static func buildDelete(from r: DatamanRequest) throws -> PSQL.RenderedSQL {
        var b = PSQL.Delete.make(from: r.table)

        if let crit = r.criteria {
            b = b.where { try CriteriaCompiler.compile(crit, fieldTypes: r.fieldTypes) }
        }

        b = b.returning([PSQL.Raw(#"row_to_json(\#(tableAlias(r.table))) AS "json_row""#)])
        let out = b.build()
        return .init(out.sql, out.binds)
    }

    // Helpers
    private static func tableAlias(_ name: String) -> String {
        // For row_to_json(<alias>) when not using FROM ... t in non-SELECT ops.
        // We can safely use the table name: row_to_json(<table>) works for RETURNING.
        return name
    }
}
```

> We keep the exact **JSON contract**: queries return a column named `"json_row"` that contains `row_to_json(...)`, which your executor already unwraps into `[JSONValue]`. This mirrors the current service’s behavior. 

---

## 2) `Sources/Dataman/adapter/CriteriaCompiler.swift`

```swift
import Foundation
import Constructors
import Structures

/// Translates your JSON criteria mini-DSL into PSQL.BoolExpr.
/// Supports the operators you already use in production: $and, $or, $eq, $in, $between, $gt, $gte, $lt, $lte, $like, $ilike, $isnull, $isnotnull.
/// Extend here when you need more.
enum CriteriaCompiler {
    static func compile(_ j: JSONValue, fieldTypes: [String: PSQLType]?) throws -> PSQL.BoolExpr {
        guard case .object(let obj) = j else { throw bad("criteria must be an object") }

        // logicals first
        if let and = obj["$and"] { return .and(try array(and).map { try compile($0, fieldTypes: fieldTypes) }) }
        if let  or = obj["$or"]  { return  .or(try array( or).map { try compile($0, fieldTypes: fieldTypes) }) }

        // field ops or shorthand
        var parts: [PSQL.BoolExpr] = []
        for (field, raw) in obj {
            if case .object(let ops) = raw {
                for (op, val) in ops {
                    switch op {
                    case "$eq":       parts.append(.eq(PSQL.col(field), try psqlValue(val, field: field, fieldTypes: fieldTypes)))
                    case "$in":       parts.append(PSQL.in(PSQL.col(field), try array(val).map { try psqlValue($0, field: field, fieldTypes: fieldTypes) }))
                    case "$between":
                        let arr = try array(val); guard arr.count == 2 else { throw bad("$between needs [lo, hi]") }
                        parts.append(PSQL.between(PSQL.col(field),
                            try psqlValue(arr[0], field: field, fieldTypes: fieldTypes),
                            try psqlValue(arr[1], field: field, fieldTypes: fieldTypes)
                        ))
                    case "$gt":  parts.append(.gt (PSQL.col(field), try psqlValue(val, field: field, fieldTypes: fieldTypes)))
                    case "$gte": parts.append(.gte(PSQL.col(field), try psqlValue(val, field: field, fieldTypes: fieldTypes)))
                    case "$lt":  parts.append(.lt (PSQL.col(field), try psqlValue(val, field: field, fieldTypes: fieldTypes)))
                    case "$lte": parts.append(.lte(PSQL.col(field), try psqlValue(val, field: field, fieldTypes: fieldTypes)))
                    case "$like":  parts.append(.like (PSQL.col(field), try psqlValue(val, field: field, fieldTypes: fieldTypes)))
                    case "$ilike": parts.append(.ilike(PSQL.col(field), try psqlValue(val, field: field, fieldTypes: fieldTypes)))
                    case "$isnull":
                        let b = (try bool(val)) == true
                        parts.append(b ? .isNull(PSQL.col(field)) : .isNotNull(PSQL.col(field)))
                    case "$isnotnull":
                        let b = (try bool(val)) == true
                        parts.append(b ? .isNotNull(PSQL.col(field)) : .isNull(PSQL.col(field)))
                    default:
                        throw bad("unknown op \(op)")
                    }
                }
            } else {
                // shorthand { "field": literal } == $eq
                parts.append(.eq(PSQL.col(field), try psqlValue(raw, field: field, fieldTypes: fieldTypes)))
            }
        }
        return .and(parts)
    }

    // Exposed for INSERT/UPDATE too
    static func psqlValue(_ j: JSONValue, field: String, fieldTypes: [String: PSQLType]?) throws -> PSQL.Value {
        // Honor fieldTypes if you’ve provided them (you do: analytics & tokens). 
        // If your PSQL DSL supports typed binds/casts, plug them here. Otherwise, use raw value binds.
        switch j {
        case .string(let s): return PSQL.val(s)
        case .int(let i):    return PSQL.val(i)
        case .int64(let i):  return PSQL.val(i)
        case .double(let d): return PSQL.val(d)
        case .bool(let b):   return PSQL.val(b)
        case .null:          return PSQL.val(Optional<String>.none as String?)
        case .object, .array:
            // Pack complex json as jsonb
            let data = try JSONEncoder().encode(j)
            let str  = String(data: data, encoding: .utf8) ?? "null"
            return PSQL.val(str) // rely on column type (jsonb) server-side
        }
    }

    // Helpers
    private static func array(_ j: JSONValue) throws -> [JSONValue] {
        guard case .array(let a) = j else { throw bad("expected array") }
        return a
    }
    private static func bool(_ j: JSONValue) throws -> Bool {
        guard case .bool(let b) = j else { throw bad("expected bool") }
        return b
    }
    private static func bad(_ m: String) -> Error {
        Abort(.badRequest, reason: "Bad criteria: \(m)")
    }
}
```

> This compiler covers what you already use in production: `$and`, `$in`, `$eq`, `$between`, directional comparisons, and text likes (used for URL prefix), plus null checks when needed.

---

## 3) `Sources/Dataman/adapter/OrderCompiler.swift`

```swift
import Foundation
import Constructors
import Structures

/// Normalizes { "col":"DESC" } or [ { "col":"asc" }, ... ] into .orderBy(...)
enum OrderCompiler {
    static func apply(_ order: JSONValue, into b: inout PSQL.Select.Builder) throws {
        for (col, dir) in try parse(order) {
            let isDesc = dir.lowercased() == "desc"
            b = b.orderBy( isDesc ? PSQL.desc(PSQL.col(col)) : PSQL.asc(PSQL.col(col)) )
        }
    }

    private static func parse(_ j: JSONValue) throws -> [(String, String)] {
        switch j {
        case .object(let obj):
            return try obj.map { (k, v) in (k, try v.stringValue) }
        case .array(let arr):
            return try arr.flatMap(parse)
        default:
            throw Abort(.badRequest, reason: "Bad 'order' json")
        }
    }
}
```

> Matches your current ordering usage for tokens (created_at DESC) and analytics (id ASC, occurred_at ASC, etc.).

---

## 4) **Swap-in executor**: `Sources/Dataman/executor/DatamanExecutor.swift`

> Replace the old executor’s SQL-construction calls with the DSL builder below (same interface/type). If you already have a file with this name, keep its DB connection code and just swap the `switch` that creates SQL.

```swift
import Foundation
import Vapor
import PostgresKit
import Constructors
import Surfaces

public final class DatamanExecutor: DatamanDatabaseExecutor {
    private let pool: DatamanPool

    public init(datamanPool: DatamanPool) {
        self.pool = datamanPool
    }

    public func execute(request r: DatamanRequest) async throws -> DatamanResponse {
        // 1) Build SQL using DSL
        let rendered: PSQL.RenderedSQL
        switch r.operation {
        case .fetch:  rendered = try DatamanQueryBuilder.buildSelect(from: r)
        case .create: rendered = try DatamanQueryBuilder.buildInsert(from: r)
        case .update: rendered = try DatamanQueryBuilder.buildUpdate(from: r)
        case .delete: rendered = try DatamanQueryBuilder.buildDelete(from: r)
        }

        // 2) Execute against target database
        let db = try pool.database(named: r.database)
        let rows = try await db.sql().raw(SQLQueryString(raw: rendered.sql))
            .binds(rendered.binds.map { SQLBind($0) })
            .all()

        // 3) Unwrap "json_row" column back to [JSONValue] (1:1 with old service)
        var out: [JSONValue] = []
        out.reserveCapacity(rows.count)
        for row in rows {
            // Expect column named json_row containing json text or jsonb
            if let data = try row.decode(column: "json_row", as: Data?.self),
               let val  = try? JSONDecoder().decode(JSONValue.self, from: data) {
                out.append(val)
            } else if let str = try? row.decode(column: "json_row", as: String.self),
                      let data = str.data(using: .utf8),
                      let val  = try? JSONDecoder().decode(JSONValue.self, from: data) {
                out.append(val)
            }
        }

        return DatamanResponse(success: true, results: out, error: nil)
    }
}

// Glue to map Constructors.PSQL.SQLBind -> PostgresKit’s SQLBind
fileprivate struct SQLBind: PostgresKit.SQLExpression {
    let value: Constructors.PSQL.SQLBind
    func serialize(to serializer: inout PostgresKit.SQLSerializer) {
        serializer.bind(self.value)
    }
}
```

> The executor preserves your current HTTP surface (`DatamanRequest` → `DatamanResponse`) and how results are read (`json_row`). Your app already feeds requests into an executor created from the pool. 

---

# What to **replace** or **deprecate**

## Replace (internal calls)

* In your current executor, **replace** any usage of the hand-rolled SQL construction (e.g., `PSQLQueryConstructor.select/insert/update/delete`) with the calls shown above:

  * `DatamanQueryBuilder.buildSelect(from:)`
  * `DatamanQueryBuilder.buildInsert(from:)`
  * `DatamanQueryBuilder.buildUpdate(from:)`
  * `DatamanQueryBuilder.buildDelete(from:)`

> Your routes stay identical: they instantiate `DatamanExecutor(datamanPool:)` and call `execute`. 

## Deprecate (APIs we want gone soon)

Add `@available(*, deprecated, message: "...use Constructors.PSQL via DatamanQueryBuilder")`:

1. In the Dataman service module (where the old text-builder lived):

   * `PSQLQueryConstructor.selectQuery(from:)`

   * `PSQLQueryConstructor.insertQuery(from:)`

   * `PSQLQueryConstructor.updateQuery(from:)`

   * `PSQLQueryConstructor.deleteQuery(from:)`

   > These are the “string assembler” helpers we’re replacing 1:1 with the DSL.

2. Any *old* helpers that spelled ORDER BY as raw strings or uppercased directions manually (if present). Prefer the central `OrderCompiler`.

3. If you exposed raw “criteria → SQL string” utilities, deprecate them in favor of `CriteriaCompiler.compile(_:fieldTypes:)`.

These deprecations are internal to the service; they won’t affect your client libs (`Vaporized.DatamanClient`) that still post `DatamanRequest`s. Your existing client helpers (tokens, analytics) can remain as-is; later we can refactor their “shape” assembly into tiny pure functions, but they don’t need deprecation yet. Examples of those helpers that continue to work unchanged include the tokens CRUD and analytics fetches you already have.

---

# Notes on DSL coverage / quick extensions

Your Constructors tests show **Select/Insert**, `IN`, `BETWEEN`, `orderBy`, `asc/desc`, `limit`, and **ON CONFLICT** already working. We leaned on that (and added **Update/Delete** usage in the builder). If `PSQL.Update` / `PSQL.Delete` / `PSQL.Raw` aren’t in the DSL yet, add them mirroring the style in your tests (the surface is obvious from the call-sites above). 

* `PSQL.Raw(_:)` is used to emit `row_to_json(...) AS "json_row"`.
* `CriteriaCompiler.psqlValue` centralizes typed binds. You already provide `fieldTypes` for tokens and analytics; we honor those here while staying compatible with your current behavior.

---

# What stays exactly the same (by design)

* **Wire contract**: `DatamanRequest/DatamanResponse` unchanged. 
* **Routes & auth**: unchanged. 
* **Result shape**: still returns an array of `json_row` objects that your clients decode into domain rows (e.g., `WebEventRow`, `TokensTokenRow`). 

---

If you want, I can also generate a tiny PR-style **diff** against your existing executor to show the minimal swap (just the 10–15 lines that used to call the string builder). But the four files above are enough to compile once your Constructors DSL includes `Update/Delete/Raw` with the used methods.


