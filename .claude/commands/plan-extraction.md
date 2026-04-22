---
description: Produce a migration plan for moving a feature out of the monolith into a microservice.
argument-hint: <feature name or area>
---

The user wants to plan extracting `$ARGUMENTS` out of `myboardgamecollection` (the monolith) into a microservice.

Delegate to the `extraction-planner` subagent. It will return a concrete plan covering target service, data migration, API surface, gateway routing, rollout sequence, and rollback. Relay the plan; do not implement anything in this invocation.

If `$ARGUMENTS` is empty, ask the user which feature or area they want to extract before delegating.
