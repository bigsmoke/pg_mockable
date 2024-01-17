-- Complain if script is sourced in `psql`, rather than via `CREATE EXTENSION`.
\echo Use "CREATE EXTENSION pg_mockable" to load this file. \quit

--------------------------------------------------------------------------------------------------------------

-- Correct and extend.
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

## Usage

First, use `mockable.wrap_function()` to create a very thin function wrapper for whichever function you
wish to wrap:

```sql
select mockable.wrap_function('pg_catalog.now()`);
```

This call will bring into being: `mockable.now()`, which just does a `return
pg_catalog.now()`.  In other words: the wrapper function, when not mocking,
calls the original function.

If, for some reason, this fails, you can specify the precise `CREATE OR REPLACE FUNCTION` statement as the
second argument to `wrap_function()`:

```sql
select mockable.wrap_function('pg_catalog.now', $$
create or replace function mockable.now()
    returns timestamptz
    stable
    language sql
    return pg_catalog.now();
$$);
```
(In fact, this example is a bit contrived; `mockable.now()` always pre-exists,
because the need to mock `now()` was the whole reason that this extension was
created in the first place.  And `now()` is a special case, because, to mock
`now()` effectively, a whole bunch of other current date-time retrieval
functions have a mockable counterpart that all call the same `mockable.now()`
function, so that mocking `pg_catalog.now()` _also_ effectively mocks
`current_timestamp()`, etc.)

After mocking a function, you can use it as you would the original function.

### `search_path` and the `mockable` schema

Note, that, in some circumstances, you can use the `search_path` to altogether
bypass the `mockable` schema (and thus the mock (wrapper) functions therein).
But, this is only in contexts which are compiled at run-time, such as PL/pgSQL
function bodies.  A `DEFAULT` expression for a table or view column, for
example, will be compiled down to references to the _actual_ function objects
involved, thus making it impossible to do a post-hoc imposition of the
`mockable` schema by prepending ti to the `search_path`.

Of course, defaults are only that—defaults—and you could, for instance, override
them while running tests, but that seems altogether more cumbersome than
directly referencing, for instance, `DEFAULT mockable.now()`.  There remains the
argument of development-time dependencies versus run-time dependencies, of
course, and the fact that the latter should be kept to a minimum…

Speaking of PostgreSQL `search_path`s, this is a good opportunity to plug a very
detailed writeup the extension author did in 2022:
https://blog.bigsmoke.us/2022/11/11/postgresql-schema-search_path

<?pg-readme-reference?>

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

<?pg-readme-colophon?>
$markdown$;

--------------------------------------------------------------------------------------------------------------

-- Clarify my intention in “not implemented” messages.
create or replace function mock_memory__before_magic()
    returns trigger
    set search_path to pg_catalog
    language plpgsql
    as $$
declare
    _regprocedure regprocedure;
    _regtype regtype;
    _pg_proc pg_proc;
    _copying bool;
    _extension_context_detection_object name;
begin
    assert tg_when = 'BEFORE';
    assert tg_op in ('INSERT', 'UPDATE');
    assert tg_level = 'ROW';
    assert tg_table_schema = 'mockable';
    assert tg_table_name = 'mock_memory';

    -- When we are inside a `COPY` command, it is likely that we're restoring from a `pg_dump`.
    -- Otherwise, why would you want to bulk insert into such a small table?
    _copying := tg_op = 'INSERT' and exists (
        select from
            pg_stat_progress_copy
        where
            relid = tg_relid
            and command = 'COPY FROM'
            and type = 'PIPE'
    );

    if tg_op = 'INSERT' and not _copying and NEW.return_type is not null then
        raise integrity_constraint_violation using message = format(
            'Please let _me_ (the `%I` on `%I.%I`) figure out the return type for `%s` myself.'
            ,tg_name, tg_table_schema, tg_table_name, NEW.routine_signature
        );
    end if;

    if tg_op = 'INSERT' then
        -- The extension context may be:
        --    a) outside of a `CREATE EXTENSION` / `ALTER EXTENSION` context (`_extension_context IS NULL`);
        --    b) inside the `CREATE EXTENSION` / `ALTER EXTENSION` context of the extension owning the config
        --       table to which this trigger is attached; or
        --    c) inside the `CREATE EXTENSION` / `ALTER EXTENSION` context of extension that changes settings
        --       in another extension's configuration table.
        _extension_context_detection_object := format(
            'extension_context_detector_%s'
            ,floor(pg_catalog.random() * 1000)
        );
        execute format('CREATE TEMPORARY TABLE %I (col int) ON COMMIT DROP', _extension_context_detection_object);
        select
            pg_extension.extname
            ,pg_extension.extversion
        into
            NEW.pg_extension_name
            ,NEW.pg_extension_version
        from
            pg_catalog.pg_depend
        inner join
            pg_catalog.pg_extension
            on pg_extension.oid = pg_depend.refobjid
        where
            pg_depend.classid = 'pg_catalog.pg_class'::regclass
            and pg_depend.objid = _extension_context_detection_object::regclass
            and pg_depend.refclassid = 'pg_catalog.pg_extension'::regclass
        ;
        execute format('DROP TABLE %I', _extension_context_detection_object);
    end if;

    if not _copying and (tg_op = 'INSERT' or NEW.routine_signature != OLD.routine_signature) then
        _regprocedure := NEW.routine_signature::regprocedure;

        NEW.routine_signature := _regprocedure::text;  -- This way we get a normalized calling signature.
        NEW.return_type := pg_get_function_result(_regprocedure);

        _pg_proc := mockable.pg_proc(_regprocedure);

        if _pg_proc.pronamespace = 'mockable'::regnamespace then
            raise invalid_recursion using
                message = 'Cannot mock a mock routine itself.'
                ,hint = 'You probably forgot to schema-qualify the routine name, while the `mockable`'
                    || ' schema is in front of the schema with the object you wish to mock.';
        end if;
        if _pg_proc.provariadic != 0 then
            raise feature_not_supported using
                message = 'Dunno (yet) how to auto-wrap functions with variadic arguments.';
        end if;
        if _pg_proc.prokind != 'f' then
            raise feature_not_supported using
                message = 'Dunno (yet) how to auto-wrap other routines than functions.';
        end if;
        if _pg_proc.proargmodes is not null then
            raise feature_not_supported using
                message = 'Dunno (yet) how to auto-wrap functions with `OUT` arguments.';
        end if;
        if _pg_proc.proargnames is not null then
            raise feature_not_supported using
                message = 'Dunno (yet) how to auto-wrap functions with named arguments.';
        end if;

        NEW.mock_signature := 'mockable.' || quote_ident(_pg_proc.proname)
            || '(' || pg_get_function_arguments(_pg_proc.oid) || ')';
    end if;

    if NEW.unmock_statement is null then
        NEW.unmock_statement := 'CREATE OR REPLACE FUNCTION '
            || NEW.mock_signature
            || ' RETURNS ' || pg_get_function_result(_regprocedure)
            || case when _pg_proc.proleakproof then ' LEAKPROOF' else '' end
            || case when _pg_proc.proisstrict then ' STRICT' else '' end
            || case
                when _pg_proc.provolatile = 'i' then ' IMMUTABLE'
                when _pg_proc.provolatile = 's' then ' STABLE'
                else ''
            end
            || ' RETURN ' || _regprocedure::regproc::text || '('
            || (
                    select
                        coalesce(string_agg('$' || arg_position::text,  ', '), '')
                    from
                        unnest(_pg_proc.proargtypes) with ordinality as arg_types(arg_type_oid, arg_position)
            )
            || ')';
    end if;

    return NEW;
end;
$$;

--------------------------------------------------------------------------------------------------------------
