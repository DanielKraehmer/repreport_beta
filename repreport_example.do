* Demo Example: REPREPORT (beta version)
clear all

/* Note: This do-file uses a fictitious data analysis (dir "example_analysis")
to demonstrate the capabilities of REPREPORT. The example mimics a real-world 
data analysis with various datasets, data processing steps, and imports/exports 
of data, tables, and graphs (in various formats). */ 

/* STEP I:
For this demo to run smoothly, make sure that you are able to run the example 
analysis (like a "real" researcher would be able to do). To do this, execute the 
following lines: */

cd ./example_analysis/do
include 01_master.do
cd ../..

/* If you don't get any error message, continue with the REPREPORT demo below. 
Otherwise, trouble-shoot the error message, e.g. by installing the following 
user-written commands:
ssc install fre 
ssc install estout
ssc install palettes
ssc install colrspace
*/


/* STEP II:
Run the example analysis again, this time using REPREPORT (see below). 
Determine where repreport's output should be saved by specifying the local.
*/

include repreport_program.do
cd ./example_analysis/do

repreport_open
include 01_master.do
repreport_close using ../..
cd ../..

exit
