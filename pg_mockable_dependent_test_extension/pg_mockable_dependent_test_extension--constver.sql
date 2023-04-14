-- Complain if script is sourced in psql, rather than via CREATE EXTENSION
\echo Use "CREATE EXTENSION pg_mockable_dependent_test_extension" to load this file. \quit

--------------------------------------------------------------------------------------------------------------

select mockable.mock('pg_catalog.now()', pg_catalog.now() - '2 days'::interval);

call mockable.unmock('pg_catalog.now()');

--------------------------------------------------------------------------------------------------------------
