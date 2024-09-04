all: main.pdf

main.pdf: main.tex ref.bib
    pdflatex main.tex
    bibtex main
    pdflatex main.tex
    pdflatex main.tex

clean:
    rm -f *.aux *.bbl *.blg *.log *.out *.pdf
