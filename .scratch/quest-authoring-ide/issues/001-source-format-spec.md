# 001 — Source Format Specification

**What to build:** Define the YAML schema for project.yaml, operation files, and blueprint files. This includes:
- project.yaml structure (name, version, target, zon_id, filiation, variables)
- operation.yaml structure (name, description, zone_ref, level_range, variables, actions array)
- blueprint.yaml structure (name, description, params, expands_to array)
- Action structure (type, id, args, condition, etc.)
- Data types and validation rules for each field
- Example files for all three types

**Blocked by:** None — can start immediately.

**Status:** ready-for-agent

- [ ] Define project.yaml schema with all required fields
- [ ] Define operation.yaml schema 
- [ ] Define blueprint.yaml schema
- [ ] Define action structure and subtypes
- [ ] Specify data types (string, number, boolean, enum, references)
- [ ] Create example project.yaml (Elwynn 1-10 Human)
- [ ] Create example operation.yaml (Northshire)
- [ ] Create example blueprint.yaml (QuestHub)
- [ ] Define validation rules (required fields, ranges, references)
- [ ] Document variable binding syntax
- [ ] Specify how parameters flow from blueprint instances to expanded actions