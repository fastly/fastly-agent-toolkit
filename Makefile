.PHONY: validate skillscheck ci

all: ci

validate:
	./scripts/validate.sh

skillscheck:
	uvx skillscheck@0.9.7 --strict skills

ci: validate skillscheck
