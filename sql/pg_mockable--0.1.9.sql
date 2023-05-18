-- Complain if script is sourced in psql, rather than via CREATE EXTENSION
\echo Use "CREATE EXTENSION pg_mockable" to load this file. \quit

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

comment
    on schema mockable
    is $markdown$
The `mockable` schema belongs to the `pg_mockable` extension.

Postgres (as of Pg 15) doesn't allow one to specify a _default_ schema, and do
something like `schema = 'mockable'` combined with `relocatable = true` in the
`.control` file.  Therefore I decided to choose the `mockable` schema name
_for_ you, even though you might have very well preferred something shorted
like `mock`, even shorter like `mck`, or more verbose such as `mock_objects`.
$markdown$;

--------------------------------------------------------------------------------------------------------------

create function pg_mockable_readme()
    returns text
    volatile
    set search_path from current
    set pg_readme.include_view_definitions_like to 'true'
    set pg_readme.include_routine_definitions_like to '{test__%}'
    language plpgsql
    as $plpgsql$
declare
    _readme text;
begin
    create extension if not exists pg_readme;

    _readme := pg_extension_readme('pg_mockable'::name);

    raise transaction_rollback;  -- to drop extension if we happened to `CREATE EXTENSION` for just this.
exception
    when transaction_rollback then
        return _readme;
end;
$plpgsql$;

-- Add previously missing comment.
comment
    on function pg_mockable_readme()
    is $markdown$
Generates the text for a `README.md` in Markdown format using the amazing power
of the `pg_readme` extension.  Temporarily installs `pg_readme` if it is not
already installed in the current database.
$markdown$;

--------------------------------------------------------------------------------------------------------------

do $$
declare
    _extension_name name := 'pg_mockable';
    _setting_name text := _extension_name || '.readme_url';
    _ddl_cmd_to_set_pg_readme_url text := format(
        'ALTER DATABASE %I SET %s = %L'
        ,current_database()
        ,_setting_name
        ,'https://github.com/bigsmoke/' || _extension_name || '/blob/master/README.md'
    );
begin
    if (select rolsuper from pg_roles where rolname = current_user) then
        execute _ddl_cmd_to_set_pg_readme_url;
    else
        -- We say `superuser = false` in the control file; so let's just whine a little instead of crashing.
        raise warning using
            message = format(
                'Because you''re installing the `%I` extension as non-superuser and because you'
                || ' are also not the owner of the `%I` DB, the database-level `%I` setting has'
                || ' not been set.'
                ,_extension_name
                ,current_database()
                ,_setting_name
            )
            ,detail = 'Settings of the form `<extension_name>.readme_url` are used by `pg_readme` to'
                || ' cross-link between extensions their README files.'
            ,hint = 'If you want full inter-extension README cross-linking, you can ask your friendly'
                || E' neighbourhood DBA to execute the following statement:\n'
                || _ddl_cmd_to_set_pg_readme_url || ';';
    end if;
end;
$$;

--------------------------------------------------------------------------------------------------------------

create function pg_mockable_meta_pgxn()
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
            }
        }'::jsonb
        ,'provides'
        ,('{
            "pg_mockable": {
                "file": "pg_mockable--0.1.9.sql",
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

comment on function pg_mockable_meta_pgxn() is
$md$Returns the JSON meta data that has to go into the `META.json` file needed for [PGXN—PostgreSQL Extension Network](https://pgxn.org/) packages.

The `Makefile` includes a recipe to allow the developer to: `make META.json` to
refresh the meta file with the function's current output, including the
`default_version`.

`pg_mockable` can indeed be found on PGXN: https://pgxn.org/dist/pg_mockable/
$md$;

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

create table mock_memory (
    routine_signature regprocedure
        primary key
    ,unmock_statement text
        not null
    ,is_prewrapped_by_pg_mockable bool
        default false
);

select pg_extension_config_dump('mock_memory', 'WHERE NOT is_prewrapped_by_pg_mockable');

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

create procedure unmock(
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

call wrap_function('pg_catalog.now()');

update
    mock_memory
set
    is_prewrapped_by_pg_mockable = true
where
    routine_signature = 'pg_catalog.now()'::regprocedure
;

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
    set plpgsql.check_asserts to true
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
