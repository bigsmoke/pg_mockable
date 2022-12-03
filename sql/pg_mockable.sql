begin transaction;

create extension pg_mockable
    cascade;

call mockable.test__pg_mockable();

rollback transaction;
