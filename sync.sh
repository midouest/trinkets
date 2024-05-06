#!/usr/bin/env bash
rsync -aPzv --progress --delete --exclude-from=".syncexclude" . "we@norns.local:/home/we/dust/code/trinkets"
