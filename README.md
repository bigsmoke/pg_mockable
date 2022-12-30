---
pg_extension_name: pg_mockable
pg_extension_version: 0.1.4
pg_readme_generated_at: 2022-12-30 15:11:54.160774+00
pg_readme_version: 0.3.4
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

There are 1 tables that directly belong to the `pg_mockable` extension.

#### Table: `mock_memory`

The `mock_memory` table has 2 attributes:

1. `mock_memory.routine_signature` `regprocedure`

   - `NOT NULL`
   - `PRIMARY KEY (routine_signature)`

2. `mock_memory.unmock_statement` `text`

### Routines

#### Function: `"current_date" ()`

`current_date()` is derived from `now()`.  To mock it, mock `now()`.

Function return type: `date`

Function attributes: `STABLE`

#### Function: `"current_time" ()`

`current_time()` is derived from `now()`.  To mock it, mock `now()`.

Unlike its standard (PostgreSQL) counterpart, `current_time()` does not support a precision parameter.
Feel free to implement it.

Function return type: `time with time zone`

Function attributes: `STABLE`

#### Function: `"current_timestamp" ()`

`current_timestamp()` is derived from `now()`.  To mock it, mock `now()`.

Unlike its standard (PostgreSQL) counterpart, `current_timestamp()` does not support a precision parameter.
Feel free to implement it.

Function return type: `timestamp with time zone`

Function attributes: `STABLE`

#### Function: `"localtime" ()`

`localtime()` is derived from `now()`.  To mock it, mock `now()`.

Unlike its standard (PostgreSQL) counterpart, `localtime()` does not support a precision parameter.
Feel free to implement it.

Function return type: `time without time zone`

Function attributes: `STABLE`

#### Function: `"localtimestamp" ()`

`localtimestamp()` is derived from `now()`.  To mock it, mock `now()`.

Unlike its standard (PostgreSQL) counterpart, `localtimestamp()` does not support a precision parameter.
Feel free to implement it.

Function return type: `timestamp without time zone`

Function attributes: `STABLE`

#### Function: `mockable.now ()`

Function return type: `timestamp with time zone`

Function attributes: `STABLE`, `RETURNS NULL ON NULL INPUT`

Function-local settings:

  *  `SET search_path TO mockable, public, pg_temp`

#### Function: `mockable.timeofday ()`

Function return type: `text`

Function attributes: `STABLE`

Function-local settings:

  *  `SET DateStyle TO Postgres`

#### Function: `mockable.transaction_timestamp ()`

Function return type: `timestamp with time zone`

Function attributes: `STABLE`

#### Function: `mock (regprocedure, anyelement)`

Function arguments:

| Arg. # | Arg. mode  | Argument name                                                     | Argument type                                                        | Default expression  |
| ------ | ---------- | ----------------------------------------------------------------- | -------------------------------------------------------------------- | ------------------- |
|   `$1` |       `IN` | `routine_signature$`                                              | `regprocedure`                                                       |  |
|   `$2` |       `IN` | `mock_value$`                                                     | `anyelement`                                                         |  |

Function return type: `anyelement`

Function-local settings:

  *  `SET search_path TO mockable, public, pg_temp`

#### Function: `pg_mockable_meta_pgxn ()`

