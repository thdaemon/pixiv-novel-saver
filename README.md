# Pixiv Loved Novel Saver

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

Login your account on browser, and get pixiv cookie `PHPSESSID` and add it to novel.sh. set `USER_ID` to your pixiv user id. It likes

```
COOKIE="PHPSESSID=XXXXXXXX_XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX;"
USER_ID="<Your user id>"
```

Run the script

```
$ ./novel.sh -c -m
```


It will avoid repeated saves after the second time when use lazy mode. (`-c` option enables lazy mode).

Warning: It's dangerous, because the novel may have been updated, and there is no way to see the last update time of the novel before getting the full novel. However, there are still some ways to allow roughly guessing whether the novel has been updated, such as the number of words, but this is not 100% accurate. 

It will save all your loved novels. (`-m` option do it)

For more infomation, run

```
$ ./novel.sh -h
```

## TODO

- [x] Basic features available

- [x] Series support

- [x] Lazy mode, Avoid repeated saves after the second time

- [ ] Add built-in login

- [ ] Save novels from author userid or series id
