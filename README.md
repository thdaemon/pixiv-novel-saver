# Pixiv Loved Novel Saver

A script to save your loved novels to local disk.

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

> It will save novels loved by the user! NOT NOVELS WRITTEN BY THIS USER

Run the script

```
$ ./novel.sh
```

## TODO

- [x] Basic features available

- [ ] Series support

- [ ] Avoid repeated saves after the second time (It's hard, because the novel may have been updated, and there is no way to see the last update time of the novel before getting the full novel. However, there are still some ways to allow roughly guessing whether the novel has been updated, such as the number of words, but this is not 100% accurate. I intend to make a separate option for it.)

- [ ] Add built-in login

- [ ] Save novels from author userid
