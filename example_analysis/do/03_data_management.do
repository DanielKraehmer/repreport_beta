****************** Demo do-file to test the program REPREPORT ******************

/* Note: All do-files in this directory only serve the purpose of beta testing 
the program REPREPORT. They carry no substantial meaning and are, in same cases, 
deliberately quirky to test the program's boundaries.*/

* 03) Data Management
* - Cleans and (re)labels the data, creates new variables, etc.

**# Dataset 1: Auto
use ../data/clean/auto_modified.dta, clear
describe 
* 50 obsverations, 6 variables

regress price weight
/* Interpretation: With every 1-unit increase in weight (+ 1 lbs.), the price of
the car increases by 2.3 USD. */
esttab

tab rep78 // strange, only 47 observations?

local mycommand fre
`mycommand' rep78 // 3 missing obsverations!

* Further descriptives
#delimit ;

tab 	// cross tab
	rep78	// repairs
	foreign // origin
; 

sum 	// summaries
	price
	weight
	length
	foreign
; 

fre 	// frequency tables
	rep78
	foreign
;
#delimit cr

tab /// cross tab, again
	rep78 ///
	foreign
	
* Keep only non-missing observations
ds
local allvar = subinstr("`r(varlist)'", " ", ", ", .)
drop if missing(`allvar')

* Categorize price variable
egen price_cat = cut(price), at(0 5000 10000 20000) icodes // see help egen
tab price price_cat
lab define price_cat_lbl 0 "Low" 1 "Medium" 2 "High"
lab val price_cat price_cat_lbl
tab price price_cat

* Save data
save ../data/clean/auto_analysis.dta, replace


**# Dataset 2: Life Expectancy (Stata)
u ../data/clean/lifeexp_original.dta, replace
describe
gen year = 1998

fre region
keep if region == 3
save ../data/clean/lifeexp_cleaned.dta, replace


**# Dataset 3: Life Expectancy (WHO)
us ../data/clean/WHO_lifeexpectancy.dta, replace
describe

* Keep only countries from South America
keep if inlist(geo_name_short, "Argentina", "Bolivia", "Brazil", "Chile") ///
	| inlist("Colombia", "Ecuador", "Paraguay", "Peru", "Uruguay", "Venezuela")

drop if dim_sex != "Total"
gen lexp = round(value_numeric, 1)
rename dim_time year
rename geo_name_short country 
keep country year lexp
save ../data/clean/WHO_cleaned.dta, replace


**# Dataset 4: Append life expectancy datasets
append using ../data/clean/lifeexp_cleaned.dta
sort country
bysort country: drop if _N == 1
keep country year lexp
save ../data/clean/life_expectany_analysis.dta, replace

* Counting
forvalues i= 1/5 {
	display "`i'"
}
