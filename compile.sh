# Compiles files formatted like those in the code/ repository
# Usage: ./compile <file>
egrep -o "    [0-9a-f]{4,8}    " $1 | egrep -o "[0-9a-f]{4,8}" | sed ':a;N;$!ba;s/\n//g' | xxd -r -p
