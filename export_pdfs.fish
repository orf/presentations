#!/usr/bin/env fish


for f in */*.md
    ./utils/desckset-scripts/markdown-to-pdf/markdown-to-pdf.sh (pwd)/$f
end
