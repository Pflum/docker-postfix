#!/bin/sh

logger () {
	if [ "$(echo "$ENTRYPOINT_DEBUG" | tr '[:upper:]' '[:lower:]')" = "true" ]; then
		echo "$1"
	else
		if [ -n "$2" ]; then
		 	echo "$2"
		fi
	fi
}

postfix_copy_replace_env () {
	# copy file and replace env vars (syntax: https://doc.dovecot.org/main/core/settings/syntax.html#environment-variables)
	rm -f "$2"
	LINENR=1
	while IFS= read -r line; do 
		# shellcheck disable=SC2016
		if MATCHES="$(echo "$line" | grep -oE '(=|\s)(%\{ENV:\w+\}|\$ENV:\w+)(\s|$)')"; then
			echo "$MATCHES" | while IFS= read -r MATCH; do
				ENVNAME="$(echo "$MATCH" | cut -d':' -f2 | cut -d'}' -f1)"
				# shellcheck disable=SC2086
				ENVVALUE="$(eval echo \"\$$ENVNAME\")"
				FIRSTCHAR="$(echo "$MATCH" | cut -c1)"
				LASTCHAR="$(echo "$MATCH" | rev | cut -c1)"
				if [ ! "$LASTCHAR" = " " ]; then
					LASTCHAR=""
				fi
				# shellcheck disable=SC2030
				line="$(echo "$line" | sed "s#${MATCH}#${FIRSTCHAR}${ENVVALUE}${LASTCHAR}#")"
				logger "Found $ENVNAME in ${1}:$LINENR and replced with \"$ENVVALUE\""
			done
		fi 
		# shellcheck disable=SC2031
		echo "$line" >> "$2"
		LINENR=$((LINENR+1))
	done < "$1"
}

postfix_compile_maps () {
	if MAPS=$(grep -vE "^\s*#.*$" "$1" | grep -oE "lmdb:/\S+"); then
		echo "$MAPS" | while IFS= read -r MAP; do
			FILE="$(echo "$MAP" | rev | cut -d':' -f1 | rev)"
			if [ -e "$FILE" ]; then
				logger "Compile postfix-map $MAP"
				postmap "$MAP" || logger "postmap for $MAP failed with exitcode $?" "postmap for $MAP failed"
			else
			    logger "postmap $MAP, file not found!"
			fi
		done
	fi
}

if [ -d "/etc/postfix.template/" ]; then
	echo "Copy config from /etc/postfix.template/ to /etc/postfix/"
	cp -r /etc/postfix.template/* "/etc/postfix/"
	find "/etc/postfix.template/" -iname "*.cf" | while read -r sourcefile; do
		targetfile=$(echo "$sourcefile" | sed 's#^/etc/postfix.template/#/etc/postfix/#')
		if [ ! "$(echo "$DISABLE_ENV_REPLACE" | tr '[:upper:]' '[:lower:]')" = true ]; then
			postfix_copy_replace_env "$sourcefile" "$targetfile"
		fi
		if [ ! "$(echo "$DISABLE_AUTO_COMPILE_MAPS" | tr '[:upper:]' '[:lower:]')" = true ]; then
			postfix_compile_maps "$targetfile"
		fi
	done
fi

if [ ! "$(echo "$DISABLE_POSTCONF_OVERWRITE" | tr '[:upper:]' '[:lower:]')" = true ]; then
	postconf -e maillog_file=/dev/stdout
fi

if [ -d "/entrypoint.d/" ]; then
	for script in /entrypoint.d/*.sh; do
		if [ -x "$script" ]; then
			echo "Run script $script"
			"$script"
		fi
	done
fi

exec /usr/sbin/postfix start-fg
