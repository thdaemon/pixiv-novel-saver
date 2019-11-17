#!/usr/bin/env bash

DEBUG="${PIXIV_NOVEL_SAVER_DEBUG:-0}"

SCRIPT_VERSION='0.2.5'

NOVELS_PER_PAGE='24'
DIR_PREFIX='pvnovels/'
COOKIE=""
USER_ID=""

ABORT_WHILE_EMPTY_CONTENT=1
LAZY_TEXT_COUNT=0
NO_LAZY_UNCON=0
NO_SERIES=0

bookmarks=0
private=0
novels=()
serieses=()
authors=()

[ -f pixiv-config ] && {
	source pixiv-config
	echo "[info] user specific configuration loaded"
}

declare -A useragent
useragent[desktop]="User-Agent: Mozilla/5.0 (X11; Linux x86_64; rv:70.0) Gecko/20100101 Firefox/70.0"
useragent[mobile]="User-Agent: Mozilla/5.0 (Android 9.0; Mobile; rv:68.0) Gecko/68.0 Firefox/68.0"

dbg() {
	[ "$DEBUG" = '1' ]
}

printdbg() {
	echo "$*" >&2
}

__sendpost() {
	curl --compressed -s "https://www.pixiv.net/$1" \
		-H "${useragent["${2:-desktop}"]}" \
		-H "Accept: application/json" \
		-H 'Accept-Language: en_US,en;q=0.5' \
		-H 'Referer: https://www.pixiv.net' \
		-H 'DNT: 1' \
		-H "Cookie: ${COOKIE}" \
		-H 'TE: Trailers'
}

sendpost() {
	dbg && printdbg "> $1"
	resp=`__sendpost "$@"`
	dbg && printdbg "$resp" && echo
	echo "$resp"
}

json_has() {
	jq -e "has(\"${2}\")" <<< "$1" > /dev/null
}

json_get_object() {
	declare -n  __msg="${3}"
	__msg=`jq -e ".${2} // empty" <<< "${1}"`
}

json_get_string() {
	declare -n  __msg="${3}"
	__msg=`jq -e -r ".${2} // empty" <<< "${1}"`
}

json_get_integer() {
	declare -n  __msg="${3}"
	__msg=`jq ".${2} | tonumber" <<< "${1}"`
}

json_is_true() {
	jq -e ".${2}" <<< "${1}" > /dev/null
}

json_array_n_items() {
	jq ".${2} | length" <<< "${1}"
}

json_array_get_item() {
	declare -n  __msg_="${3}"
	json_get_object "${1}" "[${2}]" __msg_
}

pixiv_error=''

__pixiv_parsehdr() {
	local tmp
	declare -n  __msg="$2"

	if json_has "$1" error ; then
		if json_is_true "$1" error ; then
			__msg="server error"
			json_get_string "$1" message tmp
			[ -n "$tmp" ] && __msg="server respond: $tmp"
			return 1
		fi
	else
		__msg="network error"
		return 1
	fi
	return 0
}

__pixiv_parsehdr_mobile() {
	local tmp
	declare -n  __msg="$2"

	if json_has "$1" isSucceed ; then
		if ! json_is_true "$1" isSucceed ; then
			__msg="server error (mobile mode)"
			return 1
		fi
	else
		__msg="network error"
		return 1
	fi
	return 0
}

## pixiv_errquit
#    name - the name of "subprogram" which throw a error
pixiv_errquit() {
	echo "[error] ${1}: ${pixiv_error}"
	exit 1
}

## pixiv_get_user_info
#    userid - the ID of the user
#    __meta - a pointer to recv info of the user
pixiv_get_user_info() {
	local userid="$1"
	declare -n  __meta="$2"

	local tmp

	tmp=`sendpost "ajax/user/${userid}?full=0"`
	__pixiv_parsehdr "$tmp" pixiv_error || return 1

	__meta[id]="$userid"
	json_get_string "$tmp" body.name       __meta[name]
	json_get_object "$tmp" body.isFollowed __meta[followed]
	json_get_object "$tmp" body.isMypixiv  __meta[my]
	return 0
}

## pixiv_get_series_info
#    seriesid - the ID of the series
#    __meta - a pointer to recv info of the series
pixiv_get_series_info() {
	local seriesid="$1"
	declare -n  __meta="$2"

	local tmp

	tmp=`sendpost "ajax/novel/series/${seriesid}"`
	__pixiv_parsehdr "$tmp" pixiv_error || return 1

	json_get_integer "$tmp" body.userId                    __meta[authorid]
	json_get_integer "$tmp" body.displaySeriesContentCount __meta[total]
	json_get_string "$tmp"  body.title                     __meta[title]
	return 0
}

