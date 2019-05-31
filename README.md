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

- [ ] Add built-in login

- [ ] Save novels from author userid
