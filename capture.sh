#!/bin/bash
# capture a photo from the webcam
WEB_ABSOLUTE_DIR=/var/www
CAM_RELATIVE_DIR=webcam
CAM_NAME=Webcam
HOMEPAGE_RELATIVE_PATH=/${CAM_RELATIVE_DIR}/current.jpg
HOMEPAGE_ABSOLUTE_PATH=${WEB_ABSOLUTE_DIR}${HOMEPAGE_RELATIVE_PATH}
TEMP_DIR=`mktemp -d`
CAPTURE_PATH=
GPHOTO2_PATH=
INCOMING_PATH=
HOMEPAGE_DIMENSION=640x480
THUMB_DIMENSION=320x240
WIDTH=1600
HEIGHT=1200
JPEGPIXI_PATH=
JPEGPIXI_ARGUMENT=
FLIP=
BACKUP_MESSAGE=
VERBOSE=0
UVCCAPTURE=
REMOTE_PATH=

######################################################################
# command line inputs
######################################################################

usage()
{
cat <<EOF
usage: $0 options

This script captures an image, either from certain models of Canon camera using 
either Capture or gphoto2, or from an incoming dump directory, and then rebuilds 
a web directory index.  You must specify exactly one of -a, -c, -g, or -i.

OPTIONS:
   -a      uvccapture path.  Defaults to null.
   -b      If capture fails and backup message is not null, message will
           be shown instead of last available picture.
           Defaults to ${BACKUP_MESSAGE}
   -c      Path to Capture (http://sourceforge.net/projects/capture/).  
           Defaults to null.
   -d      Absolute path to the webserver root directory.  
           Defaults to ${WEB_ABSOLUTE_DIR}
   -f      Rotate the picture this many degrees clockwise.
   -g      Path to gphoto2. Defaults to null.
   -h      This help
   -i      Path to directory of incoming photos of filename format HH:MM:SSxx.jpg. 
           Will erase contents of this directory.  Defaults to null.   
   -j      Path to jpegpixi image processer.  Defaults to null.   
   -n      Camera name.  Defaults to ${CAM_NAME}
   -p      Argument for jpexpixi processor.  Defaults to null.   
   -r      Relative path for webcam directory.  Defaults to ${CAM_RELATIVE_DIR}
   -s      Address to send picture to remote server by SCP.  Defaults to null.  If present, script will not update homepage or make thumbnail
   -t      Thumbnail dimension.  Defaults to ${THUMB_DIMENSION}.  
           If not null, creates thumbnail and index within daily directory
   -u      Current thumbnail dimension.  Defaults to ${HOMEPAGE_DIMENSION}.  
           If not null, creates a thumbnail at ${HOMEPAGE_ABSOLUTE_PATH},
           which should appear on the home page.
   -v      Debug mode
   -w      Number of seconds to wait after taking a picture.  Defaults to null.  
           If set, will try to take photos, spaced by this interval, for one minute.
           Otherwise, will take one photo and exit.
   -x      Image width for UVC Capture.  Defaults to ${WIDTH}
   -y      Image height for UVC Capture.  Defaults to ${HEIGHT}
EOF
}

while getopts a:b:c:d:f:g:hi:j:n:p:r:s:t:u:vw:x:y: o
do	
    case "$o" in
	a)      UVCCAPTURE_PATH="$OPTARG";;
	b)      BACKUP_MESSAGE="$OPTARG";;
	c)      CAPTURE_PATH="$OPTARG";;
	d)      WEB_ABSOLUTE_DIR="$OPTARG";;
	f)      FLIP="$OPTARG";;
	g)      GPHOTO2_PATH="$OPTARG";;
	h)	usage
		exit 1;;
	i)      INCOMING_PATH="$OPTARG";;
	j)      JPEGPIXI_PATH="$OPTARG";;
	n)      CAM_NAME="$OPTARG";;
	p)      JPEGPIXI_ARGUMENT="$OPTARG";;
	r)      CAM_RELATIVE_DIR="$OPTARG";;
	s)      REMOTE_PATH="$OPTARG";;
	t)      THUMB_DIMENSION="$OPTARG";;
        u)      HOMEPAGE_DIMENSION="$OPTARG";;
        v)      VERBOSE=1;;
	w)      WAIT="$OPTARG";;
        x)      WIDTH="$OPTARG";;
        y)      HEIGHT="$OPTARG";;
    esac
done

if [ "${VERBOSE}" == "1" ] 
    then
    set -x
fi

mode_count=0
if [ -n "${UVCCAPTURE_PATH}" ]
then
    mode_count=`expr $mode_count + 1`
fi

if [ -n "${CAPTURE_PATH}" ]
then
    mode_count=`expr $mode_count + 1`
