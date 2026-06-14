/**
 * CHANGELOG.md:
 *
 * - Selective logging for specific mocked/mockable functions can now be turned
 *   on (and off again) via the new `mock_memory.raise_debug_messages` table
 *   column.  Logging was added to two of the trigger functions on the
 *   `mock_memory` table:
 */
alter table mock_memory
    add column raise_debug_messages bool
        not null
        default false
;

/**
 * CHANGELOG.md:
 *
 *   + `mock_memory__after_magic()`, and
 */
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
    _proc_grantee oid;
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
            if NEW.raise_debug_messages then
                raise debug using message = format(
                    'mock_memory__after_magic() %s %s: mocking %I with value: %L'
                    ,tg_when, tg_op, NEW.routine_signature::regprocedure, NEW.mock_value
                );
            end if;

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
            if NEW.raise_debug_messages then
                raise debug using message = format(
                    'mock_memory__after_magic() %s %s: unmocking %I …'
                    ,tg_when, tg_op, NEW.routine_signature::regprocedure
                );
            end if;

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

    if _pg_proc.proacl is not null then
        execute 'REVOKE EXECUTE ON '
                || case _pg_proc.prokind
                    when 'f' then 'FUNCTION'
                    when 'p' then 'PROCEDURE'
                end
                || ' mockable.' || quote_ident(_pg_proc.proname)
                || ' FROM PUBLIC';

        for _proc_grantee in
            select
                routine_grant.grantee
            from
                pg_catalog.pg_proc
            cross join
                pg_catalog.aclexplode(pg_proc.proacl) as routine_grant
            where
                pg_proc.oid = NEW.routine_signature
        loop
            execute 'GRANT EXECUTE ON '
                || case _pg_proc.prokind
                    when 'f' then 'FUNCTION'
                    when 'p' then 'PROCEDURE'
                end
                || ' mockable.' || quote_ident(_pg_proc.proname)
                || ' TO '
                || case
                    when _proc_grantee = 0
                    then 'PUBLIC'
                    else _proc_grantee::regrole::text
                end
                ;
        end loop;
    end if;

    return null;
end;
$$;

/**
 * CHANGELOG.md:
 *
 *   + `mock_memory__reset_value()`.
 */
create or replace function mock_memory__reset_value()
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

    if NEW.raise_debug_messages then
        raise debug using message = format(
            'mockable.mock_memory__reset_value() %s %s: NEW.mock_value = %L → NULL'
            ,tg_when, tg_op, NEW.mock_value
        );
    end if;

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


/**
 * CHANGELOG.md:
 *   ~
 *   The helper functions to make function mockable now also sport a new
 *   "raise_debug_messages$" parameter; i.e.:
 *
 *   1. `wrap_function(regprocedure, text, mock_memory_duration)` has been
 *      replaced with wrap_function(regprocedure, text, mock_memory_duration,
 *      bool)`, and
 */
drop function wrap_function(regprocedure, text, mock_memory_duration);
create function wrap_function(
        function_signature$ regprocedure
        ,create_function_statement$ text
        ,mock_duration$ mock_memory_duration
            default 'TRANSACTION'
        ,"raise_debug_messages$" bool
            default false
    )
    returns mock_memory
    volatile
    language sql
begin atomic
    insert into mock_memory
        (routine_signature, unmock_statement, mock_duration, raise_debug_messages)
    values
        (function_signature$, create_function_statement$, mock_duration$, "raise_debug_messages$")
    returning
        *
    ;
end;

/**
 * CHANGELOG.md:
 *
 *   2. `wrap_function(regprocedure, mock_memory_duration)` has been replaced
 *       with `wrap_function(regprocedure, mock_memory_duration, bool)`.
 */
drop function wrap_function(regprocedure, mock_memory_duration);
create function wrap_function(
        function_signature$ regprocedure
        ,mock_duration$ mock_memory_duration
            default 'TRANSACTION'
        ,"raise_debug_messages$" bool
            default false
    )
    returns mock_memory
    volatile
    language sql
