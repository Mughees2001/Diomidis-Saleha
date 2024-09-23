```git log -M -m --pretty=tformat:'commit %H %ct' --topo-order --reverse -U0 ../test/beta.txt | perl line_changes.pl ```

used perltidy and mypy for formatting 
wrote test cases ( unit tests and integration tests)

to do: 
ci workflow/ regression testing 
make seaparate repo for testing 
add requirements.txt 
makefile.pl 
code for repo mining
test code coverage
add mypy and perltidy in ci