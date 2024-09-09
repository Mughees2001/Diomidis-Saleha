```git log -M -m --pretty=tformat:'commit %H %ct' --topo-order --reverse -U0 ../test/beta.txt | perl line_changes.pl ```
