#!/usr/bin/env bash

function check_result {
  if [ "0" -ne "$?" ]
  then
    echo $1
    exit 1
  fi
}

if [ -z "$HOME" ]
then
  echo HOME not in environment, guessing...
  export HOME=$(awk -F: -v v="$USER" '{if ($1==v) print $6}' /etc/passwd)
fi

if [ -z "$WORKSPACE" ]
then
  echo WORKSPACE not specified
  exit 1
fi

if [ -z "$CLEAN_TYPE" ]
then
  echo CLEAN_TYPE not specified
  exit 1
fi

if [ -z "$REPO_BRANCH" ]
then
  echo REPO_BRANCH not specified
  exit 1
fi

if [ -z "$LUNCH" ]
then
  echo LUNCH not specified
  exit 1
fi

if [ -z "$RELEASE_TYPE" ]
then
  echo RELEASE_TYPE not specified
  exit 1
fi

if [ -z "$SYNC_PROTO" ]
then
  SYNC_PROTO=http
fi

# colorization fix in Jenkins
export CL_PFX="\"\033[34m\""
export CL_INS="\"\033[32m\""
export CL_RST="\"\033[0m\""

cd $WORKSPACE2
rm -rf archive
mkdir -p archive
export BUILD_NO=$BUILD_NUMBER
unset BUILD_NUMBER

cd $WORKSPACE
export PATH=~/bin:$PATH

export USE_CCACHE=1
export BUILD_WITH_COLORS=0

REPO=$(which repo)
if [ -z "$REPO" ]
then
  mkdir -p ~/bin
  curl https://dl-ssl.google.com/dl/googlesource/git-repo/repo > ~/bin/repo
  chmod a+x ~/bin/repo
fi

mkdir -p $REPO_BRANCH
cd $REPO_BRANCH

# always force a fresh repo init since we can build off different branches
# and the "default" upstream branch can get stuck on whatever was init first.
if [ -z "$CORE_BRANCH" ]
then
  CORE_BRANCH=$REPO_BRANCH
fi
rm -rf .repo/manifests*
repo init -u $SYNC_PROTO://github.com/CyanogenMod/android.git -b $CORE_BRANCH

cp $WORKSPACE/hudson/$REPO_BRANCH.xml .repo/local_manifest.xml

echo Core Manifest:
cat .repo/manifests/default.xml

echo Local Manifest:
cat .repo/local_manifest.xml

echo Syncing...
repo sync -d #> /dev/null 2> /tmp/jenkins-sync-errors.txt
check_result "repo sync failed."
echo Sync complete.

if [ -f $WORKSPACE/hudson/$REPO_BRANCH-setup.sh ]
then
  $WORKSPACE/hudson/$REPO_BRANCH-setup.sh
fi

. build/envsetup.sh
lunch $LUNCH
check_result "lunch failed."

UNAME=$(uname)

if [ "$RELEASE_TYPE" = "CM_NIGHTLY" ]
then
  if [ "$REPO_BRANCH" = "gingerbread" ]
  then
    export CYANOGEN_NIGHTLY=true
  else
    export CM_NIGHTLY=true
  fi
elif [ "$RELEASE_TYPE" = "CM_SNAPSHOT" ]
then
  export CM_SNAPSHOT=true
elif [ "$RELEASE_TYPE" = "CM_RELEASE" ]
then
  export CM_RELEASE=true
fi

if [ ! -z "$CM_EXTRAVERSION" ]
then
  export CM_SNAPSHOT=true
fi

if [ ! -z "$GERRIT_CHANGES" ]
then
  export CM_SNAPSHOT=true
  IS_HTTP=$(echo $GERRIT_CHANGES | grep http)
  if [ -z "$IS_HTTP" ]
  then
    python $WORKSPACE/hudson/repopick.py $GERRIT_CHANGES
    check_result "gerrit picks failed."
  else
    python $WORKSPACE/hudson/repopick.py $(curl $GERRIT_CHANGES)
    check_result "gerrit picks failed."
  fi
fi

make $CLEAN_TYPE
mka bacon | tee $LUNCH.log
check_result "Build failed."

ZIP=$(tail -2 "$LUNCH".log | cut -f3 -d ' ' | cut -f1 -d ' ' | sed -e '/^$/ d')
rm -rf $WORKSPACE2/archive
mkdir $WORKSPACE2/archive
cp out/target/product/$DEVICE/$ZIP $WORKSPACE2/archive