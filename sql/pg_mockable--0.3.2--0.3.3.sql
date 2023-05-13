-- Complain if script is sourced in `psql`, rather than via `CREATE EXTENSION`.
\echo Use "CREATE EXTENSION pg_mockable" to load this file. \quit

--------------------------------------------------------------------------------------------------------------

comment on schema mockable is
$md$The `mockable` schema belongs to the `pg_mockable` extension.

Postgres (as of Pg 15) doesn't allow one to specify a _default_ schema, and do
something like `schema = 'mockable'` combined with `relocatable = true` in the
`.control` file.  Therefore I decided to choose the `mockable` schema name
_for_ you, even though you might have very well preferred something shorter
like `mock`, even shorter like `mck`, or more verbose such as `mock_objects`.
$md$;

--------------------------------------------------------------------------------------------------------------
