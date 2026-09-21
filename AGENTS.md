# AGENTS.md

Commit and push regularly. When a piece of work is complete and verified, commit it with a plain message saying what changed, and push to `origin`. Don't let working changes pile up uncommitted across sessions.

Keep `README.md` updated as work progresses: after each phase lands, update its row in the status table and the `## Status` note.


## ntfy Notifications

Use ntfy to notify me. The topic is `pi_alerts_wisp_notus`.

Send a notification when:
- You need me to answer a question or make a decision.
- You encounter an error, blocker, or unexpected issue that requires my input.
- A task finishes or reaches a meaningful milestone.
- A small task is done - the user loves updates!

Send notifications with:

```bash
curl -d "<message>" https://ntfy.sh/pi_alerts_wisp_notus
```

Keep notifications short but specific. Include enough context to identify the task and what you need from me.
Continue working autonomously whenever possible instead of waiting for a response.
