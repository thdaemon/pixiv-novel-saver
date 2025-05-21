#!/usr/bin/env bash

DEBUG="${PIXIV_NOVEL_SAVER_DEBUG:-0}"

SCRIPT_VERSION='0.2.31'

NOVELS_PER_PAGE='24'
FANBOX_POSTS_PER_PAGE='10'
DIR_PREFIX='pvnovels/'
COOKIE=""
USER_ID=""

ABORT_WHILE_EMPTY_CONTENT=1
ABORT_WHILE_FANBOX_POST_RESTRICTED=0
LAZY_TEXT_COUNT=0
NO_LAZY_UNCON=0
RENAMING_DETECT=1
DIRNAME_ONLY_ID=0
NO_SERIES=0
FANBOX_SAVE_RAW_DATA=1
WITH_COVER_IMAGE=0
WITH_INLINE_IMAGES=0
WITH_INLINE_FILES=0

bookmarks=0
private=0
user_bookmarks=()
novels=()
serieses=()
authors=()
fanbox=()
fanbox_authors=()

post_command=''
post_command_ignored=''

declare -A useragent
useragent[desktop]="Mozilla/5.0 (X11; Linux x86_64; rv:109) Gecko/20100101 Firefox/112.0"
useragent[mobile]="Mozilla/5.0 (Android 13; Mobile; rv:109) Gecko/112.0 Firefox/112.0"

declare -A API_GATEWAY_HOST
API_GATEWAY_HOST[raw]=""
API_GATEWAY_HOST[pixiv]="https://www.pixiv.net/"
API_GATEWAY_HOST[pixivFANBOX]="https://api.fanbox.cc/"
#API_GATEWAY_HOST[pixivFANBOX]="https://fanbox.pixiv.net/"
declare -A API_GATEWAY_REFERER
API_GATEWAY_REFERER[raw]="https://www.pixiv.net"
API_GATEWAY_REFERER[pixiv]="https://www.pixiv.net"
API_GATEWAY_REFERER[pixivFANBOX]="https://www.fanbox.cc"

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

invoke_curl() {
	local uri
	local ua="pixiv-novel-saver/$SCRIPT_VERSION ($SCRIPT_RT_OSNAME) GNUBash/$BASH_VERSION"
	declare -a opts

	while [ "$#" -gt 0 ]; do
		case "$1" in
		-uri) uri="$2"; shift ;;
		-append) append_to_array opts '-H' "$2"; shift ;;
		-useragent) ua="$2"; shift ;;
		-accept) append_to_array opts '-H' "Accept: $2"; shift ;;
		-referer) append_to_array opts '-H' "Referer: $2"; shift ;;
		-origin) append_to_array opts '-H' "Origin: $2"; shift ;;
		-cookie) append_to_array opts '-H' "Cookie: $2"; shift ;;
		esac
		shift
	done

	curl --compressed -s "${EXTRA_CURL_OPTIONS[@]}" "$uri" \
		-H "User-Agent: $ua" \
		-H 'Accept-Language: en_US,en;q=0.5' \
		"${opts[@]}" \
		-H 'DNT: 1' \
		-H 'TE: Trailers'
}

invoke_rest_api() {
	dbg && printdbg "> $1 $2"

	declare -a extra_opts
	local referer="${API_GATEWAY_REFERER[${1}]}"
	local uri="${API_GATEWAY_HOST[${1}]}$2"
	local ua="${useragent["${3:-desktop}"]}"

	[[ $uri = $referer* ]] || append_to_array extra_opts -origin "$referer"

	shift 3

	resp=`invoke_curl -uri "$uri" -useragent "$ua" -accept "application/json" -referer "$referer" -cookie "${COOKIE}" "${extra_opts[@]}" "$@"`

	dbg && echo "$resp" | jq >&2
	echo "$resp"
}

invoke_curl_simple_download() {
	local uri="$1"
	local ua="${useragent["${2:-desktop}"]}"
	local accept="$3"
	shift 3

	invoke_curl -uri "$uri" -useragent "${useragent["${2:-desktop}"]}" -accept "$accept" -referer "https://www.pixiv.net" -cookie "${COOKIE}" "$@"
}

