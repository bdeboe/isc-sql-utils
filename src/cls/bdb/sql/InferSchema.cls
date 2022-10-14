/// Basic class for inspecting a (CSV) file and inferring the probable datatypes for
/// each column. Main entry points are <query>ScanFile</query>, which projects a 
/// result set with one row for each column and <method>InferColumnList</method>, which 
/// structures that information in a DDL-ready format. 
Class bdb.sql.InferSchema
{

ClassMethod Peek(Output data, path As %String, qualifiers As %String = "", readLines As %Integer = 100) As %Status [ Internal ]
{
    #define MaxLineLength 999999
    kill data
    set sc = $$$OK
    try {
        set qualifiers = $s(qualifiers="":{}, '$isobject(qualifiers):##class(%DynamicObject).%FromJSON(qualifiers), 1:qualifiers)
        
        // stash lowercased qualifier keys
        set iterator = qualifiers.%GetIterator()
        while iterator.%GetNext(.key, .value) {
            set qf($$$LOWER(key)) = value
        }
        set verbose = +$g(qf("verbose"))

        set file = ##class(%Stream.FileCharacter).%New()
        set sc = file.LinkToFile(path)
        quit:$$$ISERR(sc)
        do Log("INFO","Reading file '"_path_"'")

        // unless there's definitely no header, skip the first nonempty line
        if '$g(qf("header")) {
            do {
                set line = $zstrip(file.ReadLine($$$MaxLineLength),"<>WC")
            } while (line="") && 'file.AtEnd
            set header = line
        }

        if file.AtEnd {
            do Log("ERROR", "File is empty")
            quit
        }

        // now start reading actual lines
        set lines = 0
        while (lines < readLines) && 'file.AtEnd {
            set lines = lines+1,
                lines(lines) = $zstrip(file.ReadLine($$$MaxLineLength),"<>WC")
        }
        if ('lines) {
            do Log("ERROR", "No lines to sample from")
            quit
        } elseif (file.AtEnd) && (lines < readLines) {
            do Log("WARNING", "Short file, only read "_lines_" nonempty lines for sampling")
        } else {
            do Log("INFO", "Read "_lines_" nonempty lines for sampling")
        }

        // we can close the file now
        kill file

        // assume quote character
        set quote = """"
            
        // identify the field separator
        if $g(qf("columnseparator"))'="" {
            do Log("INFO", "Parsing lines using supplied column separator '"_qf("columnseparator")_"'")
        } else {
            do Log("INFO", "No column separator supplied, checking candidates")

            // find the candidate with lowest variance leading to more than 1 piece
            for i = 1:1:lines {
                set line = $replace($replace(lines(i),quote_quote,""),"\"_quote,""),
                    str = "", prevQuote = 0,
                    nextQuote = $find(line,quote)
                while nextQuote {
                    set nextNextQuote = $find(line,quote,nextQuote+1)
                    quit:'nextNextQuote
                    set str = str_$e(line,prevQuote,nextQuote-2),
                        prevQuote = nextNextQuote,
                        nextQuote = $find(line,quote,prevQuote+1)
                } 
                set str = str_$e(line,prevQuote,*)
                for sep = ",",";","|",$c(9) {
                    set pieces = $l(lines(i),sep) // TODO - could try to weed out the ones between ""
                    set sep(sep) = $g(sep(sep)) + pieces, // sum
                        sep(sep, pieces) = $g(sep(sep, pieces)) + 1
                }
            }

            set sep = "", bestScore = 0
            for {
                set sep = $order(sep(sep),1,sum)
                quit:sep=""
                set l = "", half = lines/2
                for {
                    set l = $o(sep(sep,l),1,cnt)
                    quit:l=""
                    set half = half-cnt
                    if half < 0 {
                        set (mean,sep(sep,"mean")) = l
                        quit
                    }
                }
                set (avg,sep(sep,"avg")) = sum / lines,
                    stddev = 0,
                    pieces = 0
                for {
                    set pieces = $order(sep(sep,pieces),1,cnt)
                    quit:pieces=""
                    set stddev = stddev + (((avg-pieces)**2)*cnt)
                }
                set (stddev,sep(sep,"stddev")) = $s(lines:$zsqr(stddev / lines),1:0)
                if (mean > 1) && ((mean-stddev) > bestScore) {
                    set qf("columnseparator") = sep,
                        bestScore = (mean-stddev)
                }
            }
            if (bestScore = 0) {
                do Log("WARNING", "Could not find a suitable column separator, possibly because there is only one column.")
                set qf("columnseparator") = ","
            }
 
            do Log("INFO", "Assuming the column separator is '"_qf("columnseparator")_"'")
        }
 
        if $g(header)'="" {
            
            if $g(qf("header"))="" {
                // if the user didn't tell us there was a header, check if the first
                // line has numeric values, which likely means it's not a header
                set notSoString = 0, 
                    cols = $l(header,qf("columnseparator"))
                for i = 1:1:cols {
                    set f = $p(header,qf("columnseparator"),i),
                        notSoString = notSoString + $isvalidnum(f) // TODO: dates?
                }
                if (notSoString > 0) { // too bad
                    set header = ""
                    do Log("INFO","Unable to identify a header line, assuming there is none")
                } else {
                    do Log("INFO","Assuming the following header: "_$lts($lfs(header,qf("columnseparator")),", "))
                }
            } else {
                do Log("INFO","Using the following header: "_$lts($lfs(header,qf("columnseparator")),", "))
            }
        } else {
            do Log("INFO","No header in this file")
        }

        // parse lines
        for i = 1:1:lines {
            set line = $replace(lines(i),"\"_quote,quote_quote),
                pieces = $l(line, qf("columnseparator")),
                (p, new) = 1, col = 0
            while p <= pieces {
                set piece = $p(line,qf("columnseparator"),p)
                
                // start of a new column value
                if new {
                    set col = col+1

                    if $e(piece)=quote {
                        // start of new quoted string
                        if ($e(piece,*)=quote) && ($l(piece,quote)#2) {
                            // also ends this piece
                            set new = 1, p = p+1, data(i,col) = piece
                            continue
                        } else {
                            set new = 0, p = p+1, data(i,col) = piece
                            continue
                        }
                    } else {
                        // full non-quoted value
                        set new = 1, p = p+1, data(i,col) = piece
                        continue
                    }

                } else {

                    // continuing existing column value

                    if ($e(piece,*)=quote)  {

                        if '($l(piece,quote)#2) {
                            // ends with this piece
                            set new = 1, p = p+1, data(i,col) = data(i,col)_qf("columnseparator")_piece
                            continue
                        } else {
                            // continuation
                            set new = 0, p = p+1, data(i,col) = data(i,col)_qf("columnseparator")_piece
                            continue
                        }

                    } else {
                        // continuation
                        set new = 0, p = p+1, data(i,col) = data(i,col)_qf("columnseparator")_piece
                        continue
                    }
                }
            }
        }

        // now build some stats
        for i = 1:1:lines {
            set col = ""
            for {
                set col = $order(data(i,col),1,val)
                quit:col=""
                set l = $l(val), 
                    null = ('l) || (val="""""") || (val="NULL"),
                    num = $ISVALIDNUM(val), 
                    dt = val ? 2.4N1"-"1.2N1"-"1.2N, // TODO
                    ts = val ? 2.4N1"-"1.2N1"-"1.2N1" "2N1":"2N1":"2N // TODO
                set stats(col) = $g(stats(col))+1,
                    stats(col,"l") = $g(stats(col,"l"))+l, // total length
                    stats(col,"l",l) = $g(stats(col,"l",l))+1
                set:null stats(col,"null") = $g(stats(col,"null"))+1
                if (num) {
                    set stats(col,"num") = $g(stats(col,"num"))+1
                    set:('$d(stats(col,"min"),min))||(val<min) stats(col,"min")=+val
                    set:('$d(stats(col,"max"),max))||(val>max) stats(col,"max")=+val
                    set decimal = $find(val,".")-1
                    set scale = $s(decimal<0:l-decimal, 1:0)
                    set stats(col,"scale") = $g(stats(col,"scale"))+scale,
                        stats(col,"scale",scale) = $g(stats(col,"scale",scale))+1
                }
                set:dt stats(col,"dt") = $g(stats(col,"dt"))+1
                set:ts stats(col,"ts") = $g(stats(col,"ts"))+1
            }
        }

        set col = ""
        for {
            set col = $order(stats(col),1,count)
            quit:col=""
            if header'="" {
                set data("stats",col) = $piece(header,qf("columnseparator"),col)
            }
            set data("stats",col,"count") = count,
                data("stats",col,"nullPct") = $g(stats(col,"null"))/count,
                data("stats",col,"length","avg") = $g(stats(col,"l"))/count,
                data("stats",col,"length","min") = $o(stats(col,"l","")),
                data("stats",col,"length","max") = $o(stats(col,"l",""),-1)

            set stddev = 0
            set l = ""
            for {
                set l = $order(stats(col,"l",l),1,c)
                quit:l=""
                set stddev = stddev + (((data("stats",col,"length","avg")-l)**2)*c)
            }
            set data("stats",col,"length","stdDev") = $s(count:$zsqr(stddev / count), 1:0)
            
            if $g(stats(col,"num")) {
                set data("stats",col,"min") = $g(stats(col,"min")),
                    data("stats",col,"max") = $g(stats(col,"max")),
                    data("stats",col,"scale","avg") = $g(stats(col,"scale"))/count,
                    data("stats",col,"scale","min") = $o(stats(col,"scale","")),
                    data("stats",col,"scale","max") = $o(stats(col,"scale",""),-1)
                set stddev = 0, s = ""
                for {
                    set s = $order(stats(col,"scale",s),1,c)
                    quit:s=""
                    set stddev = stddev + (((data("stats",col,"scale","avg")-s)**2)*c)
                }
                set data("stats",col,"scale","stdDev") = $s(count:$zsqr(stddev / count), 1:0)
            }
 b:col=6
            // derive type
            set nonNull = count - $g(stats(col,"null"))
            if $g(stats(col,"num"))=nonNull {
                if ('$g(data("stats",col,"scale","max"))) {
                    // somewhat arbitrary criteria, up for refinement
                    if $f($$$UPPER($g(data("stats",col))),"ID") {
                        // if the column name has "ID" in it, consider it a BIGINT
                        set data("stats",col,"type") = "BIGINT"
                    } elseif (nonNull>=50) && (data("stats",col,"max")=1) && (data("stats",col,"min")=0) {
                        // if we only found 1s and 0s, assume boolean
                        set data("stats",col,"type") = "BOOLEAN"
                    } elseif (nonNull>=100) && (data("stats",col,"max")<100) && (data("stats",col,"min")>-100) {
                        // if it's only 2 digits and we were looking at >100 values, 
                        // a TINYINT will likely do
                        set data("stats",col,"type") = "TINYINT"
                    } else {
                        set data("stats",col,"type") = "INTEGER"
                    }
                    
                } else {
                    set data("stats",col,"type") = "NUMERIC"
                }
            } elseif $g(stats(col,"dt"))=nonNull {
                set data("stats",col,"type") = "DATE"
            } elseif $g(stats(col,"ts"))=nonNull {
                set data("stats",col,"type") = "TIMESTAMP" // refine
            } elseif data("stats",col,"length","max") > 10000 {
                set data("stats",col,"type") = "LONGVARCHAR"
            } else {
                set data("stats",col,"type") = "VARCHAR"
            }
        }

    } catch (ex) {
        set sc = ex.AsStatus()
        do Log("ERROR","Unexpected error occured: "_$system.Status.GetErrorText(sc))
        set logged=1
    }
    do:$$$ISERR(sc)&&'$g(logged) Log("ERROR","Error inferring schema from file: "_$system.Status.GetOneErrorText(sc))
    
    quit sc

Log(level, message)
    write:verbose !,$zdt($h)," - ",level,": ",message
    // TODO: write to %SQL_Diag
}

Query ScanFile(path As %String, qualifiers As %String = "") As %Query(ROWSPEC = "name:%String,type:%String,maxLength:%Integer,maxScale:%Integer,null:%Boolean") [ SqlName = ScanFile, SqlProc ]
{
}

ClassMethod ScanFileExecute(qHandle As %Binary, path As %String, qualifiers = "") As %Status [ Internal, ServerOnly = 1 ]
{
    kill qHandle
    set sc = $$$OK
    try {

        set sc = ..Peek(.data, path, qualifiers)
        quit:$$$ISERR(sc)

        set col = "", qHandle = 0
        for {
            set name = "", col = $order(data("stats",col),1,name)
            quit:col=""

            // skip last column if all nulls
            if ($g(name)="") && (1=$g(data("stats",col,"nullPct"))) && ($o(data("stats",col))="") {
                quit
            }

            // find a name if we didn't get one in the header
            if $g(name)="" {
                set name = "Column"_col
            }

            // suggest safe max length and scale
            set maxLen = (data("stats",col,"length","max") + (3 * data("stats",col,"length","stdDev"))) \ 1 + (data("stats",col,"length","stdDev")>0)
            set maxScale = $s($d(data("stats",col,"scale","max"),max):(max + (3 * data("stats",col,"scale","stdDev"))) \ 1 + (data("stats",col,"scale","stdDev")>0), 1:"")

            set qHandle = qHandle+1,
                qHandle(qHandle) = $lb(name, data("stats",col,"type"), maxLen, maxScale, (data("stats",col,"nullPct")>0))
        }

    } catch (ex) {
        set sc = ex.AsStatus()
    }
    set qHandle = 0
    quit sc
}

ClassMethod ScanFileFetch(ByRef qHandle As %Binary, Output Row As %List, Output AtEnd As %Boolean) As %Status [ Internal, ServerOnly = 1 ]
{
	set qHandle = $order(qHandle(qHandle),1,data)
	if qHandle="" {
		set AtEnd = 1, Row = ""
	} else {
		set AtEnd = 0, Row = data
	}
	quit $$$OK
}

ClassMethod ScanFileClose(ByRef qHandle As %Binary) As %Status [ Internal, ServerOnly = 1 ]
{
	kill qHandle
	quit $$$OK
}

/// Returns the inferred column list for the file at <var>path</var>, in a format ready for
/// wrapping in a <tt>CREATE TABLE t ( ... )</tt> statement.
ClassMethod InferColumnList(path As %String, qualifiers As %String = "") As %String [ SqlName = InferColumnList, SqlProc ]
{
    set str = ""
    try {
        set rs = ##class(%SQL.Statement).%ExecDirect(,"SELECT * FROM bdb_sql.ScanFile(?,?)", path, qualifiers)
        while rs.%Next() {
            set type = rs.%Get("type")
            set str = str _ $s(str="":"", 1:", ") _ rs.%Get("name") _ " " _ type
            if type = "VARCHAR" {
                set str = str _ "(" _ rs.%Get("maxLength") _ ")"
            } elseif (type = "NUMERIC") {
                set str = str _ "(" _ rs.%Get("maxLength") _ "," _ rs.%Get("maxScale") _ ")"
            }

            set:'rs.%Get("null") str = str _ " NOT NULL"
        }

    } catch (ex) {
        set sc = ex.AsStatus() // TODO ?
    }
    quit str
}

}
