# Local shortcuts. The database targets need an Oracle container called
# oracledb (see scripts/ci.sh) and wardround installed with pip install -e ".[dev]".

.PHONY: lint test ci pipeline bench bench-python feed reports clean

lint:
	ruff check .
	ruff format --check .

test:
	pytest -q

ci:
	RUNTIME=docker ./scripts/ci.sh

pipeline:
	RUNTIME=docker ./scripts/pipeline.sh

# The whole path at one, three and nine times the default feed, each on a
# fresh schema. Takes about six minutes.
bench:
	RUNTIME=docker SIZES="30:3 90:9 270:27" ./scripts/bench.sh

bench-python:
	python bench/python.py

feed:
	wardround generate --out build/feed.hl7

# The March reports as one HTML page, from a database the pipeline loaded.
reports:
	wardround report --from 2026-03-01 --to 2026-04-01 --format html --out build/reports.html

clean:
	rm -rf build .pytest_cache .ruff_cache
