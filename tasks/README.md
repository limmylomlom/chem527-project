# Tasks

This folder is your project's task list. A task is one piece of work with a result you can check, such as "load the data and find what is missing" or "compare the two baselines on the 1650 cm⁻¹ peak". Writing each one down, and recording what happened, is how you and your mentor see the project's decisions later, and the final submission's Workflow criterion reads this folder.

## The format

- One Markdown file per task, named `NNN-short-slug.md`, such as `004-baseline-comparison.md`. Number tasks in order from 004. A number is never reused, even when a task is abandoned.
- Each file opens with a header: the number and title as the heading, then **Status** (`active`, `blocked`, or `done`), **Created**, **Updated**, and **Due**, with dates written as 2026-11-12.
- Then three sections. **Goal** says what done looks like, in a sentence or two. **Progress log** holds dated entries, newest last, each saying what you did and what you found, with the numbers. **Outcome** is filled in when the task closes and says what the result was.
- Add a dated progress entry every time you work on a task, and change **Updated** to that date.
- To close a task, fill in **Outcome**, set **Status** to `done`, move the file into `tasks/archive/`, and update its row in the index below. The `archive` folder does not exist until you close your first task, because git cannot store an empty folder. Make it then, from the project folder in the terminal:

```bash
mkdir tasks/archive
```

```bash
git mv tasks/001-gitignore.md tasks/archive/
```

The three tasks shipped with this template say `YYYY-MM-DD` in their headers. Put in the date you start each one.

## Index

Newest first. Change the link to `archive/NNN-slug.md` when a task moves.

| Number | Task | Status | Due |
|---|---|---|---|
| 003 | [Topic declaration](003-topic-declaration.md) | active | 2026-11-08 |
| 002 | [Copy the course environment](002-environment.md) | active | 2026-11-01 |
| 001 | [Write `.gitignore`](001-gitignore.md) | active | 2026-11-01 |
