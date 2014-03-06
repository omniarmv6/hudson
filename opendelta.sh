#!/bin/bash

# Script to generate delta files for OpenDelta - by Jorrit 'Chainfire' Jongma

# Get device either from $DEVICE set by calling script, or first parameter

if [ "$DEVICE" == "" ]; then
	if [ "$1" != "" ]; then
		DEVICE=$1
	fi
fi

if [ "$DEVICE" == "" ]; then
	echo "Abort: no device set" >&2
	exit 1
fi

# ------ CONFIGURATION ------

DL_ANDROIDARMV6_ORG=/var/lib/jenkins/dl_androidarmv6_org
DELTA_ANDROIDARMV6_ORG=/var/lib/jenkins/delta_androidarmv6_org

BIN_JAVA=java
BIN_MINSIGNAPK=$WORKSPACE/hudson/bin/minsignapk.jar
BIN_XDELTA=$WORKSPACE/hudson/bin/xdelta3
BIN_ZIPADJUST=$WORKSPACE/hudson/bin/zipadjust

FILE_MATCH=omni-*.zip
PATH_CURRENT=$WORKSPACE/archive
PATH_LAST=$DL_ANDROIDARMV6_ORG/last/$DEVICE

KEY_X509=/var/lib/jenkins/.keys/platform.x509.pem
KEY_PK8=/var/lib/jenkins/.keys/platform.pk8

# ------ PROCESS ------

