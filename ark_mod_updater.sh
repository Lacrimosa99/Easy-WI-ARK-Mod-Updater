#!/bin/bash

# Debug Modus
DEBUG="OFF"

# Easy-WI Masterserver User
MASTERSERVER_USER="unknown_user"

# E-Mail Modul for Autoupdater
# deactivate E-Mail Support with empty EMAIL_TO Field
EMAIL_TO=""
SUBJECT="ARK Mod-ID failure detected on $(hostname)"


##########################################
######## from here nothing change ########
##########################################

CURRENT_UPDATER_VERSION="1.7"
ARK_APP_ID="346110"
MASTER_PATH="/home/$MASTERSERVER_USER"
STEAM_CMD_PATH="$MASTER_PATH/masterserver/steamCMD/steamcmd.sh"
ARK_MOD_PATH="$MASTER_PATH/masteraddons"
LOG_PATH="$MASTER_PATH/logs"
MOD_LOG="$LOG_PATH/ark_mod_id.log"
MOD_BACKUP_LOG="$LOG_PATH/ark_mod_id_backup.log"
INSTALL_LOG="$LOG_PATH/ark_mod_update_status_$(date +"%d-%m-%Y").log"
MOD_NO_UPDATE_LOG="$LOG_PATH/ark_mod_id_no_update.log"
MOD_LAST_VERSION="$MASTER_PATH/versions"
TMP_PATH="$MASTER_PATH/temp"
EMAIL_TMP_MESSAGE="$TMP/email.txt"
EMAIL_SCRIPT_FAILURE_LOG="$LOG_PATH/ark_mod_failure_email_$(date +"%d-%m-%Y").txt"
EMAIL_SCRIPT_OUTDATED_LOG="$LOG_PATH/ark_mod_outdated_email_$(date +"%d-%m-%Y").txt"
EMAIL_MOD_DEPRECATED_LOG="$LOG_PATH/ark_mod_deprecated_email_$(date +"%d-%m-%Y").txt"
EMAIL_MOD_DL_FAILURE_LOG="$LOG_PATH/ark_mod_dl_failure_email_$(date +"%d-%m-%Y").txt"
DEAD_MOD="deprec|outdated|brocken|not-supported|mod-is-dead|no-longer-|old|discontinued"

PRE_CHECK() {
	if [ ! "$MASTERSERVER_USER" = "" ]; then
		echo >> "$INSTALL_LOG"
		echo "-------------------- Beginn Log $(date +"%H:%M") --------------------" >> "$INSTALL_LOG"

		USER_CHECK=$(cut -d: -f6,7 /etc/passwd | grep "$MASTERSERVER_USER" | head -n1)
		if ([ ! "$USER_CHECK" == "/home/$MASTERSERVER_USER:/bin/bash" -a ! "$USER_CHECK" == "/home/$MASTERSERVER_USER/:/bin/bash" ]); then
			EMAIL_SCRIPT_FAILURE="1"
			EMAIL_SCRIPT_FAILURE_MESSAGE="User $MASTERSERVER_USER not found or wrong shell rights!\nPlease check the Masteruser inside this Script or the user shell rights."
		fi

		if [ ! -d "$ARK_MOD_PATH" ]; then
			EMAIL_SCRIPT_FAILURE="1"
			EMAIL_SCRIPT_FAILURE_MESSAGE="Masteraddons Directory $ARK_MOD_PATH not found!"
		fi

		if [ ! -f "$STEAM_CMD_PATH" ]; then
			EMAIL_SCRIPT_FAILURE="1"
			EMAIL_SCRIPT_FAILURE_MESSAGE="Steam Installation $STEAM_CMD_PATH found!"
		fi
	else
		EMAIL_SCRIPT_FAILURE="1"
		EMAIL_SCRIPT_FAILURE_MESSAGE="Variable MASTERSERVER_USER are empty!"
	fi
	sleep 2

	LATEST_UPDATER_VERSION=`wget -q --timeout=60 -O - https://api.github.com/repos/Lacrimosa99/Easy-WI-ARK-Mod-Updater/releases/latest | grep -Po '(?<="tag_name": ")([0-9]\.[0-9])'`
	if [ "`printf "${LATEST_UPDATER_VERSION}\n${CURRENT_UPDATER_VERSION}" | sort -V | tail -n 1`" != "$CURRENT_UPDATER_VERSION" ]; then
		EMAIL_SCRIPT_OUTDATED="1"
		echo >> "$INSTALL_LOG"
		EMAIL_SCRIPT_OUTDATED_MESSAGE="You are using a old ARK Mod Updater Script Version ${CURRENT_UPDATER_VERSION}."	| tee -a "$INSTALL_LOG" "$EMAIL_TMP_MESSAGE"
		EMAIL_SCRIPT_OUTDATED_MESSAGE="Please upgrade to Version ${LATEST_UPDATER_VERSION} over the ark_mod_manager.sh Script and retry." | tee -a "$INSTALL_LOG" "$EMAIL_TMP_MESSAGE"
		EMAIL_SCRIPT_OUTDATED_MESSAGE="Updater worked currently, but all fixes and updates are currently not available." | tee -a "$INSTALL_LOG" "$EMAIL_TMP_MESSAGE"
	fi

	if [ ! -d "$MOD_LAST_VERSION" ]; then
		mkdir "$MOD_LAST_VERSION"
		chown -cR "$MASTERSERVER_USER":"$MASTERSERVER_USER" "$MOD_LAST_VERSION" 2>&1 >/dev/null
	fi

	if [ ! -f "$TMP_PATH"/ark_mod_updater_status ]; then
		UPDATE
	else
		echo >> "$INSTALL_LOG"
		echo "Updater is currently running... please try again later." >> "$INSTALL_LOG"
		FINISHED
	fi
}

