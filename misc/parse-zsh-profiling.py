#!/usr/bin/env python

import datetime
import sys

def parse_line(raw_line):
    nonewline = raw_line.strip('\n')
    timestr, rest = nonewline.split(' ', 1)
    return int(timestr), rest

def main(filename, SLOW_THRESHOLD):
    with open(filename) as f:
        count = 0
        start_time, rest = parse_line(f.readline())
        print "0 {line}".format(line=rest)

        prev_line = rest
        prev_line_start = start_time
        for line in f.readlines():
            count += 1
            if len(line) == 0 or line == "\n":
                continue
            if not line[0].isdigit():
                continue

            try:
                t, rest = parse_line(line)
                diff = t - prev_line_start
                if diff > SLOW_THRESHOLD:
                    print "{since_start:4} +{diff:2} >> {prev_line}".format(
                        since_start=t-start_time, diff=diff, prev_line=prev_line)
                prev_line_start = t
                prev_line = rest
            except ValueError:
                continue

def safe_list_get (l, idx, default):
    return l[idx] if idx < len(l) else default

if __name__ == "__main__":
    main(sys.argv[1], int(safe_list_get(sys.argv, 2, '7')))
