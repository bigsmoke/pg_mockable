-- Complain if script is sourced in `psql`, rather than via `CREATE EXTENSION`
\echo Use "CREATE EXTENSION pg_mockable" to load this file. \quit

--------------------------------------------------------------------------------------------------------------

-- Reformat comment.
comment on schema mockable is
$md$The `mockable` schema belongs to the `pg_mockable` extension.

Postgres (as of Pg 15) doesn't allow one to specify a _default_ schema, and do
something like `schema = 'mockable'` combined with `relocatable = true` in the
`.control` file.  Therefore I decided to choose the `mockable` schema name
_for_ you, even though you might have very well preferred something shorted
like `mock`, even shorter like `mck`, or more verbose such as `mock_objects`.
$md$;

--------------------------------------------------------------------------------------------------------------

-- Add recommended development package.
-- Change entry `.sql` file.
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
                "file": "pg_mockable--0.2.0.sql",
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

-- Reformat comment to have synopsis on first line.
comment on function pg_proc(regprocedure) is
$md$Conveniently go from function calling signature description or OID (`regprocedure`) to `pg_catalog.pg_proc`.

Example:

```sql
SELECT pg_proc('pg_catalog.current_setting(text, bool)');
```
$md$;

--------------------------------------------------------------------------------------------------------------

-- Reformat comment to have synopsis on first line.
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

alter table mock_memory
    alter column routine_signature
        type text
    ,add column return_type text
    ,add column mock_value text
    ,add column mock_duration text
        default 'TRANSACTION'
        check (mock_duration in ('TRANSACTION', 'PERSISTENT'))
;

comment on column mock_memory.routine_signature is
$md$The mockable routine name and `IN` argument types as consumable or producable by `regprocedure`.

This concerns the name of the _original_ routine that is made mockable by the
wrapper routine that is created upon insertion in this table (or replaced upon
update).  The routine name must be qualified unless if it is a routine from the
`pg_catalog` schema.

The reason that the function signature is stored as `text` instead of the
`regprocedure` type is restorability, because OIDs cannot be assumed to be the
same between clusters and `pg_dump`/`pg_restore` cycles.

Check the official Postgres docs for more information about `regprocedure` and
other [OID types](https://www.postgresql.org/docs/8.1/datatype-oid.html).
$md$;

update
    mock_memory
set
    return_type = pg_catalog.pg_get_function_result(routine_signature::regprocedure);
;

alter table mock_memory
    alter column return_type
        set not null;

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

drop procedure wrap_function(regprocedure);

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
        (function_signature$::text, create_function_statement$, mock_duration$)
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
        (function_signature$::text, mock_duration$)
    returning
        *
    ;
end;

--------------------------------------------------------------------------------------------------------------

create or replace function mock(
        routine_signature$ regprocedure
        ,mock_value$ anyelement
    )
    returns anyelement
    volatile
    set search_path to pg_catalog
    language plpgsql
    as $plpgsql$
begin
    update  mockable.mock_memory
    set     mock_value = mock_value$
    where   routine_signature = routine_signature$::text
    ;

    return mock_value$;
end;
$plpgsql$;

--------------------------------------------------------------------------------------------------------------

-- Reformat comment to have synopsis on first line.
comment on function transaction_timestamp() is
$md$`transaction_timestamp()` is simply an alias for `mockable.now()`.  If you wish to mock it, mock `mockable.now()`.
$md$;

--------------------------------------------------------------------------------------------------------------

-- Reformat comment to have synopsis on first line.
-- Document lack of precision parameter.
comment on function "current_timestamp"() is
$md$`current_timestamp()` is derived from `mockable.now()`.  To mock it, mock `pg_catalog.now()`.

Unlike its standard (PostgreSQL) counterpart, `current_timestamp()` does not
support a precision parameter.  Feel free to implement it.
$md$;

--------------------------------------------------------------------------------------------------------------

-- Reformat comment to have synopsis on first line.
-- Document lack of precision parameter.
comment on function "current_date"() is
$md$`current_date()` is derived from `mockable.now()`.  To mock it, mock `pg_catalog.now()`.
$md$;

--------------------------------------------------------------------------------------------------------------

-- Reformat comment to have synopsis on first line.
-- Document lack of precision parameter.
comment on function "current_time"() is
$md$`current_time()` is derived from `mockable.now()`.  To mock it, mock `pg_catalog.now()`.

Unlike its standard (PostgreSQL) counterpart, `current_time()` does not support
a precision parameter.  Feel free to implement it.
$md$;

--------------------------------------------------------------------------------------------------------------

-- Reformat comment to have synopsis on first line.
-- Document lack of precision parameter.
comment on function "localtime"() is
$md$`localtime()` is derived from `mockable.now()`.  To mock it, mock `pg_catalog.now()`.

Unlike its standard (PostgreSQL) counterpart, `localtime()` does not support a
precision parameter.  Feel free to implement it.
$md$;

--------------------------------------------------------------------------------------------------------------

-- Reformat comment to have synopsis on first line.
-- Document lack of precision parameter.
comment on function timeofday() is
$md$`timeofday()` is derived from `mockable.now()`.  To mock it, mock `pg_catalog.now()`.
$md$;

--------------------------------------------------------------------------------------------------------------

create or replace procedure test__pg_mockable()
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

    perform mockable.mock('now()', '2022-01-02 10:20'::timestamptz);

    perform set_config('search_path', 'pg_catalog', true);
    assert now() = _now;

    perform set_config('search_path', 'mockable, pg_catalog', true);
    assert now() = '2022-01-02 10:20'::timestamptz;

    raise transaction_rollback;
exception
    when transaction_rollback then
end;
$plpgsql$;

--------------------------------------------------------------------------------------------------------------

create or replace procedure test_dump_restore__pg_mockable(test_stage$ text)
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
        assert exists (select from mock_memory where routine_signature = 'now()'::regprocedure::text);
        assert mockable.now() = pg_catalog.now(),
            'This wrapper function should have been restored to a wrapper of the original function.';

        assert exists (select from mock_memory where routine_signature = 'test__schema.func()');
        assert mockable.func() = 8,
            'The wrapper function should have been restored to a wrapper of the original function.';

        assert exists (select from mock_memory where routine_signature = 'test__schema.func2()');
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