fi

if [ -n "${GPHOTO2_PATH}" ]
then
    mode_count=`expr $mode_count + 1`
fi

if [ -n "${INCOMING_PATH}" ]
then
    mode_count=`expr $mode_count + 1`
fi

if [ "${mode_count}" -ne "1" ]
    then
    echo "Must specify exactly one of -a, -c, -g, or -i."
    exit 1
fi

PRETTY_DAY=`date "+%A, %d %B %Y"`
PRETTY_TIME=`date "+%l:%M %p %Z"`
YEAR_STRING=`date +%Y`
MONTH_STRING=`date +%m`
DAY_STRING=`date +%d`
HOUR_STRING=`date +%H`
MINUTE_STRING=`date +%M`
PIC_RELATIVE_DIR=/${CAM_RELATIVE_DIR}/${YEAR_STRING}/${MONTH_STRING}/${DAY_STRING}
PIC_ABSOLUTE_DIR=${WEB_ABSOLUTE_DIR}${PIC_RELATIVE_DIR}
INDEX_MASTER_ABSOLUTE_DIR=${WEB_ABSOLUTE_DIR}/index_day.php
INDEX_ABSOLUTE_DIR=${PIC_ABSOLUTE_DIR}/index.php
HOMEPAGE_RELATIVE_PATH=/${CAM_RELATIVE_DIR}/current.jpg
HOMEPAGE_ABSOLUTE_PATH=${WEB_ABSOLUTE_DIR}${HOMEPAGE_RELATIVE_PATH}
HOMEPAGE_HTML_PATH=${WEB_ABSOLUTE_DIR}/${CAM_RELATIVE_DIR}/current.html

if [ -z ${REMOTE_PATH} ]
then
    # Make a directory where the picture will go
    mkdir -p ${PIC_ABSOLUTE_DIR}

    # Set up the index for the new directory if necessary
    if [ ! -e ${INDEX_ABSOLUTE_DIR} ]
    then
	ln -s $INDEX_MASTER_ABSOLUTE_DIR $INDEX_ABSOLUTE_DIR
    fi
fi

######################################################################
# stay in the loop for the current minute
######################################################################

