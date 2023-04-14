EXTENSION = pg_mockable_dependent_test_extension

DATA = $(wildcard $(EXTENSION)*.sql)

REGRESS = $(EXTENSION)

PG_CONFIG = pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)
