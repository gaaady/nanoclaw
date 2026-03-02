# Google Calendar

You have access to `gcalcli` for reading and creating Google Calendar events.
Your credentials are mounted at `/workspace/extra/gcal/` and scoped to a single calendar.

Always pass `--config-folder /workspace/extra/gcal` to every gcalcli command.
The calendar for this group is scoped to `"Family"` — always pass `--calendar "Family"` as well.

## Reading Events

```bash
# Today's agenda
gcalcli --config-folder /workspace/extra/gcal --calendar "Family" agenda today tomorrow

# This week
gcalcli --config-folder /workspace/extra/gcal --calendar "Family" agenda

# Specific date range
gcalcli --config-folder /workspace/extra/gcal --calendar "Family" agenda "2026-03-01" "2026-03-07"

# Calendar view (week)
gcalcli --config-folder /workspace/extra/gcal --calendar "Family" calw
```

## Creating Events

```bash
# Quick add (natural language)
gcalcli --config-folder /workspace/extra/gcal --calendar "Family" quick "Team standup tomorrow 9am"

# Add with full details
gcalcli --config-folder /workspace/extra/gcal --calendar "Family" add \
  --title "Meeting with Alice" \
  --when "2026-03-05 14:00" \
  --duration 60 \
  --description "Quarterly review" \
  --where "Zoom"
```

## Searching & Deleting

```bash
# Search events
gcalcli --config-folder /workspace/extra/gcal --calendar "Family" search "standup"

# Delete (interactive — avoid in automated flows)
gcalcli --config-folder /workspace/extra/gcal --calendar "Family" delete "standup"
```

## Output Formatting

For user messages, format events cleanly:
- Date and time in local timezone (already handled by gcalcli)
- Keep it brief: title, time, location if set
- Group by day when showing multiple events
- Use *bold* for event titles in WhatsApp/Telegram

## Error Handling

If gcalcli returns an auth error, tell the user:
> Calendar credentials need to be refreshed. Ask the admin to re-run `./my/setup-gcal.sh` for this group.
