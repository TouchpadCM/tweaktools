#!/bin/sh

ME=apply_tweaks
TWEAKS_BRANCH=auto
TWEAKS_DIR=tweaks

REVIEW_URL=http://review.cyanogenmod.com/p

gettop () 
{ 
    local TOPFILE=build/core/envsetup.mk;
    if [ -n "$TOP" -a -f "$TOP/$TOPFILE" ]; then
        echo $TOP;
    else
        if [ -f $TOPFILE ]; then
            PWD= /bin/pwd;
        else
            local HERE=$PWD;
            T=;
            while [ \( ! \( -f $TOPFILE \) \) -a \( $PWD != "/" \) ]; do
                cd .. > /dev/null;
                T=`PWD= /bin/pwd`;
            done;
            cd $HERE > /dev/null;
            if [ -f "$T/$TOPFILE" ]; then
                echo $T;
            fi;
        fi;
    fi
}

get_tweaks_device_dir()
{
	local numdirs
	local HERE=$PWD;

	cd ${TOP}/${TWEAKS_DIR}/device

	numdirs=`ls -d1 */${CM_BUILD} | wc -l 2>/dev/null`
	if [ $numdirs -ne 1 ];
	then
		cd $HERE > /dev/null;
		return 0
	fi

	TWEAKS_DEVICE_DIR=`ls -d1 */${CM_BUILD}`
	cd $HERE > /dev/null;

	return 1
}

do_apply_local_patch()
{
	local HERE=$PWD;
	local c_id="${1}"
	local c_proj="${2}"
	local c_dir
	local p_dir
	local rc

	c_dir=`repo forall $c_proj -c 'echo $REPO_PATH'`

	p_dir=${TOP}/${TWEAKS_DIR}/device/${TWEAKS_DEVICE_DIR}/patches

	repo start ${TWEAKS_BRANCH} $c_proj
	rc=$?
	if [ $rc -ne 0 ]; then
		echo "$ME: ERROR: failed to start tweaks branch ${TWEAKS_BRANCH} in ${c_proj}"
		cd $HERE > /dev/null;
		exit 1
	fi

	cd ${TOP}/${c_dir}
	rc=$?
	if [ $rc -ne 0 ]; then
		echo "$ME: ERROR: cd '${c_dir}' failed"
		cd $HERE > /dev/null;
		exit 1
	fi

	if [ ! -r ${p_dir}/${c_id}.patch ]; then
		echo "$ME: ERROR: local patch ${c_id} not readable"
		cd $HERE > /dev/null;
		exit 1
	fi

	echo "$ME: applying local patch ${c_id} to ${c_proj}"
	git apply --index ${p_dir}/${c_id}.patch

	rc=$?
	if [ $rc -ne 0 ];
	then
		echo "$ME: ERROR: apply patch ${c_id} failed"
		cd $HERE > /dev/null;
		return 1
	fi

	echo "$ME: commiting patch ${c_id} in ${c_proj}"
	git commit -m "patch ${c_id}"

	rc=$?
	if [ $rc -ne 0 ];
	then
		echo "$ME: commit patch ${c_id} failed"
		cd $HERE > /dev/null;
		return 1
	fi

	cd $HERE > /dev/null;
	return 0
}

do_apply_cherry_pick()
{
	local HERE=$PWD;
	local c_id="${1}"
	local c_ps="${2}"
	local c_proj="${3}"
	local c_dir
	local c_idlt
	local rc

	c_dir=`repo forall $c_proj -c 'echo $REPO_PATH'`

	c_idlt="${c_id:3:2}"

	repo start ${TWEAKS_BRANCH} $c_proj
	rc=$?
	if [ $rc -ne 0 ]; then
		echo "$ME: Failed to start tweaks branch ${TWEAKS_BRANCH} in ${c_proj}"
		exit 1
	fi

	cd ${TOP}/${c_dir}

	echo "$ME: fetching cherry-pick ${c_id}/${c_ps} for ${c_proj}"
	git fetch ${REVIEW_URL}/${c_proj} \
		refs/changes/${c_idlt}/${c_id}/${c_ps} 

	rc=$?
	if [ $rc -ne 0 ];
	then
		echo "$ME: git fetch for ${c_id}/${c_ps} failed"
		cd $HERE > /dev/null;
		return 1
	fi

	echo "$ME: applying cherry-pick ${c_id}/${c_ps} in ${c_proj}"
	git cherry-pick FETCH_HEAD

	rc=$?
	if [ $rc -ne 0 ];
	then
		echo "$ME: git cherry-pick for ${c_id}/${c_ps} failed"
		cd $HERE > /dev/null;
		return 1
	fi

	cd $HERE > /dev/null;
	return 0
}



do_tweaks_file()
{
	local TF=${1}

	cd ${FTD}/tweakslist

	echo "$ME: Applying tweaks list ${TF}"

	tline=0

	cat ${TF} |
		while read tt ta1 ta2 ta3 ta4 ta5 ta6
		do
			# increment line counter
			tline=$((tline + 1))

			# check for empty lines
			if [ -z "${tt}" ]; then
				tt="blank"
			fi

			case $tt in
				"gcp")
					do_apply_cherry_pick $ta1 $ta2 $ta3 $ta4 $ta5 $ta6
					if [ $? -ne 0 ]; then
						return 1
					fi
					;;
				"lpf")
					do_apply_local_patch $ta1 $ta2 $ta3 $ta4 $ta5 $ta6
					if [ $? -ne 0 ]; then
						return 1
					fi
					;;
				"rem")
					# ignore comment line
					;;
				"blank")
					# ignore blank line
					;;
				*)
					echo "ME: Invalid line $tline in ${TF}"
					;;
			esac
		done
	return 0
}
			




TOP=`gettop`

if [ -z "${TOP}" ];
then
	echo "$ME: TOP not set. Aborting."
	exit 2
fi

if [ -z "${CM_BUILD}" ];
then
	echo "$ME: CM_BUILD not set. Aborting."
	exit 1
fi

if get_tweaks_device_dir ; then
	echo "$ME: TWEAKS_DEVICE_DIR not set"
	exit 3
fi

FTD="${TOP}/${TWEAKS_DIR}/device/${TWEAKS_DEVICE_DIR}"

echo "$ME: Abandoning tweaks branch ${TWEAKS_BRANCH}"
repo abandon ${TWEAKS_BRANCH}

HAS_TWEAKS=0

if [ -d ${FTD}/tweakslist ]; then
	cd ${FTD}/tweakslist
	for tweaks_file in *
	do
		HAS_TWEAKS=1
		do_tweaks_file ${tweaks_file}
		if [ $? -ne 0 ]; then
			echo "$ME: Error applying tweakslist ${tweaks_file}"
			echo "$ME: Aborting."
			exit 5
		fi
	done
fi

if [ $HAS_TWEAKS -eq 0 ]; then
	echo "$ME: No tweaks to apply."
	exit 0
fi

