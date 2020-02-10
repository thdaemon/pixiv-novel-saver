#!/usr/bin/env bash

DEBUG="${PIXIV_NOVEL_SAVER_DEBUG:-0}"

SCRIPT_VERSION='0.2.15'

NOVELS_PER_PAGE='24'
DIR_PREFIX='pvnovels/'
COOKIE=""
USER_ID=""

ABORT_WHILE_EMPTY_CONTENT=1
LAZY_TEXT_COUNT=0
NO_LAZY_UNCON=0
RENAMING_DETECT=1
NO_SERIES=0
WITH_COVER_IMAGE=0

bookmarks=0
private=0
novels=()
serieses=()
authors=()

post_command=''
post_command_ignored=''

declare -A useragent
useragent[desktop]="User-Agent: Mozilla/5.0 (X11; Linux x86_64; rv:72.0) Gecko/20100101 Firefox/72.0"
useragent[mobile]="User-Agent: Mozilla/5.0 (Android 9.0; Mobile; rv:68.0) Gecko/68.0 Firefox/68.0"

EXTRA_CURL_OPTIONS=()

_slash_replace_to=_
_max_flag_len=5
_max_id_len=9

append_to_array() {
	declare -n __arr="$1"
	shift
	for i in "$@"; do
		__arr[${#__arr[@]}]="$i"
	done
}

dbg() {
	[ "$DEBUG" = '1' ]
}

printdbg() {
	echo "[debug] $*" >&2
}

__sendpost() {
	curl --compressed -s "${EXTRA_CURL_OPTIONS[@]}" "$1" \
		-H "${useragent["${2:-desktop}"]}" \
		-H "Accept: application/json" \
		-H 'Accept-Language: en_US,en;q=0.5' \
		-H 'Referer: https://www.pixiv.net' \
		-H 'DNT: 1' \
		-H "Cookie: ${COOKIE}" \
		-H 'TE: Trailers'
}

sendpost() {
	local uri="https://www.pixiv.net/$1"
	dbg && printdbg "> $1"
	shift

	resp=`__sendpost "$uri" "$@"`

	dbg && echo "$resp" | jq >&2
	echo "$resp"
}

json_has() {
	jq -e "has(\"${2}\")" <<< "$1" > /dev/null
}

json_has_path() {
	jq -e ".${2} | has(\"${3}\")" <<< "$1" > /dev/null
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

json_get_booleanstring() {
	local __tmp
	declare -n  __msg="${5}"
	json_get_object "${1}" "${2}" __tmp
	[ "$__tmp" = 'true' ] && __msg="${3}" || __msg="${4}"
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

errquit() {
	echo "[error] $1"
	exit 1
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

# It seems at least some pixiv.net mobile version API HAVE NOT USE isSucceed now....
# Now comment the __pixiv_parsehdr_mobile because nobody use it.
#__pixiv_parsehdr_mobile() {
#	local tmp
#	declare -n  __msg="$2"
#
#	if json_has "$1" isSucceed ; then
#		if ! json_is_true "$1" isSucceed ; then
#			__msg="server error (mobile mode)"
#			return 1
#		fi
#	else
#		__msg="network error (mobile mode)"
#		return 1
#	fi
#	return 0
#}

## pixiv_errquit
#    name - the name of "subprogram" which throw a error
pixiv_errquit() {
	errquit "${1}: ${pixiv_error}"
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
	__pixiv_parsehdr "$tmp" pixiv_error || return 1

	json_get_object "$tmp" body.novels __novels
	[ "$page" = "1" ] && json_get_integer "$tmp" body.lastPage __page_number
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

	local tmp tags ntags tag tagval tagmeta

	tmp=`sendpost "ajax/novel/${novelid}"`
	__pixiv_parsehdr "$tmp" pixiv_error || return 1

	json_get_object "$tmp" body tmp
	json_get_string "$tmp" content __novel

	__novel=`sed 's/\r*$//g' <<< "$__novel"`

	if [ -n "$3" ]; then
		declare -n __meta="$3"
		json_get_string "$tmp"  uploadDate  __meta[uploadDate]
		json_get_string "$tmp"  createDate  __meta[createDate]
		json_get_integer "$tmp" id          __meta[id]
		json_get_string "$tmp"  title       __meta[title]
		json_get_string "$tmp"  userName    __meta[author]
		json_get_integer "$tmp" userId      __meta[authorid]
		json_get_string "$tmp"  description __meta[description]
		json_get_string "$tmp"  coverUrl    __meta[_cover_image_uri]
		json_get_booleanstring "$tmp" isOriginal yes no __meta[original]

		if json_has "$tmp" tags ; then
			tagmeta=''

			json_get_object "$tmp" tags.tags tags
			ntags=`json_array_n_items "$tags"`
			for i in `seq 0 $(( ${ntags} - 1 ))`; do
				json_array_get_item "$tags" "$i" tag
				json_get_string "$tag" tag tagval
				tagmeta="${tagmeta}${tagval}, "
			done

			__meta[tags]="${tagmeta%, }"
		fi

		if json_has_path "$tmp" seriesNavData seriesId ; then
			json_get_integer "$tmp" seriesNavData.seriesId __meta[series]
			json_get_string "$tmp"  seriesNavData.title    __meta[series_name]
		fi
	fi

	return 0
}

## pixiv_get_illust_url_original
#    id - the id of the illust
#    __url - a pointer to recv url string
pixiv_get_illust_url_original() {
	local id="$1"
	declare -n  __url="$2"

	local tmp

	tmp=`sendpost "ajax/illust/${id}/pages"`
	__pixiv_parsehdr "$tmp" pixiv_error || return 1

	json_get_string "$tmp" body[0].urls.original __url
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
  -R, --no-renaming-detect Do not detect author/series renaming
  --strip-nonascii-title   Strip non-ASCII title characters (not impl)
  --with-cover-image       Download the cover image of novels only if the image
                             is NOT a common cpver image
  --with-inline-image      (not impl)
  --parse-pixiv-chapters   (not impl)
  -e, --hook "<command>" Run 'cmd "\$filename"' for each downloaded novel
                             (note: the tmp file will be renamed after hook)
  --ignored-post-hook "<command>"
                           Run 'cmd "\$filename"' for each ignored novel

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

## trick_meta
#    __meta - pointer to a key-value pair
#  after trick_meta, all '/' in __meta[title], __meta[series_name], etc will be replaced.
trick_meta() {
	declare -n __meta="$1"
	[ -n "${__meta[title]}" ] && __meta[title]=`echo "${__meta[title]}" | tr '/' $_slash_replace_to`
	[ -n "${__meta[series_name]}" ] && __meta[series_name]=`echo "${__meta[series_name]}" | tr '/' $_slash_replace_to`
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

	mkdir -p "`dirname "${filename_real}"`" || errquit "write_file_atom: command failed"

	cat > "${filename}" <<EOF
Saved by pixiv-novel-saver version ${SCRIPT_VERSION} (${SCRIPT_RT_OSNAME})
At ${START_DATE}
https://github.com/thdaemon/pixiv-novel-saver

EOF
	[ "$?" = '0' ] || errquit "write_file_atom: command failed"

	for i in "${!__kv[@]}"; do
		[[ "$i" == _* ]] || echo "${i}: ${__kv[$i]}" >> "${filename}"
	done
	echo "=============================" >> "${filename}"
	echo "${content}" >> "${filename}"

	[ -n "${post_command}" ] && ${post_command} "${filename}"

	mv "${filename}" "${filename_real}" || errquit "write_file_atom: command failed"
}

## download_cover_image
#    uri: image URI
#    filename: the file to save data
download_cover_image() {
	[[ "${1}" == *s.pximg.net/common/* ]] && return 1
	mkdir -p "`dirname "${2}"`"
	__sendpost "${1}" > "${2}" || errquit "cover image download failed"
	return 0
}

## rename_check
#    parent: parent dir
#    check: glob expr, expect only one result
#    should_be: when 'check' get more than 2 results, which should be kept
rename_check() {
	local tmp
	local dirs=`find "$1" -maxdepth 1 -type d -name "$2" 2> /dev/null`

	[ -n "$dirs" ] || return 0

	local n=`echo "$dirs" | wc -l`

	if [ "$n" != "1" ]; then
		echo "[error] rename check, multiple ${2} existed, please fix it manually."
		echo "BTW, the current author/series name is '${3}'"
		echo
		echo "${dirs}"
		echo
		exit 1
	fi

	[ -d "$dirs" ] || errquit "directory assert failed: $dirs"

	tmp="${dirs%/*}/${3}"
	if [ "$dirs" != "$tmp" ]; then
		echo "[notice] directory '${dirs}' renamed to '${tmp}'. The author has changed nickname or series name."
		mv "$dirs" "$tmp" || errquit "fatal error occurred"
	fi
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
	local ignore='0'

	local series_dir filename novel
	declare -A nmeta

	trick_meta meta
	[ "$RENAMING_DETECT" = '1' ] && rename_check "${DIR_PREFIX}/${sdir}" "${meta[authorid]}-*" "${meta[authorid]}-${meta[author]}"

	if [ "${NO_SERIES}" = '0' ]; then
		if [ -z "${meta[series]}" ]; then
			series_dir=""
		else
			series_dir="/${meta[series]}-${meta[series_name]}"
			flags="${flags}S"
			[ "$RENAMING_DETECT" = '1' ] && rename_check "${DIR_PREFIX}/${sdir}/${meta[authorid]}-${meta[author]}" "${meta[series]}-*" "${meta[series]}-${meta[series_name]}"
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

	if [ "$ignore" = '0' ]; then
		pixiv_get_novel "${meta[id]}" novel nmeta || pixiv_errquit pixiv_get_novel
		if [ -z "${novel}" ]; then
			echo "[warning] empty novel content detected, but server responed a success hdr."
			[ "$ABORT_WHILE_EMPTY_CONTENT" = '1' ] && exit 1
		fi

		for i in "${!nmeta[@]}"; do
			[ -z "${meta[$i]}" ] && meta[$i]="${nmeta[$i]}"
		done

		if [ "$WITH_COVER_IMAGE" = '1' -a -n "${meta[_cover_image_uri]}" ]; then
			download_cover_image "${meta[_cover_image_uri]}" "${filename}.coverimage" && flags="${flags}C"
		fi

		printf "=> %-${_max_flag_len}s %-${_max_id_len}s %s %s\n" "$flags" "${meta[id]}" "'${meta[title]}'" "${meta[author]}"

		write_file_atom "$filename" meta "$novel"
	else
		printf "=> %-${_max_flag_len}s %-${_max_id_len}s %s %s\n" "$flags" "${meta[id]}" "'${meta[title]}'" "${meta[author]}"
		[ -n "${post_command_ignored}" ] && ${post_command_ignored} "${filename}"
	fi
}

## save_id
#    id - the novel ID
save_id() {
	local id="$1"
	local flags='N'

	local series_dir filename content
	declare -A meta

	pixiv_get_novel "$id" content meta || pixiv_errquit pixiv_get_novel
	if [ -z "$content" ]; then
		echo "[warning] empty novel content detected, but server responed a success hdr."
		[ "$ABORT_WHILE_EMPTY_CONTENT" = '1' ] && exit 1
	fi

	trick_meta meta
	[ "$RENAMING_DETECT" = '1' ] && rename_check "${DIR_PREFIX}/singles/" "${meta[authorid]}-*" "${meta[authorid]}-${meta[author]}"

	if [ "${NO_SERIES}" = '0' ]; then
		if [ -z "${meta[series]}" ]; then
			series_dir=""
		else
			series_dir="/${meta[series]}-${meta[series_name]}"
			flags="${flags}S"
			[ "$RENAMING_DETECT" = '1' ] && rename_check "${DIR_PREFIX}/singles/${meta[authorid]}-${meta[author]}" "${meta[series]}-*" "${meta[series]}-${meta[series_name]}"
		fi
	fi

	filename="${DIR_PREFIX}/singles/${meta[authorid]}-${meta[author]}${series_dir}/${meta[id]}-${meta[title]}.txt"

	if [ "$WITH_COVER_IMAGE" = '1' -a -n "${meta[_cover_image_uri]}" ]; then
		download_cover_image "${meta[_cover_image_uri]}" "${filename}.coverimage" && flags="${flags}C"
	fi

	printf "=> %-${_max_flag_len}s %-${_max_id_len}s %s %s\n" "$flags" "${meta[id]}" "'${meta[title]}'" "${meta[author]}"

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
	-R|--no-renaming-detect)
		RENAMING_DETECT=0
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
	-e|--hook)
		post_command="$2"
		shift
		;;
	--ignored-post-hook)
		post_command_ignored="$2"
		shift
		;;
	--with-cover-image)
		WITH_COVER_IMAGE=1
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

[ -f pixiv-config ] && {
	source pixiv-config
	echo "[info] user specific configuration loaded"
}

START_DATE=`LANG=C LANGUAGE= LC_ALL=C date -R`
SCRIPT_RT_OSNAME=`uname -s`

dbg && append_to_array EXTRA_CURL_OPTIONS -v

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
