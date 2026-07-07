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
		MATCHES="$(echo "$line" | grep -oE '(=|\s)(%\{env:\w+\}|\$ENV:\w+)(\s|$)')"
		if [ -n "$MATCHES" ]; then
			while IFS= read -r MATCH; do
				ENVNAME="$(echo "$MATCH" | cut -d':' -f2 | cut -d'}' -f1)"
				# shellcheck disable=SC2086
				ENVVALUE="$(eval echo \"\$$ENVNAME\")"
				FIRSTCHAR="$(echo "$MATCH" | cut -c1)"
				LASTCHAR="$(echo "$MATCH" | rev | cut -c1)"
				if [ ! "$LASTCHAR" = " " ]; then
					LASTCHAR=""
				fi
				line="$(echo "$line" | sed "s#${MATCH}#${FIRSTCHAR}${ENVVALUE}${LASTCHAR}#")"
				logger "Found $ENVNAME in ${1}:$LINENR and replaced with \"$ENVVALUE\""
			done <<EOF
$MATCHES
EOF
		fi 
		echo "$line" >> "$2"
		LINENR=$((LINENR+1))
	done < "$1"
}

postfix_compile_maps () {
	MAPS=$(grep -vE "^\s*#.*$" "$1")
	if [ -n "$MAPS" ]; then
		echo "$MAPS" | while IFS= read -r LINE; do
			MAP=$(echo "$LINE" | grep -oE "lmdb:/\S+")
			FILE="$(echo "$MAP" | rev | cut -d':' -f1 | rev)"
			if [ -e "$FILE" ]; then
				POSTMAPARGS=""
				echo "$LINE" | grep -q -e "tls_server_sni_maps" && POSTMAPARGS="${POSTMAPARGS}-F "

				logger "Compile postfix-map with \"postmap ${POSTMAPARGS}${MAP}\""
				postmap "$POSTMAPARGS" "$MAP" || logger "postmap for $MAP failed with exitcode $?" "postmap for $MAP failed"
			else
			    logger "postmap $MAP, file not found!"
			fi
		done
	fi
}

if [ -d "/etc/postfix.template/" ]; then
	echo "Copy config from /etc/postfix.template/ to /etc/postfix/"
	find "/etc/postfix.template/" ! -path "*/..*" ! -type d | while read -r file; do
		targetfile="$(echo "$file" | sed 's#^/etc/postfix.template/#/etc/postfix/#')"
		rm -f "$targetfile"
		install -D -m 0640 "$file" "$targetfile"
	done
	find "/etc/postfix.template/" ! -path "*/..*" -iname "*.cf" ! -type d | while read -r sourcefile; do
		targetfile="$(echo "$sourcefile" | sed 's#^/etc/postfix.template/#/etc/postfix/#')"
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
