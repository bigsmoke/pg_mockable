-- complain if script is sourced in psql, rather than via CREATE EXTENSION
\echo Use "CREATE EXTENSION pg_mockable" to load this file. \quit

--------------------------------------------------------------------------------------------------------------

-- The previous version of this comment had a copy-paste error: it referred to
-- `pg_readme` instead of `pg_mockable`.
comment
    on function pg_mockable_meta_pgxn()
    is $markdown$
Returns the JSON meta data that has to go into the `META.json` file needed for
[PGXN—PostgreSQL Extension Network](https://pgxn.org/) packages.

The `Makefile` includes a recipe to allow the developer to: `make META.json` to
refresh the meta file with the function's current output, including the
`default_version`.

`pg_mockable` can indeed be found on PGXN: https://pgxn.org/dist/pg_mockable/
$markdown$;

--------------------------------------------------------------------------------------------------------------

-- The newest version of `pg_readme` will include schema `COMMENT` object if
-- the extension is fixedly bound to a schema (which `pg_mockable` is).
comment
    on schema mockable
    is $markdown$
The `mockable` schema belongs to the `pg_mockable` extension.

Postgres (as of Pg 15) doesn't allow one to specify a _default_ schema, and do
something like `schema = 'mockable'` combined with `relocatable = true` in the
`.control` file.  Therefore I decided to choose the `mockable` schema name
_for_ you, even though you might have very well preferred something shorted
like `mock`, even shorter like `mck`, or more verbose such as `mock_objects`.
$markdown$;

--------------------------------------------------------------------------------------------------------------
