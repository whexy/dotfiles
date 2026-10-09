import os
import sys

args = sys.argv[1:]
if '-W' in args:
    remote = args[args.index('-W') + 1]
    os.execvp('socat', ['socat', 'STDIO', f'UNIX-CONNECT:{remote}'])
else:
    os.execvp('sh', ['sh', '-s'])
