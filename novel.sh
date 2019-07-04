#!/usr/bin/env bash

SCRIPT_VERSION='0.1.4'

NOVELS_PER_PAGE='24'
DIR_PREFIX='pixiv_novels/'
COOKIE=""
USER_ID=""

ABORT_WHILE_EMPTY_CONTENT=1
LAZY_TEXT_COUNT=0
NO_SERIES=0

bookmarks=0
novels=()
serieses=()
authors=()

[ -f pixiv-config ] && {
	source pixiv-config
	echo "[info] user specific configuration loaded"
}

declare -A useragent
useragent[desktop]="User-Agent: Mozilla/5.0 (X11; Linux x86_64; rv:67.0) Gecko/20100101 Firefox/67.0"
useragent[mobile]="User-Agent: Mozilla/5.0 (Android 9.0; Mobile; rv:67.0) Gecko/67.0 Firefox/67.0"

sendpost() {
	curl -s "https://www.pixiv.net/$1" -H "${useragent["${2:-desktop}"]}" -H "Accept: application/json" -H 'Accept-Language: en_US,en;q=0.5' --compressed -H 'Referer: https://www.pixiv.net' -H 'DNT: 1' -H "Cookie: ${COOKIE}" -H 'TE: Trailers'
}

ls_novels() {
	local userid="$1"
	local offset=$(( ${NOVELS_PER_PAGE} * ${2} ))
	sendpost "ajax/user/${userid}/novels/bookmarks?tag=&offset=${offset}&limit=${NOVELS_PER_PAGE}&rest=show"
}

ls_novels_by_author() {
	local userid="$1"
	local page="${2:-0}"
	sendpost "touch/ajax/user/novels?id=${userid}&p=${page}" mobile
}

get_novel() {
	local novelid="$1"
	sendpost "ajax/novel/${novelid}"
}

parsehdr() {
	local tmp

	tmp=`jq -e .isSucceed <<< "$1"`
	if [ "$?" = '0' ]; then
		if [ "$tmp" != "true" ]; then
			echo "[error] error detected when parsing hdr (mobile mode)"
			return 1
		fi
	else
		tmp=`jq .error <<< "$1"`
		if [ "$tmp" = "true" -o "$?" != "0" ]; then
			tmp=`echo "$1" | jq .message`
			echo "[error] error detected when parsing hdr, server respond: $tmp"
			return 1
		fi
	fi

	return 0
}

parsenovelmetamobile() {
	declare -n  __meta="$2"
	__meta[id]=`echo "$1" | jq '.id | tonumber'`
	__meta[title]=`echo "$1" | jq -r '.title'`
	__meta[author]=`echo "$1" | jq -r '.user_name'`
	__meta[authorid]=`echo "$1" | jq '.user_id | tonumber'`
	__meta[text_count]=`echo "$1" | jq '.text_length'`

	local tmp=`echo "$1" | jq '.series'`
	if [ "$tmp" = 'null' ]; then
		__meta[series]=''
	else
		__meta[series]=`echo "$1" | jq '.series.id | tonumber'`
		__meta[series_name]=`echo "$1" | jq -r '.series.title'`
	fi
}

parsenovelmeta() {
	declare -n  __meta="$2"
	__meta[id]=`echo "$1" | jq '.id | tonumber'`
	__meta[title]=`echo "$1" | jq -r '.title'`
	__meta[author]=`echo "$1" | jq -r '.userName'`
	__meta[authorid]=`echo "$1" | jq '.userId | tonumber'`
	__meta[text_count]=`echo "$1" | jq '.textCount'`

	local tmp=`echo "$1" | jq '.seriesId'`
	if [ "$tmp" = 'null' ]; then
		__meta[series]=''
	else
		__meta[series]=`echo "$1" | jq '.seriesId | tonumber'`
		__meta[series_name]=`echo "$1" | jq -r '.seriesTitle'`
	fi
}

parsenovel() {
	declare -n  __data="$2"
	__data[content]=`echo "$1" | jq -r '.content'`
	__data[date]=`echo "$1" | jq -r '.uploadDate'`
}

