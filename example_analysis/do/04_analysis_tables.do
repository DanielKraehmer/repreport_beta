****************** Demo do-file to test the program REPREPORT ******************

/* Note: All do-files in this directory only serve the purpose of beta testing 
the program REPREPORT. They carry no substantial meaning and are, in same cases, 
deliberately quirky to test the program's boundaries.*/

* 04) Analysis (tables)
* - Creates and exports descriptives and regression tables for the auto data

* Descriptives
use ../clean/auto_analysis.dta, clear

table (foreign) (price_cat), ///
	statistic(frequency) statistic(percent) nototals ///
	nformat(%6.1f percent) sformat("%s%%" percent)

collect dims
collect label list price_cat, all
collect label dim price_cat "Price (category)", modify
collect style cell border_block, border(right, pattern(nil))
collect preview

collect style putdocx, layout(autofitcontents) ///
	title("Table 1: Descriptives of Origin by Price")
collect export ../../output/descriptives.docx, as(docx) replace

* Regression
regress price /* length */ weight
esttab using ../../output/regression.rtf, replace