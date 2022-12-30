\pset tuples_only
\pset format unaligned

begin;

create extension pg_mockable
    cascade;

select jsonb_pretty(mockable.pg_mockable_meta_pgxn());

rollback;
