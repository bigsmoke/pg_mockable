---
pg_extension_name: pg_mockable
pg_extension_version: 0.1.3
pg_readme_generated_at: 2022-12-30 14:59:35.472552+00
pg_readme_version: 0.1.2
---

The `pg_mockable` PostgreSQL extension can be used to create mockable versions
of functions from other schemas.

## Installation

To make the extension files available to PostgreSQL:

```
make install
```

To make the extension available in the current database:

```sql
create extension pg_mockable cascade;
```

You _can_ install the extension into a different schema, but choose your schema
name wisely, since `pg_mockable` is _not_ relocatable.

## Usage

First, use `mockable.wrap_function()` to create a very thin function wrapper for whichever function you
wish to wrap:

```sql
call mockable.wrap_function('pg_catalog.now()`);
```

This call will bring into being: `mockable.now()`, which just does a `return pg_catalog.now()`.

If, for some reason, this fails, you can specify the precise `CREATE OR REPLACE FUNCTION` statement as the
second argument to `wrap_function()`:

```sql
call mockable.wrap_function('pg_catalog.now', $$
create or replace function mockable.now()
    returns timestamptz
    stable
    language sql
    return pg_catalog.now();
$$);
```

In fact, this example won't work, because `mockable.now()` _always_ exists, because the need to mock `now()`
was the whole reason that this extension was created in the first place.

## Object reference

### Tables

### Table: `mockable.mock_memory`

### Routines

#### Function: `mockable."current_date"()`

`current_date()` is derived from `now()`.  To mock it, mock `now()`.

#### Function: `mockable."current_time"()`

`current_time()` is derived from `now()`.  To mock it, mock `now()`.

Unlike its standard (PostgreSQL) counterpart, `current_time()` does not support a precision parameter.
Feel free to implement it.

#### Function: `mockable."current_timestamp"()`

`current_timestamp()` is derived from `now()`.  To mock it, mock `now()`.

Unlike its standard (PostgreSQL) counterpart, `current_timestamp()` does not support a precision parameter.
Feel free to implement it.

#### Function: `mockable."localtime"()`

`localtime()` is derived from `now()`.  To mock it, mock `now()`.

Unlike its standard (PostgreSQL) counterpart, `localtime()` does not support a precision parameter.
Feel free to implement it.

#### Function: `mockable."localtimestamp"()`

`localtimestamp()` is derived from `now()`.  To mock it, mock `now()`.

Unlike its standard (PostgreSQL) counterpart, `localtimestamp()` does not support a precision parameter.
Feel free to implement it.

#### Function: `mockable.mock(regprocedure,anyelement)`

#### Function: `mockable.now()`

#### Function: `mockable.pg_mockable_meta_pgxn()`

Returns the JSON meta data that has to go into the `META.json` file needed for
[PGXN—PostgreSQL Extension Network](https://pgxn.org/) packages.

The `Makefile` includes a recipe to allow the developer to: `make META.json` to
refresh the meta file with the function's current output, including the
`default_version`.

`pg_rowalesce` can indeed be found on PGXN: https://pgxn.org/dist/pg_mockable/

#### Function: `mockable.pg_mockable_readme()`

#### Function: `mockable.pg_proc(regprocedure)`

Conveniently go from function calling signature description or OID (`regprocedure`) to `pg_catalog.pg_proc`.

Example:

```sql
select pg_proc('pg_catalog.current_setting(text, bool)');
```

#### Procedure: `mockable.test__pg_mockable()`

#### Function: `mockable.timeofday()`

#### Function: `mockable.transaction_timestamp()`

#### Procedure: `mockable.unmock(regprocedure)`

#### Procedure: `mockable.wrap_function(regprocedure)`

#### Procedure: `mockable.wrap_function(regprocedure,text)`

## Colophon

This `README.md` for the `pg_mockable` `extension` was automatically generated using the
[`pg_readme`](https://github.com/bigsmoke/pg_readme) PostgreSQL
extension.
