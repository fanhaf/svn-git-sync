#!/bin/bash
set -e
echo Syncing at `date`

LOCK_FILE=/tmp/gitupdate.lockfile

FETCHER_DIR=/home/michalg/src/bash/svn-git-sync/fetchers/svn2git/.git
GIT_DIR=$FETCHER_DIR
GIT_WORK_TREE=${FETCHER_DIR%/.git}

export SVN_USERNAME=sally
export GIT_ASKPASS="/home/git/.config/git_askpass"

cd $GIT_WORK_TREE
echo "GIT: $GIT_DIR; in $GIT_WORK_TREE (`pwd`)"
(
    flock -n 9 || exit 1

    git svn --username=$SVN_USERNAME fetch

    function rebase_svn_branch() {
        echo "Rebasing $@"
        git checkout $@
        git svn --username=$SVN_USERNAME rebase
    }
    
    for branch in $(git for-each-ref --format='%(refname:short)' refs/heads/); do
    	git reset --hard
    	git clean -dfx

        rebase_svn_branch $branch
    done
    
    exit 0 
    
) 9>$LOCK_FILE

git push --all --force gitlab 

echo
