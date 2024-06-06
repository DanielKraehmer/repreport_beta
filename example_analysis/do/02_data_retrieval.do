****************** Demo do-file to test the program REPREPORT ******************

/* Note: All do-files in this directory only serve the purpose of beta testing 
the program REPREPORT. They carry no substantial meaning and are, in same cases, 
deliberately quirky to test the program's boundaries.*/

* 02) Data Retrieval
* - Retrieves two system datasets (auto, lifeexp) and one csv-file


* Auto Dataset
sysuse auto.dta, clear
set seed 1234
gen random = runiform()
sort random
keep in 1/50
drop random
keep make price rep78 weight length foreign
save ./data/clean/auto_modified.dta, replace


* Lifeexp Dataset
sysuse lifeexp.dta, clear
save ./data/clean/lifeexp_original.dta, replace


* CSV file
/* World Health Organization 2024, Healthy life expectancy at birth (years). 
https://data.who.int/indicators/i/C64284D (Accessed on 1 May 2024) */
cd ./data/raw
import delimited using C64284D_ALL_LATEST.csv, clear
keep dim_geo_code_m49 geo_name_short dim_time dim_sex value_numeric
cd ..
save ./clean/WHO_lifeexpectancy.dta, replace
export delimited ./clean/WHO_lifeexpectancy.csv, replace
cd ..

