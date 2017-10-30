# Downloads the binary from iClicker flash to a file
# Usage: ./download.sh <output file> <device>
avrdude -v -P $2 -c avrisp -p m8 -b 19200 -U flash:r:$1:r