UPDATE() {
	if [ ! -f "$TMP_PATH"/ark_mod_updater_status ]; then
		touch "$TMP_PATH"/ark_mod_updater_status
	else
		echo >> "$INSTALL_LOG"
		echo "Update in work... aborted!" >> "$INSTALL_LOG"
		echo >> "$INSTALL_LOG"
		echo "---------------------------- Finished ----------------------------" >> "$INSTALL_LOG"
		echo >> "$INSTALL_LOG"
		echo >> "$INSTALL_LOG"
		exit 1
	fi

	rm -rf "$STEAM_WORKSHOP_PATH"
	if [ -f "$MOD_LOG" ]; then
		if [ -f "$MOD_BACKUP_LOG" ]; then
			rm -rf "$MOD_BACKUP_LOG"
		fi
		cp "$MOD_LOG" "$TMP_PATH"/ark_custom_appid_tmp.log
		mv "$MOD_LOG" "$MOD_BACKUP_LOG"
	elif [ -f "$MOD_BACKUP_LOG" ]; then
		cp "$MOD_BACKUP_LOG" "$TMP_PATH"/ark_custom_appid_tmp.log
	else
		echo 'File "ark_mod_id.log" in /logs not found!' >> "$INSTALL_LOG"
		echo "Update canceled!" >> "$INSTALL_LOG"
		FINISHED
	fi

	if [ -f "$TMP_PATH"/ark_custom_appid_tmp.log ]; then
		ARK_MOD_ID=$(cat "$TMP_PATH"/ark_custom_appid_tmp.log)
		INSTALL_CHECK
	else
		echo "TMP Log in /temp not found!" >> "$INSTALL_LOG"
		echo "Update canceled!" >> "$INSTALL_LOG"
	fi

	if [ -f "$TMP_PATH"/ark_update_failure.log ]; then
		SECOND_DOWNLOAD=1
		rm -rf "$STEAM_WORKSHOP_PATH"
		sleep 120
		COUNTER=0
		unset ARK_MOD_ID
		ARK_MOD_ID=$(cat "$TMP_PATH"/ark_update_failure.log)
		INSTALL_CHECK
	fi
	FINISHED
}

