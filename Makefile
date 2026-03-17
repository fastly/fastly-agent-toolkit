.PHONY: validate skillscheck ci

validate:
	./scripts/validate.sh

skillscheck:
	uvx skillscheck --strict .

ci: validate skillscheck
