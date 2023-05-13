---
pg_extension_name: pg_mockable
pg_extension_version: 0.3.3
pg_readme_generated_at: 2023-05-13 16:31:19.642381+01
pg_readme_version: 0.6.3
---

# `pg_mockable` – mock PostgreSQL functions

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

In fact, this example won't work, because `mockable.now()` _always_ exists,
because the need to mock `now()` was the whole reason that this extension was
created in the first place.  And `now()` is a special case, because, to mock
`now()` effectively, a whole bunch of other current date-time retrieval
functions have a mockable counterpart that all call the same `mockable.now()`
function, so that mocking `pg_catalog.now()` _also_ effectively mocks
`current_timestamp()`, etc.

## Object reference

### Schema: `mockable`

`pg_mockable` must be installed in the `mockable` schema.  Hence, it is not relocatable.

---

The `mockable` schema belongs to the `pg_mockable` extension.

Postgres (as of Pg 15) doesn't allow one to specify a _default_ schema, and do
something like `schema = 'mockable'` combined with `relocatable = true` in the
`.control` file.  Therefore I decided to choose the `mockable` schema name
_for_ you, even though you might have very well preferred something shorter
like `mock`, even shorter like `mck`, or more verbose such as `mock_objects`.

### Tables

There are 1 tables that directly belong to the `pg_mockable` extension.

#### Table: `mock_memory`

The `mock_memory` table has 8 attributes:

