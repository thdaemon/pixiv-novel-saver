#!/usr/bin/env bash

SCRIPT_VERSION='0.1.5'

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
useragent[desktop]="User-Agent: Mozilla/5.0 (X11; Linux x86_64; rv:68.0) Gecko/20100101 Firefox/68.0"
useragent[mobile]="User-Agent: Mozilla/5.0 (Android 9.0; Mobile; rv:68.0) Gecko/68.0 Firefox/68.0"

sendpost() {
	curl -s "https://www.pixiv.net/$1" -H "${useragent["${2:-desktop}"]}" -H "Accept: application/json" -H 'Accept-Language: en_US,en;q=0.5' --compressed -H 'Referer: https://www.pixiv.net' -H 'DNT: 1' -H "Cookie: ${COOKIE}" -H 'TE: Trailers'
}

json_has() {
	jq -e "has(\"${2}\")" <<< "$1" > /dev/null
}

json_get_object() {
	declare -n  __msg="$3"
	__msg=`jq "$2" <<< "$1"`
}

json_get_string() {
	declare -n  __msg="$3"
	__msg=`jq -e -r "$2 // empty" <<< "$1"`
}

json_get_integer() {
	declare -n  __msg="$3"
	__msg=`jq "$2 | tonumber" <<< "$1"`
}

pixiv_error=''

__pixiv_parsehdr() {
	local tmp
	declare -n  __msg="$2"

	if json_has "$1" error ; then
		json_get_object "$1" .error tmp
		if [ "$tmp" = "true" ]; then
			json_get_string "$1" .message tmp
			[ -n "$tmp" ] && __msg="server respond: $tmp"
			return 1
		fi
	else
		__msg="network error"
		return 1
	fi
	return 0
}

pixiv_errquit() {
	echo "[error] ${1}: ${pixiv_error}"
	exit 1
}

pixiv_get_user_info() {
	local userid="$1"
	declare -n  __meta="$2"

	local tmp

	tmp=`sendpost "ajax/user/${userid}?full=0"`
	__pixiv_parsehdr "$tmp" pixiv_error || return 1

	__meta[id]="$userid"
	json_get_string "$tmp" .body.name __meta[name]
	json_get_object "$tmp" .body.isFollowed __meta[followed]
	json_get_object "$tmp" .body.isMypixiv __meta[my]
	return 0
}

# TODO: refactor ugly old pixiv functions implementations

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

get_series_info() {
	local seriesid="$1"
	sendpost "ajax/novel/series/${seriesid}"
}

