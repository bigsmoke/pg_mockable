begin transaction;

create extension pg_mockable version '0.1.8' cascade;

call mockable.test__pg_mockable();

rollback transaction and chain;

create extension pg_mockable cascade;

call mockable.test__pg_mockable();

rollback transaction;
