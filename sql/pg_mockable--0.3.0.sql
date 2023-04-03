-- complain if script is sourced in psql, rather than via CREATE EXTENSION
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

comment on schema mockable is
$md$The `mockable` schema belongs to the `pg_mockable` extension.

Postgres (as of Pg 15) doesn't allow one to specify a _default_ schema, and do
something like `schema = 'mockable'` combined with `relocatable = true` in the
`.control` file.  Therefore I decided to choose the `mockable` schema name
_for_ you, even though you might have very well preferred something shorted
like `mock`, even shorter like `mck`, or more verbose such as `mock_objects`.
$md$;

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
                "file": "pg_mockable--0.1.0.sql",
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

create or replace function pg_mockable_readme()
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

comment on function pg_mockable_readme() is
$md$Generates the text for a `README.md` in Markdown format with the help of the `pg_readme` extension.

This function temporarily installs `pg_readme` if it is not already installed
in the current database.
$md$;

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

create function pg_proc(regprocedure)
    returns pg_proc
    stable
    language sql
    return (
        select
            row(pg_proc.*)::pg_proc
        from
            pg_proc
        where
            oid = $1
    );

comment on function pg_proc(regprocedure) is
$md$Conveniently go from function calling signature description or OID (`regprocedure`) to `pg_catalog.pg_proc`.

Example:

```sql
SELECT pg_proc('pg_catalog.current_setting(text, bool)');
```
$md$;

--------------------------------------------------------------------------------------------------------------

create cast (regprocedure as pg_proc)
    with function pg_proc(regprocedure)
    as assignment;

comment on cast (regprocedure as pg_proc) is
$md$Conveniently go from function calling signature description or OID (`regprocedure`) to `pg_catalog.pg_proc`.

Examples:

```sql
select 'pg_catalog.current_setting(text, bool)'::regprocedure::pg_proc;
select 'pg_catalog.now()'::regprocedure::pg_proc;
```
$md$;

--------------------------------------------------------------------------------------------------------------

create type mock_memory_duration as enum ('TRANSACTION', 'SESSION', 'PERSISTENT');

--------------------------------------------------------------------------------------------------------------

create table mock_memory (
    routine_signature regprocedure
        primary key
    ,return_type text
        not null
    ,unmock_statement text
        not null
    ,is_prewrapped_by_pg_mockable bool
        default false
    ,mock_value text
    ,mock_duration text
        default 'TRANSACTION'
        check (mock_duration in ('TRANSACTION', 'PERSISTENT'))
);

comment on column mock_memory.routine_signature is
$md$The mockable routine `oid` (via its `regprocedure` alias).

