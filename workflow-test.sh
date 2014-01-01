#!/bin/bash
set -x
set -e


GITREPO=gitrepo
ROOT=svnrepo
FROOT=fetchers

rm -rf $ROOT
rm -rf $FROOT
rm -rf $GITREPO
killall svnserve || echo "No SVN server running"

mkdir $GITREPO && cd $GITREPO && git init --bare && cd ..

ln pre-receive $GITREPO/hooks/pre-receive -s
ln post-receive $GITREPO/hooks/post-receive -s

mkdir -p $ROOT ; cd $ROOT

svnadmin create svn

cd svn
cat >| conf/svnserve.conf <<SVN
[general]
anon-access=none
auth-access=write
realm=My first repo
password-db=passwd
SVN

cat >| conf/passwd <<SVN
[users]
harry=harryssecret
sally=sallyssecret
guminiak=secret
SVN

cat >| conf/authz <<SVN
[repository:/experiments]
harry=rw
sally=rw
guminiak=rw
SVN

cd ..

svn mkdir --parents file://$ROOT/svn/experiments/{trunk,branches,tags} -m 'Initial structure'
svnserve -d -r $ROOT/svn

echo "Created server"

svn co --username harry --password harryssecret svn://localhost/experiments/ svnwork 

cd svnwork/trunk
echo "Mashed Potatoes" >> recipe
svn add recipe
svn commit --username harry --password harryssecret -m 'Added recipe.'

cd $FROOT 
git svn clone --username=guminiak -s svn://localhost/experiments/ svn2git
cd svn2git

git remote add gitlab git@localhost:gitrepo

git push gitlab master

cd $ROOT
git clone git@localhost:gitrepo work
cd work
git push origin :testbranch :testbranch2

echo '**********************************'
echo 'Simple push single commit scenario'
echo '**********************************'
cd $ROOT/work
cat >> recipe <<ing
4 Potatoes, diced
salt, 4 cups
water, 1 tablespoon
ing
git add recipe
git commit -m 'Added ingredients list.'
git push 2>&1 | tee $ROOT/tmp
fgrep "Committing to svn://localhost/experiments/trunk" $ROOT/tmp || exit 1
fgrep "Some branches could not be pushed to SVN" $ROOT/tmp && exit 1

echo Single push success;

echo '**********************************'
echo 'Simple push next commit scenario'
echo '**********************************'
cd $ROOT/work
git pull --rebase
cat >> recipe <<ing
Servings: 3
ing
git commit -am 'Added Serving size.'
git push 2>&1 | tee $ROOT/tmp
fgrep "Committing to svn://localhost/experiments/trunk" $ROOT/tmp || exit 1
fgrep "Some branches could not be pushed to SVN" $ROOT/tmp && exit 1


echo '**********************************'
echo 'Changing from svn scenario'
echo '**********************************'
cd $ROOT/svnwork/trunk
svn update
cat >| shopping <<LIST
Potatoes
LIST
svn add shopping
svn commit -m 'Started a shopping list.'

$FROOT/../bin/sync-svnrepo.sh

cd $ROOT/work
cat >> recipe <<INST
Begin by adding salt to the water and bringing it to a boil.
INST

git commit -am "Added step 1"
git push
PUSH_RES=$?
if [ $PUSH_RES = 0 ]; then
    exit 1
fi

git push 2>&1 | tee $ROOT/tmp
fgrep "master -> master (non-fast-forward)" $ROOT/tmp || exit 1

git pull --rebase
git push 2>&1 | tee $ROOT/tmp
fgrep "Committing to svn://localhost/experiments/trunk" $ROOT/tmp || exit 1
fgrep "Some branches could not be pushed to SVN" $ROOT/tmp && exit 1

echo '****************************************'
echo 'Updating from git with SVN changes newer'
echo '****************************************'
cd $ROOT/svnwork/trunk
svn update
sed -i 's/salt, 4 cups/Salt, 4 tablespoons/' recipe
svn commit -m 'Reduced the salt level.'

cd $ROOT/work
git pull --rebase
sed -i 's/salt, 4 cups/Salt, 1 tablespoon/' recipe
sed -i 's/water, 1 tablespoon/Water, 1 cup/' recipe
git commit -am 'Fixed salt/water qty mismatch'

git push 2>&1 | tee push.log
grep -q "Some branches could not be pushed to SVN." push.log
PUSH_RESULT=$?
if [ "$PUSH_RESULT" = "0" ]; then
    exit 1
fi

#git push 2>&1 | tee $ROOT/tmp
#fgrep "Some branches could not be pushed to SVN." $ROOT/tmp || exit 1


echo '****************************************'
echo 'Pushing different branch than controlled'
echo '****************************************'
git push origin master:testbranch 2>&1 | tee $ROOT/tmp
fgrep "master -> testbranch" $ROOT/tmp || exit 1


echo '****************************************'
echo 'Pushing multiple branches'
echo '****************************************'

cd $ROOT/work
git pull --rebase
sed -i 's/tablespoon/small spoon/' recipe
git commit -am 'Changed tablespoon to small spoon'

git push origin master:master master:testbranch2 2>&1 | tee $ROOT/tmp
fgrep "Committing to svn://localhost/experiments/trunk" $ROOT/tmp || exit 1
fgrep "Some branches could not be pushed to SVN" $ROOT/tmp && exit 1
fgrep "master -> testbranch" $ROOT/tmp || exit 1

echo '****************************************'
echo 'Pushing while update in progress'
echo '****************************************'

cd $ROOT/work
git pull --rebase
sed -i 's/small spoons/tablespoons/' recipe
git commit -am 'Fixing one instance of small spoons'

(
    flock 9
    git push origin master:master 2>&1 | tee $ROOT/tmp
    fgrep "SVN update is in progress, please push again in a moment!" $ROOT/tmp || exit 1
) 9</tmp/gitupdate.lockfile 

if [ $? -ne 0 ]; then
    exit 1
fi

git push origin master:master 2>&1 | tee $ROOT/tmp
fgrep "Committing to svn://localhost/experiments/trunk" $ROOT/tmp || exit 1
fgrep "Some branches could not be pushed to SVN" $ROOT/tmp && exit 1

echo 'SUCCESS!'