1. `mock_memory.routine_signature` `regprocedure`

   The mockable routine `oid` (via its `regprocedure` alias).

   Check the official Postgres docs for more information about `regprocedure` and
   other [OID types](https://www.postgresql.org/docs/8.1/datatype-oid.html).

   As evidenced by the [`test_dump_restore__pg_mockable()`
   procedure](#procedure-test_dump_restore__pg_mockable-text), storing an
   `regprocedure` is not a problem with `pg_dump`/`pg_restore`.  The same is true
   for other `oid` alias types, because these are all serialized as their `text`
   representation during `pg_dump` and then loaded from that text representation
   again during `pg_restore`.  See https://dba.stackexchange.com/a/324899/79909 for
   details.

   - `NOT NULL`
   - `PRIMARY KEY (routine_signature)`

2. `mock_memory.mock_signature` `text`

   The mock (wrapper) function its calling signature.

   The `mock_signature`, contrary to `routine_signature`, is stored as `text`,
   because we want to be able to set in the `BEFORE` trigger before the function
   is actually created in the `AFTER` trigger.

   - `NOT NULL`
   - `UNIQUE (mock_signature)`

3. `mock_memory.return_type` `text`

   - `NOT NULL`

4. `mock_memory.unmock_statement` `text`

   - `NOT NULL`

5. `mock_memory.mock_value` `text`

6. `mock_memory.mock_duration` `text`

   - `DEFAULT 'TRANSACTION'::text`
   - `CHECK (mock_duration = ANY (ARRAY['TRANSACTION'::text, 'PERSISTENT'::text]))`

7. `mock_memory.pg_extension_name` `name`

8. `mock_memory.pg_extension_version` `text`

### Routines

#### Function: `"current_date"()`

`current_date()` is derived from `mockable.now()`.  To mock it, mock `pg_catalog.now()`.

Function return type: `date`

Function attributes: `STABLE`

#### Function: `"current_time"()`

`current_time()` is derived from `mockable.now()`.  To mock it, mock `pg_catalog.now()`.

Unlike its standard (PostgreSQL) counterpart, `current_time()` does not support
a precision parameter.  Feel free to implement it.

Function return type: `time with time zone`

Function attributes: `STABLE`

#### Function: `"current_timestamp"()`

`current_timestamp()` is derived from `mockable.now()`.  To mock it, mock `pg_catalog.now()`.

Unlike its standard (PostgreSQL) counterpart, `current_timestamp()` does not
support a precision parameter.  Feel free to implement it.

Function return type: `timestamp with time zone`

Function attributes: `STABLE`

#### Function: `"localtime"()`

`localtime()` is derived from `mockable.now()`.  To mock it, mock `pg_catalog.now()`.

Unlike its standard (PostgreSQL) counterpart, `localtime()` does not support a
precision parameter.  Feel free to implement it.

Function return type: `time without time zone`

Function attributes: `STABLE`

#### Function: `"localtimestamp"()`

`localtimestamp()` is derived from `mockable.now()`.  To mock it, mock `pg_catalog.now()`.

Unlike its standard (PostgreSQL) counterpart, `localtimestamp()` does not support a precision parameter.
Feel free to implement it.

Function return type: `timestamp without time zone`

Function attributes: `STABLE`

#### Function: `mockable.now()`

Mockable wrapper function for `now()`.

Function return type: `timestamp with time zone`

Function attributes: `STABLE`, `RETURNS NULL ON NULL INPUT`

#### Function: `mockable.timeofday()`

Function return type: `text`

Function attributes: `STABLE`

Function-local settings:

  *  `SET DateStyle TO Postgres`

#### Function: `mockable.transaction_timestamp()`

Function return type: `timestamp with time zone`

Function attributes: `STABLE`

#### Function: `mock_memory__after_magic()`

Function return type: `trigger`

Function-local settings:

  *  `SET search_path TO pg_catalog`

#### Function: `mock_memory__before_magic()`

Function return type: `trigger`

Function-local settings:

  *  `SET search_path TO pg_catalog`

#### Function: `mock_memory__reset_value()`

This trigger ensures that the mocked value is always forgotten before transaction end.

Resetting the value in turn ensures that another trigger unmocks the wrapper
function; that is, it will be restored to act as a thin wrapper around the
original (wrapped) function.

Function return type: `trigger`

Function-local settings:

  *  `SET search_path TO pg_catalog`

#### Function: `mock (regprocedure, anyelement)`

Function arguments:

| Arg. # | Arg. mode  | Argument name                                                     | Argument type                                                        | Default expression  |
| ------ | ---------- | ----------------------------------------------------------------- | -------------------------------------------------------------------- | ------------------- |
|   `$1` |       `IN` | `routine_signature$`                                              | `regprocedure`                                                       |  |
|   `$2` |    `INOUT` | `mock_value$`                                                     | `anyelement`                                                         |  |

Function return type: `anyelement`

Function-local settings:

  *  `SET search_path TO pg_catalog`

#### Function: `pg_mockable_meta_pgxn()`

Returns the JSON meta data that has to go into the `META.json` file needed for [PGXN—PostgreSQL Extension Network](https://pgxn.org/) packages.

The `Makefile` includes a recipe to allow the developer to: `make META.json` to
refresh the meta file with the function's current output, including the
`default_version`.

`pg_mockable` can indeed be found on PGXN: https://pgxn.org/dist/pg_mockable/

Function return type: `jsonb`

Function attributes: `STABLE`

#### Function: `pg_mockable_readme()`

Generates the text for a `README.md` in Markdown format with the help of the `pg_readme` extension.

This function temporarily installs `pg_readme` if it is not already installed
in the current database.

Function return type: `text`

Function-local settings:

  *  `SET search_path TO mockable, pg_temp`
  *  `SET pg_readme.include_view_definitions_like TO true`
  *  `SET pg_readme.include_routine_definitions_like TO {test__%}`

#### Function: `pg_proc (regprocedure)`

Conveniently go from function calling signature description or OID (`regprocedure`) to `pg_catalog.pg_proc`.

Example:

```sql
SELECT pg_proc('pg_catalog.current_setting(text, bool)');
```

Function arguments:

| Arg. # | Arg. mode  | Argument name                                                     | Argument type                                                        | Default expression  |
| ------ | ---------- | ----------------------------------------------------------------- | -------------------------------------------------------------------- | ------------------- |
|   `$1` |       `IN` |                                                                   | `regprocedure`                                                       |  |

Function return type: `pg_proc`

Function attributes: `STABLE`

#### Procedure: `test_dump_restore__pg_mockable (text)`

This procedure is to be called by the `test_dump_restore.sh` and `test_dump_restore.sql` companion scripts, once before `pg_dump` (with `test_stage$ = 'pre-dump'` argument) and once after `pg_restore` (with the `test_stage$ = 'post-restore'`).

Procedure arguments:

| Arg. # | Arg. mode  | Argument name                                                     | Argument type                                                        | Default expression  |
| ------ | ---------- | ----------------------------------------------------------------- | -------------------------------------------------------------------- | ------------------- |
|   `$1` |       `IN` | `test_stage$`                                                     | `text`                                                               |  |

Procedure-local settings:

  *  `SET search_path TO pg_catalog, mockable`
  *  `SET plpgsql.check_asserts TO true`
  *  `SET pg_readme.include_this_routine_definition TO true`

```sql
CREATE OR REPLACE PROCEDURE mockable.test_dump_restore__pg_mockable(IN "test_stage$" text)
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'mockable'
 SET "plpgsql.check_asserts" TO 'true'
 SET "pg_readme.include_this_routine_definition" TO 'true'
AS $procedure$
declare
begin
    assert test_stage$ in ('pre-dump', 'post-restore');

    if test_stage$ = 'pre-dump' then
        create schema test__schema;
        create function test__schema.func() returns int return 8;
        perform wrap_function('test__schema.func()');
        assert mockable.mock('test__schema.func()', 88::int) = 88::int;
        assert mockable.func() = 88;

        create function test__schema.func2() returns text[] return array['beh', 'blah'];
        perform wrap_function('test__schema.func2()', mock_duration$ => 'PERSISTENT');
        assert mockable.func2() = array['beh', 'blah'];
        assert mockable.mock('test__schema.func2()', array['boe', 'bah']) = array['boe', 'bah'];
        assert mockable.func2() = array['boe', 'bah'];

        assert mockable.mock('pg_catalog.now()', '2022-01-02 10:30'::timestamptz)
            = '2022-01-02 10:30'::timestamptz;
        assert mockable.now() = '2022-01-02 10:30'::timestamptz;

    elsif test_stage$ = 'post-restore' then
        assert exists (select from mock_memory where routine_signature = 'now()'::regprocedure);
        assert mockable.now() = pg_catalog.now(),
            'This wrapper function should have been restored to a wrapper of the original function.';

        assert exists (select from mock_memory where routine_signature = 'test__schema.func()'::regprocedure);
        assert mockable.func() = 8,
            'The wrapper function should have been restored to a wrapper of the original function.';

        assert exists (select from mock_memory where routine_signature = 'test__schema.func2()'::regprocedure);
        assert mockable.func2() = array['boe', 'bah'],
            'The wrapper function should have been restored, and not unmocked.';
        call mockable.unmock('test__schema.func2()');
        assert mockable.func2() = array['beh', 'blah'];
    end if;
end;
$procedure$
```

#### Procedure: `test__pg_mockable()`

Procedure-local settings:

  *  `SET search_path TO pg_catalog`
  *  `SET plpgsql.check_asserts TO true`
  *  `SET pg_readme.include_this_routine_definition TO true`

```sql
CREATE OR REPLACE PROCEDURE mockable.test__pg_mockable()
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog'
 SET "plpgsql.check_asserts" TO 'true'
 SET "pg_readme.include_this_routine_definition" TO 'true'
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

    create schema test__schema;
    create function test__schema.func() returns int return 8;
    perform mockable.wrap_function('test__schema.func()');

    --
    -- Now, let's demonstrate how to use the `search_path` to alltogether skip the mocking layer…
    --

    _now := now();  -- just to not have to use qualified names

    perform mockable.mock('pg_catalog.now()', '2022-01-02 10:20'::timestamptz);

    perform set_config('search_path', 'pg_catalog', true);
    assert now() = _now;

    perform set_config('search_path', 'mockable, pg_catalog', true);
    assert now() = '2022-01-02 10:20'::timestamptz;

    <<recursive_mock_attempt>>
    begin
        assert current_schema = 'mockable';
        assert 'now()'::regprocedure = 'mockable.now()'::regprocedure;
        assert 'now()'::regprocedure != 'pg_catalog.now()'::regprocedure;

        perform mockable.mock('now()', '2021-01-01 00:00'::timestamptz);

        raise assert_failure using
            message = 'Mocking an unwrapped function should have been forbidden.';
    exception
        when no_data_found then  -- Good.
    end recursive_mock_attempt;

    <<recursive_wrap_attempt>>
    begin
        assert current_schema = 'mockable';
        assert 'now()'::regprocedure = 'mockable.now()'::regprocedure;
        assert 'now()'::regprocedure != 'pg_catalog.now()'::regprocedure;

        perform mockable.wrap_function('now()');

        raise assert_failure using
            message = 'Wrapping a wrapper function should have been forbidden.';
    exception
        when invalid_recursion then  -- Good.
    end recursive_wrap_attempt;

    create extension pg_mockable_dependent_test_extension
        with version 'constver';

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

  *  `SET search_path TO pg_catalog`

#### Function: `wrap_function (regprocedure, mock_memory_duration)`

Function arguments:

| Arg. # | Arg. mode  | Argument name                                                     | Argument type                                                        | Default expression  |
| ------ | ---------- | ----------------------------------------------------------------- | -------------------------------------------------------------------- | ------------------- |
|   `$1` |       `IN` | `function_signature$`                                             | `regprocedure`                                                       |  |
|   `$2` |       `IN` | `mock_duration$`                                                  | `mock_memory_duration`                                               | `'TRANSACTION'::mock_memory_duration` |

Function return type: `mock_memory`

#### Function: `wrap_function (regprocedure, text, mock_memory_duration)`

Function arguments:

| Arg. # | Arg. mode  | Argument name                                                     | Argument type                                                        | Default expression  |
| ------ | ---------- | ----------------------------------------------------------------- | -------------------------------------------------------------------- | ------------------- |
|   `$1` |       `IN` | `function_signature$`                                             | `regprocedure`                                                       |  |
|   `$2` |       `IN` | `create_function_statement$`                                      | `text`                                                               |  |
|   `$3` |       `IN` | `mock_duration$`                                                  | `mock_memory_duration`                                               | `'TRANSACTION'::mock_memory_duration` |

Function return type: `mock_memory`

### Types

The following extra types have been defined _besides_ the implicit composite types of the [tables](#tables) and [views](#views) in this extension.

#### Enum type: `mock_memory_duration`

```sql
CREATE TYPE mock_memory_duration AS ENUM (
    'TRANSACTION',
    'SESSION',
    'PERSISTENT'
);
```

## Authors and contributors

* [Rowan](https://www.bigsmoke.us/) originated this extension in 2022 while
  developing the PostgreSQL backend for the [FlashMQ SaaS MQTT cloud
  broker](https://www.flashmq.com/).  Rowan does not like to see himself as a
  tech person or a tech writer, but, much to his chagrin, [he
  _is_](https://blog.bigsmoke.us/category/technology). Some of his chagrin
  about his disdain for the IT industry he poured into a book: [_Why
  Programming Still Sucks_](https://www.whyprogrammingstillsucks.com/).  Much
  more than a “tech bro”, he identifies as a garden gnome, fairy and ork rolled
  into one, and his passion is really to [regreen and reenchant his
  environment](https://sapienshabitat.com/).  One of his proudest achievements
  is to be the third generation ecological gardener to grow the wild garden
  around his beautiful [family holiday home in the forest of Norg, Drenthe,
  the Netherlands](https://www.schuilplaats-norg.nl/) (available for rent!).

## Colophon

This `README.md` for the `pg_mockable` extension was automatically generated using the [`pg_readme`](https://github.com/bigsmoke/pg_readme) PostgreSQL extension.
