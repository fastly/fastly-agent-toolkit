.PHONY: validate skillscheck ci package

all: ci

validate:
	./scripts/validate.sh

skillscheck:
	uvx skillscheck@0.9.7 --strict skills

ci: validate skillscheck

package: ci
	uv run --no-project python scripts/package.py
