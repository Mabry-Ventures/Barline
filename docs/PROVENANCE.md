# Source provenance

## Import record

The workspace was an empty Git repository on `main`. No target commits or
remote were present to preserve. The source history was imported with Git, not
from an archive:

```bash
git remote add ice-community https://github.com/lxy1992/Ice.git
git remote add ice-upstream https://github.com/jordanbaird/Ice.git
git fetch ice-community --tags --prune
git fetch ice-upstream --tags --prune
git cat-file -e 79654cd8c249e2a1465a262cfda7175346fe7772^{commit}
git cat-file -e 6d74d25c33a9ab04307c1f222fbe68ad71847234^{commit}
git merge-base --is-ancestor 6d74d25c33a9ab04307c1f222fbe68ad71847234 79654cd8c249e2a1465a262cfda7175346fe7772
git switch -C main 79654cd8c249e2a1465a262cfda7175346fe7772
git tag -a vendor/ice-0.11.13-macos26.4 79654cd8c249e2a1465a262cfda7175346fe7772 -m "Imported Ice macOS 26.4 compatibility baseline"
```

`vendor/ice-0.11.13-macos26.4` is the immutable reference for evaluating all
Barline changes. Original author, committer, and merge history remain intact.

## Binary provenance policy

Every distributed Barline binary must identify an exact Barline source tag and
publish the corresponding source, dependency lock, project files, build tools,
GPLv3 license, notices, and build instructions. Release evidence must record
the exact clean commit; results from a different SHA are not transferable.
