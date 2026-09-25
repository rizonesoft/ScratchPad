# Nightly schedule history

The governed nightly task's trigger history (D00 T02 §40 item 3). The trend reads each night's due state from the row in force that night, so a trigger edit applies from its `From` date and never rewrites earlier nights. Add a row when `tools/tasks/nightly-ui.xml` changes its `StartBoundary` time or `DaysInterval`; never edit a past row. A night is due-through only once its trigger plus the task's 4 h execution limit plus 30 minutes has passed, so a running job reads `pending`, not `missing`. An interval of `0` records the schedule disabled from its `From` date: those nights read `disabled`, not `missing` (D00 T02 §47 item 9).

| From | Trigger | Interval days |
| --- | --- | --- |
| 2026-09-19 | 02:30 | 1 |
