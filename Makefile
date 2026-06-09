.PHONY: validate skillscheck ci

validate:
	./scripts/validate.sh

skillscheck:
	uvx skillscheck@0.9.5 --strict .

ci: validate skillscheck
