# Pixiv Novel Saver

A script to save your loved novels to local disk.

**Thanks to the authors for their creativity! And be sure to respect the author's work!**

**This tool is designed to help save our favorite novels locally so that they can be read on a variety of devices anytime even if author deletes them. But please NEVER distribute the novels until you have permission from the author.**

## Usage

### Installation

Install dependents: `GNU Bash (4.4 or later)` (old versions may or may not work), `cURL` and `jq`

OS|Installation Notes
-----|---------
Debian, Ubuntu, etc| `sudo apt install curl jq`
macOS| Install [Homebrew](http://brew.sh/) first, and run `brew install bash curl jq`. You must use the new bash (may not in PATH env-var).
Windows (64 bit)| Install [MSYS2](https://www.msys2.org/) first, and then open msys2 environment, run it in msys2-MINGW64 terminal: `pacman -S mingw-w64-x86_64-jq`. Cygwin may also work, but I haven't tested.

> On Windows, 32bit msys2-MINGW32 should work but I have NOT tested it. And you should install packages by `pacman -S mingw-w64-i686-jq`

### Quick start

Create a `pixiv-config` file.

Login your account on a browser, and get pixiv cookie `PHPSESSID` and add it to `pixiv-config`. set `USER_ID` to your pixiv user id. It likes

```
COOKIE="PHPSESSID=XXXXXXXX_XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX;"
USER_ID="<Your user id>"
```

> If you are using Mozilla Firefox, open https://www.pixiv.net in browser, click `F12`, and you can find `PHPSESSID` in `Storage` -> `Cookie`. Click your avatar in web page, and then you can find your user id in the end of the URL.

Run the script

```
$ ./novel.sh -c -m
```

`-c` or `--lazy-text-count` option enables "text count" lazy mode. For this example, it will avoid repeated saves after the second time.  But in this example it's a little dangerous, because the novel may have been updated, and there is no way to see the last update time of the novel before getting the full novel for this source type (bookmarks). However, there are still some ways to allow roughly guessing whether the novel has been updated, such as the number of words, but this is not 100% accurate. For more information, please refer to "Lazy mode" section.

`-m` or `--save-my-bookmarks` option make program to save all your bookmarked novels.

To save all novels in your private bookmarks, you can use `-p` or `--save-my-private`.

To save all novels by an author, you can use `-A <ID>` or `--save-author <ID>`. (Can be specified multiple times)

To save all novels from a series, you can use `-s <ID>` or `--save-series <ID>`. (Can be specified multiple times)

To save novels by it ID, you can use `-a <ID>` or `--save-novel <ID>`. (Can be specified multiple times)

Some other options are useful, such as `-d, --no-series`, `-E, --ignore-empty`, `-w, --window-size`, `--with-cover-image`, `-R, --no-renaming-detect`, etc.

For more infomation, run

```
$ ./novel.sh -h
```

**NOTE**: You can also set default options in `pixiv-config`, see [This document](/doc/config-file.md).

## Lazy mode

We support different levels of lazy mode for different sources. There are three types. Lazy mode will avoid repeated saves after the second time.

Mode|Source|Description
----------|------------------|---------
always (full supported)|`-s, --save-series`|For this source, Pixiv gives us "update time" before getting full content of novel. So lazy mode is always on. Novels will be updated only when the author updates their novel. It will avoid repeated saves after the second time. It's not dangerous.
text count|`-m, --save-my-bookmarks`, `-p, --save-my-private` and `-A, --save-author`|For this source, Pixiv does NOT give us "update time" before getting full content of novel. However, there are still some ways to allow roughly guessing whether the novel has been updated, such as the number of words, but this is not 100% accurate. `-c` or `--lazy-text-count` option enables "text count" Lazy Mode. It's a little dangerous.
never (not supported)|`-a, --save-novel`|For this source, lazy mode is impossible.

To disable all lazy modes unconditionally, you can use specify `-u` or `--disable-lazy-mode` option. But usually not needed.

And we recommend that you generally use the option `-c` to enable the "text count" lazy mode to reduce network traffic and Pixiv server stress.

## Flags

You may have noticed the uppercase letters before each novel in the output, which is a set of flags. Here is a brief introduction to them.

- `N` means it is a novel. It should be displayed always.

- `S` means the novel is in a series. To disable series support, specify `-d` or `--no-series`.

- `T` Timestamp available. Pixiv gives us "update time" before getting full content of novel and lazy mode is always on.

- `I` on Lazy mode, this novel have been ignored.

- `C` when specify `--with-cover-image`, and this novel has an uncommon (author customized) cover image.

## Line ending

The line breaks in pixiv novels is no promises, usually it is CR or CRLF. Now pixiv-novel-saver removed all CR before the LF automatically. So if you want to save files as DOS-format (CRLF), you can use the "post hook" function to handle this automatically for each novel. Here is an example:

```
$ ./novel.sh -c -m -p --hook 'unix2dos -q'
```

## Notice

0.2.x version is not compatible with 0.1.x version. So in order to avoid trouble, the default save location has also changed.

## Proxy settings

You can set proxy settings which `cURL` knows. For example, a SOCKS5-with-remote-DNS-resolution:

```
$ export all_proxy="socks5h://127.0.0.1:1080"
$ ./novel.sh ...
```

And you can use `export` in `pixiv-config` to avoid typing manually every time.

## Automatically rename files

Author may change their nickname, their serieses' name, etc. pixiv-novel-save now can automatically rename them. To learn more, see [this](https://github.com/thdaemon/pixiv-novel-saver/pull/1).

But pixiv-novel-save will NOT rename novels' name. The philosophy is that if the author changes the name of novels, it means that the author updated the novel, even if the author did not modify the content. pixiv-novel-saver will usually keep old versions of novels.

## Built-In Login support

It is very sad that pixiv.net login interface is protected by reCAPTCHA. If you have some methods to bypass it, please contact me.

## TODO

- [x] Basic features available

- [x] Series support

- [x] Lazy Mode, Avoid repeated saves after the second time

- [ ] Add built-in login for pixiv.net (IT MAY NOT)

- [x] Save novels from author userid

- [x] Save novels from series id

- [x] Refactor ugly old pixiv functions implementations

- [x] Save novels from private (non-public) bookmarks

- [x] Automatically handle line ending (CR, CRLF)

- [x] Save more infomation of novels (tags, description, series, original, creation/uploaded date, etc)

- [x] Post-hook: run a command for each downloaded/ignored novel

- [ ] Implement all unimplemented options (`(not impl)` in `-h` usage)

	- [x] A option to disable all lazy modes unconditionally

	- [ ] A option to allow to strip non-ascii title in filename

	- [x] A option to save cover image of novels

	- [ ] A option to save inline images in novels
	
	- [ ] A option to split pixiv novel chapters

- [x] Automatically detect the author rename and series rename.