date_string_to_timestamp() {
	date '+%s' -d "$1"
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

json_array_get_string_item() {
	declare -n  __msg_="${3}"
	json_get_string "${1}" "[${2}]" __msg_
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

__pixivfanbox_parsehdr() {
	local tmp
	declare -n  __msg="$2"

	if [ -n "$1" ]; then
		if json_has "$1" error ; then
			json_get_string "$1" error tmp
			__msg="server respond: $tmp"
			return 1
		elif ! json_has "$1" body ; then
			__msg="network error"
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
	errquit "${1}: ${pixiv_error}"
}

## pixiv_get_user_info
#    userid - the ID of the user
#    __meta - a pointer to recv info of the user
pixiv_get_user_info() {
	local userid="$1"
	declare -n  __meta="$2"

	local tmp

	tmp=`invoke_rest_api pixiv "ajax/user/${userid}?full=0"`
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

	tmp=`invoke_rest_api pixiv "ajax/novel/series/${seriesid}"`
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

	tmp=`invoke_rest_api pixiv "ajax/user/${userid}/novels/bookmarks?tag=&offset=${offset}&limit=${NOVELS_PER_PAGE}&rest=${rest}"`
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

	tmp=`invoke_rest_api pixiv "touch/ajax/user/novels?id=${userid}&p=${page}" mobile`
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

	tmp=`invoke_rest_api pixiv "ajax/novel/series_content/${seriesid}?limit=${NOVELS_PER_PAGE}&last_order=${offset}&order_by=asc"`
	__pixiv_parsehdr "$tmp" pixiv_error || return 1

	json_get_object "$tmp" body.page.seriesContents __novels
	return 0
}

## pixivfanbox_list_post
#    type - 'first' or 'next
#    target - the userid while type is first, URL while type is next
#    __items - a pointer to recv items
#    __next_url - a pointer to recv URL for next page, blank means ending
pixivfanbox_list_post() {
	local scope api
	local idtype=creatorId
	local target="$2"

	if [[ "$target" =~ ^pixiv: ]]; then
		target="${target#pixiv:}"
		idtype=userId
	fi

	case "$1" in
	first)
		scope=pixivFANBOX
		api="post.listCreator?${idtype}=${target}&limit=${FANBOX_POSTS_PER_PAGE}"
		;;
	next)
		scope=raw
		api="${target}"
		;;
	esac

	declare -n  __items="$3"
	declare -n  __next_url="$4"

	local tmp

	tmp=`invoke_rest_api "$scope" "$api"`
	__pixivfanbox_parsehdr "$tmp" pixiv_error || return 1

	json_get_object "$tmp" body.items items
	json_get_string "$tmp" body.nextUrl __next_url

	return 0
}
## pixivfanbox_parse_post_meta
#    data - json data
#    __content_ - a pointer to recv content
#    __meta_ - a pointer to recv some post infomation
pixivfanbox_parse_post() {
	local data="$1"
	declare -n __content_="$2"
	declare -n __meta_="$3"
	local tagmeta tags ntags tag

	json_get_string "$tmp" type __meta_[type]

	case "${__meta_[type]}" in
	text)
		json_get_string "$tmp" body.text __content_
		;;
	article|image|file)
		json_get_object "$tmp" body __content_
		;;
	*)
		pixiv_error="Unsupported post type '${__meta_[type]}'"
		return 2
		;;
	esac

	__meta_[pixivFANBOX]=yes

	json_get_integer "$data" id                __meta_[id]
	json_get_string "$data"  title             __meta_[title]
	json_get_integer "$data" user.userId       __meta_[authorid]
	json_get_string "$data"  user.name         __meta_[author]
	json_get_string "$data"  creatorId         __meta_[creatorId]
	json_get_string "$data"  coverImageUrl     __meta_[_cover_image_uri]
	json_get_string "$data"  publishedDatetime __meta_[publishedDatetime]
	json_get_string "$data"  updatedDatetime   __meta_[updatedDatetime]
	json_get_string "$data"  restrictedFor     __meta_[restrictedFor]

	__meta_[_lazy_tag]="-ts`date_string_to_timestamp "${__meta_[updatedDatetime]}"`"

	if json_has "$data" tags ; then
		json_get_object "$data" tags tags
		ntags=`json_array_n_items "$tags"`
		for i in `seq 0 $(( ${ntags} - 1 ))`; do
			json_array_get_string_item "$tags" "$i" tag
			tagmeta="${tagmeta}${tag}, "
		done

		__meta_[tags]="${tagmeta%, }"
	fi

	return 0
}

