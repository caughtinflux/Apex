#!/usr/bin/env python

import os, sys

def main():
    if not len(sys.argv) > 1:
        print("Usage: {0} <version>".format(sys.argv[0]))
        exit(-1)

    try:
        version = sys.argv[1]
        with open("STKVersion.h", "w") as fd:
            fd.write("#define kPackageVersion \"{0}\"".format(version))

    except IOError as e:
        print e


if __name__ == '__main__':
    main()
