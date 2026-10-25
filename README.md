# CHEM 427/527 final project template

This repository is the starting point for your final project in CHEM 427/527, Data Science for Chemical Measurements. You make your own copy of it, and that copy holds your project from the topic declaration on Sunday, November 8, to the final submission on Wednesday, December 9. It is also what you submit: each project milestone on Canvas is the URL of the commit you want read, the GitHub page of one saved state of your repository. What is scored, and how, is on the course's [final project page](https://github.com/mfbush/signals-to-insights/blob/main/final-project.md). This page says how to make your copy and start it.

## What is here

- `AGENTS.md` holds instructions that Claude Code reads at the start of every conversation in this folder. It carries the course rules from the course repository's `CLAUDE.md`, which does not load here, and it ends with a section for your project's own lines.
- `tasks/` is your project's task list, one file per piece of work. Three tasks are open on day one, and `tasks/README.md` explains the format.
- `judgment-log.md` is your judgment log, with the headings from the final project page.

Five files are missing on purpose: `.gitignore`, the three environment files `pyproject.toml`, `uv.lock`, and `.python-version`, and a notebook. Tasks 001 to 003 have you add them, in that order.

## Make your copy

This takes about 10 minutes.

1. Sign in to [GitHub](https://github.com), or create a free account there. Use an email address you will keep through the end of the quarter.
2. At the top of this repository's page, click **Use this template**, then **Create a new repository**. Do not fork the repository instead, because a fork of a public repository cannot be made private.
3. Leave **Owner** as your account. Under **Repository name**, type `chem427-project` or `chem527-project`. CHEM 427 projects are assigned on Tuesday, November 3, so name the repository for the course, not for the project.
4. Choose **Public** or **Private**. Either is fine for the course. Click **Create repository**.
5. If you chose **Private**, share the repository with the instructional team. Open your new repository's **Settings**, choose **Collaborators**, click **Add people**, and add each of these three GitHub usernames: `mfbush` (Matt), `lnarisawa` (Lucas), and `ChrisJWeir` (Chris). Your mentor cannot read a private repository until they accept the invitation.

**You know it worked when** your browser shows a repository under your own account with this README on its front page.

## Clone it beside the course repository

Put your project in your home folder, beside the `signals-to-insights` folder from setup, never inside it. Claude Code reads `AGENTS.md` only when there is no `CLAUDE.md` in the folder or in any folder above it, so a project inside the course folder gets the course's `CLAUDE.md` and none of your project's instructions. For the reason given in step 6 of the course `setup.md`, keep it out of folders synced by OneDrive or iCloud.

Run the commands below in the terminal inside VS Code, so that VS Code can sign you in to GitHub when git needs it. Open VS Code, and from the **Terminal** menu choose **New Terminal**.

The first time you use git to make commits, tell it the name and email address to record with each one. To keep your email address out of a public repository, use the address ending in `users.noreply.github.com` that GitHub shows under **Settings**, **Emails**.

```bash
git config --global user.name "Your Name"
```

```bash
git config --global user.email "your-address@users.noreply.github.com"
```

Then clone your repository, replacing `your-username` and the repository name with yours:

```bash
cd ~
```

```bash
git clone https://github.com/your-username/chem527-project.git
```

```bash
code chem527-project
```

If VS Code asks to sign in to GitHub, allow it and sign in with your GitHub account in the browser. A private repository asks at the clone, and a public one asks at your first `git push`. If VS Code asks whether you trust the authors of the files in the folder, choose **Yes, I trust the authors**.

**You know it worked when** a new VS Code window opens with `AGENTS.md`, `README.md`, `judgment-log.md`, and `tasks` in the file list on the left.

## What to do next

Open `tasks/001-gitignore.md`. Tasks 001 to 003 take about 30 minutes in all. Tasks 001 and 002 are due Sunday, November 1, and task 003 ends with the topic declaration on Canvas, due Sunday, November 8.
