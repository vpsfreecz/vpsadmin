#!/bin/sh

DAYS=3
DIR=/storage/vpsfree.cz/download

find $DIR -type f -mtime +$DAYS -delete
find $DIR -type d -empty -delete
