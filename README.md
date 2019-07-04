# Pixiv Novel Saver

A script to save your loved novels to local disk.

**Thanks to the authors for their creativity!**

**This tool is designed to help save our favorite novels locally so that they can be read on a variety of devices. Please DO NOT distribute the novels until you have permission from the author.**

## Usage:

Install dependents:

```
GNU Bash
cURL
jq
```

Create a `pixiv-config` file.

Login your account on browser, and get pixiv cookie `PHPSESSID` and add it to `pixiv-config`. set `USER_ID` to your pixiv user id. It likes

```
COOKIE="PHPSESSID=XXXXXXXX_XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX;"
USER_ID="<Your user id>"
```

Run the script

```
$ ./novel.sh -c -m
```

It will avoid repeated saves after the second time when use Lazy Mode. (`-c` or `--lazy-text-count` option enables Lazy Mode).

Warning: It's dangerous, because the novel may have been updated, and there is no way to see the last update time of the novel before getting the full novel. However, there are still some ways to allow roughly guessing whether the novel has been updated, such as the number of words, but this is not 100% accurate. 

It will save all your bookmarked novels. (`-m` or `--save-my-bookmarks` option do it)

To save novels by an author, you can use `-A <ID>` or `--save-author <ID>`.

Some other options are useful, such as `-d, --no-series`, `-E, --ignore-empty`, `-w, --window-size`, etc.

For more infomation, run

```
$ ./novel.sh -h
```

You can also set default options in `pixiv-config`, but you need to read source code to find which you want...

## Flags

You may have noticed the uppercase letters before each novel in the output, which is a set of flags. Here is a brief introduction to them.

- `N` means it is a novel. It should be displayed always.

- `S` means the novel is in a series. To disable series support, specify `-d` or `--no-series`.

- `I` on Lazy Mode, this novel have been ignored.

- `U` on Lazy Mode, this novel have been updated.

## TODO

- [x] Basic features available

- [x] Series support

- [x] Lazy Mode, Avoid repeated saves after the second time

- [ ] Add built-in login

- [x] Save novels from author userid

- [ ] Save novels from series id

- [ ] Implement all unimplemented options (see `(not impl)` in `-h` usage)
