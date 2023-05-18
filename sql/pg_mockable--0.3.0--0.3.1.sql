-- Complain if script is sourced in `psql`, rather than via `CREATE EXTENSION`
\echo Use "CREATE EXTENSION pg_mockable" to load this file. \quit

--------------------------------------------------------------------------------------------------------------

-- `WITH CASCADE`
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
    create extension if not exists pg_readme
        with cascade;

    _readme := pg_extension_readme('pg_mockable'::name);

    raise transaction_rollback;  -- to drop extension if we happened to `CREATE EXTENSION` for just this.
exception
    when transaction_rollback then
        return _readme;
end;
$plpgsql$;

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
                "file": "pg_mockable--0.3.1.sql",
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

-- Store `mock_signature`.
-- Detect extension script context and set `pg_extension_name` and `pg_extension_version` accordingly.
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

-- Take care of which extension should own which mock routine.
create or replace function mock_memory__after_magic()
    returns trigger
    set search_path to pg_catalog
    language plpgsql
    as $$
declare
    _mock_mem mockable.mock_memory;
    _proc_schema name := 'mockable';
    _pg_proc pg_proc := mockable.pg_proc(NEW.routine_signature::regprocedure);
    _signature_changed bool := tg_op = 'UPDATE' and (
        NEW.routine_signature != OLD.routine_signature
        or NEW.unmock_statement != OLD.unmock_statement
    );
    _must_mock bool := NEW.mock_value is not null
        and (_signature_changed or NEW.mock_value is distinct from OLD.mock_value);
    _must_unmock bool := NEW.mock_value is null and (OLD.mock_value is not null or tg_op = 'INSERT');
    _extension_context_detection_object name;
    _extension_context name;
begin
    assert tg_when = 'AFTER';
    assert tg_op in ('INSERT', 'UPDATE');
    assert tg_level = 'ROW';
    assert tg_table_schema = 'mockable';
    assert tg_table_name = 'mock_memory';

    -- The extension context may be:
    --    a) outside of a `CREATE EXTENSION` / `ALTER EXTENSION` context (`_extension_context IS NULL`);
    --    b) inside the `CREATE EXTENSION` / `ALTER EXTENSION` context of the extension owning the config
    --       table to which this trigger is attached; or
    --    c) inside the `CREATE EXTENSION` / `ALTER EXTENSION` context of extension that changes settings in
    --       another extension's configuration table.
    _extension_context_detection_object := format(
        'extension_context_detector_%s'
        ,floor(pg_catalog.random() * 1000)
    );
    execute format('CREATE TEMPORARY TABLE %I (col int) ON COMMIT DROP', _extension_context_detection_object);
    select
        pg_extension.extname
    into
        _extension_context
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

    if _signature_changed then
        execute 'DROP FUNCTION ' || NEW.mock_signature;
    end if;

    if _must_mock or _must_unmock then
        if NEW.pg_extension_name is not null and _extension_context is distinct from NEW.pg_extension_name
        then
            execute 'ALTER EXTENSION ' || NEW.pg_extension_name || ' DROP '
                || case _pg_proc.prokind when 'f' then 'FUNCTION' when 'p' then 'PROCEDURE' end
                || ' ' || NEW.mock_signature;
            if _extension_context is not null then
                execute 'ALTER EXTENSION ' || _extension_context || ' ADD '
                    || case _pg_proc.prokind when 'f' then 'FUNCTION' when 'p' then 'PROCEDURE' end
                    || ' ' || NEW.mock_signature;
            end if;
        end if;

        if _must_mock then
            execute 'CREATE OR REPLACE '
                || case _pg_proc.prokind
                    when 'f' then 'FUNCTION'
                    when 'p' then 'PROCEDURE'
                end
                || ' ' || NEW.mock_signature
                || ' RETURNS ' || pg_get_function_result(_pg_proc.oid)
                || ' LANGUAGE SQL'
                || ' IMMUTABLE'
                || ' SET search_path FROM CURRENT'
                || ' RETURN ' || quote_literal(NEW.mock_value)
                || '::' || pg_get_function_result(_pg_proc.oid)
            ;
        elsif _must_unmock then
            execute NEW.unmock_statement;

            execute 'COMMENT ON FUNCTION mockable.' || quote_ident(_pg_proc.proname)
                || ' IS $md$Mockable wrapper function for `' || NEW.routine_signature || '`.$md$';
        end if;

        if NEW.pg_extension_name is not null and _extension_context is distinct from NEW.pg_extension_name
        then
            if _extension_context is not null then
                execute 'ALTER EXTENSION ' || _extension_context || ' DROP '
                    || case _pg_proc.prokind when 'f' then 'FUNCTION' when 'p' then 'PROCEDURE' end
                    || ' ' || NEW.mock_signature;
            end if;
            execute 'ALTER EXTENSION ' || NEW.pg_extension_name || ' ADD '
                || case _pg_proc.prokind when 'f' then 'FUNCTION' when 'p' then 'PROCEDURE' end
                || ' ' || NEW.mock_signature;
        end if;
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

--------------------------------------------------------------------------------------------------------------

alter table mock_memory
    add column mock_signature text
        unique
    ,add column pg_extension_name text
    ,add column pg_extension_version text
    ;

comment on column mock_memory.mock_signature is
$md$The mock (wrapper) function its calling signature.

The `mock_signature`, contrary to `routine_signature`, is stored as `text`,
because we want to be able to set in the `BEFORE` trigger before the function
is actually created in the `AFTER` trigger.
$md$;

update
    mock_memory
set
    pg_extension_name = 'pg_mockable'
    ,pg_extension_version = (select extversion from pg_extension where extname = 'pg_mockable')
    ,mock_signature = 'mockable.'
        || (select quote_ident(pg_proc.proname) from pg_proc where pg_proc.oid = routine_signature)
        || '(' || pg_get_function_arguments(routine_signature) || ')'
where
    is_prewrapped_by_pg_mockable
;

alter table mock_memory
    alter column mock_signature
        set not null;

select pg_extension_config_dump('mock_memory', 'WHERE pg_extension_name IS NULL');

--------------------------------------------------------------------------------------------------------------

-- Test a `pg_mockable` dependent extension.
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

    create extension pg_mockable_dependent_test_extension
        with version 'constver';

    raise transaction_rollback;
exception
    when transaction_rollback then
end;
$plpgsql$;

--------------------------------------------------------------------------------------------------------------

drop function wrap_function(regprocedure, text, mock_memory_duration);

--------------------------------------------------------------------------------------------------------------

drop function wrap_function(regprocedure, mock_memory_duration);

--------------------------------------------------------------------------------------------------------------

alter table mock_memory
    drop column is_prewrapped_by_pg_mockable;

--------------------------------------------------------------------------------------------------------------

-- Recreate with new return type (minus a column).
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

-- Recreate with new return type (minus a column).
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
