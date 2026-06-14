#!/bin/sh

logger () {
	if [ ${ENTRYPOINT_DEBUG,,} == "true" ]; then
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
		MATCHES="$(echo "$line" | grep -oP '(=|\s)(%{ENV:\w+}|\$ENV:\w+)(\s|$)')"
		if [[ "$?" -eq 0 ]]; then
			while IFS= read -r MATCH; do
				ENVNAME="$(echo "$MATCH" | cut -d':' -f2 | cut -d'}' -f1)"
				ENVVALUE="${!ENVNAME}"
				FIRSTCHAR="$(echo "$MATCH" | cut -c1)"
				LASTCHAR="$(echo "$MATCH" | rev | cut -c1)"
				if [ ! "$LASTCHAR" == " " ]; then
					LASTCHAR=""
				fi
				line="$(echo "$line" | sed "s#${MATCH}#${FIRSTCHAR}${ENVVALUE}${LASTCHAR}#")"
				logger "Found $ENVNAME in ${1}:$LINENR and replced with \"$ENVVALUE\""
			done <<< "$MATCHES"
		fi 
		echo "$line" >> "$2"
		((LINENR++))
	done < "$1"
}

postfix_compile_maps () {
	MAPS=$(grep -vP "^\s*#.*$" "$1" | grep -oP "lmdb:/\S+")
	if [[ "$?" -eq 0 ]]; then
		while IFS= read -r MAP; do
			FILE="$(echo "$MAP" | rev | cut -d':' -f1 | rev)"
			if [ -e "$FILE" ]; then
				logger "Compile postfix-map $MAP"
				postmap "$MAP" || logger "postmap for $MAP failed with exitcode $?" "postmap for $MAP failed"
			else
			    logger "postmap $MAP, file not found!"
			fi
		done <<< "$MAPS"
	fi
}

if [ -d "/etc/postfix.template/" ]; then
	echo "Copy config from /etc/postfix.template/ to /etc/postfix/"
	cp -r "/etc/postfix.template/" "/etc/postfix/"
	find "/etc/postfix.template/" -iname "*.cf" | while read -r sourcefile; do
		targetfile=$(echo "$sourcefile" | sed 's#^/etc/postfix.template/#/etc/postfix/#')
		if [ ! ${DISABLE_ENV_REPLACE,,} == true ]; then
			postfix_copy_replace_env "$sourcefile" "$targetfile"
		fi
		if [ ! ${DISABLE_AUTO_COMPILE_MAPS,,} == true ]; then
			postfix_compile_maps "$targetfile"
		fi
	done
fi

if [ ! ${DISABLE_POSTCONF_OVERWRITE,,} == true ]; then
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
