#!/usr/bin/env bash
rsync -aPzv --progress --delete --include=trinkets.lua --include='lib/' --include='lib/*' --exclude='*' . 'we@norns.local:/home/we/dust/code/trinkets'
