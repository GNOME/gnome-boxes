#!/bin/sh

set -e # exit on errors

srcdir=`dirname $0`
test -z "$srcdir" && srcdir=.

olddir=`pwd`

cd "$srcdir"
git submodule update --init --recursive
autoreconf -v --force --install

cd "$olddir"
if [ -z "$NOCONFIGURE" ]; then
    "$srcdir"/configure --enable-maintainer-mode --enable-vala --enable-debug ${1+"$@"}
fi
