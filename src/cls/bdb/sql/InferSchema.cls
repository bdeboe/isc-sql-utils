/// Basic class for inspecting a (CSV) file and inferring the probable datatypes for
/// each column. Main entry points are <query>ScanFile</query>, which projects a 
/// result set with one row for each column and <method>InferColumnList</method>, which 
/// structures that information in a DDL-ready format. 
Class bdb.sql.InferSchema
{

ClassMethod ScanFile(Output info, path As %String, qualifiers As %String = "", Output data) As %Status [ Internal ]
{
    #define MaxLineLength 999999
    kill data
    set sc = $$$OK, info = {}
    try {
        set qualifiers = $s(qualifiers="":{}, '$isobject(qualifiers):##class(%DynamicObject).%FromJSON(qualifiers), 1:qualifiers)
        
        // stash lowercased qualifier keys
        set iterator = qualifiers.%GetIterator()
        while iterator.%GetNext(.key, .value) {
            set qf($$$LOWER(key)) = value
        }
        set verbose = +$g(qf("verbose"))
        set readLines = $g(qf("readLines"),200)

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

        set info.columnSeparator = qf("columnseparator")

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
                    set scale = $s(decimal>0:l-decimal, 1:0)
                    set stats(col,"scale") = $g(stats(col,"scale"))+scale,
                        stats(col,"scale",scale) = $g(stats(col,"scale",scale))+1
                }
                set:dt stats(col,"dt") = $g(stats(col,"dt"))+1
                set:ts stats(col,"ts") = $g(stats(col,"ts"))+1
            }
        }

        set info.columns = []
        set col = ""
        for {
            set col = $order(stats(col),1,count)
            quit:col=""
            set colInfo = {}
            if header'="" {
                set colInfo.name = $piece(header,qf("columnseparator"),col)
            }
            set colInfo.count = count,
                colInfo.nullPct = $g(stats(col,"null"))/count,
                colInfo.length = {"avg": ($g(stats(col,"l"))/count),
                                  "min": (+$o(stats(col,"l",""))),
                                  "max": (+$o(stats(col,"l",""),-1))}

            set stddev = 0
            set l = ""
            for {
                set l = $order(stats(col,"l",l),1,c)
                quit:l=""
                set stddev = stddev + (((colInfo.length.avg-l)**2)*c)
            }
            set colInfo.length.stdDev = $s(count:$zsqr(stddev / count), 1:0)
            
            if $g(stats(col,"num")) {
                set colInfo.min = $g(stats(col,"min")),
                    colInfo.max = $g(stats(col,"max")),
                    colInfo.scale = {"avg": ($g(stats(col,"scale"))/count),
                                     "min": (+$o(stats(col,"scale",""))),
                                     "max": (+$o(stats(col,"scale",""),-1)) }
                set stddev = 0, s = ""
                for {
                    set s = $order(stats(col,"scale",s),1,c)
                    quit:s=""
                    set stddev = stddev + (((colInfo.scale.avg-s)**2)*c)
                }
                set colInfo.scale.stdDev = $s(count:$zsqr(stddev / count), 1:0)
            }
 
            // derive type
            set nonNull = count - $g(stats(col,"null"))
            if $g(stats(col,"num"))=nonNull {
                if ('colInfo.scale.max) {
                    set colInfo.type = "integer"

                    // somewhat arbitrary criteria, up for refinement
                    if $f($$$UPPER(colInfo.name),"ID") {
                        // if the column name has "ID" in it, consider it a BIGINT
                        set colInfo.sqlType = "BIGINT"
                    } elseif (nonNull>=50) && (colInfo.max=1) && (colInfo.min=0) {
                        // if we only found 1s and 0s, assume boolean
                        set colInfo.sqlType = "BOOLEAN"
                    } elseif (nonNull>=100) && (colInfo.max<100) && (colInfo.min>-100) {
                        // if it's only 2 digits and we were looking at >100 values, 
                        // a TINYINT will likely do
                        set colInfo.sqlType = "TINYINT"
                    } else {
                        set colInfo.sqlType = "INTEGER("_$$SafeMargin(colInfo.length)_")"
                    }
                    
                } else {
                    set colInfo.type = "number",
                        colInfo.sqlType = "NUMERIC("_$$SafeMargin(colInfo.length)_","_$$SafeMargin(colInfo.scale)_")"
                }
            } elseif $g(stats(col,"dt"))=nonNull {
                set colInfo.type = "date", 
                    colInfo.sqlType = "DATE"
            } elseif $g(stats(col,"ts"))=nonNull {
                set colInfo.type = "timestamp", 
                    colInfo.sqlType = "TIMESTAMP" // refine
            } elseif colInfo.length.max > 10000 {
                set colInfo.type = "stream", 
                    colInfo.sqlType = "LONGVARCHAR"
            } else {
                set colInfo.type = "string",
                    colInfo.sqlType = "VARCHAR("_$$SafeMargin(colInfo.length)_")"
            }

            do info.columns.%Push(colInfo)
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
    if $isobject($g(info)) && (level'="INFO") && (level'="DEBUG") {
        set:(info.errors="") info.errors = []
        do info.errors.%Push({ "level": (level), "message": (message) })
    }
    quit
SafeMargin(el)
    quit el.max + $s(el.stdDev>00.34:(3*el.stdDev)\1, 1:1)
}

/// SQL entry point for <method>ScanFile</method>
ClassMethod ScanFileSQL(path As %String, qualifiers As %String = "") As %String [ SqlName = ScanFile, SqlProc ]
{
    set sc = ..ScanFile(path, .info, qualifiers)
    quit $s($$$ISERR(sc):{ "error": ($SYSTEM.Status.GetErrorText(sc)) }, 1:info.%ToJSON())
}

/// Returns the inferred column list for the file at <var>path</var>, in a format ready for
/// wrapping in a <tt>CREATE TABLE t ( ... )</tt> statement.
ClassMethod InferColumnList(path As %String, qualifiers As %String = "") As %String [ SqlName = InferColumnList, SqlProc ]
{
    set str = ""
    try {
        set sc = ..ScanFile(.info, path, qualifiers)
        quit:$$$ISERR(sc)
        quit:'$isobject(info.columns)
        set iterator = info.columns.%GetIterator(), i=1
        while iterator.%GetNext(,.column) {
            set str = str _ $s(str="":"", 1:", ") _ $s(column.name="":"Column"_i, 1:column.name) _ " " _ column.sqlType
            set:'column.nullPct str = str _ " NOT NULL"
            set i = i+1
        }

    } catch (ex) {
        set sc = ex.AsStatus() // TODO ?
    }
    quit str
}

}
