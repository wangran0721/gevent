#!/usr/bin/env bash
# GEVENT: Taken from https://raw.githubusercontent.com/DRMacIver/hypothesis/master/scripts/install.sh

# Special license: Take literally anything you want out of this file. I don't
# care. Consider it WTFPL licensed if you like.
# Basically there's a lot of suffering encoded here that I don't want you to
# have to go through and you should feel free to use this to avoid some of
# that suffering in advance.

set -e


# Where installations go
BASE=${BUILD_RUNTIMES-$PWD/.runtimes}
PYENV=$BASE/pyenv
echo $BASE
mkdir -p $BASE


if [ ! -d "$PYENV/.git" ]; then
  rm -rf $PYENV
  git clone https://github.com/pyenv/pyenv.git $BASE/pyenv
else
  back=$PWD
  cd $PYENV
  git fetch || echo "Fetch failed to complete. Ignoring"
  git reset --hard origin/master
  cd $back
fi


SNAKEPIT=$BASE/snakepit

##
# install(exact-version, alias)
#
# Produce a python executable at $SNAKEPIT/alias
# having the exact version given as exact-version
##
install () {

  VERSION="$1"
  ALIAS="$2"
  mkdir -p $BASE/versions
  DESTINATION=$BASE/versions/$VERSION

  if [ ! -e "$DESTINATION" ]; then
    mkdir -p $SNAKEPIT
    mkdir -p $BASE/versions
    $BASE/pyenv/plugins/python-build/bin/python-build $VERSION $DESTINATION --keep
  fi
 rm -f $SNAKEPIT/$ALIAS
 mkdir -p $SNAKEPIT
 # Overwrite an existing alias
 ln -sf $DESTINATION/bin/python $SNAKEPIT/$ALIAS
 $SNAKEPIT/$ALIAS --version
 $SNAKEPIT/$ALIAS -m pip install --upgrade --no-warn-script-location pip wheel virtualenv
 ls -l $SNAKEPIT
}


for var in "$@"; do
  case "${var}" in
    2.7)
      install 2.7.16 python2.7
      ;;
    3.5)
      install 3.5.6 python3.5
      ;;
    3.6)
      install 3.6.8 python3.6
      ;;
    3.7)
      install 3.7.2 python3.7
      ;;
    pypy2.7)
      install pypy2.7-7.1.0 pypy2.7
      ;;
    pypy3.6)
      install pypy3.6-7.1.0 pypy3.6
      ;;
  esac
done
