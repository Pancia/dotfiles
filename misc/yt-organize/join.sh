#!/usr/bin/env bash

#cat input-json-file | jq '.videos[] | .titleLong' -r > output.txt
paste -d' ' $1 <(echo "$3" | tr ',' '\n' | sed 's/1/#entertainment/;s/2/#personal_development/;s/3/#spirituality/;s/4/#education/;s/5/#social_political/;s/6/#dating') > $2