## pixivfanbox_get_post
#    id - the ID of the post
#    __data - a pointer to recv post content
#    __meta - a pointer to recv some post infomation
pixivfanbox_get_post() {
	local id="$1"
	declare -n __data="$2"
	declare -n __meta="$3"
	local tmp type

	tmp=`invoke_rest_api pixivFANBOX "post.info?postId=$id"`
	__pixivfanbox_parsehdr "$tmp" pixiv_error || return 1

	json_get_object "$tmp" body tmp

	pixivfanbox_parse_post "$tmp" __data __meta
	return $?
}

## pixiv_get_novel
#    novelid - the ID of the novel
#    __novel - a pointer to recv novel content
#    __meta (optional) - a pointer to recv some novel infomation
pixiv_get_novel() {
	local novelid="$1"
	declare -n  __novel="$2"

	local tmp tags ntags tag tagval tagmeta

	tmp=`invoke_rest_api pixiv "ajax/novel/${novelid}"`
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
		json_get_integer "$tmp" xRestrict   __meta[xRestrict]
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
	local id=(${1//-/ })
	local index=${id[1]:-1}
	index=$(( $index - 1 ))
	declare -n  __url="$2"

	local tmp

	tmp=`invoke_rest_api pixiv "ajax/illust/${id[0]}/pages"`
	__pixiv_parsehdr "$tmp" pixiv_error || return 1

	json_get_string "$tmp" body[${index}].urls.original __url
	return 0
}

strip_filename_component() {
	declare -n __val="$1"
	__val="${__val//\//${_slash_replace_to}}"
}

usage() {
	cat <<EOF
Pixiv novel saver ${SCRIPT_VERSION}
Copyright thxdaemon <thxdaemon@gmail.com>

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
  -w, --window-size <NPP>  How many novels/fanbox_post per page request
                             default 24 for novels and 10 for fanbox post
                             (not available in --save-author, --save-novel
                             and --save-fanbox-post)
  -u, --disable-lazy-mode  Disable all lazy modes unconditionally
  -R, --no-renaming-detect Do not detect author/series renaming
  --path-id-only           Do not append name to dir path, IDs only
                             (Will active -R, --no-renaming-detect)
  --with-cover-image       Download the cover image of novels/posts if and only
                             if the image is NOT a common cover image
  --with-inline-images     Download inline images in novels/posts
                             Download location:
                             in novels: <DIR>/illusts
                             in fanbox posts: images subdir of posts saved
  --with-inline-files      Download inline files in fanbox posts
                             Download location: files subdir of posts saved
  --no-ignore-fanbox-restricted
                           fanbox posts restricted will be treated as error
  --no-save-fanbox-raw     Do not keep raw data for fanbox posts
  -e, --hook "<command>"   Run 'cmd "\$filename"' for each downloaded novel
                             (note: the tmp file will be renamed after hook)
  --ignored-post-hook "<command>"
                           Run 'cmd "\$filename"' for each ignored novel

SOURCE OPTIONS:
  -m, --save-my-bookmarks  Save all my bookmarked novels
                             Lazy mode: text count (enable it by -c)
  -p, --save-my-private    Save all my private bookmarked novels
                             Lazy mode: text count (enable it by -c)
  -b, --save-user-bookmarks <ID>
                           Save all novels from public bookmarks by user ID
                             Lazy mode: text count (enable it by -c)
                             Can be specified multiple times
  -a, --save-novel <ID>    Save a novel by its ID
                             Lazy mode: never (not supported)
                             Can be specified multiple times
  -s, --save-series <ID>   Save all public novels in a series by ID
                             Lazy mode: always (full supported, disable by -u)
                             Can be specified multiple times
  -A, --save-author <ID>   Save all public novels published by an author
                             Lazy mode: text count (enable it by -c)
                             Can be specified multiple times
  -f, --save-fanbox-post <post ID>
                           Save a fanbox post by its ID
			     Lazy mode: embed (disable by -u)
                             Can be specified multiple times
  -F, --save-fanbox-user pixiv:<pixiv ID>
  -F, --save-fanbox-user <fanbox creator ID>
                           Save all posts by authors' ID
                             Lazy mode: embed (disable by -u)
                             Can be specified multiple times

EXAMPLES:
	$1 -c -m
	$1 -c -m -a ID -s ID -s ID -s ID -E
	$1 -c -a ID -A ID -A ID -o some_dir
	$1 -c -m -p -e 'unix2dox -q' --with-cover-image
	$1 --with-inline-images --with-inline-files -F ID
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

	mkdir -p -- "`dirname -- "${filename_real}"`" || errquit "write_file_atom: command failed"

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

	mv -- "${filename}" "${filename_real}" || errquit "write_file_atom: command failed"
}

## download_cover_image
#    uri: image URI
#    filename: the file to save data
download_cover_image() {
	[[ "${1}" == *s.pximg.net/common/* ]] && return 1
	mkdir -p -- "`dirname -- "${2}"`"
	invoke_curl_simple_download "${1}" desktop 'image/webp,*/*' > "${2}" || errquit "cover image download failed"
	return 0
}

## download_inline_images
#    content - the novel's content
download_inline_images() {
	local illust
	local ext
	local url=''
	local stat='done'

	for i in `grep -o -E '\[(pixiv|uploaded)image:[0-9-]+\]' <<< "$1"`; do
		illust=`echo "$i" | cut -d : -f 2 | cut -d ] -f 1`
		pixiv_get_illust_url_original "$illust" url || echo "[warning] pixiv_get_illust_url_original: $pixiv_error"
		if [ -z "$url" ]; then
			stat="ignored, illust may not exist or be removed"
		else
			ext="${url##*.}"
			grep -E "^[a-zA-Z0-9]+$" <<< "$ext" > /dev/null 2>&1 || ext='image'
			mkdir -p -- "${DIR_PREFIX}/illusts/" || errquit "download_inline_images: command failed"
			invoke_curl_simple_download "${url}" desktop 'image/webp,*/*' > "${DIR_PREFIX}/illusts/${illust}.${ext}" || errquit "inline image(s) download failed"
		fi
		echo "   => Downloading illust $illust $stat"
	done
}

## download_fanbox_inline_stuff
#    type - 'image', 'file' or 'embed'(not-impl)
#    id - image id/file id
#    info - the infomation of the inline thing (image/file/embed(not-impl))
#    prefix - the save prefix
#    post_id  = the id of fanbox post
download_fanbox_inline_stuff() {
	local type="$1"
	local id="$2"
	local info="$3"
	local prefix="$4"
	local post_id="$5"

	local url ext key name

	case "$type" in
	image) key=originalUrl ;;
	file) key=url; json_get_string "$info" name name; name="-$name" ;;
	esac

	json_get_string "$info" "$key" url
	json_get_string "$info" extension ext

	echo "   => Downloading $type $id (in $post_id)"
	mkdir -p -- "${prefix}/${type}/"
	invoke_curl_simple_download "${url}" desktop '*/*' > "${prefix}/${type}/${post_id}-${id}${name}.${ext}" || errquit "fanbox inline $type download failed"
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

## prepare_filename
#    __meta - pointer to novel_meta associative array
#    subdir - the subdir name
#    lazytag - add a tag to filename for lazy mode
#    __flags - pointer to flags var
#    __filename - pointer to recv filename
prepare_filename() {
	declare -n __meta="$1"
	local sdir="$2"
	local lazytag="$3"
	declare -n __flags="$4"
	declare -n __filename="$5"

	local series_dir author

	[ -n "${__meta[creatorId]}" ] && author="-${__meta[creatorId]}-${__meta[author]}" || author="-${__meta[author]}"
	local series_name="-${__meta[series_name]}"
	local title="-${__meta[title]}"
	strip_filename_component author
	strip_filename_component series_name
	strip_filename_component title

	if [ "$DIRNAME_ONLY_ID" = '1' ]; then
		author=""
		series_name=""
		title=""
	fi

	[ "$RENAMING_DETECT" = '1' ] && rename_check "${DIR_PREFIX}${sdir}" "${__meta[authorid]}-*" "${__meta[authorid]}${author}"

	if [ "${NO_SERIES}" = '0' ]; then
		if [ -z "${__meta[series]}" ]; then
			series_dir=""
		else
			series_dir="/${__meta[series]}${series_name}"
			__flags="${__flags}S"
			[ "$RENAMING_DETECT" = '1' ] && rename_check "${DIR_PREFIX}${sdir}/${__meta[authorid]}${author}" "${__meta[series]}-*" "${__meta[series]}${series_name}"
		fi
	fi

	__filename="${DIR_PREFIX}${sdir}/${__meta[authorid]}${author}${series_dir}/${__meta[id]}${title}${lazytag}.txt"
}

## print_complete_line
#    flags - flags of the novel/post
#    __kv - pointer to a key-value pair to write
print_complete_line() {
	local flags="$1"
	declare -n __kv="$2"
	local author="${__kv[author]}"
	[ -n "${__kv[creatorId]}" ] && author="${__kv[creatorId]} ($author)"
	printf "=> %-${_max_flag_len}s %-${_max_id_len}s '%s' %s\n" "$flags" "${__kv[id]}" "${__kv[title]}" "$author"
}

## post_novel_content_recv
#    __meta - pointer to novel_meta associative array
#    content - the novel content
#    filename - pointer to recv filename
#    __flags - pointer to flags var
post_novel_content_recv() {
	declare -n __meta="$1"
	local content="$2"
	local filename="$3"
	declare -n __flags="$4"

	if [ -z "${content}" ]; then
		echo "[warning] empty novel content detected, but server responed a success hdr."
		[ "$ABORT_WHILE_EMPTY_CONTENT" = '1' ] && exit 1
	fi

	if [ "$WITH_COVER_IMAGE" = '1' -a -n "${__meta[_cover_image_uri]}" ]; then
		download_cover_image "${__meta[_cover_image_uri]}" "${filename}.coverimage" && __flags="${__flags}C"
	fi

	if [ "$WITH_INLINE_IMAGES" = '1' ]; then
		download_inline_images "$content"
	fi

	print_complete_line "$__flags" __meta

	write_file_atom "$filename" __meta "$content"
}

## post_fanbox_data_recv
#    __meta - pointer to novel_meta associative array
#    data - the post data, depends on __meta[type]
#    filename - the save prefix
#    __flags - pointer to flags var
post_fanbox_data_recv() {
	declare -n __meta="$1"
	local data="$2"
	local filename="$3"
	declare -n __flags="$4"

	local prefix=`dirname -- "$filename"`

	local type blocks n item item_text item_type content tmp

	if [ -n "${__meta[restrictedFor]}" ]; then
		__flags="${__flags}R"
		if [ "$ABORT_WHILE_FANBOX_POST_RESTRICTED" = '1' ]; then
			echo "[error] fanbox post ${__meta[authorid]}/${__meta[id]} is restricted. aborted."
			exit 1
		fi
		if [ -z "$data" ]; then
			print_complete_line "$__flags" __meta
			return 0
		fi
	elif [ -z "${data}" ]; then
		echo "[warning] empty post content detected, but server responed a success hdr."
		[ "$ABORT_WHILE_EMPTY_CONTENT" = '1' ] && exit 1
	fi

	if [ "$NO_LAZY_UNCON" = '0' -a -f "$filename" ]; then
		__flags="${__flags}I"
		print_complete_line "$__flags" __meta
		return 0
	fi

	type="${__meta[type]}"

	case "$type" in
	text)
		write_file_atom "$filename" __meta "$data"
		;;
	article)
		json_get_object "$data" blocks blocks
		n=`json_array_n_items "$blocks"`
		for i in `seq 0 $(( ${n} - 1 ))`; do
			json_array_get_item "$blocks" "$i" item
			json_get_string "$item" type item_type
			case "$item_type" in
			p)
				json_get_string "$item" text item_text
				content="$content"$'\n'"$item_text"
				json_has "$item" links && echo "[warning] post_fanbox_data_recv: article: links stub"
				json_has "$item" styles && echo "[warning] post_fanbox_data_recv: article: styles stub"
				;;
			image)
				if [ "$WITH_INLINE_IMAGES" = '1' ]; then
					json_get_string "$item" imageId item_text
					json_get_object "$data" "imageMap.\"$item_text\"" tmp
					download_fanbox_inline_stuff image "$item_text" "$tmp" "$prefix" "${__meta[id]}"
				fi
				;;
			file)
				if [ "$WITH_INLINE_FILES" = '1' ]; then
					json_get_string "$item" fileId item_text
					json_get_object "$data" "fileMap.\"$item_text\"" tmp
					download_fanbox_inline_stuff file "$item_text" "$tmp" "$prefix" "${__meta[id]}"
				fi
				;;
			*)
				echo "[warning] post_fanbox_data_recv: article: type ${item_type}: stub"
				;;
			esac
		done

		[ "$FANBOX_SAVE_RAW_DATA" = '1' ] && write_file_atom "${filename}.raw" __meta "$data"
		write_file_atom "$filename" __meta "$content"
		;;
	image|file)
		case "$type" in
		image) [ "$WITH_INLINE_IMAGES" = '1' ] || return; tmp="images" ;;
		file) [ "$WITH_INLINE_FILES" = '1' ] || return; tmp="files" ;;
		esac
		json_get_string "$data" text content
		json_get_object "$data" "${tmp}" blocks
		n=`json_array_n_items "$blocks"`
		for i in `seq 0 $(( ${n} - 1 ))`; do
			json_array_get_item "$blocks" "$i" item
			json_get_string "$item" id item_text
			download_fanbox_inline_stuff "$type" "$item_text" "$item" "$prefix" "${__meta[id]}"
		done
		write_file_atom "$filename" __meta "$content"
		;;
	*)
		echo "[warning] post_fanbox_data_recv: $type: stub"
		;;
	esac

	[ "$WITH_COVER_IMAGE" = '1' -a -n "${__meta[_cover_image_uri]}" ] && \
	       download_cover_image "${__meta[_cover_image_uri]}" "${filename}.coverimage" && __flags="${__flags}C"

	print_complete_line "$__flags" __meta
}

