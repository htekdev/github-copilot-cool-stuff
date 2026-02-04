# Spec-Driven Development (SDD) Workflow

A repeatable, disciplined workflow for AI-assisted development that keeps you in control.

---

## Quick Reference

```
┌─────────────────────────────────────────────────────────────────┐
│  1. SPECIFY  →  2. DESIGN  →  3. PLAN  →  4. IMPLEMENT  →  5. VALIDATE  │
└─────────────────────────────────────────────────────────────────┘
```

---

## Phase 1: SPECIFY (Requirements)

**Goal:** Define WHAT you're building in human-reviewable form.

### Checklist
- [ ] Write user story in "As a... I want... So that..." format
- [ ] Define 3-5 acceptance criteria (GIVEN/WHEN/THEN)
- [ ] Identify scope boundaries (what's IN and OUT)
- [ ] Flag dependencies on existing code/systems

### Template

```markdown
## Feature: [Feature Name]

### User Story
As a [role], I want [capability], so that [benefit].

### Acceptance Criteria
1. GIVEN [context], WHEN [action], THEN [outcome]
2. GIVEN [context], WHEN [action], THEN [outcome]
3. GIVEN [context], WHEN [action], THEN [outcome]

### Scope
**In Scope:**
- ...

**Out of Scope:**
- ...

### Dependencies
- Existing: [files/modules this depends on]
- External: [APIs, services, packages]
```

### ⚠️ Quality Gate
**Is this human-reviewable in under 5 minutes?** If not, decompose further.

---

## Phase 2: DESIGN (Technical Approach)

**Goal:** Define HOW you'll build it before touching code.

### Checklist
- [ ] Identify affected files/modules
- [ ] Define data models/schemas (if any)
- [ ] Sketch API contracts/interfaces
- [ ] Note error handling approach
- [ ] List edge cases to handle

### Template

```markdown
## Technical Design: [Feature Name]

### Affected Files
- `path/to/file1.ts` - [what changes]
- `path/to/file2.ts` - [what changes]

### Data Model
```typescript
interface Example {
  id: string;
  // ...
}
```

### API/Interface Contract
```typescript
function doThing(input: Input): Output
```

### Error Handling
- [Error case 1]: [How handled]
- [Error case 2]: [How handled]

### Edge Cases
1. [Edge case] → [Behavior]
2. [Edge case] → [Behavior]
```

### ⚠️ Quality Gate
**Can another developer implement this without asking questions?**

---

## Phase 3: PLAN (Task Breakdown)

**Goal:** Create small, independently-deliverable tasks.

### Checklist
- [ ] Break into tasks of 30 minutes or less each
- [ ] Each task should be testable in isolation
- [ ] Order tasks by dependency (what must come first)
- [ ] Mark tasks that can be parallelized

### Template

```markdown
## Implementation Plan: [Feature Name]

### Tasks (in order)

#### Task 1: [Name]
- **Files:** `path/to/file.ts`
- **Action:** [Specific action]
- **Test:** [How to verify]
- **Estimate:** ~15 min

#### Task 2: [Name]
- **Files:** `path/to/file.ts`
- **Action:** [Specific action]
- **Test:** [How to verify]
- **Estimate:** ~20 min

### Parallel Tasks (can run simultaneously)
- Task 3 and Task 4 have no dependencies on each other
```

### ⚠️ Quality Gate
**Is each task small enough to review in one glance?**

---

## Phase 4: IMPLEMENT (Code Generation)

**Goal:** Generate code task-by-task with AI assistance.

### Checklist
- [ ] Provide spec + design + task context to AI
- [ ] Generate code for ONE task at a time
- [ ] Review generated code immediately
- [ ] Run tests before moving to next task
- [ ] Commit after each verified task

### Effective Prompt Structure

```markdown
## Context
[Paste relevant spec section]

## Current Task
[Paste specific task from plan]

## Existing Code Context
[Paste relevant existing code or file paths]

## Requirements
- Follow existing code style
- Include error handling for [cases]
- Add tests for [scenarios]

## Constraints
- Do not modify [protected areas]
- Use existing [patterns/utilities]
```

### ⚠️ Quality Gate
**Does the generated code match the spec exactly?** If not, refine or regenerate.

---

## Phase 5: VALIDATE (Verification)

**Goal:** Confirm implementation matches specification.

### Checklist
- [ ] All acceptance criteria pass
- [ ] Edge cases handled as designed
- [ ] No unintended side effects
- [ ] Tests cover the new functionality
- [ ] Code review complete

### Validation Matrix

| Acceptance Criteria | Implementation | Test | Status |
|---------------------|----------------|------|--------|
| AC1: [description]  | `file:line`    | `test_name` | ✅/❌ |
| AC2: [description]  | `file:line`    | `test_name` | ✅/❌ |

---

## Anti-Patterns to Avoid

| ❌ Don't | ✅ Do Instead |
|----------|---------------|
| Write specs longer than 1 page | Decompose into smaller features |
| Let AI generate entire features at once | One task at a time |
| Skip human review of specs | Review every spec before implementation |
| Accept verbose AI-generated specs | Edit for conciseness |
| Treat specs as documentation | Treat specs as source of truth |
| Ignore spec-implementation drift | Validate continuously |

---

## Sizing Guide

| Feature Size | Spec Length | Tasks | Time |
|--------------|-------------|-------|------|
| **Tiny** (bug fix) | 5-10 lines | 1-2 | <30 min |
| **Small** (single function) | 20-30 lines | 2-4 | 1-2 hours |
| **Medium** (component) | 50-100 lines | 5-10 | Half day |
| **Large** (feature) | Decompose first! | N/A | N/A |

**Rule:** If your spec exceeds 100 lines, you need to decompose.

---

## File Organization

```
your-repo/
├── .specs/                    # Spec documents (optional, can use issues instead)
│   ├── feature-name/
│   │   ├── spec.md           # Requirements
│   │   ├── design.md         # Technical design
│   │   └── plan.md           # Task breakdown
├── .github/
│   └── copilot-instructions.md  # AI context (memory bank)
└── src/
    └── ...
```

---

## Integration with Copilot CLI

### Using Plan Mode for SDD

```bash
# Enter plan mode
copilot
# Then press Shift+Tab to enter plan mode, or:
/plan "Implement [feature name] per spec in .specs/feature-name/"
```

### Workflow with Copilot CLI

1. **Write spec manually** (Phase 1-2) - Human writes SPECIFY + DESIGN
2. **Use /plan for task breakdown** (Phase 3) - AI assists with PLAN
3. **Implement task-by-task** (Phase 4) - AI generates, human reviews
4. **Validate** (Phase 5) - Human verifies against spec

---

## Quick Start Checklist

For EVERY feature/change:

```markdown
## Pre-Implementation
- [ ] Spec written and reviewed (< 5 min to read)
- [ ] Technical design documented
- [ ] Tasks broken down (each < 30 min)
- [ ] Dependencies identified

## Implementation (per task)
- [ ] Context provided to AI
- [ ] Code generated
- [ ] Code reviewed by human
- [ ] Tests pass
- [ ] Committed

## Post-Implementation
- [ ] All acceptance criteria verified
- [ ] Spec matches implementation
- [ ] PR/code review complete
```

---

## References

- [Martin Fowler: Understanding SDD](https://martinfowler.com/articles/exploring-gen-ai/sdd-3-tools.html)
- [GitHub Spec Kit](https://github.com/github/spec-kit)
- [Intent-Driven Dev Best Practices](https://intent-driven.dev/knowledge/best-practices/)
- [Augment Code SDD Guide](https://www.augmentcode.com/guides/mastering-spec-driven-development-with-prompted-ai-workflows-a-step-by-step-implementation-guide)