while [ "`date +%H%M`" -le "${HOUR_STRING}${MINUTE_STRING}" ]
do

    BASE=`date +%H:%M:%S`
    FILE_NAME=${BASE}.jpg
    TEMP_FILE_NAME=${BASE}_raw.jpg
    TEMP_FILE_PATH=${TEMP_DIR}/${TEMP_FILE_NAME}
    THUMB_NAME=${BASE}_thumb.jpg
    THUMB_HTML_NAME=${BASE}.html
    PIC_ABSOLUTE_PATH=${PIC_ABSOLUTE_DIR}/${FILE_NAME}
    PIC_RELATIVE_PATH=${PIC_RELATIVE_DIR}/${FILE_NAME}
    THUMB_ABSOLUTE_PATH=${PIC_ABSOLUTE_DIR}/${THUMB_NAME}
    THUMB_RELATIVE_PATH=${PIC_RELATIVE_DIR}/${THUMB_NAME}
    THUMB_HTML_PATH=${PIC_ABSOLUTE_DIR}/${THUMB_HTML_NAME}

    ######################################################################
    # Capture via one of the methods
    ######################################################################

    if [ -n "${UVCCAPTURE_PATH}" ]
    then
        # the kill deals with any lingering capture from previous runs

        pushd ${TEMP_DIR}
        `${UVCCAPTURE_PATH} -x${WIDTH} -y${HEIGHT} -o${TEMP_FILE_NAME}`
        popd
    fi

    if [ -n "${CAPTURE_PATH}" ]
    then
        # the kill deals with any lingering capture from previous runs
        killall -9 capture

        pushd ${TEMP_DIR}
        # The premise of capture is that you can start once, then capture many times 
        # without closing and re-opening the lens, but that didn't seem to work, so
        # we go through the full cycle each time
        ${CAPTURE_PATH} 'start'
        ${CAPTURE_PATH} "capture ${TEMP_FILE_NAME}"
        ${CAPTURE_PATH} 'quit'
        popd
    fi

    if [ -n "${GPHOTO2_PATH}" ]
    then
	# trying a special temp_dir because gphoto2 seems ultra-sensative to directory
        # gphoto2 does not seem to like it if the filename is pathed, so run it from the working directory
        pushd ${TEMP_DIR}
        capture_result=`gphoto2 --filename ${TEMP_FILE_NAME} --capture-image-and-download`
	chmod a+r ${TEMP_FILE_NAME}
        popd
    fi

    if [ -n "${INCOMING_PATH}" ]
    then
        pushd ${INCOMING_PATH}
        # grab most recent file for this minute
        incoming_array=(`ls -t *jpg`)
        newest_file=${incoming_array[0]}

	if [ -z "${newest_file}" ]
	then
	    break
	fi

	# make sure the file is roughly correct by checking the hour part of the stamp
        hour=${newest_file:0:2}

        if [ "${hour}" = "${HOUR_STRING}" ]
        then
    	    cp -f $newest_file ${TEMP_FILE_PATH}
    	    rm ${INCOMING_PATH}/*jpg
        fi
	popd
    fi

    ######################################################################
    # Image post-processing
    ######################################################################

    if [ ! -e "${TEMP_FILE_PATH}" ] 
    then
	if [ -n "${BACKUP_MESSAGE}" ]
	then
            cat > $HOMEPAGE_HTML_PATH <<EOF 
${BACKUP_MESSAGE}
<p>${PRETTY_TIME}, ${PRETTY_DAY}</p>
EOF
	fi
        break
    fi

    if [ -n "${FLIP}" ]
    then
	mogrify -rotate ${FLIP} ${TEMP_FILE_PATH}
    fi

    if [ -n "${JPEGPIXI_PATH}" ] && [ -n "${JPEGPIXI_ARGUMENT}" ]
    then
	jpegpixi $TEMP_FILE_PATH $TEMP_FILE_PATH ${JPEGPIXI_ARGUMENT}
    fi


    ######################################################################
    # Possibly copy the file to a remote server and quit
    ######################################################################

    if [ -n "${REMOTE_PATH}" ]
    then
	scp ${TEMP_FILE_PATH} ${REMOTE_PATH}${FILE_NAME}
	if [ "$VERBOSE" == "0" ] 
	then
	    rm -rf $TEMP_DIR
	fi
	break
    fi

    ######################################################################
    # make thumbnail image and html snippet
    ######################################################################

    cp $TEMP_FILE_PATH $PIC_ABSOLUTE_PATH

    # if something went wrong and the picture is not where it should be, abort
    if [ ! -e "${PIC_ABSOLUTE_PATH}" ]
    then
	break
    fi

    dimension=`identify -verbose ${PIC_ABSOLUTE_PATH} | grep Geometry`
    dimension=${dimension#  Geometry: }
    dimension=${dimension%+0+0}

    if [ -n "${HOMEPAGE_DIMENSION}" ]
    then
	# Prepare a picture for the homepage.  Scale it if necessary.
        cat > ${HOMEPAGE_HTML_PATH} <<EOF 
<div class="candybox">
  <div class="titlebar">
    <span class="name">${CAM_NAME}</span>
    <span>${PRETTY_TIME}, ${PRETTY_DAY}</span>
    <a class="buttonright" href="${PIC_RELATIVE_DIR}">pics</a>
  </div>
  <div>
EOF

	if [ "${dimension}" != "${HOMEPAGE_DIMENSION}" ]
	then
            convert -geometry ${HOMEPAGE_DIMENSION} ${PIC_ABSOLUTE_PATH} ${HOMEPAGE_ABSOLUTE_PATH}
            cat >> ${HOMEPAGE_HTML_PATH} <<EOF 
    <a href="${PIC_RELATIVE_PATH}"><img src="${HOMEPAGE_RELATIVE_PATH}" alt="current picture." title="Click to zoom."/></a>
EOF
	else
            cat >> ${HOMEPAGE_HTML_PATH} <<EOF 
    <img src="${PIC_RELATIVE_PATH}" alt="current picture"/>
EOF
	fi

	cat >> ${HOMEPAGE_HTML_PATH} <<EOF
  </div>
</div>
EOF
    fi

    if [ -n "${THUMB_DIMENSION}" ] 
    then
	# Make a thumbnail for the daily page
	if [ "${dimension}" != "${THUMB_DIMENSION}" ]
	then
            convert -geometry ${THUMB_DIMENSION} ${PIC_ABSOLUTE_PATH} ${THUMB_ABSOLUTE_PATH}
            cat > ${THUMB_HTML_PATH} <<EOF 
    <a href="${PIC_RELATIVE_PATH}"><img src="${THUMB_RELATIVE_PATH}" alt="Thumbnail" title="${PRETTY_TIME}"/></a><br/>
EOF
	else
            cat > ${THUMB_HTML_PATH} <<EOF 
    <img src="${PIC_RELATIVE_PATH}" title="${PRETTY_TIME}"/><br/>
EOF
	fi
    fi
    
    if [ -z "${WAIT}" ]
    then
	break
    else 
	sleep ${WAIT}
    fi

done

######################################################################
# clean up
######################################################################

if [ "$VERBOSE" == "0" ] 
    then
    rm -rf $TEMP_DIR
fi
