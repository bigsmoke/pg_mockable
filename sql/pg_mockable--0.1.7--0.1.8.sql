-- Complain if script is sourced in psql, rather than via CREATE EXTENSION
\echo Use "CREATE EXTENSION pg_mockable" to load this file. \quit

--------------------------------------------------------------------------------------------------------------

-- First pg_dump/pg_restore test procedure for this extension.
create procedure test_dump_restore__pg_mockable(test_stage$ text)
    set search_path from current
    set plpgsql.check_asserts to true
    set pg_readme.include_this_routine_definition to true
    language plpgsql
    as $$
declare
begin
    assert test_stage$ in ('pre-dump', 'post-restore');

    if test_stage$ = 'pre-dump' then
        create schema test__schema;
        create function test__schema.func() returns int return 8;
        call wrap_function('test__schema.func()');
        assert @extschema@.mock('test__schema.func()', 88::int) = 88::int;
        assert @extschema@.func() = 88;

        assert @extschema@.mock('pg_catalog.now()', '2022-01-02 10:30'::timestamptz)
            = '2022-01-02 10:30'::timestamptz;
        assert @extschema@.now() = '2022-01-02 10:30'::timestamptz;

    elsif test_stage$ = 'post-restore' then
        assert exists (select from mock_memory where routine_signature = 'pg_catalog.now()'::regprocedure);
        assert @extschema@.now() = pg_catalog.now(),
            'This wrapper function should have been restored to a wrapper of the original function.';

        assert exists (select from mock_memory where routine_signature = 'test__schema.func()'::regprocedure);
        assert @extschema@.func() = 88,
            'The wrapper function should have been restored, _with_ the mocked value.';

        call unmock('test__schema.func()');
        assert @extschema@.func() = 8;
    end if;
end;
$$;

--------------------------------------------------------------------------------------------------------------
--
-- Now, let me fix the problems revealed by `test_dump_restore`…
--
--------------------------------------------------------------------------------------------------------------

alter table mock_memory
    add column is_prewrapped_by_pg_mockable bool
        default false;

update  mock_memory
set     is_prewrapped_by_pg_mockable = true
where   routine_signature = 'pg_catalog.now()'::regprocedure
;

select pg_extension_config_dump('mock_memory', 'WHERE NOT is_prewrapped_by_pg_mockable');

--------------------------------------------------------------------------------------------------------------

create cast (regprocedure as pg_proc)
    with function pg_proc(regprocedure)
    as assignment;

comment on cast (regprocedure as pg_proc)
    is $markdown$
Conveniently go from function calling signature description or OID (`regprocedure`) to `pg_catalog.pg_proc`.

Examples:

```sql
select 'pg_catalog.current_setting(text, bool)'::regprocedure::pg_proc;
select 'pg_catalog.now()'::regprocedure::pg_proc;
```
$markdown$;

--------------------------------------------------------------------------------------------------------------

-- Fix `mockable.<original_schema>.func_name()` bug.
create or replace procedure wrap_function(
        function_signature$ regprocedure
    )
    set search_path from current
    language plpgsql
    as $plpgsql$
declare
    _create_statement text;
    _comment_statement text;
    _pg_proc pg_proc;
begin
    _pg_proc := pg_proc(function_signature$);

    assert _pg_proc.provariadic = 0,
        'Dunno how to auto-wrap functions with variadic arguments.';
    assert _pg_proc.prokind = 'f',
        'Dunno how to auto-wrap other routines than functions.';
    assert _pg_proc.proargmodes is null,
        'Dunno how to auto-wrap functions with `OUT` arguments.';
    assert _pg_proc.proargnames is null,
        'Dunno how to auto-wrap functions with named arguments.';

    _create_statement := 'CREATE OR REPLACE FUNCTION '
        || quote_ident('@extschema@') || '.' || quote_ident(_pg_proc.proname)
        || '(' || pg_get_function_arguments(function_signature$) || ')'
        || ' RETURNS ' || pg_get_function_result(function_signature$)
        || case when _pg_proc.proleakproof then ' LEAKPROOF' else '' end
        || case when _pg_proc.proisstrict then ' STRICT' else '' end
        || case
            when _pg_proc.provolatile = 'i' then ' IMMUTABLE'
            when _pg_proc.provolatile = 's' then ' STABLE'
            else ''
        end
        || ' SET search_path FROM CURRENT'
        || ' RETURN ' || function_signature$::regproc::text || '('
        || coalesce(
            (
                select
                    string_agg('$' || arg_position::text,  ', ')
                from
                    unnest(_pg_proc.proargtypes) with ordinality as arg_types(arg_type_oid, arg_position)
            ),
            ''
        )
        || ');';
    _comment_statement := 'COMMENT ON FUNCTION ' || function_signature$::text
        || ' IS ''Mockable wrapper function for `' || function_signature$::text || '`.'
        || ''';';

    call wrap_function(function_signature$, _create_statement);
end;
$plpgsql$;

--------------------------------------------------------------------------------------------------------------

-- Fix `mockable.<original_schema>.func_name()` bug.
create or replace function mock(
        routine_signature$ regprocedure
        ,mock_value$ anyelement
    )
    returns anyelement
    set search_path from current
    language plpgsql
    volatile
    as $plpgsql$
declare
    _create_ddl text;
    _grant_ddl text;
    _proc_signature text;
    _pg_proc pg_catalog.pg_proc;
    _quoted_arg_types text[];
    _quoted_ret_type text;
begin
    _pg_proc := pg_proc(routine_signature$);

    assert _pg_proc.prokind in ('f', 'p'),
        'I can, so far, only mock regular functions and routines.';

    _create_ddl := 'CREATE OR REPLACE ' || case _pg_proc.prokind
            when 'f' then 'FUNCTION'
            when 'p' then 'PROCEDURE'
        end
        || ' '
        || quote_ident('@extschema@') || '.' || quote_ident(_pg_proc.proname)
        || '(' || pg_get_function_arguments(routine_signature$) || ')'
        || ' RETURNS ' || pg_get_function_result(routine_signature$)
        || ' LANGUAGE SQL'
        || ' IMMUTABLE'
        || ' SET search_path FROM CURRENT'
        || ' RETURN ' || quote_literal(mock_value$) || '::' || pg_get_function_result(routine_signature$);
    execute _create_ddl;

    _grant_ddl := 'GRANT EXECUTE ON ' || case _pg_proc.prokind
            when 'f' then 'FUNCTION'
            when 'p' then 'PROCEDURE'
        end
        || ' ' || routine_signature$::text || ' TO public';
    execute _grant_ddl;

    return mock_value$;
end;
$plpgsql$;

--------------------------------------------------------------------------------------------------------------

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

<?pg-readme-colophon?>
$markdown$;

--------------------------------------------------------------------------------------------------------------