Returns the JSON meta data that has to go into the `META.json` file needed for
[PGXN—PostgreSQL Extension Network](https://pgxn.org/) packages.

The `Makefile` includes a recipe to allow the developer to: `make META.json` to
refresh the meta file with the function's current output, including the
`default_version`.

`pg_rowalesce` can indeed be found on PGXN: https://pgxn.org/dist/pg_mockable/

Function return type: `jsonb`

Function attributes: `STABLE`

#### Function: `pg_mockable_readme ()`

Generates the text for a `README.md` in Markdown format using the amazing power
of the `pg_readme` extension.  Temporarily installs `pg_readme` if it is not
already installed in the current database.

Function return type: `text`

Function-local settings:

  *  `SET search_path TO mockable, public, pg_temp`
  *  `SET pg_readme.include_view_definitions_like TO true`
  *  `SET pg_readme.include_routine_definitions_like TO {test__%}`

#### Function: `pg_proc (regprocedure)`

Conveniently go from function calling signature description or OID (`regprocedure`) to `pg_catalog.pg_proc`.

Example:

```sql
select pg_proc('pg_catalog.current_setting(text, bool)');
```

Function arguments:

| Arg. # | Arg. mode  | Argument name                                                     | Argument type                                                        | Default expression  |
| ------ | ---------- | ----------------------------------------------------------------- | -------------------------------------------------------------------- | ------------------- |
|   `$1` |       `IN` |                                                                   | `regprocedure`                                                       |  |

Function return type: `pg_proc`

Function attributes: `STABLE`

Function-local settings:

  *  `SET search_path TO mockable, public, pg_temp`

#### Procedure: `test__pg_mockable ()`

Procedure-local settings:

  *  `SET search_path TO mockable, public, pg_temp`
  *  `SET plpgsql.check_asserts TO true`

```
CREATE OR REPLACE PROCEDURE mockable.test__pg_mockable()
 LANGUAGE plpgsql
 SET search_path TO 'mockable', 'public', 'pg_temp'
 SET "plpgsql.check_asserts" TO 'true'
AS $procedure$
declare
    _now timestamptz;
begin
    assert mockable.now() = pg_catalog.now();
    assert mockable.current_date() = current_date;

    assert mockable.mock('pg_catalog.now()', '2022-01-02 10:20'::timestamptz)
        = '2022-01-02 10:20'::timestamptz;
    perform mockable.mock('pg_catalog.now()', '2022-01-02 10:30'::timestamptz);

    assert mockable.now() = '2022-01-02 10:30'::timestamptz,
        'Failed to mock `pg_catalog.now()` as `mockable.now()`.';
    assert mockable.current_date() = '2022-01-02'::date;
    assert mockable.localtime() = '10:30'::time;

    call mockable.unmock('pg_catalog.now()');
    assert pg_catalog.now() = mockable.now();
    assert current_date = mockable.current_date();

    --
    -- Now, let's demonstrate how to use the `search_path` to alltogether skip the mocking layer…
    --

    _now := now();  -- just to not have to use qualified names

    perform mockable.mock('now()', '2022-01-02 10:20'::timestamptz);

    perform set_config('search_path', 'pg_catalog', true);
    assert now() = _now;

    perform set_config('search_path', 'mockable,pg_catalog', true);
    assert now() = '2022-01-02 10:20'::timestamptz;

    raise transaction_rollback;
exception
    when transaction_rollback then
end;
$procedure$
```

#### Procedure: `unmock (regprocedure)`

Procedure arguments:

| Arg. # | Arg. mode  | Argument name                                                     | Argument type                                                        | Default expression  |
| ------ | ---------- | ----------------------------------------------------------------- | -------------------------------------------------------------------- | ------------------- |
|   `$1` |       `IN` | `routine_signature$`                                              | `regprocedure`                                                       |  |

Procedure-local settings:

  *  `SET search_path TO mockable, public, pg_temp`

#### Procedure: `wrap_function (regprocedure)`

Procedure arguments:

| Arg. # | Arg. mode  | Argument name                                                     | Argument type                                                        | Default expression  |
| ------ | ---------- | ----------------------------------------------------------------- | -------------------------------------------------------------------- | ------------------- |
|   `$1` |       `IN` | `function_signature$`                                             | `regprocedure`                                                       |  |

Procedure-local settings:

  *  `SET search_path TO mockable, public, pg_temp`

#### Procedure: `wrap_function (regprocedure, text)`

Procedure arguments:

| Arg. # | Arg. mode  | Argument name                                                     | Argument type                                                        | Default expression  |
| ------ | ---------- | ----------------------------------------------------------------- | -------------------------------------------------------------------- | ------------------- |
|   `$1` |       `IN` | `function_signature$`                                             | `regprocedure`                                                       |  |
|   `$2` |       `IN` | `create_function_statement$`                                      | `text`                                                               |  |

Procedure-local settings:

  *  `SET search_path TO mockable, public, pg_temp`

## Colophon

This `README.md` for the `pg_mockable` `extension` was automatically generated using the [`pg_readme`](https://github.com/bigsmoke/pg_readme) PostgreSQL extension.
