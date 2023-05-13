-- Complain if script is sourced in `psql`, rather than via `CREATE EXTENSION`
\echo Use "CREATE EXTENSION pg_mockable" to load this file. \quit

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
                "file": "pg_mockable--0.3.0.sql",
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

drop function wrap_function(regprocedure, text, mock_memory_duration);

drop function wrap_function(regprocedure, mock_memory_duration);

--------------------------------------------------------------------------------------------------------------

alter table mock_memory
    alter column routine_signature type regprocedure using routine_signature::regprocedure;

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

--------------------------------------------------------------------------------------------------------------

-- Protect against mocking a mock function/procedure.
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

--------------------------------------------------------------------------------------------------------------

-- No need to cast `routine_signature` to `text` any more.
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

-- No need to cast `routine_signature` to `text` any more.
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

-- Add error condition.
create or replace function mock(
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

-- No need to cast `routine_signature` to `text` any more.
create or replace procedure unmock(
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

-- Test protection against trying to mock mock functions/procedures.
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

-- Adjust to the fact that `routine_signature` is now of type `regprocedure`.
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

--------------------------------------------------------------------------------------------------------------
