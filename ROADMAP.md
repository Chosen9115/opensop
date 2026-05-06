# OpenSOP roadmap

OpenSOP is a v0.1 developer preview. The core runtime is useful today, but the spec is intentionally ahead of some side effects. This roadmap keeps the public repo honest about what we plan to harden next.

## Now

- YAML process parser
- Instance executor
- REST API under `/sop/`
- Admin UI
- RSpec coverage
- Real step execution for `form`, `automated`, and `notification`
- Modeled state transitions for `judgment`, `approval`, `webhook`, `subprocess`, and `wait`

## Next

- Real outbound webhook delivery
- LLM-backed `judgment` steps with confidence thresholds and escalation
- Human approval UI for `approval` steps
- Process metrics and run dashboards
- Example SOP library for common ops and engineering workflows
- More agent-harness examples: PR review, dependency bumping, CI re-runs, release notes

## Later

- Process Designer UI
- Version diff/replay UI
- Runtime adapters for other execution backends
- Hosted playground for trying OpenSOP without local setup
- Compatibility tooling for importing runbooks from Markdown, Notion, or Confluence

## Good first issues

- Add another example `.sop.yaml` under `processes/examples/`
- Improve error messages for invalid field references
- Add screenshots or GIFs to the README quickstart
- Document how to run OpenSOP behind a reverse proxy
- Add an example agent workflow that writes receipts without side effects
