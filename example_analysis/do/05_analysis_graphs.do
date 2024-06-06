****************** Demo do-file to test the program REPREPORT ******************

/* Note: All do-files in this directory only serve the purpose of beta testing 
the program REPREPORT. They carry no substantial meaning and are, in same cases, 
deliberately quirky to test the program's boundaries.*/

* 05) Analysis (graphs)
* - Creates and exports graphs for the life expectancy data

/* Graphical analysis */
use ../data/clean/life_expectany_analysis.dta, clear
sort country year

colorpalette viridis

#delim ;
twoway 
	(connected lexp year if country == "Argentina", 
		color("108 172 228") msym(O) msize(medlarge) lpattern(dash))
	(scatter lexp year if country == "Argentina" & year == 2019, 
		mlabcolor("108 172 228") msym(none) mlabel(country) mlabpos(3) mlabgap(2))
	
	(connected lexp year if country == "Brazil", 
		color("0 151 57") msym(S) msize(medlarge) lpattern(dash))
	(scatter lexp year if country == "Brazil" & year == 2019, 
		mlabcolor("0 151 57") msym(none) mlabel(country) mlabpos(3) mlabgap(2))
		
	(connected lexp year if country == "Chile", 
		color("218 41 28") msym(T) msize(medlarge) lpattern(dash))
	(scatter lexp year if country == "Chile" & year == 2019, 
		mlabcolor("218 41 28") msym(none) mlabel(country) mlabpos(3) mlabgap(2))
	, 
		graphregion(color(white)) 
		xlab(1995(5)2020)
		xscale(range(2022))
		ylab(, angle(0))
		xtitle("") ytitle("Life Expectancy (years)")
		legend(off)
	;
#delim cr

gr export ../output/trend_life_expectancy.pdf, replace

use ../data/raw/mydata.dta, clear

scatter price weight

graph export ../output/price_weight.pdf, replace