## download_novel
#    subdir - the subdir name
#    meta - pointer to novel_meta associative array
#    lazymode - 'always', 'textcount' or 'disable'
#    lazytag - add a tag to filename for lazy mode
#    extra_flags - append extra flag
download_novel() {
	local sdir="$1"
	declare -n meta="$2"
	local lazymode="$3"
	local lazytag="$4"
	local flags="N${5}"
	local ignore='0'

	local filename novel
	declare -A nmeta

	prepare_filename meta "$sdir" "$lazytag" flags filename

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
		for i in "${!nmeta[@]}"; do
			[ -z "${meta[$i]}" ] && meta[$i]="${nmeta[$i]}"
		done

		post_novel_content_recv meta "$novel" "$filename" flags
	else
		print_complete_line "$flags" meta
		[ -n "${post_command_ignored}" ] && ${post_command_ignored} "${filename}"
	fi
}

## save_id
#    id - the novel ID
#    type - novel (default), fanbox_post
save_id() {
	local id="$1"
	local type="$2"
	local flags='N'
	local core_api_func=pixiv_get_novel
	local path_prefix="/singles"
	local post_func=post_novel_content_recv

	case "$type" in
	fanbox_post)
		flags='F'
		core_api_func=pixivfanbox_get_post
		path_prefix="/fanbox-singles"
		post_func=post_fanbox_data_recv
		;;
	esac

	local filename content
	declare -A meta

	$core_api_func "$id" content meta || pixiv_errquit $core_api_func

	prepare_filename meta "$path_prefix" "${meta[_lazy_tag]}" flags filename

	$post_func meta "$content" "$filename" flags
}

