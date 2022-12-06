-- complain if script is sourced in psql, rather than via CREATE EXTENSION
\echo Use "CREATE EXTENSION pg_mockable" to load this file. \quit

--------------------------------------------------------------------------------------------------------------

alter procedure test__pg_mockable
    set plpgsql.check_asserts to true;

--------------------------------------------------------------------------------------------------------------