## pixiv_list_novels_by_bookmarks
#    userid - save bookmarks from this user.
#    offset - from 0, the page offset.
#    rest - 'show' for public novels or 'hide' for private novels
#    __novels - a pointer to recv novels list for this page
#    __total - a pointer to recv total number of novels (only when offset==0)
pixiv_list_novels_by_bookmarks() {
	local userid="$1"
	local offset=$(( ${NOVELS_PER_PAGE} * ${2} ))
	local rest="${3:-show}"
	declare -n  __novels="$4"
	declare -n  __total="$5"

	local tmp

	tmp=`sendpost "ajax/user/${userid}/novels/bookmarks?tag=&offset=${offset}&limit=${NOVELS_PER_PAGE}&rest=${rest}"`
	__pixiv_parsehdr "$tmp" pixiv_error || return 1

	json_get_object "$tmp" body.works __novels
	[ "$offset" = "0" ] && json_get_integer "$tmp" body.total __total
	return 0
}

## pixiv_list_novels_by_author
#    userid - author userid
#    page - the page number, from 0.
#    __novels - a pointer to recv novels list for this page
#    __page_number - a pointer to recv total number of novels (only when page==0)
pixiv_list_novels_by_author() {
	local userid="$1"
	local page="${2}"
	declare -n  __novels="$3"
	declare -n  __page_number="$4"

	local tmp

	tmp=`sendpost "touch/ajax/user/novels?id=${userid}&p=${page}" mobile`
	__pixiv_parsehdr_mobile "$tmp" pixiv_error || return 1

	json_get_object "$tmp" novels __novels
	[ "$page" = "1" ] && json_get_integer "$tmp" lastPage __page_number
	return 0
}

## pixiv_list_novels_by_bookmarks
#    seriesid - the series ID
#    offset - from 0, the page offset.
#    __novels - a pointer to recv novels list for this page
pixiv_list_novels_by_series() {
	local seriesid="$1"
	local offset=$(( ${NOVELS_PER_PAGE} * ${2} ))
	declare -n  __novels="$3"

	local tmp

	tmp=`sendpost "ajax/novel/series_content/${seriesid}?limit=${NOVELS_PER_PAGE}&last_order=${offset}&order_by=asc"`
	__pixiv_parsehdr "$tmp" pixiv_error || return 1

	json_get_object "$tmp" body.seriesContents __novels
	return 0
}

