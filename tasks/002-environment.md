# 002: Copy the course environment

- **Status:** active
- **Created:** YYYY-MM-DD
- **Updated:** YYYY-MM-DD
- **Due:** 2026-11-01, after task 001

## Goal

This repository builds the same Python environment as the course repository, from its own copy of `pyproject.toml`, `uv.lock`, and `.python-version`, and a notebook here runs on it. The copy matters because Reproducibility is a criterion of the final submission. A reader who clones your repository needs the lock file to rebuild the packages your notebook ran with, and a path to the course folder on your laptop gives them nothing.

## Steps

1. In the VS Code terminal, in your project folder, copy three files from the course clone beside it. `pyproject.toml` lists the packages, `uv.lock` fixes their versions, and `.python-version` says Python 3.14. Without the third file, uv builds the environment with any Python from 3.13 on that it finds on your laptop.

```bash
cp ../signals-to-insights/pyproject.toml .
```

```bash
cp ../signals-to-insights/uv.lock .
```

```bash
cp ../signals-to-insights/.python-version .
```

2. Build the environment. It takes a minute or less, because uv reuses the packages it downloaded for the course.

```bash
uv sync
```

3. Check what git sees:

```bash
git status
```

The list of untracked files should show `.python-version`, `pyproject.toml`, and `uv.lock`, and no `.venv/`. If `.venv/` is listed, `.gitignore` is missing or misspelled; fix task 001 before you go on. If it is not listed, close task 001.

4. Make a new notebook named `check.ipynb`. Click **Select Kernel** at the top right, choose **Python Environments**, and pick the entry that shows `.venv` and Python 3.14. Paste this cell and run it:

```python
import sys

import numpy as np
import pandas as pd
import matplotlib
import scipy

print(f"Python     {sys.version.split()[0]}")
print(f"NumPy      {np.__version__}")
print(f"pandas     {pd.__version__}")
print(f"SciPy      {scipy.__version__}")
print(f"Matplotlib {matplotlib.__version__}")
```

5. Compare its output with the last cell of any session notebook you have run in the course clone. Then delete `check.ipynb`, and commit and push the three files:

```bash
git add pyproject.toml uv.lock .python-version
```

```bash
git commit -m "Copy the course environment"
```

```bash
git push
```

If the course announces a change to its package list, copy the three files again, run `uv sync`, and commit them. If you use conda for the course, choose the kernel named `signals` in step 4, and still commit the three files so that a reader with uv can rebuild the environment.

## Done when

The cell in step 4 prints Python 3.14 and the same package versions as a session notebook, and the three files are pushed.

## Progress log

## Outcome