save_bookmarks() {
	local page='0'
	local total=''
	local suffix=''
	local user="$1"
	local rest="$2"

	local works works_length tmp

	[ "$rest" = 'show' ] || suffix="-$rest"

	while true ; do
		pixiv_list_novels_by_bookmarks "$user" "$page" "$rest" works total || pixiv_errquit pixiv_list_novels_by_bookmarks
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

			if [ "${novel_meta[authorid]}" = "0" ];then
				echo "[warning] novel ${novel_meta[id]} has been removed, ignoring..."
				continue
			fi

			if json_has "$tmp" seriesId ; then
				json_get_integer "$tmp" seriesId    novel_meta[series]
				json_get_string "$tmp"  seriesTitle novel_meta[series_name]
			fi

			tmp=''
			[ -n "${novel_meta[text_count]}" ] && tmp="-tc${novel_meta[text_count]}"
			download_novel "/bookmarks/${user}${suffix}" novel_meta textcount "${tmp}"
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
			download_novel "/by-author" novel_meta textcount "$tmp"
		done

		page_cur=$(( $page_cur + 1 ))
		[ "$page_cur" -gt "$page_nember" ] && break
	done
}

save_fanbox_author() {
	local id="$1"
	local page_cur='1'
	local items next_url n tmp flags filename content

	pixivfanbox_list_post first "$id" items next_url || pixiv_errquit pixivfanbox_list_post
	while true ; do
		n=`json_array_n_items "$items"`

		echo "[info] in this page: ${n}"
		for i in `seq 0 $(( $n - 1 ))` ; do
			json_array_get_item "$items" "$i" tmp

			unset meta
			declare -A meta
			flags='F'

			pixivfanbox_parse_post "$tmp" content meta || pixiv_errquit pixivfanbox_parse_post

			prepare_filename meta "/by-fanbox-author" "${meta[_lazy_tag]}" flags filename

			post_fanbox_data_recv meta "$content" "$filename" flags
		done

		[ -z "$next_url" ] && break
		pixivfanbox_list_post next "$next_url" items next_url || pixiv_errquit pixivfanbox_list_post
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
			download_novel "/by-series" novel_meta always "$tmp" "$extra_flags"
		done

		page=$(( $page + 1 ))
		tmp=$(( $page * $NOVELS_PER_PAGE ))
		[ "$tmp" -ge "${series_info[total]}" ] && break
	done
}

