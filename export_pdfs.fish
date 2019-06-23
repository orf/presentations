#!/usr/bin/env fish


for f in $argv[1]/*.md
    ./utils/desckset-scripts/markdown-to-pdf/markdown-to-pdf.sh (pwd)/$f
end
