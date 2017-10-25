import sys
import json

from lib import parser, pipfile_parser

if __name__ == "__main__":
    args = json.loads(sys.stdin.read())

    if args["function"] == "parse":
        print(parser.parse(args["args"][0]))
    elif args["function"] == "parse_pipfile":
        print(pipfile_parser.parse(args["args"][0]))
