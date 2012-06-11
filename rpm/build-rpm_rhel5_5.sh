#!/bin/bash

# Copyright (C) 2011 by Stefan Berggren
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.

# How to build a rpm on RHEL 5.5
# NOTE: Run this as a non-priviliged user (not root).

VERSION=1
RELEASE=5

echo "Do not run this just yet, you most likely need to adapt this to your needs."
exit 1

if [ $USER == "root" ]; then
	echo "Run this script as a normal user"
	exit 1
fi

function mess() {
	echo
	echo "###"
	echo "# $1"
	echo "###"
	echo
}

mess "Installing packages (if needed)"
sudo yum install rpm-build
sudo yum install redhat-rpm-config

mess "Creating rpmmacros"
if [ -f ~/.rpmmacros ]; then
	echo -n "This will overwrite ~/.rpmmacros, press ENTER to continue. "
	read
fi

if [ -e ~/rpmbuild ]; then
	echo -n "This will overwrite ~/rpmbuild, press ENTER to continue. "
	read
fi
mkdir -p ~/rpmbuild/{BUILD,RPMS,SOURCES,SPECS,SRPMS,tmp}
echo "%packager $(finger $USER | grep Name | awk -F ": " '{print $NF}'), <$USER@example.com>" > ~/.rpmmacros
echo "%_topdir $HOME/rpmbuild" >> ~/.rpmmacros
echo "%_tmppath $HOME/rpmbuild/tmp" >> ~/.rpmmacros
echo "%_signature     gpg" >> ~/.rpmmacros
echo "%_gpg_name      replace_with_name" >> ~/.rpmmacros

mess "Copy files"
cd /opt/lsf/utils/housekeeping/
mkdir -pv ~/rpmbuild/tmp/src/housed-$VERSION
for file in $(find * | egrep -v '/\.' | grep -v rpm); do
	if [ -f $file ]; then
		cp -pv $file ~/rpmbuild/tmp/src/housed-$VERSION/$file
	else
		mkdir -pv ~/rpmbuild/tmp/src/housed-$VERSION/$file
	fi
done

mess "Create archive"
cd ~/rpmbuild/tmp/src
tar cf ~/rpmbuild/SOURCES/housed.tar *

mess "Create spec file"

cat << BLOCK > ~/rpmbuild/SPECS/housed.spec
Summary: Housekeeping script
Name: housed
Version: $VERSION
Release: $RELEASE
Source0: housed.tar
License: MIT
Group: Applications/System
BuildArch: noarch
BuildRoot: %{_tmppath}/%{name}-buildroot
%description
Housed is a housekeeping script intended for clusters.
%prep
%setup -q
%build
%install
install -m 0755 -d \$RPM_BUILD_ROOT/etc/housed
install -m 0755 -d \$RPM_BUILD_ROOT/etc/init.d
install -m 0755 -d \$RPM_BUILD_ROOT/var/housed
install -m 0755 -d \$RPM_BUILD_ROOT/usr/bin
install -m 0744 etc/housed.conf \$RPM_BUILD_ROOT/etc/housed
install -m 0744 etc/init.d/housed \$RPM_BUILD_ROOT/etc/init.d/
install -m 0744 var/{lsf.conf,sge.conf} \$RPM_BUILD_ROOT/var/housed
install -m 0755 bin/{housed,mcastr,mcasts} \$RPM_BUILD_ROOT/usr/bin/
%clean
rm -rf \$RPM_BUILD_ROOT
%post
chkconfig --add housed
echo "housed added to startup by chkconfig"
service housed start
echo "Service started"
%files
%dir /etc/housed
%dir /var/housed
/etc/housed/housed.conf
/etc/init.d/housed
/var/housed/lsf.conf
/var/housed/sge.conf
/usr/bin/housed
/usr/bin/mcastr
/usr/bin/mcasts
BLOCK

mess "Build rpm"

cd ~/rpmbuild/
rpmbuild -ba SPECS/housed.spec
