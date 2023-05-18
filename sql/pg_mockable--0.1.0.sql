-- complain if script is sourced in psql, rather than via CREATE EXTENSION
\echo Use "CREATE EXTENSION pg_mockable" to load this file. \quit

--------------------------------------------------------------------------------------------------------------

comment
    on extension pg_mockable
    is $markdown$
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

<?pg-readme-reference?>

<?pg-readme-colophon?>
$markdown$;

--------------------------------------------------------------------------------------------------------------

create function pg_mockable_readme()
    returns text
    volatile
    set search_path from current
    set pg_readme.include_view_definitions to 'true'
    set pg_readme.include_routine_definitions to 'false'
    language plpgsql
    as $plpgsql$
declare
    _readme text;
begin
    create extension if not exists pg_readme
        with version '0.1.2';

    _readme := pg_extension_readme('pg_mockable'::name);

    raise transaction_rollback;  -- to drop extension if we happened to `CREATE EXTENSION` for just this.
exception
    when transaction_rollback then
        return _readme;
end;
$plpgsql$;

--------------------------------------------------------------------------------------------------------------

create function pg_proc(regprocedure)
    returns pg_proc
    stable
    set search_path from current
    language sql
    return (
        select
            row(pg_proc.*)::pg_proc
        from
            pg_proc
        where
            oid = $1
    );
comment
    on function pg_proc(regprocedure)
    is $markdown$
Conveniently go from function calling signature description or OID (`regprocedure`) to `pg_catalog.pg_proc`.

Example:

```sql
select pg_proc('pg_catalog.current_setting(text, bool)');
```
$markdown$;

--------------------------------------------------------------------------------------------------------------

create table mock_memory (
    routine_signature regprocedure
        primary key
    ,unmock_statement text
        not null
);

--------------------------------------------------------------------------------------------------------------

create procedure wrap_function(
        function_signature$ regprocedure
        ,create_function_statement$ text
    )
    set search_path from current
    language plpgsql
    as $plpgsql$
begin
    insert into mock_memory
        (routine_signature, unmock_statement)
    values
        (function_signature$, create_function_statement$)
    ;

    execute create_function_statement$;
end;
$plpgsql$;

--------------------------------------------------------------------------------------------------------------

create procedure wrap_function(
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
        || quote_ident('@extschema@') || '.' || function_signature$::regproc::text
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

create procedure @extschema@.unmock(
        routine_signature$ regprocedure
    )
    set search_path from current
    language plpgsql
    as $plpgsql$
declare
    _mock_mem @extschema@.mock_memory;
    _proc_schema name;
begin
    _proc_schema := 'mockable';

    select
        mm.*
    into
        strict _mock_mem
    from
        @extschema@.mock_memory as mm
    where
        mm.routine_signature = routine_signature$
    ;

    execute _mock_mem.unmock_statement;
exception
    when no_data_found then
        raise exception 'Could not remember how to unmock %.%(%)', _proc_schema, proc_name$, arg_types$;
    when too_many_rows then
        raise exception 'Ambiguous function specification; this is probably a bug in mockable.unmock()';
end;
$plpgsql$;

--------------------------------------------------------------------------------------------------------------

create function mock(
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
    _proc_schema name;
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
        || quote_ident('@extschema@') || '.' || routine_signature$::regproc::text
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

call wrap_function('pg_catalog.now()');

--------------------------------------------------------------------------------------------------------------

create function transaction_timestamp()
    returns timestamptz
    stable
    language sql
    return @extschema@.now();
comment
    on function transaction_timestamp()
    is $markdown$
`transaction_timestamp()` is simply an alias for `now()`.  If you wish to mock it, mock `now()`.
$markdown$;

--------------------------------------------------------------------------------------------------------------

create function "current_timestamp"()
    returns timestamptz
    stable
    language sql
    return @extschema@.now();
comment
    on function "current_timestamp"()
    is $markdown$
`current_timestamp()` is derived from `now()`.  To mock it, mock `now()`.

Unlike its standard (PostgreSQL) counterpart, `current_timestamp()` does not support a precision parameter.
Feel free to implement it.
$markdown$;

--------------------------------------------------------------------------------------------------------------

create function "current_date"()
    returns date
    stable
    language sql
    return @extschema@.now()::date;
comment
    on function "current_date"()
    is $markdown$
`current_date()` is derived from `now()`.  To mock it, mock `now()`.
$markdown$;

--------------------------------------------------------------------------------------------------------------

create function "current_time"()
    returns timetz
    stable
    language sql
    return @extschema@.now()::timetz;
comment
    on function "current_time"()
    is $markdown$
`current_time()` is derived from `now()`.  To mock it, mock `now()`.

Unlike its standard (PostgreSQL) counterpart, `current_time()` does not support a precision parameter.
Feel free to implement it.
$markdown$;

--------------------------------------------------------------------------------------------------------------

create function "localtime"()
    returns time
    stable
    language sql
    return @extschema@.now()::time;
comment
    on function "localtime"()
    is $markdown$
`localtime()` is derived from `now()`.  To mock it, mock `now()`.

Unlike its standard (PostgreSQL) counterpart, `localtime()` does not support a precision parameter.
Feel free to implement it.
$markdown$;

--------------------------------------------------------------------------------------------------------------

create function "localtimestamp"()
    returns timestamp
    stable
    language sql
    return @extschema@.now()::timestamp;
comment
    on function "localtimestamp"()
    is $markdown$
`localtimestamp()` is derived from `now()`.  To mock it, mock `now()`.

Unlike its standard (PostgreSQL) counterpart, `localtimestamp()` does not support a precision parameter.
Feel free to implement it.
$markdown$;

--------------------------------------------------------------------------------------------------------------

create function timeofday()
    returns text
    stable
    set datestyle to 'Postgres'
    language sql
    return @extschema@.now()::text;
comment
    on function timeofday()
    is $markdown$
`timeofday()` is derived from `now()`.  To mock it, mock `now()`.
$markdown$;

--------------------------------------------------------------------------------------------------------------

create procedure test__pg_mockable()
    set search_path from current
    language plpgsql
    as $plpgsql$
declare
    _now timestamptz;
begin
    assert @extschema@.now() = pg_catalog.now();
    assert @extschema@.current_date() = current_date;

    assert @extschema@.mock('pg_catalog.now()', '2022-01-02 10:20'::timestamptz)
        = '2022-01-02 10:20'::timestamptz;
    perform @extschema@.mock('pg_catalog.now()', '2022-01-02 10:30'::timestamptz);

    assert @extschema@.now() = '2022-01-02 10:30'::timestamptz,
        'Failed to mock `pg_catalog.now()` as `mockable.now()`.';
    assert @extschema@.current_date() = '2022-01-02'::date;
    assert @extschema@.localtime() = '10:30'::time;

    call @extschema@.unmock('pg_catalog.now()');
    assert pg_catalog.now() = @extschema@.now();
    assert current_date = @extschema@.current_date();

    --
    -- Now, let's demonstrate how to use the `search_path` to alltogether skip the mocking layer…
    --

    _now := now();  -- just to not have to use qualified names

    perform @extschema@.mock('now()', '2022-01-02 10:20'::timestamptz);

    perform set_config('search_path', 'pg_catalog', true);
    assert now() = _now;

    perform set_config('search_path', 'mockable,pg_catalog', true);
    assert now() = '2022-01-02 10:20'::timestamptz;

    raise transaction_rollback;
exception
    when transaction_rollback then
end;
$plpgsql$;

--------------------------------------------------------------------------------------------------------------