INSTALL_CHECK() {
	for MODID in ${ARK_MOD_ID[@]}; do
		ARK_MOD_NAME_NORMAL=$(curl -s "http://steamcommunity.com/sharedfiles/filedetails/?id=$MODID" | sed -n 's|^.*<div class="workshopItemTitle">\([^<]*\)</div>.*|\1|p')
		ARK_LAST_CHANGES_DATE=$(curl -s "https://steamcommunity.com/sharedfiles/filedetails/changelog/$MODID" | sed -n 's|^.*Update: \([^<]*\)</div>.*|\1|p' | head -n1 | tr -d ',\t')

		if [ -f "$MOD_LAST_VERSION"/ark_mod_id_"$MODID".txt ]; then
			ARK_LOCAL_UPDATE=$(cat "$MOD_LAST_VERSION"/ark_mod_id_"$MODID".txt)
		else
			ARK_LOCAL_UPDATE=""
		fi

		if [ ! "$ARK_MOD_NAME_NORMAL" = "" ]; then
			if [ ! "$ARK_LOCAL_UPDATE" = "$ARK_LAST_CHANGES_DATE" ]; then
				ARK_MOD_NAME_TMP=$(echo "$ARK_MOD_NAME_NORMAL" | egrep "Difficulty|ItemTweaks|NPC")
				if [ ! "$ARK_MOD_NAME_TMP" = "" ]; then
					ARK_MOD_NAME=$(echo "$ARK_MOD_NAME_NORMAL" | tr "/" "-" | tr "[A-Z]" "[a-z]" | tr " " "-" | tr -d ".,!()[]" | sed "s/-updated//;s/+/-plus/;s/+/plus/" | sed 's/\\/-/;s/\\/-/;s/---/-/')
				else
					ARK_MOD_NAME=$(echo "$ARK_MOD_NAME_NORMAL" | tr "/" "-" | tr "[A-Z]" "[a-z]" | tr " " "-" | tr -d ".,+!()[]" | sed "s/-updated//;s/-v[0-9][0-9]*//;s/-[0-9][0-9]*//" | sed 's/\\/-/;s/\\/-/;s/---/-/')
				fi
				ARK_MOD_NAME_DEPRECATED=$(echo "$ARK_MOD_NAME" | egrep "$DEAD_MOD")

				COUNTER=0
				while [ $COUNTER -lt 4 ]; do
					RESULT=$(su "$MASTERSERVER_USER" -c "$STEAM_CMD_PATH +login anonymous +workshop_download_item $ARK_APP_ID $MODID validate +quit" | egrep "Success" | cut -c 1-7)

					if [ -d $MASTER_PATH/Steam/steamapps/workshop/content/$ARK_APP_ID/$MODID ]; then
						STEAM_WORKSHOP_PATH="$MASTER_PATH/Steam/steamapps/workshop"
					else
						STEAM_WORKSHOP_PATH="$MASTER_PATH/masterserver/steamCMD/steamapps/workshop"
					fi

					STEAM_CONTENT_PATH="$STEAM_WORKSHOP_PATH/content/$ARK_APP_ID"
					STEAM_DOWNLOAD_PATH="$STEAM_WORKSHOP_PATH/downloads/$ARK_APP_ID"

					if [ "$RESULT" == "Success" ] && [ -d "$STEAM_CONTENT_PATH"/"$MODID" ]; then
						if [ -f "$TMP_PATH"/ark_update_failure.log ]; then
							TMP_ID=$(cat "$TMP_PATH"/ark_update_failure.log | grep "$MODID")
							if [ "$TMP_ID" = "" ]; then
								sed -i "/$MODID/d" "$TMP_PATH"/ark_update_failure.log
							fi
						fi
						echo >> "$INSTALL_LOG"
						if  [ "$SECOND_DOWNLOAD" = "1" ]; then
							echo >> "$INSTALL_LOG"
							echo "Second Download:" >> "$INSTALL_LOG"
							echo >> "$INSTALL_LOG"
							echo >> "$INSTALL_LOG"
						fi
						echo "$ARK_MOD_NAME_NORMAL" >> "$INSTALL_LOG"
						echo "$MODID" >> "$INSTALL_LOG"
						echo "Steam Download Status: $RESULT" >> "$INSTALL_LOG"
						echo "Connection Attempts: $COUNTER" >> "$INSTALL_LOG"
						echo >> "$INSTALL_LOG"
						break
					else
						if [ "$COUNTER" = "3" ]; then
							echo >> "$INSTALL_LOG"
							if  [ "$SECOND_DOWNLOAD" = "1" ]; then
								echo >> "$INSTALL_LOG"
								echo "Second Download:" >> "$INSTALL_LOG"
								echo >> "$INSTALL_LOG"
								echo >> "$INSTALL_LOG"
							fi
							echo "$ARK_MOD_NAME_NORMAL" >> "$INSTALL_LOG"
							echo "$MODID" >> "$INSTALL_LOG"
							echo "Steam Download Status: FAILED" >> "$INSTALL_LOG"
							if [ ! -f "$TMP_PATH"/ark_update_failure.log ]; then
								touch "$TMP_PATH"/ark_update_failure.log
							fi
							TMP_ID=$(cat "$TMP_PATH"/ark_update_failure.log | grep "$MODID")
							if [ "$TMP_ID" = "" ]; then
								echo "$MODID" >> "$TMP_PATH"/ark_update_failure.log
							fi
							sed -i "/$MODID/d" "$TMP_PATH"/ark_custom_appid_tmp.log >/dev/null 2>&1
							break
						else
							rm -rf $STEAM_CONTENT_PATH/*
							rm -rf $STEAM_DOWNLOAD_PATH/*
							let COUNTER=$COUNTER+1
							sleep 5
						fi
					fi
				done

				if [ -d "$STEAM_CONTENT_PATH"/"$MODID" ]; then
					rm -rf "$ARK_MOD_PATH"/ark_"$MODID"/ShooterGame/Content/Mods/"$MODID"/ 2>&1 >/dev/null
					DECOMPRESS
				else
					echo "ModID $MODID in the Steam Content Folder not found!" >> "$INSTALL_LOG"
				fi
				if [ -d "$ARK_MOD_PATH"/ark_"$MODID" ]; then
					if [ "$ARK_MOD_NAME_DEPRECATED" = "" ]; then
						if [ -f "$MOD_LOG" ]; then
							MOD_TMP_NAME=$(cat "$MOD_LOG" | grep "$MODID" )
						fi
						if [ "$MOD_TMP_NAME" = "" ]; then
							echo "$MODID" >> "$MOD_LOG"
						fi
						chown -cR "$MASTERSERVER_USER":"$MASTERSERVER_USER" "$ARK_MOD_PATH"/ark_"$MODID" 2>&1 >/dev/null
						sed -i "/$MODID/d" "$TMP_PATH"/ark_custom_appid_tmp.log >/dev/null 2>&1
						echo "$ARK_LAST_CHANGES_DATE" > ""$MOD_LAST_VERSION"/ark_mod_id_"$MODID".txt"
						chown -cR "$MASTERSERVER_USER":"$MASTERSERVER_USER" "$MOD_LAST_VERSION" 2>&1 >/dev/null
					else
						EMAIL_MOD_DEPRECATED="1"
						if [ ! -f "$MOD_NO_UPDATE_LOG" ]; then
							touch "$MOD_NO_UPDATE_LOG"
            	MOD_NO_UPDATE_TMP_NAME=""
						else
            	MOD_NO_UPDATE_TMP_NAME=$(cat "$MOD_NO_UPDATE_LOG" | grep "$MODID")
						fi
						if [ -f "$MOD_NO_UPDATE_LOG" -a "$MOD_NO_UPDATE_TMP_NAME" = "" ]; then
							echo "$MODID" >> "$MOD_NO_UPDATE_LOG"
						fi
						sed -i "/$MODID/d" "$MOD_BACKUP_LOG"
						echo >> "$INSTALL_LOG"
						echo "Mod $ARK_MOD_NAME_NORMAL with ModID "$MODID" are not more Supported and deactivated for Updater!" >> "$INSTALL_LOG"
						echo 'You can self deinstall from Disk over the "ark_mod_manager.sh".' >> "$INSTALL_LOG"
					fi
				else
					echo "Mod $ARK_MOD_NAME_NORMAL in the masteraddons Folder has not been installed!" >> "$INSTALL_LOG"
				fi
			else
				echo "$MODID" >> "$MOD_LOG"
				echo "Mod is Up-to-Date: $MODID ($ARK_MOD_NAME_NORMAL)" >> "$INSTALL_LOG"
			fi
		else
			echo "$MODID" >> "$MOD_LOG"
			echo "Steam Community are currently not available or ModID $MODID not known!" >> "$INSTALL_LOG"
			echo "Please try again later." >> "$INSTALL_LOG"
		fi
	done
}

DECOMPRESS() {
	mod_appid=$ARK_APP_ID
	mod_branch=Windows
	modid=$MODID

	modsrcdir="$STEAM_CONTENT_PATH/$MODID"
	moddestdir="$ARK_MOD_PATH/ark_$MODID/ShooterGame/Content/Mods/$MODID"
	modbranch="${mod_branch:-Windows}"

	for varname in "${!mod_branch_@}"; do
		if [ "mod_branch_$modid" == "$varname" ]; then
			modbranch="${!varname}"
		fi
	done

	if [ \( ! -f "$moddestdir/.modbranch" \) ] || [ "$(<"$moddestdir/.modbranch")" != "$modbranch" ]; then
		rm -rf "$moddestdir"
	fi

	if [ -f "$modsrcdir/mod.info" ]; then
		echo "Copying files to $moddestdir"

		if [ -f "$modsrcdir/${modbranch}NoEditor/mod.info" ]; then
			modsrcdir="$modsrcdir/${modbranch}NoEditor"
		fi

		find "$modsrcdir" -type d -printf "$moddestdir/%P\0" | xargs -0 -r mkdir -p

		find "$modsrcdir" -type f ! \( -name '*.z' -or -name '*.z.uncompressed_size' \) -printf "%P\n" | while read f; do
			if [ \( ! -f "$moddestdir/$f" \) -o "$modsrcdir/$f" -nt "$moddestdir/$f" ]; then
				printf "%10d  %s  " "`stat -c '%s' "$modsrcdir/$f"`" "$f"
				cp "$modsrcdir/$f" "$moddestdir/$f"
				echo -ne "\r\\033[K"
			fi
		done

		find "$modsrcdir" -type f -name '*.z' -printf "%P\n" | while read f; do
			if [ \( ! -f "$moddestdir/${f%.z}" \) -o "$modsrcdir/$f" -nt "$moddestdir/${f%.z}" ]; then
				printf "%10d  %s  " "`stat -c '%s' "$modsrcdir/$f"`" "${f%.z}"
				perl -M'Compress::Raw::Zlib' -e '
					my $sig;
					read(STDIN, $sig, 8) or die "Unable to read compressed file";
					if ($sig != "\xC1\x83\x2A\x9E\x00\x00\x00\x00"){
						die "Bad file magic";
					}
					my $data;
					read(STDIN, $data, 24) or die "Unable to read compressed file";
					my ($chunksizelo, $chunksizehi,
						$comprtotlo,  $comprtothi,
						$uncomtotlo,  $uncomtothi)  = unpack("(LLLLLL)<", $data);
					my @chunks = ();
					my $comprused = 0;
					while ($comprused < $comprtotlo) {
						read(STDIN, $data, 16) or die "Unable to read compressed file";
						my ($comprsizelo, $comprsizehi,
							$uncomsizelo, $uncomsizehi) = unpack("(LLLL)<", $data);
						push @chunks, $comprsizelo;
							$comprused += $comprsizelo;
					}
					foreach my $comprsize (@chunks) {
						read(STDIN, $data, $comprsize) or die "File read failed";
						my ($inflate, $status) = new Compress::Raw::Zlib::Inflate();
						my $output;
						$status = $inflate->inflate($data, $output, 1);
						if ($status != Z_STREAM_END) {
							die "Bad compressed stream; status: " . ($status);
						}
						if (length($data) != 0) {
							die "Unconsumed data in input"
						}
						print $output;
					}
				' <"$modsrcdir/$f" >"$moddestdir/${f%.z}"
				touch -c -r "$modsrcdir/$f" "$moddestdir/${f%.z}"
				echo -ne "\r\\033[K"
			fi
		done

		perl -e '
			my $data;
			{ local $/; $data = <STDIN>; }
			my $mapnamelen = unpack("@0 L<", $data);
			my $mapname = substr($data, 4, $mapnamelen - 1);
				$mapnamelen += 4;
			my $mapfilelen = unpack("@" . ($mapnamelen + 4) . " L<", $data);
			my $mapfile = substr($data, $mapnamelen + 8, $mapfilelen);
			print pack("L< L< L< Z8 L< C L< L<", $ARGV[0], 0, 8, "ModName", 1, 0, 1, $mapfilelen);
			print $mapfile;
			print "\x33\xFF\x22\xFF\x02\x00\x00\x00\x01";
		' $modid <"$moddestdir/mod.info" >"$moddestdir/.mod"

		if [ -f "$moddestdir/modmeta.info" ]; then
			cat "$moddestdir/modmeta.info" >>"$moddestdir/.mod"
		else
			echo -ne '\x01\x00\x00\x00\x08\x00\x00\x00ModType\x00\x02\x00\x00\x001\x00' >>"$moddestdir/.mod"
		fi

		echo "$modbranch" >"$moddestdir/.modbranch"
	fi
}

CLEANFILES() {
	find "$LOG_PATH" -name "ark_mod_update_status_*" -mtime +7 -exec rm -rf {} \;
	find "$LOG_PATH" -name "ark_mod_failure_email_*" -mtime +7 -exec rm -rf {} \;
	find "$LOG_PATH" -name "ark_mod_outdated_email_*" -mtime +7 -exec rm -rf {} \;
	find "$LOG_PATH" -name "ark_mod_deprecated_email_*" -mtime +7 -exec rm -rf {} \;
	find "$LOG_PATH" -name "ark_mod_dl_failure_email_*" -mtime +7 -exec rm -rf {} \;

	if [ -f "$TMP_PATH"/ark_update_failure.log ]; then
		cp "$MOD_BACKUP_LOG" "$MOD_LOG"
	fi

	if [ -f "$TMP_PATH"/ark_custom_appid_tmp.log ]; then
		rm -rf "$TMP_PATH"/ark_custom_appid_tmp.log
	fi

	if [ -f "$TMP_PATH"/ark_update_failure.log ]; then
		rm -rf "$TMP_PATH"/ark_update_failure.log
	fi

	chown -cR "$MASTERSERVER_USER":"$MASTERSERVER_USER" "$LOG_PATH"/* 2>&1 >/dev/null
	chown -cR "$MASTERSERVER_USER":"$MASTERSERVER_USER" "$MOD_LAST_VERSION"/* 2>&1 >/dev/null
}

SEND_EMAIL() {
	mail -s "$SUBJECT" "$EMAIL_TO" < "$EMAIL_TMP_MESSAGE"
	sleep 3
}

FINISHED() {
	if [ ! "$EMAIL_TO" = "" ]; then
		if [ "$EMAIL_SCRIPT_FAILURE" = "1" -o "$EMAIL_SCRIPT_OUTDATED" = "1" -o "$EMAIL_MOD_DEPRECATED" = "1" -o -f "$TMP_PATH"/ark_update_failure.log ]; then
			# EMAIL HEADER
			echo >> "$EMAIL_TMP_MESSAGE"
			echo "Date: $(date +%d.%m.%Y_%H:%M)" >> "$EMAIL_TMP_MESSAGE"
			echo "Hostname: $(hostname)" >> "$EMAIL_TMP_MESSAGE"
			echo "IP: $(ip -4 -o addr show dev eth0 | awk '{split($4,a,"/") ;print a[1]}' | head -n1)"	>> "$EMAIL_TMP_MESSAGE"
			echo >> "$EMAIL_TMP_MESSAGE"
			# Script Failure
			if [ "$EMAIL_SCRIPT_FAILURE" = "1" ]; then
				echo "Failure Message:" >> "$EMAIL_TMP_MESSAGE"
				echo "$EMAIL_SCRIPT_FAILURE_MESSAGE" | tee -a "$INSTALL_LOG" "$EMAIL_TMP_MESSAGE"
				echo >> "$EMAIL_TMP_MESSAGE"
				echo 'Ark Mod Updater has been stopped!' >> "$EMAIL_TMP_MESSAGE"
				echo 'Please fix it in the next time.' >> "$EMAIL_TMP_MESSAGE"
			# Script Outdated
			elif [ "$EMAIL_SCRIPT_OUTDATED" = "1" ]; then
				echo "$EMAIL_SCRIPT_OUTDATED_MESSAGE" | tee -a "$INSTALL_LOG" "$EMAIL_TMP_MESSAGE"
			# Mod Deprecated
			elif [ "$EMAIL_MOD_DEPRECATED" = "1" ]; then
				echo "The following IDs are obsolete and have not been updated:" >> "$EMAIL_TMP_MESSAGE"
				cat "$DEPRECATED_LOG" >> "$EMAIL_TMP_MESSAGE"
			# Download Failure
			elif [ -f "$TMP_PATH"/ark_update_failure.log ]; then
				echo "Error in Logfiles found!" | tee -a "$INSTALL_LOG" "$EMAIL_TMP_MESSAGE"
				echo "Logfile Backup restored" | tee -a "$INSTALL_LOG" "$EMAIL_TMP_MESSAGE"
				echo | tee -a "$INSTALL_LOG" "$EMAIL_TMP_MESSAGE"
				echo "The following IDs were not downloaded:" | tee -a "$INSTALL_LOG" "$EMAIL_TMP_MESSAGE"
				echo | tee -a "$INSTALL_LOG" "$EMAIL_TMP_MESSAGE"
				cat "$TMP_PATH"/ark_update_failure.log | tee -a "$INSTALL_LOG" "$EMAIL_TMP_MESSAGE"
				echo | tee -a "$INSTALL_LOG" "$EMAIL_TMP_MESSAGE"
			fi
		fi

		if [ -f "$EMAIL_TMP_MESSAGE" ] ; then
			# Script Failure
			if [ "$EMAIL_SCRIPT_FAILURE" = "1" -a ! -f "$EMAIL_SCRIPT_FAILURE_LOG" ]; then
				SEND_EMAIL
				mv "$EMAIL_TMP_MESSAGE" "$EMAIL_SCRIPT_FAILURE_LOG"
			# Script Outdated
			elif [ "$EMAIL_SCRIPT_OUTDATED" = "1" -a ! -f "$EMAIL_SCRIPT_OUTDATED_LOG" ]; then
				SEND_EMAIL
				mv "$EMAIL_TMP_MESSAGE" "$EMAIL_SCRIPT_OUTDATED_LOG"
			# Mod Deprecated
			elif [ "$EMAIL_MOD_DEPRECATED" = "1" ]; then
				SEND_EMAIL
				if [ -f "$EMAIL_MOD_DEPRECATED_LOG" ]; then
					mv "$EMAIL_MOD_DEPRECATED_LOG" "$EMAIL_MOD_DEPRECATED_LOG"_old
				fi
				mv "$EMAIL_TMP_MESSAGE" "$EMAIL_MOD_DEPRECATED_LOG"
			# Download Failure
			elif [ -f "$TMP_PATH"/ark_update_failure.log ]; then
				SEND_EMAIL
			fi
			find "$LOG_PATH" -name "ark_mod_emailmessage_*" -mtime +3 -exec rm -rf {} \;
		fi
	fi

	CLEANFILES

##########

	echo "--------------------- Finished $(date +"%H:%M") ---------------------" >> "$INSTALL_LOG"
	echo >> "$INSTALL_LOG"
	echo >> "$INSTALL_LOG"

	if [ -f "$TMP_PATH"/ark_mod_updater_status ]; then
		rm -rf "$TMP_PATH"/ark_mod_updater_status
	fi

	if [ "$DEBUG" == "ON" ]; then
		set +x
	fi
	exit
}

if [ "$DEBUG" == "ON" ]; then
	set -x
fi

PRE_CHECK
