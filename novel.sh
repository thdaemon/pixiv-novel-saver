#!/usr/bin/env bash

NOVELS_PER_PAGE='24'
DIR_PREFIX='pixiv_novels/'
COOKIE=""
USER_ID=""
ABORT_WHILE_EMPTY_CONTENT=0

[ -f pixiv-config ] && {
	source pixiv-config
	echo "[info] user specific configuration loaded"
}

sendpost() {
	curl -s "https://www.pixiv.net/$1" -H "User-Agent: Mozilla/5.0 (X11; Linux x86_64; rv:67.0) Gecko/20100101 Firefox/67.0" -H "Accept: application/json" -H 'Accept-Language: en_US,en;q=0.5' --compressed -H 'Referer: https://www.pixiv.net' -H 'DNT: 1' -H "Cookie: ${COOKIE}" -H 'TE: Trailers'
}

ls_novels() {
	local userid="$1"
	local offset=$(( ${NOVELS_PER_PAGE} * ${2} ))
	sendpost "ajax/user/${userid}/novels/bookmarks?tag=&offset=${offset}&limit=${NOVELS_PER_PAGE}&rest=show"
}

get_novel() {
	local novelid="$1"
	sendpost "ajax/novel/${novelid}"
}

parsehdr() {
	local tmp=`echo "$1" | jq .error`
	if [ "$tmp" = "true" -o "$?" != "0" ]; then
		tmp=`echo "$1" | jq .message`
		echo "[error] error detected when parsing hdr, server respond: $tmp"
		return 1
	fi
	return 0
}

parsenovelmeta() {
	declare -n  __meta="$2"
	__meta[id]=`echo "$1" | jq '.id | tonumber'`
	__meta[title]="`echo "$1" | jq -r '.title'`"
	__meta[author]="`echo "$1" | jq -r '.userName'`"
	__meta[authorid]="`echo "$1" | jq '.userId | tonumber'`"
	__meta[desc]="`echo "$1" | jq -r '.description'`"
}

parsenovel() {
	declare -n  __data="$2"
	__data[content]=`echo "$1" | jq -r '.content'`
	__data[date]=`echo "$1" | jq -r '.uploadDate'`
}

page='0'
total=''
while true ; do
	data=`ls_novels "${USER_ID}" "$page"`
	parsehdr "$data" || exit 1

	[ -z "$total" ] && total=`echo "$data" | jq .body.total`

	works=`echo "$data" | jq .body.works`
	works_length=`echo "$works" | jq '. | length'`

	echo "[info] total: ${total}, processing page: ${page}, in this page: ${works_length}"

	for i in `seq 0 $(( $works_length - 1 ))` ; do
		tmp=`echo "$works" | jq .[${i}]`
		declare -A meta
		parsenovelmeta "$tmp" meta
		echo "=> ${meta[title]}  ${meta[id]}  ${meta[author]}"

		tmp=`get_novel ${meta[id]}`
		parsehdr "$tmp" || exit 1
		tmp=`echo "$tmp" | jq .body`

		declare -A novel
		parsenovel "$tmp" novel

		if [ -z "${novel[content]}" ]; then
			echo "[warning] empty novel content detected, but server responed a success hdr."
			[ "$ABORT_WHILE_EMPTY_CONTENT" = '1' ] && exit 1
		fi

		mkdir -p "${DIR_PREFIX}/${meta[author]}/"
		echo "${novel[content]}" > "${DIR_PREFIX}/${meta[author]}/${meta[id]}-${meta[title]}-${novel[date]}.txt"
	done

	page=$(( $page + 1 ))
	tmp=$(( $page * $NOVELS_PER_PAGE ))
	[ "$tmp" -ge "$total" ] && break
done