ls_novels_by_series() {
	local seriesid="$1"
	local offset=$(( ${NOVELS_PER_PAGE} * ${2:-0} ))
	sendpost "ajax/novel/series_content/${seriesid}?limit=${NOVELS_PER_PAGE}&last_order=${offset}&order_by=asc"
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

__pnm_series_try0() {
	declare -n  __meta_="$2"
	local tmp
	tmp=`echo "$1" | jq -e '.seriesId'`
	if [ "$?" = '0' -a "$tmp" != 'null' ]; then
		__meta_[series]=`echo "$1" | jq '.seriesId | tonumber'`
		__meta_[series_name]=`echo "$1" | jq -r '.seriesTitle'`
		return 0
	fi
	return 1
}
__pnm_series_try1() {
	declare -n  __meta_="$2"
	local tmp
	tmp=`echo "$1" | jq -e '.seriesNavData'`
	if [ "$?" = '0' -a "$tmp" != 'null' ]; then
		__meta_[series]=`echo "$tmp" | jq '.seriesId | tonumber'`
		__meta_[series_name]=`echo "$tmp" | jq -r '.title'`
		return 0
	fi
	return 1
}

__pnm_timestamp() {
	declare -n  __meta_="$2"
	local tmp
	tmp=`echo "$1" | jq -e '.reuploadTimestamp'`
	if [ "$?" = '0' -a "$tmp" != 'null' ]; then
		__meta_[timestamp]="$tmp"
		return 0
	fi
	return 1
}

parsenovelmeta() {
	declare -n  __meta="$2"

	__meta[id]=`echo "$1" | jq '.id | tonumber'`
	__meta[title]=`echo "$1" | jq -r '.title'`
	__meta[author]=`echo "$1" | jq -r '.userName'`
	__meta[authorid]=`echo "$1" | jq '.userId | tonumber'`
	__meta[text_count]=`echo "$1" | jq '.textCount'`

	__meta[series]=''
	__pnm_series_try0 "$1" __meta || \
		__pnm_series_try1 "$1" __meta

	__pnm_timestamp "$1" __meta
	return 0
}

parsenovel() {
	declare -n  __data="$2"
	__data[content]=`echo "$1" | jq -r '.content'`
	__data[date]=`echo "$1" | jq -r '.uploadDate'`
}

usage() {
	cat <<EOF
Pixiv novel saver ${SCRIPT_VERSION}
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
                             (Not available in --save-author and --save-novel)
  --strip-nonascii-title   Strip non-ASCII title characters (not impl)
  --download-inline-image  (not impl)
  --parse-pixiv-chapters   (not impl)

SOURCE OPTIONS:
  -m, --save-my-bookmarks  Save all my bookmarked novels
                             Lazy mode: text count (enable it by -c)
  -a, --save-novel <ID>    Save a novel by its ID
                             Lazy mode: never (not supported)
                             Can be specified multiple times
  -s, --save-series <ID>   Save all public novels in a series by ID
                             Lazy mode: always (full supported)
                             Can be specified multiple times
  -A, --save-author <ID>   Save all public novels published by an author
                             Lazy mode: text count (enable it by -c)
                             Can be specified multiple times

EXAMPLES:
	$1 -c -m
	$1 -c -m -d
	$1 -c -m -a ID -s ID -s ID -s ID -E
	$1 -c -a ID -A ID -A ID -o some_dir
EOF
}

download_novel() {
	local flag_pad="     "
	local flag_max_len=5
	local sdir="$1"
	declare -n  meta="$2"

	local ignore flags series_dir dir old_text_count old_ts tmp

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
		if [ -n "${meta[timestamp]}" ]; then
			flags="${flags}T"
			old_ts=`cat "${dir}/${meta[id]}-v1.nmeta" | jq -e .reuploadTimestamp`

			if [ "$old_ts" = "${meta[timestamp]}" ]; then
				flags="${flags}I"
				ignore=1
			else
				flags="${flags}U"
			fi
		else
			old_text_count=`cat "${dir}/${meta[id]}-v1.nmeta" | jq -e .textCount`
			[ "$?" != '0' ] && old_text_count=`cat "${dir}/${meta[id]}-v1.nmeta" | jq -e .text_length`

			if [ "$old_text_count" = "${meta[text_count]}" -a "$LAZY_TEXT_COUNT" = '1' ]; then
				flags="${flags}I"
				ignore=1
			else
				flags="${flags}U"
			fi
		fi
	fi

	flags="${flags}${flag_pad}"
	echo "=> ${flags:0:${flag_max_len}} ${meta[id]} '${meta[title]}' ${meta[author]}"

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

save_id() {
	local id="$1"
	local flags='N'

	local tmp series_dir dir

	tmp=`get_novel ${id}`
	parsehdr "$tmp" || exit 1

	tmp=`echo "$tmp" | jq .body`

	declare -A meta
	declare -A novel
	parsenovelmeta "$tmp" meta
	parsenovel "$tmp" novel

	if [ "${NO_SERIES}" = '0' ]; then
		if [ -z "${meta[series]}" ]; then
			series_dir=""
		else
			series_dir="/${meta[series]}-${meta[series_name]}"
			flags="${flags}S"
		fi
	fi
	dir="${DIR_PREFIX}/singles/${meta[authorid]}-${meta[author]}${series_dir}/"

	echo "=> ${flags}  ${meta[id]} '${meta[title]}' ${meta[author]}"

	if [ -z "${novel[content]}" ]; then
		echo "[warning] empty novel content detected, but server responed a success hdr."
		[ "$ABORT_WHILE_EMPTY_CONTENT" = '1' ] && exit 1
	fi

	mkdir -p "$dir"
	echo "${novel[content]}" > "${dir}/${meta[id]}-${meta[title]}-${novel[date]}.txt"
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

save_series() {
	local id="$1"
	local page='0'

	local novels works_length tmp total title authorid
	declare -A author_info

	tmp=`get_series_info "$id"`
	parsehdr "$tmp" || exit 1

	authorid=`jq -r .body.userId <<< "$tmp"`
	total=`jq .body.displaySeriesContentCount <<< "$tmp"`
	title=`jq -r .body.title <<< "$tmp"`

	pixiv_get_user_info "$authorid" author_info || pixiv_errquit pixiv_get_user_info

	echo "[info] series '${title}' ($id) by '${author_info[name]}' has $total novels"

	while true ; do
		novels=`ls_novels_by_series "$id" "$page"`
		parsehdr "$novels" || exit 1

		novels=`jq .body.seriesContents	<<< "$novels"`
		works_length=`jq '. | length' <<< "$novels"`

		echo "[info] series page: $page, in this page: ${works_length}"

		for i in `seq 0 $(( $works_length - 1 ))` ; do
			metastr=`echo "$novels" | jq .[${i}]`
			declare -A novel_meta
			parsenovelmeta "$metastr" novel_meta
			novel_meta[series]="$id"
			novel_meta[series_name]="$title"
			novel_meta[author]="${author_info[name]}"
			novel_meta[authorid]="$authorid"
			download_novel "by-series" novel_meta
		done

		page=$(( $page + 1 ))
		tmp=$(( $page * $NOVELS_PER_PAGE ))
		[ "$tmp" -ge "$total" ] && break
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
		serieses[${#serieses[@]}]="$2"
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

[ "${#novels[@]}" = '0' ] || {
	echo "[info] saving novels by ID..."
	for i in "${novels[@]}"; do
		save_id "${i}"
	done
}

[ "${#authors[@]}" = '0' ] || {
	echo "[info] saving novels by author..."
	for i in "${authors[@]}"; do
		echo "[info] starting to save novels of author whose ID is ${i}"
		save_author "${i}"
	done
}

[ "${#serieses[@]}" = '0' ] || {
	echo "[info] saving novels by series..."
	for i in "${serieses[@]}"; do
		echo "[info] starting to save novels from series ID ${i}"
		save_series "${i}"
	done
}
