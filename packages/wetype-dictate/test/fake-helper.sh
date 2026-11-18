#!/bin/sh
# Stands in for wetype_dictate.py: FAKE_MODE picks how the session ends.
printf 'status\tListening…\n'
printf 'partial\tone two\n'
cat >/dev/null
case "$FAKE_MODE" in
final) printf 'status\tPolishing…\npartial\tone two three\nfinal\tOne, two.\\nThree \\\\o/\n' ;;
error) printf 'status\tDictation failed\nerror\t\n' ;;
crash) exit 1 ;;
esac
