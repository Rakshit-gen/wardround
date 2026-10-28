# Local shortcuts. The database targets need an Oracle container called
# oracledb (see scripts/ci.sh) and wardround installed with pip install -e ".[dev]".

.PHONY: lint test ci pipeline feed clean

lint:
	ruff check .
	ruff format --check .

test:
	pytest -q

ci:
	RUNTIME=docker ./scripts/ci.sh

pipeline:
	RUNTIME=docker ./scripts/pipeline.sh

feed:
	wardround generate --out build/feed.hl7

clean:
	rm -rf build .pytest_cache .ruff_cache