## pixiv_get_novel
#    novelid - the ID of the novel
#    __novel - a pointer to recv novel content
#    __meta (optional) - a pointer to recv some novel infomation
pixiv_get_novel() {
	local novelid="$1"
	declare -n  __novel="$2"

	local tmp

	tmp=`sendpost "ajax/novel/${novelid}"`
	__pixiv_parsehdr "$tmp" pixiv_error || return 1

	json_get_string "$tmp" body.content __novel

	if [ -n "$3" ]; then
		declare -n __meta="$3"
		json_get_string "$tmp"  body.uploadDate  __meta[uploadDate]
		json_get_integer "$tmp" body.id          __meta[id]
		json_get_string "$tmp"  body.title       __meta[title]
		json_get_string "$tmp"  body.userName    __meta[author]
		json_get_integer "$tmp" body.userId      __meta[authorid]
		json_get_string "$tmp"  body.description __meta[description]
		if json_has "$tmp" body.seriesNavData ; then
			json_get_integer "$tmp" body.seriesNavData.seriesId __meta[series]
			json_get_string "$tmp"  body.seriesNavData.title    __meta[series_name]
		fi
	fi

	return 0
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
  -o, --output <DIR>       default: 'pvnovels/'
  -E, --ignore-empty       Do not stop while meeting a empty content
  -w, --window-size <NPP>  default: 24, how many items per page
                             (Not available in --save-author and --save-novel)
  -u, --disable-lazy-mode  Disable all lazy modes unconditionally
  --strip-nonascii-title   Strip non-ASCII title characters (not impl)
  --download-cover-image   (not impl)
  --download-inline-image  (not impl)
  --parse-pixiv-chapters   (not impl)

SOURCE OPTIONS:
  -m, --save-my-bookmarks  Save all my bookmarked novels
                             Lazy mode: text count (enable it by -c)
  -p, --save-my-private    Save all my private bookmarked novels
                             Lazy mode: text count (enable it by -c)
  -a, --save-novel <ID>    Save a novel by its ID
                             Lazy mode: never (not supported)
                             Can be specified multiple times
  -s, --save-series <ID>   Save all public novels in a series by ID
                             Lazy mode: always (full supported, disable by -u)
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

## write_file_atom
#    filename - file name
#    __kvpair - pointer to a key-value pair to write
#    content - the content to write
write_file_atom() {
	local filename_real="$1"
	declare -n __kv="$2"
	local content="$3"

	local filename="${filename_real}.tmp"

	mkdir -p "`dirname "${filename_real}"`"
	cat /dev/null > "${filename}"
	for i in "${!__kv[@]}"; do
		echo "${i}: ${__kv[$i]}" >> "${filename}"
	done
	echo "=============================" >> "${filename}"
	echo "${content}" >> "${filename}"

	mv "${filename}" "${filename_real}"
}

## download_novel
#    subdir - the subdir name
#    meta - pointer to novel_meta associative array
#    lazymode - 'always', 'textcount' or 'disable'
#    lazytag - add a tag to filename for lazy mode
#    extra_flags - append extra flag
download_novel() {
	local sdir="$1"
	declare -n  meta="$2"
	local lazymode="$3"
	local lazytag="$4"
	local flags="N${5}"
	local flag_pad="    "
	local flag_max_len=4
	local ignore='0'

	local series_dir filename novel
	declare -A nmeta

	if [ "${NO_SERIES}" = '0' ]; then
		if [ -z "${meta[series]}" ]; then
			series_dir=""
		else
			series_dir="/${meta[series]}-${meta[series_name]}"
			flags="${flags}S"
		fi
	fi

	filename="${DIR_PREFIX}/${sdir}/${meta[authorid]}-${meta[author]}${series_dir}/${meta[id]}-${meta[title]}${lazytag}.txt"
	[ -n "$lazytag" -a -f "${filename}" ] && ignore=1

	case "$lazymode" in
	always) ;;
	textcount) [ "$LAZY_TEXT_COUNT" = '1' ] || ignore='0' ;;
	*) ignore='0' ;;
	esac

	[ "$NO_LAZY_UNCON" = '1' ] && ignore='0'

	[ "$ignore" = '1' ] && flags="${flags}I"

	flags="${flags}${flag_pad}"
	echo "=> ${flags:0:${flag_max_len}} ${meta[id]} '${meta[title]}' ${meta[author]}"

	if [ "$ignore" = '0' ]; then
		pixiv_get_novel "${meta[id]}" novel nmeta || pixiv_errquit pixiv_get_novel
		if [ -z "${novel}" ]; then
			echo "[warning] empty novel content detected, but server responed a success hdr."
			[ "$ABORT_WHILE_EMPTY_CONTENT" = '1' ] && exit 1
		fi

		for i in "${!nmeta[@]}"; do
			[ -z "${meta[$i]}" ] && meta[$i]="${nmeta[$i]}"
		done

		write_file_atom "$filename" meta "$novel"
	fi
}

## save_id
#    id - the novel ID
save_id() {
	local id="$1"
	local flags='N'
	local flag_pad="    "
	local flag_max_len=4

	local series_dir filename content
	declare -A meta

	pixiv_get_novel "$id" content meta || pixiv_errquit pixiv_get_novel
	if [ "${NO_SERIES}" = '0' ]; then
		if [ -z "${meta[series]}" ]; then
			series_dir=""
		else
			series_dir="/${meta[series]}-${meta[series_name]}"
			flags="${flags}S"
		fi
	fi

	filename="${DIR_PREFIX}/singles/${meta[authorid]}-${meta[author]}${series_dir}/${meta[id]}-${meta[title]}.txt"

	flags="${flags}${flag_pad}"
	echo "=> ${flags:0:${flag_max_len}} ${meta[id]} '${meta[title]}' ${meta[author]}"

	if [ -z "$content" ]; then
		echo "[warning] empty novel content detected, but server responed a success hdr."
		[ "$ABORT_WHILE_EMPTY_CONTENT" = '1' ] && exit 1
	fi

	write_file_atom "$filename" meta "$content"
}

