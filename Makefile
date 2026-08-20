.PHONY: validate skillscheck ci

all: ci

validate:
	./scripts/validate.sh

skillscheck:
	uvx skillscheck@0.9.6 --strict skills

ci: skillscheck validate
