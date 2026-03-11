.PHONY: validate skillscheck ci

validate:
	./scripts/validate.sh

skillscheck:
	uvx skillscheck skills

ci: validate skillscheck
