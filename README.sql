\pset tuples_only
\pset format unaligned

begin;

create extension pg_mockable cascade;

select mockable.pg_mockable_readme();

rollback;