begin atomic
    insert into mock_memory
        (routine_signature, mock_duration, raise_debug_messages)
    values
        (function_signature$, mock_duration$, "raise_debug_messages$")
    returning
        *
    ;
end;


/**
 * CHANGELOG.md:
 *
 * - The `test__pg_mockable()` procedure now also tests the indirect invocation
 *   of mocked/mockable functions.
 */
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

    <<test_that_grants_are_copied>>
    begin
        create role underling;

        create function test__schema.private_func() returns int return 100;
        revoke execute on function test__schema.private_func() from public;
        assert not has_function_privilege('underling', 'test__schema.private_func()', 'EXECUTE');

        perform mockable.wrap_function('test__schema.private_func()');
        assert not has_function_privilege('underling', 'mockable.private_func()', 'EXECUTE');
        perform mockable.mock('test__schema.private_func()', 1000::int);
        assert not has_function_privilege('underling', 'mockable.private_func()', 'EXECUTE');

        grant execute on function test__schema.private_func() to underling;
        assert has_function_privilege('underling', 'test__schema.private_func()', 'EXECUTE');

        perform mockable.mock('test__schema.private_func()', 1000::int);
        assert has_function_privilege('underling', 'mockable.private_func()', 'EXECUTE');

    end test_that_grants_are_copied;

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

    <<indirect_mocked_function_call>>
    declare
        _initial_ts timestamptz := mockable.now();
        _changed_ts timestamptz;
    begin
        create function f()
            returns table (moment timestamptz)
            language sql
            parallel safe leakproof
        begin atomic
            select
                s.moment
            from
                generate_series(
                    mockable.now()
                    ,mockable.now() + '1 year'::interval
                    ,'1 month'::interval
                ) as s (moment)
            ;
        end;

        create function ff()
            returns table (moment timestamptz, blaat text)
            language sql
            parallel safe leakproof
        begin atomic
            select
                f.moment
                ,'dfdfdf' as blaat
            from
                f() as f
            ;
        end;

        assert (select moment from ff() order by moment limit 1) = _initial_ts;

        _changed_ts := mockable.mock('pg_catalog.now()', mockable.now() + '5 minute'::interval);
        assert (select moment from ff() order by moment limit 1) = _changed_ts;
        <<blaat>>
        begin
            _changed_ts := mockable.mock('pg_catalog.now()', mockable.now() + '25 minute'::interval);
            assert (select moment from ff() order by moment limit 1) = _changed_ts;
        exception
            when transaction_rollback then
        end blaat;
        _changed_ts := mockable.mock('pg_catalog.now()', mockable.now() + '15 minute'::interval);
        assert (select moment from ff() order by moment limit 1) = _changed_ts;
    end indirect_mocked_function_call;

    raise transaction_rollback;
exception
    when transaction_rollback then
end;
$plpgsql$;


/**
 * CHANGELOG.md:
 *
 * - The bare URL in the Markdown comment on the
 *   `mock_memory.routine_signature` table column has been marked as such with
 *   proper markdown syntax: `<URL>`
 */
comment on column mock_memory.routine_signature is
$md$The mockable routine `oid` (via its `regprocedure` alias).

Check the official Postgres docs for more information about `regprocedure` and
other [OID types](https://www.postgresql.org/docs/8.1/datatype-oid.html).

As evidenced by the [`test_dump_restore__pg_mockable()`
procedure](#procedure-test_dump_restore__pg_mockable-text), storing an
`regprocedure` is not a problem with `pg_dump`/`pg_restore`.  The same is true
for other `oid` alias types, because these are all serialized as their `text`
representation during `pg_dump` and then loaded from that text representation
again during `pg_restore`.  See <https://dba.stackexchange.com/a/324899/79909>
for details.
$md$;