getFileName() {
	echo ${1##*/}
}

getFileNameNoExt() {
	echo ${1%.*}
}

getFileMD5() {
	TEMP=$(md5sum -b $1)
	for T in $TEMP; do echo $T; break; done
}

getFileSize() {
	echo $(stat --print "%s" $1)
}

FILE_CURRENT=$(getFileName $(ls -1 $PATH_CURRENT/$FILE_MATCH))
FILE_LAST=$(getFileName $(ls -1 $PATH_LAST/$FILE_MATCH))
FILE_LAST_BASE=$(getFileNameNoExt $FILE_LAST)

if [ "$FILE_CURRENT" == "" ]; then
	echo "Abort: CURRENT zip not found" >&2
	exit 1
fi

if [ "$FILE_LAST" == "" ]; then
	echo "Abort: LAST zip not found" >&2
	mkdir -p $PATH_LAST
	cp $PATH_CURRENT/$FILE_CURRENT $PATH_LAST/$FILE_CURRENT
	exit 0
fi

if [ "$FILE_LAST" == "$FILE_CURRENT" ]; then
	echo "Abort: CURRENT and LAST zip have the same name" >&2
	exit 1
fi

rm -rf work.d
mkdir work.d
rm -rf delta_out.d
mkdir delta_out.d

$BIN_ZIPADJUST --decompress $PATH_CURRENT/$FILE_CURRENT work.d/current.zip
$BIN_ZIPADJUST --decompress $PATH_LAST/$FILE_LAST work.d/last.zip
$BIN_JAVA -Xmx1024m -jar $BIN_MINSIGNAPK $KEY_X509 $KEY_PK8 work.d/current.zip work.d/current_signed.zip
$BIN_JAVA -Xmx1024m -jar $BIN_MINSIGNAPK $KEY_X509 $KEY_PK8 work.d/last.zip work.d/last_signed.zip
$BIN_XDELTA -9evfS none -s work.d/last.zip work.d/current.zip delta_out.d/$FILE_LAST_BASE.update
$BIN_XDELTA -9evfS none -s work.d/current.zip work.d/current_signed.zip delta_out.d/$FILE_LAST_BASE.sign

MD5_CURRENT=$(getFileMD5 $PATH_CURRENT/$FILE_CURRENT)
MD5_CURRENT_STORE=$(getFileMD5 work.d/current.zip)
MD5_CURRENT_STORE_SIGNED=$(getFileMD5 work.d/current_signed.zip)
MD5_LAST=$(getFileMD5 $PATH_LAST/$FILE_LAST)
MD5_LAST_STORE=$(getFileMD5 work.d/last.zip)
MD5_LAST_STORE_SIGNED=$(getFileMD5 work.d/last_signed.zip)
MD5_UPDATE=$(getFileMD5 delta_out.d/$FILE_LAST_BASE.update)
MD5_SIGN=$(getFileMD5 delta_out.d/$FILE_LAST_BASE.sign)

SIZE_CURRENT=$(getFileSize $PATH_CURRENT/$FILE_CURRENT)
SIZE_CURRENT_STORE=$(getFileSize work.d/current.zip)
SIZE_CURRENT_STORE_SIGNED=$(getFileSize work.d/current_signed.zip)
SIZE_LAST=$(getFileSize $PATH_LAST/$FILE_LAST)
SIZE_LAST_STORE=$(getFileSize work.d/last.zip)
SIZE_LAST_STORE_SIGNED=$(getFileSize work.d/last_signed.zip)
SIZE_UPDATE=$(getFileSize delta_out.d/$FILE_LAST_BASE.update)
SIZE_SIGN=$(getFileSize delta_out.d/$FILE_LAST_BASE.sign)

DELTA=delta_out.d/$FILE_LAST_BASE.delta

echo "{" > $DELTA
echo "  \"version\": 1," >> $DELTA
echo "  \"in\": {" >> $DELTA
echo "      \"name\": \"$FILE_LAST\"," >> $DELTA
echo "      \"size_store\": $SIZE_LAST_STORE," >> $DELTA
echo "      \"size_store_signed\": $SIZE_LAST_STORE_SIGNED," >> $DELTA
echo "      \"size_official\": $SIZE_LAST," >> $DELTA
echo "      \"md5_store\": \"$MD5_LAST_STORE\"," >> $DELTA
echo "      \"md5_store_signed\": \"$MD5_LAST_STORE_SIGNED\"," >> $DELTA
echo "      \"md5_official\": \"$MD5_LAST\"" >> $DELTA
echo "  }," >> $DELTA
echo "  \"update\": {" >> $DELTA
echo "      \"name\": \"$FILE_LAST_BASE.update\"," >> $DELTA
echo "      \"size\": $SIZE_UPDATE," >> $DELTA
echo "      \"size_applied\": $SIZE_CURRENT_STORE," >> $DELTA
echo "      \"md5\": \"$MD5_UPDATE\"," >> $DELTA
echo "      \"md5_applied\": \"$MD5_CURRENT_STORE\"" >> $DELTA
echo "  }," >> $DELTA
echo "  \"signature\": {" >> $DELTA
echo "      \"name\": \"$FILE_LAST_BASE.sign\"," >> $DELTA
echo "      \"size\": $SIZE_SIGN," >> $DELTA
echo "      \"size_applied\": $SIZE_CURRENT_STORE_SIGNED," >> $DELTA
echo "      \"md5\": \"$MD5_SIGN\"," >> $DELTA
echo "      \"md5_applied\": \"$MD5_CURRENT_STORE_SIGNED\"" >> $DELTA
echo "  }," >> $DELTA
echo "  \"out\": {" >> $DELTA
echo "      \"name\": \"$FILE_CURRENT\"," >> $DELTA
echo "      \"size_store\": $SIZE_CURRENT_STORE," >> $DELTA
echo "      \"size_store_signed\": $SIZE_CURRENT_STORE_SIGNED," >> $DELTA
echo "      \"size_official\": $SIZE_CURRENT," >> $DELTA
echo "      \"md5_store\": \"$MD5_CURRENT_STORE\"," >> $DELTA
echo "      \"md5_store_signed\": \"$MD5_CURRENT_STORE_SIGNED\"," >> $DELTA
echo "      \"md5_official\": \"$MD5_CURRENT\"" >> $DELTA
echo "  }" >> $DELTA
echo "}" >> $DELTA


mkdir -p $DELTA_ANDROIDARMV6_ORG/nightlies/$DEVICE >/dev/null 2>/dev/null
cp delta_out.d/* $DELTA_ANDROIDARMV6_ORG/nightlies/$DEVICE/.

rm -rf work.d
rm -rf delta_out.d

rm -rf $PATH_LAST/*
mkdir -p $PATH_LAST
cp $PATH_CURRENT/$FILE_CURRENT $PATH_LAST/$FILE_CURRENT

exit 0

