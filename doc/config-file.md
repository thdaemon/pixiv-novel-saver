# Configure file

## Syntax

Set a variable

```
name=value
```

value can be `123`, `string`, `"string"`, `'string'`. like Bash variable

Append variables to array

```
append_to_array <ArrayName> <arg0> [arg1] [arg2] ...
```

e.g.

```
append_to_array authors 123456 654321 111111
```

Export env-vars to sub processes (such as curl proxy env-var)

```
export name=value
```

## General

### Set pixiv.net auth cookie

```
COOKIE="PHPSESSID=XXXXXXXX_XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX;"
```

### Set your user id

```
USER_ID="<Your user id>"
```

## Download Source options

Same as `-m, --save-my-bookmarks`. Save all my bookmarked novels

```
bookmarks=1
```

Same as `-p, --save-my-private`. Save all my private bookmarked novels

```
private=1
```

Same as `-a, --save-novel <ID>`. Save a novel by its ID

```
append_to_array novels <ID>
```

Same as `-s, --save-series <ID>`. Save all public novels in a series by ID

```
append_to_array serieses <ID>
```

Same as `-A, --save-author <ID>`. Save all public novels published by an author

```
append_to_array authors <ID>
```

## Misc options

Command-line option|Configure file equivalent
-------------------|-------------------------
`-c`, `--lazy-text-count`|`LAZY_TEXT_COUNT=1`
`-d`, `--no-series`|`NO_SERIES=1`
`-o <DIR>`, `--output <DIR>`|`DIR_PREFIX="<DIR>"`
`-E`, `--ignore-empty`|`ABORT_WHILE_EMPTY_CONTENT=0`
`-w <NPP>`, `--window-size <NPP>`|`NOVELS_PER_PAGE=<NPP>`
`-u`, `--disable-lazy-mode`|`NO_LAZY_UNCON=1`
`-R`, `--no-renaming-detect`|`RENAMING_DETECT=0`
`--with-cover-image`|`WITH_COVER_IMAGE=1`
`-e "<command>"`, `--hook "<command>"`|`post_command="<command>"`
`--ignored-post-hook "<command>"`|`post_command_ignored="<command>"`


## Extra options

### Change useragent (desktop/mobile)

```
useragent[desktop]="User-Agent: Mozilla/5.0 (X11; Linux x86_64; rv:72.0) Gecko/20100101 Firefox/72.0"
useragent[mobile]="User-Agent: Mozilla/5.0 (Android 9.0; Mobile; rv:68.0) Gecko/68.0 Firefox/68.0"
```

### Add extra cURL options

```
append_to_array EXTRA_CURL_OPTIONS <Your options>
```