# 003 — Compiler: YAML Parser and AST

**What to build:** Create the foundation of the compiler pipeline:
- YAML parser that reads project.yaml, operations/*.operation.yaml, blueprints/*.blueprint.yaml
- Abstract Syntax Tree (AST) representation of the source files
- Symbol table for tracking variables, blueprints, and operation references
- Basic validation: duplicate definitions, circular references
- Error reporting with line/column numbers
- Integration with enhanced QueryClient for validation (stubbed initially)

**Blocked by:** 001 — Source Format Specification

**Status:** ready-for-agent

- [ ] Create YAML parser using existing Lua YAML library or bind to serde via FFI if needed
- [ ] Define AST node types: Project, Operation, Blueprint, Action, Parameter, Expression
- [ ] Implement symbol table with scopes (project, operation, blueprint)
- [ ] Detect and report duplicate definitions (same name in same scope)
- [ ] Detect and report circular blueprint expansions
- [ ] Validate references exist (e.g., action.type is valid)
- [ ] Provide error context: filename, line number, column
- [ ] Parse project.yaml into Project AST node
- [ ] Parse all operation.yaml files into Operation AST nodes
- [ ] Parse all blueprint.yaml files into Blueprint AST nodes
- [ ] Resolve variable references ($variable) and blueprint references
- [ ] Test with simple example project