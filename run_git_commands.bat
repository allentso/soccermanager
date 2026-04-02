@echo off
cd /d "C:\Users\pedre\OneDrive\Documentos\dev\openfootmanager.worktrees\copilot-worktree-2026-04-02T15-29-01"

echo === 1. git remote -v ===
git remote -v

echo.
echo === 2. git branch -a ===
git branch -a

echo.
echo === 3. git log --oneline -8 ===
git log --oneline -8

echo.
echo === 4. git fetch --all ===
git fetch --all

echo.
echo === 5. git log --oneline origin/develop -10 ===
git log --oneline origin/develop -10 2>nul || (
    echo Trying upstream/develop...
    git log --oneline upstream/develop -10 2>nul || echo Neither origin/develop nor upstream/develop found
)

echo.
echo === 6. git log --oneline develop -10 ===
git log --oneline develop -10 2>nul || echo Local develop branch not found