save_my_bookmarks() {
	local page='0'
	local total=''
	local suffix=''
	local rest="$1"

	local works works_length tmp

	[ "$rest" = 'show' ] || suffix="-$rest"

	while true ; do
		pixiv_list_novels_by_bookmarks "${USER_ID}" "$page" "$rest" works total || pixiv_errquit pixiv_list_novels_by_bookmarks
		works_length=`json_array_n_items "$works"`

		echo "[info] total: ${total}, processing page: ${page}, in this page: ${works_length}"

		for i in `seq 0 $(( $works_length - 1 ))` ; do
			json_array_get_item "$works" "$i" tmp

			unset novel_meta
			declare -A novel_meta

			json_get_integer "$tmp" id        novel_meta[id]
			json_get_string "$tmp"  title     novel_meta[title]
			json_get_string "$tmp"  userName  novel_meta[author]
			json_get_integer "$tmp" userId    novel_meta[authorid]
			json_get_integer "$tmp" textCount novel_meta[text_count]

			if json_has "$tmp" seriesId ; then
				json_get_integer "$tmp" seriesId    novel_meta[series]
				json_get_string "$tmp"  seriesTitle novel_meta[series_name]
			fi

			tmp=''
			[ -n "${novel_meta[text_count]}" ] && tmp="-tc${novel_meta[text_count]}"
			download_novel "bookmarks/${USER_ID}${suffix}/" novel_meta textcount "${tmp}"
		done

		page=$(( $page + 1 ))
		tmp=$(( $page * $NOVELS_PER_PAGE ))
		[ "$tmp" -ge "$total" ] && break
	done
}

save_author() {
	local id="$1"
	local page_cur='1'

	local works works_length page_nember tmp

	while true ; do
		pixiv_list_novels_by_author "$id" "$page_cur" works page_nember || pixiv_errquit pixiv_list_novels_by_author
		works_length=`json_array_n_items "$works"`

		echo "[info] page: $page_cur/$page_nember, in this page: ${works_length}"

		for i in `seq 0 $(( $works_length - 1 ))` ; do
			json_array_get_item "$works" "$i" tmp

			unset novel_meta
			declare -A novel_meta

			json_get_integer "$tmp" id          novel_meta[id]
			json_get_string "$tmp"  title       novel_meta[title]
			json_get_string "$tmp"  user_name   novel_meta[author]
			json_get_integer "$tmp" user_id     novel_meta[authorid]
			json_get_integer "$tmp" text_length novel_meta[text_count]

			if json_has "$tmp" series ; then
				json_get_integer "$tmp" series.id    novel_meta[series]
				json_get_string "$tmp"  series.title novel_meta[series_name]
			fi

			tmp=''
			[ -n "${novel_meta[text_count]}" ] && tmp="-tc${novel_meta[text_count]}"
			download_novel "by-author" novel_meta textcount "$tmp"
		done

		page_cur=$(( $page_cur + 1 ))
		[ "$page_cur" -gt "$page_nember" ] && break
	done
}

save_series() {
	local id="$1"
	local page='0'

	local novels works_length tmp extra_flags
	declare -A series_info author_info

	pixiv_get_series_info "$id" series_info || pixiv_errquit pixiv_get_series_info
	pixiv_get_user_info "${series_info[authorid]}" author_info || pixiv_errquit pixiv_get_user_info

	echo "[info] series '${series_info[title]}' ($id) by '${author_info[name]}' has ${series_info[total]} novels"

	while true ; do
		pixiv_list_novels_by_series "$id" "$page" novels || pixiv_errquit pixiv_list_novels_by_series
		works_length=`json_array_n_items "$novels"`

		echo "[info] series page: $page, in this page: ${works_length}"

		for i in `seq 0 $(( $works_length - 1 ))` ; do
			json_array_get_item "$novels" "$i" tmp

			unset novel_meta
			declare -A novel_meta

			json_get_integer "$tmp" id                novel_meta[id]
			json_get_string "$tmp"  title             novel_meta[title]
			json_get_integer "$tmp" reuploadTimestamp novel_meta[timestamp]

			novel_meta[series]="$id"
			novel_meta[series_name]="${series_info[title]}"
			novel_meta[author]="${author_info[name]}"
			novel_meta[authorid]="${series_info[authorid]}"

			tmp=''
			extra_flags=''
			if [ -n "${novel_meta[timestamp]}" ]; then
				tmp="-ts${novel_meta[timestamp]}"
				extra_flags='T'
			fi
			download_novel "by-series" novel_meta always "$tmp" "$extra_flags"
		done

		page=$(( $page + 1 ))
		tmp=$(( $page * $NOVELS_PER_PAGE ))
		[ "$tmp" -ge "${series_info[total]}" ] && break
	done
}

while [ "$#" -gt 0 ]; do
	case "$1" in
	-c|--lazy-text-count)
		LAZY_TEXT_COUNT=1
		;;
	-u|--disable-lazy-mode)
		NO_LAZY_UNCON=1
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
	-p|--save-my-private)
		private=1
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
	save_my_bookmarks show
}

[ "$private" = '1' ] && {
	echo "[info] saving my private bookmarked novels..."
	save_my_bookmarks hide
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
