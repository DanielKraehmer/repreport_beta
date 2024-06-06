****************** Demo do-file to test the program REPREPORT ******************

/* Note: All do-files in this directory only serve the purpose of beta testing 
the program REPREPORT. They carry no substantial meaning and are, in same cases, 
deliberately quirky to test the program's boundaries.*/

* 01) Master
* - Includes the setup and invokes all other do-files 

* Header
cap log close 
macro drop _all
version 17
set more off
set varabbrev off

* Subroutines
cd ..
include ./do/02_data_retrieval.do

cd ./do
include 03_data_management.do

cd ../data/clean
include ../../do/04_analysis_tables.do

pwd

cd ../../do
include 05_analysis_graphs.do


********************************************************************************
exit 
********************************************************************************