usage() {
	cat <<EOF
Pixiv novel saver
Copyright thdaemon <thxdaemon@gmail.com>

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 3 of the License , or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.
You should have received a copy of the GNU General Public License
along with this program.

usage: $1 [OPTIONS]

MISC OPTIONS:
  -c, --lazy-text-count    Do not re-download novel when same text count
                           (May lose updates, but should be rare)
                           (For series, pixiv can give us a timestamp, lazy
                           mode enabled always and won't use textCount)
  -d, --no-series          Save novel to author's directory, no series subdir
  -o, --output <DIR>       default: 'pixiv_novels/'
  -E, --ignore-empty       Do not stop while meeting a empty content
  -w, --window-size <NPP>  default: 24, how many items per page
                           (Not available in --save-author)
  --strip-nonascii-title   Strip non-ASCII title characters (not impl)
  --download-inline-image   (not impl)
  --parse-pixiv-chapters    (not impl)

SOURCE OPTIONS:
  -m, --save-my-bookmarks  Save all my bookmarked novels
  -a, --save-novel <ID>    (Can be specified multiple times)
                           Save a novel by ID  (not impl)
  -s, --save-series <ID>   (Can be specified multiple times)
                           Save all public novels in a series by ID (not impl)
  -A, --save-author <ID>   (Can be specified multiple times)
                           Save all public novels by a author (not impl)

EXAMPLES:
	$1 -c -m
	$1 -c -m -d
	$1 -c -m -a ID -s ID -s ID -s ID -E
	$1 -c -a ID -A ID -A ID -o some_dir
EOF
}

download_novel() {
	local sdir="$1"
	declare -n  meta="$2"

	local ignore flags series_dir dir old_text_count tmp

	ignore='0'
	flags='N'
	series_dir=''

	if [ "${NO_SERIES}" = '0' ]; then
		if [ -z "${meta[series]}" ]; then
			series_dir=""
		else
			series_dir="/${meta[series]}-${meta[series_name]}"
			flags="${flags}S"
		fi
	fi

	dir="${DIR_PREFIX}/${sdir}/${meta[authorid]}-${meta[author]}${series_dir}/"
	if [ -f "${dir}/${meta[id]}-v1.nmeta" ]; then
		old_text_count=`cat "${dir}/${meta[id]}-v1.nmeta" | jq -e .textCount`
		[ "$?" != '0' ] && old_text_count=`cat "${dir}/${meta[id]}-v1.nmeta" | jq -e .text_length`

		if [ "$old_text_count" = "${meta[text_count]}" -a "$LAZY_TEXT_COUNT" = '1' ]; then
			flags="${flags}I"
			ignore=1
		else
			flags="${flags}U"
		fi
	fi

	echo "=> ${flags}  ${meta[id]} '${meta[title]}' ${meta[author]}"

	if [ "$ignore" = '0' ]; then
		tmp=`get_novel ${meta[id]}`
		parsehdr "$tmp" || exit 1
		tmp=`echo "$tmp" | jq .body`

		declare -A novel
		parsenovel "$tmp" novel

		if [ -z "${novel[content]}" ]; then
			echo "[warning] empty novel content detected, but server responed a success hdr."
			[ "$ABORT_WHILE_EMPTY_CONTENT" = '1' ] && exit 1
		fi

		mkdir -p "$dir"
		echo "${novel[content]}" > "${dir}/${meta[id]}-${meta[title]}-${novel[date]}.txt"
		echo "$metastr" > "${dir}/${meta[id]}-v1.nmeta"
	fi
}

save_author() {
	local id="$1"
	local page_nember=''
	local page_cur='1'

	local novels works works_length

	while true ; do
		novels=`ls_novels_by_author "$id" "$page_cur"`
		parsehdr "$novels" || exit 1

		[ -z "$page_nember" ] && page_nember=`jq .lastPage <<< "$novels"`

		works=`jq .novels <<< "$novels"`
		works_length=`jq '. | length' <<< "$works"`

		echo "[info] page: $page_cur/$page_nember, in this page: ${works_length}"

		for i in `seq 0 $(( $works_length - 1 ))` ; do
			metastr=`echo "$works" | jq .[${i}]`
			declare -A novel_meta
			parsenovelmetamobile "$metastr" novel_meta
			download_novel "by-author" novel_meta
		done

		page_cur=$(( $page_cur + 1 ))
		[ "$page_cur" -gt "$page_nember" ] && break
	done
}

save_my_bookmarks() {
	local page='0'
	local total=''

	local data works works_length tmp metastr

	while true ; do
		data=`ls_novels "${USER_ID}" "$page"`
		parsehdr "$data" || exit 1

		[ -z "$total" ] && total=`echo "$data" | jq .body.total`

		works=`echo "$data" | jq .body.works`
		works_length=`echo "$works" | jq '. | length'`

		echo "[info] total: ${total}, processing page: ${page}, in this page: ${works_length}"

		for i in `seq 0 $(( $works_length - 1 ))` ; do
			metastr=`echo "$works" | jq .[${i}]`
			declare -A novel_meta
			parsenovelmeta "$metastr" novel_meta
			download_novel "bookmarks/$USER_ID/" novel_meta
		done

		page=$(( $page + 1 ))
		tmp=$(( $page * $NOVELS_PER_PAGE ))
		[ "$tmp" -ge "$total" ] && break
	done
}

while [ "$#" -gt 0 ]; do
	case "$1" in
	-c|--lazy-text-count)
		LAZY_TEXT_COUNT=1
		;;
	-d|--no-series)
		NO_SERIES=1
		;;
	-o|--output)
		DIR_PREFIX="$2"
		shift
		;;
	-E|--ignore-empty)
		ABORT_WHILE_EMPTY_CONTENT=0
		;;
	-w|--window-size)
		NOVELS_PER_PAGE="$2"
		shift
		;;
	-m|--save-my-bookmarks)
		bookmarks=1
		;;
	-a|--save-novel)
		novels[${#novels[@]}]="$2"
		shift
		;;
	-s|--save-series)
		seriesesp[${#serieses[@]}]="$2"
		shift
		;;
	-A|--save-author)
		authors[${#authors[@]}]="$2"
		shift
		;;
	-h|*)
		usage "$0"
		exit
		;;
	--)
		break
		;;
	esac
	shift
done

[ "$bookmarks" = '1' ] && {
	echo "[info] saving my bookmarked novels..."
	save_my_bookmarks
}

[ "${#authors[@]}" = '0' ] || {
	echo "[info] saving novels by author..."
	for i in "${authors[@]}"; do
		echo "[info] starting to save novels of author whose ID is ${i}"
		save_author "${i}"
	done
}
