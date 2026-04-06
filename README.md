# TargetCount

World of Warcraft addon that **counts how often you select each unit** as your target and keeps a **persistent log** of that history. Use it to see whether you are actually tabbing to the right adds, bosses, or priority targets often enough—or whether your targeting drifts elsewhere.

## Dislaimer

This addon might cause perfomance issues, as it has not been tested properly yet. Use at your own discretion.

## What it does

- Records every **new** target selection (with light **deduplication** so clearing and re-targeting the same thing in a hurry does not inflate numbers).
- Stores **totals**, **hostile / friendly / neutral** breakdowns, **zones**, a **per-hour timeline**, and **target-of-target** stats when you have something targeted.
- In **party/raid**, also tracks what **teammates** are targeting (throttled), so you can compare who is on which mob.
- **Profiles** keep separate datasets (e.g. one profile per character or raid tier).

## UI

Open the window from the **minimap button**. Tabs: **Targets**, **Party**, **Timeline**. Search, zone filter, **session vs all-time**, sort columns, and **Export** top entries as plain text for notes or spreadsheets.

## Commands

| Command                 | Action                             |
| ----------------------- | ---------------------------------- |
| `/tc` or `/targetcount` | Toggle the window                  |
| `/tc reset`             | Clear stats for the active profile |
| `/tc export`            | Open export with text selected     |
| `/tc profile <name>`    | Switch profile                     |
| `/tc minimap`           | Show or hide the minimap button    |

Data is saved in `TargetCountDB` (per-profile, survives relogs).