Check the official Postgres docs for more information about `regprocedure` and
other [OID types](https://www.postgresql.org/docs/8.1/datatype-oid.html).

As evidenced by the [`test_dump_restore__pg_mockable()`
procedure](#procedure-test_dump_restore__pg_mockable-text), storing an
`regprocedure` is not a problem with `pg_dump`/`pg_restore`.  The same is true
for other `oid` alias types, because these are all serialized as their `text`
representation during `pg_dump` and then loaded from that text representation
again during `pg_restore`.  See https://dba.stackexchange.com/a/324899/79909 for
details.
$md$;

select pg_extension_config_dump('mock_memory', 'WHERE NOT is_prewrapped_by_pg_mockable');

--------------------------------------------------------------------------------------------------------------

create function mock_memory__before_magic()
    returns trigger
    set search_path to pg_catalog
    language plpgsql
    as $$
declare
    _regprocedure regprocedure;
    _regtype regtype;
    _pg_proc pg_proc;
    _copying bool;
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
                message = 'Dunno how to auto-wrap functions with variadic arguments.';
        end if;
        if _pg_proc.prokind != 'f' then
            raise feature_not_supported using
                message = 'Dunno how to auto-wrap other routines than functions.';
        end if;
        if _pg_proc.proargmodes is not null then
            raise feature_not_supported using
                message = 'Dunno how to auto-wrap functions with `OUT` arguments.';
        end if;
        if _pg_proc.proargnames is not null then
            raise feature_not_supported using
                message = 'Dunno how to auto-wrap functions with named arguments.';
        end if;
    end if;

    if NEW.unmock_statement is null then
        NEW.unmock_statement := 'CREATE OR REPLACE FUNCTION '
            || 'mockable.' || quote_ident(_pg_proc.proname)
            || '(' || pg_get_function_arguments(_regprocedure) || ')'
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

create trigger before_magic
    before insert or update on mock_memory
    for each row
    execute function mock_memory__before_magic();

--------------------------------------------------------------------------------------------------------------

create function mock_memory__after_magic()
    returns trigger
    set search_path to pg_catalog
    language plpgsql
    as $$
declare
    _mock_mem mockable.mock_memory;
    _proc_schema name := 'mockable';
    _pg_proc pg_proc := mockable.pg_proc(NEW.routine_signature::regprocedure);
    _signature_changed bool;
begin
    assert tg_when = 'AFTER';
    assert tg_op in ('INSERT', 'UPDATE');
    assert tg_level = 'ROW';
    assert tg_table_schema = 'mockable';
    assert tg_table_name = 'mock_memory';

    _signature_changed := tg_op = 'UPDATE' and (
        NEW.routine_signature != OLD.routine_signature
        or NEW.unmock_statement != OLD.unmock_statement
    );

    if _signature_changed then
        execute 'DROP FUNCTION mockable.' || quote_ident(_pg_proc.proname);
    end if;

    if NEW.mock_value is not null
        and (_signature_changed or NEW.mock_value is distinct from OLD.mock_value)
    then
        execute 'CREATE OR REPLACE '
            || case _pg_proc.prokind
                when 'f' then 'FUNCTION'
                when 'p' then 'PROCEDURE'
            end
            || ' '
            || 'mockable.' || quote_ident(_pg_proc.proname)
            || '(' || pg_get_function_arguments(_pg_proc.oid) || ')'
            || ' RETURNS ' || pg_get_function_result(_pg_proc.oid)
            || ' LANGUAGE SQL'
            || ' IMMUTABLE'
            || ' SET search_path FROM CURRENT'
            || ' RETURN ' || quote_literal(NEW.mock_value)
            || '::' || pg_get_function_result(_pg_proc.oid)
        ;
    elsif NEW.mock_value is null and (OLD.mock_value is not null or tg_op = 'INSERT') then
        execute NEW.unmock_statement;

        execute 'COMMENT ON FUNCTION mockable.' || quote_ident(_pg_proc.proname)
            || ' IS $md$Mockable wrapper function for `' || NEW.routine_signature || '`.$md$';
    end if;

    execute 'GRANT EXECUTE ON '
        || case _pg_proc.prokind
            when 'f' then 'FUNCTION'
            when 'p' then 'PROCEDURE'
        end
        || ' mockable.' || quote_ident(_pg_proc.proname)
        || ' TO public'
        -- TODO: duplicate original GRANTs
        ;

    return null;
end;
$$;

create trigger after_magic
    after insert or update on mock_memory
    for each row
    execute function mock_memory__after_magic();

--------------------------------------------------------------------------------------------------------------

create function mock_memory__reset_value()
    returns trigger
    set search_path to pg_catalog
    language plpgsql
    as $$
begin
    assert tg_when = 'AFTER';
    assert tg_op in ('INSERT', 'UPDATE');
    assert tg_level = 'ROW';
    assert tg_table_schema = 'mockable';
    assert tg_table_name = 'mock_memory';
    assert NEW.mock_duration = 'TRANSACTION',
        '`WHEN (NEW.mock_duration = ''TRANSACTION'')` condition missing in trigger definition.';
    assert NEW.mock_value is not null,
        '`WHEN (NEW.mock_value IS NOT NULL)` condition missing in trigger definition.';

    -- Normally, I would avoid operations that mutate data from a `CONSTRAINT TRIGGER`.  However, as long as
    -- we don't have a C part in this extension, this hack is the only way I can think of to latch some logic
    -- onto transaction end.

    update  mockable.mock_memory
    set     mock_value = null
    where   routine_signature = NEW.routine_signature
    ;

    return null;
end;
$$;

comment on function mock_memory__reset_value() is
$md$This trigger ensures that the mocked value is always forgotten before transaction end.

Resetting the value in turn ensures that another trigger unmocks the wrapper
function; that is, it will be restored to act as a thin wrapper around the
original (wrapped) function.
$md$;

create constraint trigger reset_value
    after insert or update on mock_memory
    initially deferred
    for each row
    when (NEW.mock_duration = 'TRANSACTION' and NEW.mock_value is not null)
    execute function mock_memory__reset_value();

--------------------------------------------------------------------------------------------------------------

create function wrap_function(
        function_signature$ regprocedure
        ,create_function_statement$ text
        ,mock_duration$ mock_memory_duration
            default 'TRANSACTION'
    )
    returns mock_memory
    volatile
    language sql
begin atomic
    insert into mock_memory
        (routine_signature, unmock_statement, mock_duration)
    values
        (function_signature$, create_function_statement$, mock_duration$)
    returning
        *
    ;
end;

--------------------------------------------------------------------------------------------------------------

create function wrap_function(
        function_signature$ regprocedure
        ,mock_duration$ mock_memory_duration
            default 'TRANSACTION'
    )
    returns mock_memory
    volatile
    language sql
begin atomic
    insert into mock_memory
        (routine_signature, mock_duration)
    values
        (function_signature$, mock_duration$)
    returning
        *
    ;
end;

--------------------------------------------------------------------------------------------------------------

create function mock(
        in routine_signature$ regprocedure
        ,inout mock_value$ anyelement
    )
    returns anyelement
    volatile
    set search_path to pg_catalog
    language plpgsql
    as $plpgsql$
begin
    update  mockable.mock_memory
    set     mock_value = mock_value$
    where   routine_signature = routine_signature$
    ;

    if not found then
        raise no_data_found using
            message = format(
                'No `mock_memory` record of `%I` found.'
                ,routine_signature$
            )
            ,hint = 'You should probably call the `wrap_function()` function first.';
    end if;
end;
$plpgsql$;

--------------------------------------------------------------------------------------------------------------

create procedure unmock(
        routine_signature$ regprocedure
    )
    set search_path to pg_catalog
    language plpgsql
    as $plpgsql$
begin
    update  mockable.mock_memory
    set     mock_value = null
    where   routine_signature = routine_signature$
    ;
end;
$plpgsql$;

--------------------------------------------------------------------------------------------------------------

insert into mock_memory (
    routine_signature
    ,is_prewrapped_by_pg_mockable
)
values (
    'pg_catalog.now()'
    ,true
);

--------------------------------------------------------------------------------------------------------------

create function transaction_timestamp()
    returns timestamptz
    stable
    language sql
    return mockable.now();

comment on function transaction_timestamp() is
$md$`transaction_timestamp()` is simply an alias for `mockable.now()`.  If you wish to mock it, mock `mockable.now()`.
$md$;

--------------------------------------------------------------------------------------------------------------

create function "current_timestamp"()
    returns timestamptz
    stable
    language sql
    return mockable.now();

comment on function "current_timestamp"() is
$md$`current_timestamp()` is derived from `mockable.now()`.  To mock it, mock `pg_catalog.now()`.

Unlike its standard (PostgreSQL) counterpart, `current_timestamp()` does not
support a precision parameter.  Feel free to implement it.
$md$;

--------------------------------------------------------------------------------------------------------------

create function "current_date"()
    returns date
    stable
    language sql
    return mockable.now()::date;

comment on function "current_date"() is
$md$`current_date()` is derived from `mockable.now()`.  To mock it, mock `pg_catalog.now()`.
$md$;

--------------------------------------------------------------------------------------------------------------

create function "current_time"()
    returns timetz
    stable
    language sql
    return mockable.now()::timetz;

comment on function "current_time"() is
$md$`current_time()` is derived from `mockable.now()`.  To mock it, mock `pg_catalog.now()`.

Unlike its standard (PostgreSQL) counterpart, `current_time()` does not support
a precision parameter.  Feel free to implement it.
$md$;

--------------------------------------------------------------------------------------------------------------

create function "localtime"()
    returns time
    stable
    language sql
    return mockable.now()::time;

comment on function "localtime"() is
$md$`localtime()` is derived from `mockable.now()`.  To mock it, mock `pg_catalog.now()`.

Unlike its standard (PostgreSQL) counterpart, `localtime()` does not support a
precision parameter.  Feel free to implement it.
$md$;

--------------------------------------------------------------------------------------------------------------

create function "localtimestamp"()
    returns timestamp
    stable
    language sql
    return mockable.now()::timestamp;
comment
    on function "localtimestamp"()
    is $md$
`localtimestamp()` is derived from `mockable.now()`.  To mock it, mock `pg_catalog.now()`.

Unlike its standard (PostgreSQL) counterpart, `localtimestamp()` does not support a precision parameter.
Feel free to implement it.
$md$;

--------------------------------------------------------------------------------------------------------------

create function timeofday()
    returns text
    stable
    set datestyle to 'Postgres'
    language sql
    return mockable.now()::text;

comment on function timeofday() is
$md$`timeofday()` is derived from `mockable.now()`.  To mock it, mock `pg_catalog.now()`.
$md$;

--------------------------------------------------------------------------------------------------------------

create procedure test__pg_mockable()
    set search_path to pg_catalog
    set plpgsql.check_asserts to true
    set pg_readme.include_this_routine_definition to true
    language plpgsql
    as $plpgsql$
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

    raise transaction_rollback;
exception
    when transaction_rollback then
end;
$plpgsql$;

--------------------------------------------------------------------------------------------------------------

create procedure test_dump_restore__pg_mockable(test_stage$ text)
    set search_path to pg_catalog, mockable
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
$$;

comment on procedure test_dump_restore__pg_mockable(text) is
$md$This procedure is to be called by the `test_dump_restore.sh` and `test_dump_restore.sql` companion scripts, once before `pg_dump` (with `test_stage$ = 'pre-dump'` argument) and once after `pg_restore` (with the `test_stage$ = 'post-restore'`).
$md$;

--------------------------------------------------------------------------------------------------------------
