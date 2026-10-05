# Triage Labels

The skills speak in terms of five canonical triage roles. This file maps those roles to the actual label strings used in this repo's issue tracker.

| Label in mattpocock/skills | Label in our tracker | Meaning                                  |
| -------------------------- | -------------------- | ---------------------------------------- |
| `needs-triage`             | `needs-triage`       | Maintainer needs to evaluate this issue  |
| `needs-info`               | `needs-info`         | Waiting on reporter for more information |
| `ready-for-agent`          | `ready-for-agent`    | Fully specified, ready for an AFK agent  |
| `ready-for-human`          | `ready-for-human`    | Requires human implementation            |
| `wontfix`                  | `wontfix`            | Will not be actioned                     |

When a skill mentions a role (e.g. "apply the AFK-ready triage label"), use the corresponding label string from this table.

## Workflow labels

| Role | Label in our tracker | Meaning |
| ---- | -------------------- | ------- |
| Specification | `spec` | Specification awaiting ticket breakdown; never an AFK execution signal |
| Claimed | `in-progress` | An agent or human has claimed the ticket and is working on it |

The workflow labels are separate from the five triage roles. In particular, never map `spec` to `ready-for-agent`. Claiming a ticket removes `ready-for-agent` and adds `in-progress`; `in-progress` is removed once the ticket closes.

Edit the right-hand column to match whatever vocabulary you actually use.
