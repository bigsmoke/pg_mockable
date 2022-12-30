-- complain if script is sourced in psql, rather than via CREATE EXTENSION
\echo Use "CREATE EXTENSION pg_mockable" to load this file. \quit

--------------------------------------------------------------------------------------------------------------

-- Change `SET pg_readme.include_routine_definitions` boolean setting to `SET
-- pg_readme.include_routine_definitions_like` array (with what happens to be the new `pg_readme` default).
-- 
-- No longer pin `CREATE EXTENSION pg_readme` to a specific version; let Pg pick the default.
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

-- Add previously missing comment.
comment
    on function pg_mockable_readme()
    is $markdown$
Generates the text for a `README.md` in Markdown format using the amazing power
of the `pg_readme` extension.  Temporarily installs `pg_readme` if it is not
already installed in the current database.
$markdown$;

--------------------------------------------------------------------------------------------------------------