[ -f pixiv-config ] && {
	source pixiv-config
	echo "[info] user specific configuration loaded"
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
	--path-id-only)
		RENAMING_DETECT=0
		DIRNAME_ONLY_ID=1
		;;
	-E|--ignore-empty)
		ABORT_WHILE_EMPTY_CONTENT=0
		;;
	-w|--window-size)
		NOVELS_PER_PAGE="$2"
		FANBOX_POSTS_PER_PAGE="$2"
		shift
		;;
	-m|--save-my-bookmarks)
		bookmarks=1
		;;
	-p|--save-my-private)
		private=1
		;;
	-b|--save-user-bookmarks)
		append_to_array user_bookmarks "$2"
		shift
		;;
	-a|--save-novel)
		append_to_array novels "$2"
		shift
		;;
	-s|--save-series)
		append_to_array serieses "$2"
		shift
		;;
	-A|--save-author)
		append_to_array authors "$2"
		shift
		;;
	-f|--save-fanbox-post)
		append_to_array fanbox "$2"
		shift
		;;
	-F|--save-fanbox-user)
		append_to_array fanbox_authors "$2"
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
	--with-inline-images)
		WITH_INLINE_IMAGES=1
		;;
	--with-inline-files)
		WITH_INLINE_FILES=1
		;;
	--no-ignore-fanbox-restricted)
		ABORT_WHILE_FANBOX_POST_RESTRICTED=1
		;;
	--no-save-fanbox-raw)
		FANBOX_SAVE_RAW_DATA=0
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

