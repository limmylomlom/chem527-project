# 001: Write `.gitignore`

- **Status:** active
- **Created:** YYYY-MM-DD
- **Updated:** YYYY-MM-DD
- **Due:** 2026-11-01, before task 002

## Goal

A file named `.gitignore` in the top folder of the repository, committed and pushed before anything else is added. It lists the files git should never track. Task 002 builds the Python environment, a folder named `.venv` of about 400 MB and thousands of files, and without this file a single `git add .` would put all of it in your repository's history, where it stays even after you delete it.

## Steps

1. In VS Code, click the **New File** icon above the file list and name the file `.gitignore`, with the leading dot and no extension. Windows File Explorer hides names that start with a dot, so make it in VS Code.
2. Paste in these lines. Each comment says why the line is there.

```text
# Python environment built by `uv sync`; anyone can rebuild it from uv.lock
.venv/

# Python's cache of compiled files
__pycache__/

# Jupyter's autosaved copies of each notebook
.ipynb_checkpoints/

# Operating system files
.DS_Store
Thumbs.db
desktop.ini

# Files your notebook writes, rebuilt each time it runs
output/

# Claude Code's record of the permissions you granted on this laptop
.claude/settings.local.json
```

3. Save the file, then commit and push it:

```bash
git add .gitignore
```

```bash
git commit -m "Add .gitignore"
```

```bash
git push
```

Do not add `data/`, `AGENTS.md`, `judgment-log.md`, `tasks/`, or `.claude/skills/` to this file. The final submission needs all five. Note that the course repository ignores `.claude/skills/`, because a skill you write in session 12 is yours alone, whereas in this repository your skill is part of what you submit.

## Data: commit them as downloaded

Your data go in the repository, in a `data/` folder, exactly as you downloaded them. Your mentor runs your notebook from the commit you submit with downloads blocked, so the notebook reads its data from the committed files, never from the source URL. All cleaning happens in code: a value you correct or a row you drop is a line in your notebook, and the file stays as it came. You add the files in task 003, so you can finish this task before you know your dataset.

GitHub refuses a push with any file over 100 MB and warns about a file over 50 MB. The warning is not an error, and the push goes through. Every dataset on the CHEM 427 project list fits under the limit, and projects 2, 4, 5, and 11 push with the warning. Commit and push with git, because GitHub's web page uploads files of at most 25 MB. If you expect your data to total more than 5 GB, talk to your mentor before you commit them.

If your data cannot be stored on GitHub, because they are too large or their license does not allow a copy to be shared, ask your mentor for an exemption, with your topic declaration or at any time up to Tuesday, December 1. Once your mentor approves it, commit `data/EXEMPT.md` with the reason, the date of the approval, and a copy of the notebook's download cell. Then list each downloaded file by name in `.gitignore`, such as `data/spectra.csv`, but not the whole `data/` folder, which holds `EXEMPT.md`. The [final project page](https://github.com/mfbush/signals-to-insights/blob/main/final-project.md#your-project-repository) has the rest of the rule.

## Done when

`.gitignore` is pushed, and after `uv sync` in task 002, `git status` does not list `.venv/`. Close this task then.

## Progress log

## Outcome
