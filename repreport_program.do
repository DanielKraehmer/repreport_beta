*! beta version \ Daniel Krähmer \ June 2024


********************************************************************************
* Program for opening a REPREPORT
********************************************************************************
cap program drop repreport_open
program repreport_open
syntax

* Save system information (at start of analysis) in tmpdir
foreach j in current_date current_time pwd rng rngstate linesize{
	file open `j' using "`c(tmpdir)'/`j'.txt", write replace
	file write `j' "`c(`j')'"
	file close `j'
}

* Open log file that documents the entire analysis
set linesize 255
log using "`c(tmpdir)'/repreport.txt", text name(replog) replace

end 


********************************************************************************
* Program for closing and compiling a REPREPORT
********************************************************************************
cap program drop repreport_close
program repreport_close
syntax using/

qui{

* Test for fatal conditions 
local dir "`c(pwd)'"
cap cd `using'
if _rc != 0 {
	cd "`dir'"
	noisily display as error "unable to change to `using'"
	exit
}
else{
	local maindir "`c(pwd)'"
}
cd "`dir'"	
log close replog

*preserve 


**# 0) Preliminaries
cap mkdir "`maindir'/repreport"
foreach folder in ados input output {
	cap mkdir "`maindir'/repreport/`folder'"
} 

* Access information stored in txt-files (from repreport_open)
foreach file in current_date current_time pwd rng rngstate linesize {
	local `file' = subinstr(fileread("`c(tmpdir)'/`file'.txt"), "\", "/", .)
}

* Read in analysis log-file and reverse-engineer Stata command history
import delimited using "`c(tmpdir)'/repreport.txt", clear varnames(nonames) delim("\t")

* Keep commands (lines starting with . or >) and loops (lines starting with #.)
local command inlist(substr(v1, 1, 1), ".", ">")
local loop regexm(substr(strtrim(v1), 1, strpos(strtrim(v1), " ")), "([0-9]+)(\.)")
keep if `command' | `loop'

* Drop empty commands (.) and line comments
drop if strtrim(v1) == "."								
drop if substr(stritrim(strtrim(v1)), 1, 3) == ". *"

* Flag multiline observations + remove anything after inline/multiline comments
gen multiline = substr(v1[_n], 1, 1) == ">" | substr(v1[_n+1], 1, 1) == ">"
replace v1 = strtrim(substr(v1, 1, strpos(v1, "//") - 1))  if strpos(v1, " //")
replace v1 = strtrim(substr(v1, 1, strpos(v1, "///") - 1))  if strpos(v1, "///")

* Delete trailing and leading characters that indicate a multiline command
replace v1 = subinstr(v1, "///","", .)
replace v1 = strtrim(subinstr(v1, ">","", 1))

* Group multiline commands into blocks and concatenate (full code in last obs)
gen newblock = 1  if multiline != multiline[_n-1]
gen block = sum(newblock)
sort block, stable
by block : gen concat = v1 if _n == 1 & multiline == 1
by block : replace concat = concat[_n-1] + " " + v1 if _n > 1 & multiline == 1
replace concat = "" if missing(newblock[_n+1])

* Generate updated command variable and reduce dataset
gen fullcommand = v1 if multiline == 0
replace fullcommand = concat if !missing(concat)
replace fullcommand = strtrim(subinstr(fullcommand, ".","", 1))
keep fullcommand

* Remove anything between multiline comments (/* ... */)
gen mlcomment = 1 if strpos(fullcommand, "/*") 
split fullcommand, parse("/*" "*/") generate(part)
replace fullcommand = "" if mlcomment == 1

* Concatenate part of multiline comments in loop and write into command variable
ds part*
local nwords: word count `r(varlist)'
forvalues i = 1(2)`nwords'{
	replace fullcommand = fullcommand + part`i' if mlcomment == 1
}

* Note: This solution does not work for nested multiline comments like:
* tab weight /*brace yourself this is /* very weird*/ */ foreign /*price*/

* Clean command variable and drop observations with missing values
drop if missing(fullcommand)
keep fullcommand
replace fullcommand = stritrim(fullcommand)
gen command = fullcommand
replace command = strtrim(substr(fullcommand, 1, strpos(fullcommand, " "))) ///
	if strpos(fullcommand, " ")

* Flag start/end of loops
gen loopstart = inlist(command, "forvalues", "foreach", "while", "for")
gen loopend = regexm(fullcommand, "([0-9]+) }")

* Number loops consecutively
gen loop = sum(loopstart) if loopstart > 0
replace loop = loop[_n-1] if loopend[_n-1] != 1 & loopstart != 1

* Flag body/delimiters of loops
gen loopbody = cond(!missing(loop) & loopstart != 1 & loopend != 1, 1, 0)
gen loopdelim = 1 if !missing(loop) & loopbody == 0

* Drop all lines that start with a number but are not (!) part of a loop
drop if regexm(command, "([0-9]+)") & missing(loop)

* Remove numbers from fullcommands that belong to a loop 
replace fullcommand = subinstr(fullcommand, word(fullcommand, 1), "", 1) ///
	if !missing(loop) & loopstart != 1
drop if strtrim(fullcommand) == "."		

* Duplicate all macro definitions (one set will have to be executed)
gen order = _n
expand 2 if substr(fullcommand, 1, 3) == "loc", gen(duplicate)
sort order duplicate

* Prefix loop lines with "{res}" (will serve as a flag to identify executed commands)
gen fullcommand_prefixed = strtrim(fullcommand), before(fullcommand)
order fullcommand_prefixed loopbody
replace fullcommand_prefixed = `"{res} "' + fullcommand_prefixed if loopbody == 1

* Prefix all commands (except the duplicated locals!) with "display `" ..."' "
replace fullcommand_prefixed = `"display "' ///
	+ char(96) + char(34) 	/// opening double quotes
	+ fullcommand_prefixed 	/// command
	+ char(34) + char(39) 	/// closing double quotes
	if missing(loopdelim) & duplicate == 0

* Keep fullcommand_dis only and export to dataset
local fmt: format fullcommand_prefixed
local fmt: subinstr local fmt "%" "%-"
format fullcommand_prefixed `fmt'

keep fullcommand_prefixed
outfile using "`c(tmpdir)'/temp.do", noquote replace

* Run do-file and capture results in log
log using "`c(tmpdir)'/prefix_display.txt", replace
noisily do "`c(tmpdir)'/temp.do"
log close

* Read in log-file
import delimited using "`c(tmpdir)'/prefix_display.txt", clear varnames(nonames) delim("\t")
replace v1 = strtrim(v1)
local fmt: format v1
local fmt: subinstr local fmt "%" "%-"
format v1 `fmt'

* Keep commands only (as interpreted by Stata) and strip prefix
keep if substr(v1, 1, 5) == "{res}"
replace  v1 = strtrim(substr(v1, 6, .))
rename v1 fullcommand

* Remove delimiter changes and braces (these cause problems later otherwise)
replace fullcommand = "" if inlist(substr(fullcommand, 1, 1), "}")
gen delimflag = 1 if substr(fullcommand, 1, 2) == "#d"
replace fullcommand = subinstr(fullcommand, word(fullcommand, 1), "delimit", 1) if delimflag == 1

* Clean command variable and drop observations with missing values
drop if missing(fullcommand)
replace fullcommand = stritrim(fullcommand)
gen command = fullcommand
replace command = strtrim(substr(fullcommand, 1, strpos(fullcommand, " "))) ///
	if strpos(fullcommand, " ")


**# 1) User-written commands

* Create commandtype and version variable 
gen commandtype = .
lab define commandtype_lbl 1"Built-in" 2"Stata Base" 3"User written" 4"Unidentifiable", modify
lab val commandtype commandtype_lbl
gen version = ""

* Loop over commands and classify them
levelsof command
foreach command in `r(levels)'  {
	
	if !inlist("`command'", "repreport_close", "delimit") {
	local vers
	
	* Remove options (if applicable)
	local command_comma `command'
	if strpos("`command'", ",") {
		local command = substr("`command'", 1, strrpos("`command'", ",")-1)
	}
	
	* Check command's version and save output in log-file
	log using `command'.txt, text name(`command') replace
	cap noisily which `command'
	log close `command'
	
	* Read content of log file, scan for key words and extract details
	local logtext = fileread("`command'.txt")
	
	if strpos(`"`logtext'"', "built-in command") {
		replace commandtype = 1 if command == "`command'"
	}
	
	else {
		
		* Extract command's version number
		local versionpos = strpos(`"`logtext'"', " version ") + 9
		local vers = strtrim(substr(`"`logtext'"', `versionpos', .))
		local blankpos = strpos(`"`vers'"', " ")
		local vers = strtrim(substr(`"`vers'"', 1, `blankpos'))
		
		* Create locals with paths to ado directories
		foreach dir in base plus personal {
			local `dir'_backsl = subinstr("`c(sysdir_`dir')'", "/", "\", .)
		}
		
		* Look for command name in either base, plus, or personal ado directory
		if strpos(`"`logtext'"', "`base_backsl'") {
			replace commandtype = 2 if command == "`command'"
		}
		else if strpos(`"`logtext'"', "`plus_backsl'") | strpos(`"`logtext'"', "`personal_backsl)'"){
			replace commandtype = 3 if command == "`command'"
		}
		else if strpos(`"`logtext'"', "not found as either built-in or ado-file") { 
			replace commandtype = 4 if command == "`command_comma'"
		}
	}
	replace version = `"`vers'"' if command == "`command'"
	
	* Clean up
	erase `command'.txt
	}
}

* Improve visuals in editor and reduce dataset
foreach variable in command version {
	char `variable'[_de_col_width_] 20
	local fmt: format `variable'
	local fmt: subinstr local fmt "%" "%-"
	format `variable' `fmt'
}

* Loop over user-written commands and write their name and version into local
levelsof command if commandtype == 3, clean
local adonames `r(levels)'

* Determine max number of characters (for column width of table in report)
if "`adonames'" != "" {
	local wordCount : word count `adonames'
	local width 17 // minimum column width
	
	* Update width (if needed)
	forval i = 1/`wordCount' {
		local currentword : word `i' of `adonames'
		local length : strlen local currentword
		if `length' + 10 > `width' local width = `length' + 10
	}	
}

* Adapt line separator based on width (-----)
forvalues i = 1/`=`width' + 10' {
	local lineseparator "`lineseparator'-"
}

* Add scaffold for report 
# delimit ;
local ados `"
	"`lineseparator'"
	_n _col(1) "Command" _col(`width') "Version"
	_n "`lineseparator'" 
	_n
"'
;
#delimit cr

* Loop over user-written ados and append them to scaffold
foreach ado in `adonames' {
	levelsof version if command == "`ado'", clean
	local ados `"`ados' _col(1) "`ado'" _col(`width') "`r(levels)'" _n"'
}

* Loop over unidentifiable ados (if applicable) and put them in a local 
levelsof command if commandtype == 4, clean separate(", ")
if "`r(levels)'" != "" local unidentified "Unidentified commands: `r(levels)'"


**# 2) Input Files (e.g., Datasets) 

* Add variable that tracks the current working directory throughout the code
insobs 1, before(1)
gen wd = "`pwd'" if _n == 1

* Establish order of commands
gen order = _n

* Generate indicator for directory changes and update wd
gen dirchange = command == "cd"
replace wd = substr(fullcommand, strpos(fullcommand, " "), .) if dirchange == 1
* Note: Assumes that users use quotes for their file path
gen dirchange_block = sum(dirchange) 
sort order, stable
replace wd = wd[_n-1] if _n != 1 & missing(wd)
replace wd = subinstr(wd, "\", "/", .)
replace wd = subinstr(wd, `"""', "", .)

* Remove ./ and create new wd variable
replace wd = strtrim(wd)
replace wd = substr(wd, 2, .) if substr(wd, 1, 2) == "./"
gen relpath = cond(regexm(wd, "^[A-Za-z]:"), 0, 1) // 0: no, 1: yes
gen wd_new = wd

* Turn relative into absolute file paths
forval i = 2/`=_N' {
	
	if relpath[`i'] == 1 {
		
		* Count how many levels we need to go up
		local before = strtrim(wd[`i'])
		local after = subinstr("`before'", "..", "", .)
		local levels_up = (length("`before'") - length("`after'")) / 2
		if `levels_up' > 0 local after = substr("`after'", `levels_up', .)
		
		* Extract last absolute path
		summarize order if relpath == 0, meanonly
		local lastabs = wd[`r(max)']
				
		* Walk up the last absolute path as far as needed (see levels_up)
		while `levels_up' > 0 {
			local lastabs = substr(`"`lastabs'"', 1, strrpos(`"`lastabs'"', "/") - 1)
			local levels_up = `levels_up' - 1
		}
		
		* Concatenate remainder of absolute path + relative path & replace
		qui levelsof dirchange_block if _n == `i', local(dirblock)
		replace wd = "`lastabs'`after'" if _n >= `i' & dirchange_block == `dirblock'
		replace relpath = 0 if _n >= `i' & dirchange_block == `dirblock'
		
		* Clean up
		macro drop _lastabs
	}
}
replace wd = substr(wd, 1, length(wd) - 1) if substr(wd, -1, 1) == "/"

* Flag commands that load/save files (i.e. datasets)
gen command_noabbrev = command 
replace command_noabbrev = "use" 	if inlist(command, "u", "us")
replace command_noabbrev = "infile" if inlist(command, "inf", "infi", "infil")
replace command_noabbrev = "append" if inlist(command, "app", "appe", "appen")
replace command_noabbrev = "merge" 	if inlist(command, "mer", "merg")
replace command_noabbrev = "infile"	if inlist(command, "inf", "infi", "infil")

replace command_noabbrev = "save"	if inlist(command, "sa", "sav")
replace command_noabbrev = "xmlsave" if inlist(command, "xmlsav")
replace command_noabbrev = "outfile" if inlist(command, "ou", "out", "outf", "outfi", "outfil")

gen load = inlist(command_noabbrev, "use", "import", "file", "merge", "append", "infile", "insheet", "webuse", "xmluse")
gen save = inlist(command_noabbrev, "save", "saveold", "export", "xmlsave", "outfile")

gen temp = fullcommand if load == 1 | save == 1 
gen filepath = stritrim(strtrim(temp))

* Delete first word (for "use" and "save")
replace filepath = substr(filepath, strpos(filepath, " ") + 1, .) ///
	if inlist(command_noabbrev, "use", "save")

* Delete first and second word (for "import", "export", "append", "merge")
replace filepath = subinstr(filepath, word(filepath, 1) + " " + ///
	word(filepath, 2) + " ", "", 1) ///
	if inlist(command_noabbrev, "import", "export", "append", "merge") 

* Delete remaining words (anything before "using")
replace filepath = substr(filepath, strpos(filepath, "using") + 6, .) ///
	if strpos(filepath, "using")

* Fix remaining blanks and strip all options
replace filepath = stritrim(strtrim(filepath)) 
replace filepath = substr(filepath, 1, strrpos(filepath, ",") - 1) if strpos(filepath, ",")

* Get rid of all backslashes and split filepath in file and path
replace filepath = subinstr(filepath, "\", "/", .)
gen input_path = strtrim(substr(filepath, 1, strrpos(filepath, "/") - 1))
gen input_file = strtrim(substr(filepath, strrpos(filepath, "/") + 1, .))
gen input_filepath = filepath

* Resolve relative names in "path" (similar to above)
gen path_full = ""
replace path_full = wd + "/" + filepath if !strpos(filepath, "/") & !missing(filepath)
replace input_path = substr(input_path, 2, .) if substr(input_path, 1, 2) == "./"
gen flag_rel = cond(regexm(input_path, "^[A-Za-z]:"), 0, 1) if !missing(input_path)
forval i = 1/`=_N' {
	if flag_rel[`i'] == 1 {
		
		* Count how many levels we need to go up
		local before = strtrim(input_path[`i'])
		local after = subinstr("`before'", "..", "", .)
		local levels_up = (length("`before'") - length("`after'")) / 2
				
		* Walk up the current absolute path as far as needed
		levelsof wd if _n == `i', local(lastabs) clean
		while `levels_up' > 0 {
			local lastabs = substr(`"`lastabs'"', 1, strrpos(`"`lastabs'"', "/") - 1)
			local levels_up = `levels_up' - 1
		}
		
		* Concatenate remainder of absolute path + relative path & replace
		replace path_full = "`lastabs'" + "`after'" + "/" + input_file if _n == `i'
		
		* Clean up
		macro drop _lastabs
	}
}

* Clean up
drop temp filepath flag_rel
sort order
drop if _n == 1
replace order = _n

* Count max characters in filename & path (for column width of table in report)
gen path = strtrim(substr(path_full, 1, strrpos(path_full, "/") - 1))
gen file = strtrim(substr(path_full, strrpos(path_full, "/") + 1, .))
foreach var in path file {
	egen smax = max(strlen(`var'))
	local max_`var' = smax[1] + 10
	drop smax
}

* Check loads against saves
gen load_nosave = load
forvalues i = 1 / `=_N' {
    if load[`i'] == 1 {
        local current_path = path_full[`i']
	
        * Check if the current path_full value exists in previous observations where load is 1
        forvalues j = 1 / `=`i'-1' {			
			if path_full[`j'] == "`current_path'" & save[`j'] == 1 {
                replace load_nosave = 0 in `i'
                continue, break
            }
        }
    }
}

* Adapt line separator based on width (-----)
forvalues i = 1/`=`max_file'+`max_path'+30' {
	local lineseparator2 "`lineseparator2'-"
}

* Add scaffold for report 
# delimit ;
local data `"
	"`lineseparator2'"
	_n 	_col(1) 						"File" 
		_col(`max_file') 				"Path"
		_col(`=`max_file'+`max_path'')	"Data Signature (if applicable)" 	
	_n "`lineseparator2'" 
	_n
"'
;
#delimit cr

* Loop over input datasets that are not generated and append them to scaffold
levelsof path_full if load_nosave == 1, local(datasets)
foreach dataset in `datasets' {
	local file = substr("`dataset'", strrpos("`dataset'", "/") + 1, .)
	local path = substr("`dataset'", 1, strrpos("`dataset'", "/") - 1)
	if substr("`file'", strrpos("`file'", "."), .) == ".dta" {
		cap confirm file "`dataset'"
		if _rc == 0 {
			frame create tempframe
			frame change tempframe
			use "`dataset'", clear 
			quietly datasignature
			local sig `r(datasignature)'
			frame change default
			frame drop tempframe
		}
	}
	local data `" `data' _col(1) "`file'" _col(`max_file') "`path'" _col(`=`max_file'+`max_path'') "`sig'" _n"'
	mac drop _sig
}
keep fullcommand command wd order load save load_nosave input_path input_file input_filepath delimflag


**# 3) Subroutines
gen subr_ind = 1 if inlist(command, "include", "do", "run", "ru")
gen subr =  fullcommand if subr_ind == 1
replace subr = substr(subr, strpos(subr, " ") + 1, .) 	// delete command (do, run, include)
replace subr = subinstr(subr, "\", "/", .) 				// change backslashes to forward slashed
replace subr = subinstr(subr, `"""', "", .) 			// strip quotation marks
replace subr = substr(subr, 1, strrpos(subr, ",") - 1) if strpos(subr, ",") // strip options

* Flag relative paths and remove "./" at the beginning
replace subr = strtrim(subr)
replace subr = strtrim(subr)
replace subr = substr(subr, 3, .) if substr(subr, 1, 2) == "./"

gen relpath = strpos(subr, "../") > 0

* Get file path
gen subr_full_path = ""

* Turn relative into absolute file paths
forval i = 1/`=_N' {
	
	if relpath[`i'] == 1 {
		
		* Count how many levels we need to go up
		local before = strtrim(subr[`i'])
		local after = subinstr("`before'", "..", "", .)
		local levels_up = (length("`before'") - length("`after'")) / 2
		if `levels_up' > 0 local after = substr("`after'", `levels_up', .)
		
		* Extract absolute path and walk up as far as needed
		local abs = wd[`i']
		while `levels_up' > 0 {
			local abs = substr(`"`abs'"', 1, strrpos(`"`abs'"', "/") - 1)
			local levels_up = `levels_up' - 1
		}
		
		* Concatenate
		replace subr_full_path = "`abs'" + "`after'" in `i'
		
		* Clean up
		macro drop _abs
	}
}
replace subr_full_path = wd + "/" + subr if !missing(subr) & relpath == 0

* Extract filename and filepath of subroutine
local cutpoint = strrpos(subr_full_path, "/")
gen subr_path = substr(subr_full_path, 1, `cutpoint' - 1)
gen subr_file = substr(subr_full_path, `cutpoint' + 1, .)

* Add scaffold for report 
# delimit ;
local routines `"
	"-------------------------------------------------------------"
	_n "File" _col(30) "Original path"
	_n "-------------------------------------------------------------"
	_n
"'
;
#delimit cr

* Loop over routines and write names and paths into local
sort subr_ind order
qui count if !missing(subr)
forvalues i = 1/`r(N)' {
	local file = subr_file[`i']
	local path = subr_path[`i']
	local routines `"`routines' _col(1) "`file'" _col(30) "`path'" _n"'
}


**# 4) Randomness
local randomness 0

if "`rngstate'" != "`c(rngstate)'" { // if rngstate has changed --> randomness
	local randomness 1
}
else { // double check common functions & commands involving randomness
	#delim ;
	local randomfunctions	
	`"rbeta\("'
	`"rbinomial\("'
	`"rcauchy\("'
	`"rchi2\("'
	`"rexponential\("'
	`"rgamma\("'
	`"rhypergeometric\("'
	`"rigaussian\("'
	`"rlaplace\("'
	`"rlogistic\("'
	`"rnbinomial\("'
	`"rnormal\("'
	`"rpoisson\("'
	`"rt\("'
	`"runiform\("'
	`"runiformint\("'
	`"rweibull\("'
	`"rweibullph\("'
	;
	#delim cr
	local randomcommands sample simulate permute bootstrap
	
	foreach element in `"`randomfunctions'"' {
		sum order if regexm(fullcommand, "`element'") == 1
		local randomness = `randomness' + r(N)
	}
	foreach element in `randomcommands' {
		sum order if word(fullcommand, 1) == "`element'"
		local randomness = `randomness' + r(N)
	}
}

if `randomness' == 0 {
	local randomocc "No randomness detected (no change in rngstate)"
}
else if `randomness' >= 1 {
	local randomocc "Yes, randomness detected (change in rngstate)"
}

* Check if random number generator was set
local rng = fileread("`c(tmpdir)'/rng.txt")

sum order if substr(fullcommand, 1,7) == "set rng"
return list
if r(N) > 0 {
	levelsof fullcommand if order == `r(mean)', clean
	local rng: word 3 of `r(levels)'
}

* Check if seed was set
sort order
sum order if substr(fullcommand, 1,6) == "set se"
local sdef = r(N)
local seedval "N.A."

if `sdef' == 0 {
	local seedno "No"
}
else if `sdef'  == 1 {
	local seedno "Yes"
	levelsof fullcommand if regexm(fullcommand[`r(min)'],"([0-9]+)"), clean
	local seedval = real(regexs(1))	
}
else {
	local seedno "Yes, multiple"
}


**# 5) General information

* Extract start time from datetime.txt and calculate runtime
foreach j in date time {
	local `j'_start = strtrim(fileread("`c(tmpdir)'/current_`j'.txt"))
}
local start = clock("`date_start' `time_start'", "DMY hms")
local stop 	= clock("`c(current_date)' `c(current_time)'", "DMY hms")
local runtime = clockdiff(`start', `stop', "second")
local date_trimmed = strtrim("`c(current_date)'")

* Convert time difference to HH:MM:SS format
local h 	= int(`runtime' / 3600)
local m 	= int((`runtime' - (`h' * 3600)) / 60)
local s 	= mod(`runtime', 60)
local runtime 	= "`=string(`h', "%02.0f")':`=string(`m', "%02.0f")':`=string(`s', "%02.0f")'"


**# 6) Generate REPREPORT

local colwidth 18
file open repreport using "`maindir'/repreport/REPREPORT.txt", write replace
#delimit ;
file write repreport 
	"***************************************************" _n 
	"Reproduction Report (created using ado 'REPREPORT')" _n 
	"***************************************************" 
	_n 
	_n "*** General Information"
	_n "Date:" 		_col(`colwidth') 	"`date_trimmed'"
	_n "Start:" 	_col(`colwidth') 	"`time_start' (`date_start')"
	_n "Stop:" 		_col(`colwidth') 	"`c(current_time)' (`date_trimmed')"
	_n "Runtime:"	_col(`colwidth') 	"`runtime'"
	_n _n
	_n "*** System Information"
	_n "Stata Version:" _col(`colwidth') 	"`c(stata_version)'"
	_n "Version (set):" _col(`colwidth')	"`c(version)'"
	_n "Update level:"  _col(`colwidth')	"`c(born_date)'"
	_n "Edition:"		_col(`colwidth')	"`c(edition_real)'"
	_n "OS:" 			_col(`colwidth')	"`c(os)'"
	_n "Machine:" 		_col(`colwidth')	"`c(machine_type)'"
	_n _n
	_n "*** Setup Information"
	_n "Var. Abbrev.:" 	_col(`colwidth') "`c(varabbrev)'"
	_n "Niceness:" 		_col(`colwidth') "`c(niceness)'"
	_n _n
	_n "*** User-written commands"
	_n `ados'
	_n
	_n "*** Input Files (i.e. datasets)"
	_n `data'
	_n
	_n "*** Subroutines (i.e. other do-files)"
	_n `routines' 
	_n 
	_n "*** Randomness"
	_n "Randomness:" 	_col(`colwidth') 	"`randomocc'"
	_n "RNG:" 			_col(`colwidth')	"`rng'"
	_n "Seed set?" 		_col(`colwidth') 	"`seedno'"
	_n "Seed value:" 	_col(`colwidth') 	"`seedval'"
	_n
	_n
	;
#delimit cr	
file close repreport


**# 7) Compile reproduction material
* Ado files
foreach ado in `adonames' {
	local firstletter = substr("`ado'", 1, 1)
	local adopath_plus = "`c(sysdir_plus)'`firstletter'/`ado'.ado"
	cap confirm file "`adopath_plus'"
	if _rc == 0 {
		copy "`adopath_plus'" "`maindir'/repreport/ados/", replace
	}
	else {
		local adopath_pers = "`c(sysdir_personal)'`ado'.ado"
		cap confirm file "`adopath_pers'"
		if _rc == 0 {
			copy "`adopath_pers'" "`maindir'/repreport/ados/", replace
		}
	}
}

* Datasets
foreach dataset in `datasets' {
	copy "`dataset'" "`maindir'/repreport/input/", replace
}

*** "Brute Force" Do-File ***
drop if _n == _N
drop if subr_ind == 1
drop if command == "cd"

* Clean paths for inputs and outputs
replace fullcommand = regexr(fullcommand,input_filepath, "./input/" + input_file) if load == 1 & load_nosave == 1
replace fullcommand = regexr(fullcommand,input_filepath, "./output/" + input_file) if save == 1
replace fullcommand = regexr(fullcommand,input_filepath, "./output/" + input_file) if load == 1 & load_nosave == 0

* Handle delimiters, exports, and using 
replace fullcommand = subinstr(fullcommand, word(fullcommand, 1), "#delimit", 1) if delimflag == 1
replace fullcommand = subinstr(fullcommand, word(fullcommand, 1), "graph", 1) if substr(fullcommand, 1, 2) == "gr"

* Target word after export
gen export_ind = 1 if word(fullcommand, 2) == "export" & load == 0
gen target = word(fullcommand, 3) if export_ind == 1
replace target = substr(target, strrpos(target, "/") + 1, .) if strpos(target, "/")
replace fullcommand = subinstr(fullcommand, word(fullcommand, 3), "./output/" + target, 1) if export_ind == 1
drop target

* Target word after using
gen using_ind = cond(strpos(fullcommand, "using") & load == 0, 1, 0)
gen target = ""
levelsof fullcommand if using_ind == 1, local(using_commands)
foreach level in `r(levels)' {
	local pos: list posof "using" in level
	local target = word("`level'", `=`pos'+1')
	local replacement = substr("`target'", strrpos("`target'", "/") + 1, .)
	replace fullcommand = subinstr(fullcommand, word(fullcommand, `=`pos'+1'), "./output/" + "`replacement'", 1) if fullcommand == "`level'"
}

* Udate ado path
insobs 1, before(1)
replace fullcommand = `"adopath ++ "`maindir'/repreport/ados""' in 1

outfile fullcommand using "`maindir'/repreport/reproduction.do", noquote replace


**# 8) Cleanup
foreach file in current_date current_time prefix_display pwd rng linesize rngstate repreport{
	cap erase "`c(tmpdir)'/`file'.txt"
}
erase "`c(tmpdir)'/temp.do"

cd `"`pwd'"'
set linesize `linesize'
* restore
}
end