START_DATE=`LANG=C LANGUAGE= LC_ALL=C date -R`
SCRIPT_RT_OSNAME=`uname -s`

dbg && append_to_array EXTRA_CURL_OPTIONS -v

[ "$bookmarks" = '1' ] && {
	echo "[info] saving my bookmarked novels..."
	save_bookmarks "${USER_ID}" show
}

[ "$private" = '1' ] && {
	echo "[info] saving my private bookmarked novels..."
	save_bookmarks "${USER_ID}" hide
}

[ "${#user_bookmarks[@]}" = '0' ] || {
	echo "[info] saving novels which are bookmarked by users..."
	for i in "${user_bookmarks[@]}"; do
		echo "[info] starting to save novels which are bookmarked by ${i}..."
		save_bookmarks "${i}" show
	done
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

[ "${#fanbox[@]}" = '0' ] || {
	echo "[warning] pixivFANBOX support is early experimental, there are many things not completed. If you meet a problem, please submit an issue"
	echo "[info] saving posts by fanbox post id..."
	for i in "${fanbox[@]}"; do
		save_id "$i" fanbox_post
	done
}

[ "${#fanbox_authors[@]}" = '0' ] || {
	echo "[warning] pixivFANBOX support is early experimental, there are many things not completed. If you meet a problem, please submit an issue"
	echo "[info] saving posts by fanbox user..."
	for i in "${fanbox_authors[@]}"; do
		save_fanbox_author "$i"
	done
}
