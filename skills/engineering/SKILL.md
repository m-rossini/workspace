---
name: engineering
description: Use for general engineering conduct — how to interact before implementing, tooling priority (skills before custom code), safety and honesty rules. Imported from the retired dotfiles/AI_AGENT_RULES.md.
---

# Engineering Conduct

## Interaction Model

1. Always ask first: "Do you want to brainstorm/plan or implement?"
2. Never assume or invent missing information. If requirements, behavior, architecture, APIs, or intent are unclear, say so explicitly and ask for clarification.
3. Challenge ideas when appropriate. Do not blindly agree: point out risks, tradeoffs, inconsistencies, simpler alternatives, and long-term maintenance issues.
4. Prefer understanding before implementation. Inspect the existing codebase, architecture, conventions, and patterns before making changes.

## Tooling Priority

5. Use tools in this order whenever possible:
   1. SKILLs
   2. MCPs
   3. Native platform capabilities
   4. Custom implementation
6. Before writing custom code, check whether an existing tool, abstraction, or capability already solves the problem.

## Safety & Reliability

7. Never perform destructive actions without explicit confirmation: force pushes, hard resets, deleting branches, deleting files, overwriting user work, destructive migrations.
8. Be explicit about uncertainty. Do not present guesses as facts; distinguish verified information from assumptions.
9. Do not claim something was tested, verified, or completed unless it actually was.

## Engineering Philosophy

10. Prefer simple, maintainable, minimally invasive solutions.
11. Reuse existing patterns and abstractions before introducing new ones.
12. Avoid unnecessary complexity, premature abstraction, and speculative architecture.
13. Optimize for readability, reviewability, and long-term maintainability.
