-- Complain if script is sourced in `psql`, rather than via `CREATE EXTENSION`
\echo Use "CREATE EXTENSION pg_mockable" to load this file. \quit

--------------------------------------------------------------------------------------------------------------

-- Add author section.
comment on extension pg_mockable is
$markdown$
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

<?pg-readme-reference?>

## Authors and contributors

* [Rowan](https://www.bigsmoke.us/) originated this extension in 2022 while
  developing the PostgreSQL backend for the [FlashMQ SaaS MQTT cloud
  broker](https://www.flashmq.com/).  Rowan does not like to see himself as a
  tech person or a tech writer, but, much to his chagrin, [he
  _is_](https://blog.bigsmoke.us/category/technology).  He identifies more as
  a garden gnome, fairy and ork rolled into one and his passion is really to
  [regreen and reenchant his environment](https://sapienshabitat.com/).  One of
  his proudest achievements is to be the third generation ecological gardener
  to grow the wild garden around his beautiful [family holiday home in the
  forest of Norg, Drenthe, the Netherlands](https://www.schuilplaats-norg.nl/)
  (available for rent).

<?pg-readme-colophon?>
$markdown$;

--------------------------------------------------------------------------------------------------------------

create or replace function pg_mockable_meta_pgxn()
    returns jsonb
    stable
    language sql
    return jsonb_build_object(
        'name'
        ,'pg_mockable'
        ,'abstract'
        ,'Create mockable versions of functions from other schemas.'
        ,'description'
        ,'The `pg_mockable` extension can be used to create mockable versions of functions from other'
            ' schemas.'
        ,'version'
        ,(
            select
                pg_extension.extversion
            from
                pg_catalog.pg_extension
            where
                pg_extension.extname = 'pg_mockable'
        )
        ,'maintainer'
        ,array[
            'Rowan Rodrik van der Molen <rowan@bigsmoke.us>'
        ]
        ,'license'
        ,'postgresql'
        ,'prereqs'
        ,'{
            "test": {
                "requires": {
                    "pgtap": 0
                }
            },
            "develop": {
                "recommends": {
                    "pg_readme": 0
                }
            }
        }'::jsonb
        ,'provides'
        ,('{
            "pg_mockable": {
                "file": "pg_mockable--0.3.2.sql",
                "version": "' || (
                    select
                        pg_extension.extversion
                    from
                        pg_catalog.pg_extension
                    where
                        pg_extension.extname = 'pg_mockable'
                ) || '",
                "docfile": "README.md"
            }
        }')::jsonb
        ,'resources'
        ,'{
            "homepage": "https://blog.bigsmoke.us/tag/pg_mockable",
            "bugtracker": {
                "web": "https://github.com/bigsmoke/pg_mockable/issues"
            },
            "repository": {
                "url": "https://github.com/bigsmoke/pg_mockable.git",
                "web": "https://github.com/bigsmoke/pg_mockable",
                "type": "git"
            }
        }'::jsonb
        ,'meta-spec'
        ,'{
            "version": "1.0.0",
            "url": "https://pgxn.org/spec/"
        }'::jsonb
        ,'generated_by'
        ,'`select pg_mockable_meta_pgxn()`'
        ,'tags'
        ,array[
            'plpgsql',
            'function',
            'functions',
            'mocking',
            'testing'
        ]
    );

--------------------------------------------------------------------------------------------------------------
