/// <p>Utility class for inspecting a (CSV) file and inferring the probable datatypes for
/// each column. The main entry points are <method>ScanFile</method>, which returns a 
/// <class>%DynamicObject</class> with anything we could glean from the file and
/// <method>InferColumnList</method>, which structures that information in a DDL-ready format.
/// For a one-stop-shop method that scans all files in a directory, creates tables for them
/// and then loads them, check <method>BuildAll</method></p>
Class bdb.sql.InferSchema
{

/// <p>The <method>qualifiers</method> passed into this method are assumed to follow the same
/// somewhat verbose format as <tt>LOAD DATA</tt>, meaning the ones relevant to file parsing
/// are nested in <tt>from.file.*</tt> structure. The ones only relevant to this inferencing
/// routine are simply at the root. For example:</p>
/// <pre>
///  { 
///     "from": 
///         { 
///             "file": 
///                 {
///                     "columnseparator": ";"
///                 }
///         },
///     "verbose": 1,
///     "readlines": 1000
///  }
/// </pre>
/// <p>To read the whole file, set `readlines` to 0. This will ensure any proposed datatypes are
/// generic enough for all the rows in the input file to match.</p>
ClassMethod ScanFile(Output info, path As %String, qualifiers As %String = "", Output data) As %Status
{
    #define MaxLineLength 999999
    kill data, ^||lines
    set sc = $$$OK, info = {}
    try {
        set qualifiers = $s(qualifiers="":{}, '$isobject(qualifiers):##class(%DynamicObject).%FromJSON(qualifiers), 1:qualifiers)
        
        // push seeded qualifiers to output for use in LOAD DATA
        set info.qualifiers = qualifiers
        set:'$isobject(info.qualifiers.from) info.qualifiers.from = { "file": {} }
        set:'$isobject(info.qualifiers.from.file) info.qualifiers.from.file = {}
        
        // stash lowercased qualifier keys
        do ..FlattenQualifiers(.qf, qualifiers)
        set verbose = +$g(qf("verbose"))
        set readLines = $g(qf("readlines"),200)
        #define qfHeader qf("from.file.header")
        #define qfSeparator qf("from.file.columnseparator")

        set file = ##class(%Stream.FileCharacter).%New()
        set sc = file.LinkToFile(path)
        quit:$$$ISERR(sc)
        do Log("INFO","Reading file '"_path_"'")

        // unless there's definitely no header, skip the first nonempty line
        if $g($$$qfHeader,-1)'=0 {
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
        while (('readLines) || (lines < readLines)) && 'file.AtEnd {
            set lines = lines+1,
                ^||lines(lines) = $zstrip(file.ReadLine($$$MaxLineLength),"<>WC")
        }
        if ('lines) {
            do Log("ERROR", "No lines to sample from")
            quit
        } elseif (file.AtEnd) && (lines < readLines) {
            do Log("WARNING", "Short file, only read "_lines_" nonempty lines for sampling")
        } else {
            do Log("INFO", "Read "_lines_" nonempty lines for sampling")
        }

        // estimate total number of rows (if we didn't read all of them)
        if 'file.AtEnd {
            set totalLength = 0, lt = $l(file.LineTerminator)
            for i = 1:1:lines {
                set totalLength = totalLength + $l(^||lines(i)) + lt
            }
            if (file.Size <= 0) || 'totalLength {
                do Log("WARNING", "Unable to estimate number of rows")
            } else {
                set info.estimatedLines = lines * ( file.Size / totalLength ) \ 1
            }
        } else {
            set info.estimatedLines = lines
        }

        // we can close the file now
        kill file

        // assume quote character
        set quote = """"
            
        // identify the field separator
        if $g($$$qfSeparator)'="" {
            do Log("INFO", "Parsing lines using supplied column separator '"_$$$qfSeparator_"'")
        } else {
            do Log("INFO", "No column separator supplied, checking candidates")

            // find the candidate with lowest variance leading to more than 1 piece
            for i = 1:1:lines {
                set line = $replace($replace(^||lines(i),quote_quote,""),"\"_quote,""),
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
                    set pieces = $l(^||lines(i),sep) // TODO - could try to weed out the ones between ""
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
                    quit:'pieces // we're beyond the numbers
                    set stddev = stddev + (((avg-pieces)**2)*cnt)
                }
                set (stddev,sep(sep,"stddev")) = $s(lines:$zsqr(stddev / lines),1:0)
                if (mean > 1) && ((mean-stddev) > bestScore) {
                    set $$$qfSeparator = sep,
                        bestScore = (mean-stddev)
                }
            }
            if (bestScore = 0) {
                do Log("WARNING", "Could not find a suitable column separator, possibly because there is only one column.")
                set $$$qfSeparator = ","
            }
 
            do Log("INFO", "Assuming the column separator is '"_$$$qfSeparator_"'")
            set info.qualifiers.from.file.columnseparator = $$$qfSeparator
        }
 
        if $g(header)'="" {
            
            if $g($$$qfHeader)="" {
                // if the user didn't tell us there was a header, check if the first
                // line has numeric values, which likely means it's not a header
                set notSoString = 0, 
                    cols = $l(header,$$$qfSeparator)
                for i = 1:1:cols {
                    set f = $p(header,$$$qfSeparator,i),
                        notSoString = notSoString + $isvalidnum(f) // TODO: dates?
                }
                if (notSoString > 0) { // too bad
                    set header = ""
                    do Log("INFO","Unable to identify a header line, assuming there is none")
                } else {
                    do Log("INFO","Assuming the following header: "_$lts($lfs(header,$$$qfSeparator),", "))
                    set info.qualifiers.from.file.header = 1
                }
            } else {
                do Log("INFO","Using the following header: "_$lts($lfs(header,$$$qfSeparator),", "))
            }
        } else {
            do Log("INFO","No header in this file")
            set header="" // initialize as empty
        }

        // parse lines
        for i = 1:1:lines {
            set line = $replace(^||lines(i),"\"_quote,quote_quote),
                pieces = $l(line, $$$qfSeparator),
                (p, new) = 1, col = 0
            while p <= pieces {
                set piece = $p(line,$$$qfSeparator,p)
                
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
                            set new = 1, p = p+1, data(i,col) = data(i,col)_$$$qfSeparator_piece
                            continue
                        } else {
                            // continuation
                            set new = 0, p = p+1, data(i,col) = data(i,col)_$$$qfSeparator_piece
                            continue
                        }

                    } else {
                        // continuation
                        set new = 0, p = p+1, data(i,col) = data(i,col)_$$$qfSeparator_piece
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
                set colInfo.name = $piece(header,$$$qfSeparator,col)
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

            // if this is the last column, with just NULLs and no name, it's probably
            // just a trailing separator, so skip
            if ($order(stats(col))="") && (colInfo.name="") && (colInfo.nullPct=1) { quit }
 
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
                        set colInfo.sqlType = "INT("_$$SafeMargin(colInfo.length)_")"
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
    
    kill ^||lines

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

ClassMethod FlattenQualifiers(ByRef qf, obj As %DynamicObject, prefix As %String = "") [ Internal, Private ]
{
    set iterator = obj.%GetIterator()
    while iterator.%GetNext(.key, .value) {
        set sub = $s(prefix="":$$$LOWER(key), 1:prefix_"."_$$$LOWER(key))
        if $isobject(value) {
            do ..FlattenQualifiers(.qf, value, sub)
        } else {
            set qf(sub) = value
        }
    }
}

/// SQL entry point for <method>ScanFile</method>
ClassMethod ScanFileSQL(path As %String, qualifiers As %String = "") As %String [ SqlName = ScanFile, SqlProc ]
{
    set sc = ..ScanFile(path, .info, qualifiers)
    quit $s($$$ISERR(sc):{ "error": ($SYSTEM.Status.GetErrorText(sc)) }, 1:info.%ToJSON())
}

/// Returns the inferred column list for the file at <var>path</var>, in a format ready for
/// wrapping in a <tt>CREATE TABLE t ( ... )</tt> or <tt>LOAD DATA FROM FILE .. COLUMNS (..)</tt>
/// statement.
ClassMethod InferColumnList(path As %String, qualifiers As %String = "") As %String [ SqlName = InferColumnList, SqlProc ]
{
    set str = ""
    try {
        set qualifiers = $s(qualifiers="":{}, '$isobject(qualifiers):##class(%DynamicObject).%FromJSON(qualifiers), 1:qualifiers)
        do ..FlattenQualifiers(.qf, qualifiers)

        set sc = ..ScanFile(.info, path, qualifiers)
        quit:$$$ISERR(sc)
        set str = ..InferColumnListInternal(info, $g(qf("strict")))

    } catch (ex) {
        set sc = ex.AsStatus() 
    }
    quit str
}

ClassMethod InferColumnListInternal(info As %DynamicObject, strict As %Boolean = 0, namesOnly As %Boolean = 0) As %String [ Internal, Private ]
{
    quit:'$isobject(info.columns) ""
    set iterator = info.columns.%GetIterator(), i=1, str=""
    while iterator.%GetNext(,.column) {
        set str = str _ $s(str="":"", 1:", ") _ $s(column.name="":"Column"_i, 1:column.name) 
        set i = i+1
        continue:namesOnly
        set str = str _ " " _ column.sqlType
        set:strict&&'column.nullPct str = str _ " NOT NULL"
    }
    quit str
}

/// <p>This one-stop-shop method scans the files in <var>path</var> (single filename or basic mask also accepted) and creates a 
/// table for each of them based on the output of <method>ScanFile</method> if none exists. Then, it builds and executes 
/// a <tt>LOAD DATA</tt> statement to load the table from the file. This method's optimistic implementation will skip
/// tables for which errors are raised, but continues with tables that were successfully scanned and created.</p>
/// <p>The <var>qualifiers</var> JSON string accepts the same arguments as other methods in this class, as well as an
/// additional flag to specify the schema in which to look for or create the target tables:</p>
/// <example>
///  do ##class(bdb.sql.InferSchema).BuildAll("/tmp/data-dump/*.csv", { "verbose": 1, "targetSchema": "MySchema" })
/// </example>
ClassMethod BuildAll(path As %String, qualifiers As %String = "") As %Status [ SqlName = BuildSchemaFromPath, SqlProc ]
{
    set sc = $$$OK
    try {
        set qualifiers = $s(qualifiers="":{}, '$isobject(qualifiers):##class(%DynamicObject).%FromJSON(qualifiers), 1:qualifiers)
        do ..FlattenQualifiers(.qf, qualifiers)
        set verbose = +$g(qf("verbose"))
        set targetSchema = $g(qf("targetschema"))
        set info = {}  // not sure if we'll use this

        // scan path
        set pathSeparator = $s($$$isWINDOWS:"\",1:"/"),
            files = 0
        if ##class(%File).Exists(path) && '##class(%File).DirectoryExists(path) {
            do Log("INFO","Found a single file '"_path_"'")
            set files($i(files)) = path
        } else {
            if ##class(%File).DirectoryExists(path) {
                set wildcard = "", queryPath = path
            } else {
                set wildcard = $piece(path, pathSeparator,*),
                    queryPath = $piece(path,pathSeparator,1,*-1)
            }
            set rs = ##class(%SQL.Statement).%ExecDirect(,"CALL %Library.File_FileSet(?, ?,, ?)", queryPath, wildcard, 0)
            while rs.%Next() {
                set f = rs.%Get("Name")
                if ##class(%File).DirectoryExists(f) {
                    do Log("INFO","Skipping directory '"_f_"'")
                    continue
                }
                do Log("INFO","Found file '"_f_"'")
                set files($i(files)) = f
            }
        }
        if 'files {
            do Log("WARNING","No files found at '"_path_"', exiting")
            quit
        }

        do Log()
        do Log(,"Scanning "_files_" files...")

        for i = 1:1:files {
            kill scanInfo
            do Log(,"Scanning file structure for '"_files(i)_"'")
            set sc = ..ScanFile(.scanInfo, files(i), qualifiers)
            set files(i,"info") = scanInfo
            if $$$ISERR(sc) {
                do Log("ERROR", "Error scanning file structure: "_$SYSTEM.Status.GetOneErrorText(sc))
                continue
            }

            set tableName = $tr($piece($piece(files(i), pathSeparator, *), ".", 1, *-1),"- .","___")
            set:targetSchema'="" tableName = targetSchema_"."_tableName
            set files(i,"tableName") = tableName

            if $SYSTEM.SQL.Schema.TableExists(tableName) {
                do Log(,"Using existing target table "_tableName)
                continue
            }

            set ddl = "CREATE TABLE "_tableName_" ("_..InferColumnListInternal(scanInfo, $g(qf("strict")))_")"
            do Log(,"Creating target table: "_$c(13,10,9)_ddl)
            
            set rs = ##class(%SQL.Statement).%ExecDirect(,ddl)
            if rs.%SQLCODE {
                do Log("ERROR","Error creating table: "_rs.%Message)
                kill files(i,"tableName")
            }

            do Log()
        }
        set sc = $$$OK // continue with what worked

        do Log()
        do Log(,"Loading "_files_" tables...")

        set totalRows = 0, totalTables = 0
        for i = 1:1:files {
            if '$d(files(i,"tableName")) {
                do Log("WARNING", "No target table for file "_files(i)_", skipping...")
                continue
            }

            set ddl = "LOAD BULK %NOJOURN DATA FROM FILE '"_files(i)_"'"_$c(13,10)
            set ddl = ddl_$c(9)_"COLUMNS ("_..InferColumnListInternal(files(i,"info"))_")"_$c(13,10)
            set ddl = ddl_$c(9)_"INTO "_files(i,"tableName")_" ("_..InferColumnListInternal(files(i,"info"),,1)_")"_$c(13,10)
            set ddl = ddl_$c(9)_"USING "_files(i,"info").qualifiers.%ToJSON()

            do Log(,"Loading into table: "_$c(13,10,9)_ddl)

            set rs = ##class(%SQL.Statement).%ExecDirect(,ddl)
            if rs.%SQLCODE {
                do Log("ERROR","Error loading table: "_rs.%Message)
            } else {
                do Log(,"Loaded "_rs.%ROWCOUNT_" rows")
                set totalRows = totalRows+rs.%ROWCOUNT, totalTables = totalTables+1
            }

            do Log()
        }
        do:totalTables>1 Log(,"Loaded "_totalRows_" records into "_totalTables_" tables")

    } catch (ex) {
        set sc = ex.AsStatus()
        do Log("ERROR","Unexpected error occured: "_$system.Status.GetErrorText(sc))
        set logged=1
    }
    do:$$$ISERR(sc)&&'$g(logged) Log("ERROR","Error building schema: "_$system.Status.GetOneErrorText(sc))
    do Log()
    quit sc

Log(level="INFO", message="")
    if verbose && ($g(message)="") {
        write !
    } else {
        write:verbose !,$zdt($h)," - ",level,": ",message
        // TODO: write to %SQL_Diag
        if $isobject($g(info)) && (level'="INFO") && (level'="DEBUG") {
            set:(info.errors="") info.errors = []
            do info.errors.%Push({ "level": (level), "message": (message) })
        }
    }
    quit
}

/// <p>This method scans the files in <var>path</var> (single filename or basic mask also accepted) and creates a <a 
/// href="https://docs.intersystems.com/irislatest/csp/docbook/DocBook.UI.Page.cls?KEY=GSQL_tables#GSQL_tables_foreign">Foreign
/// Table</a> for each of them based on the output of <method>ScanFile</method>. A Foreign Server is also created representing
/// the directory holding your files.</p>
/// <p>The <var>qualifiers</var> JSON string accepts the same arguments as other methods in this class, as well as
/// additional flags to specify the schema in which to look for or create the target tables, and the preferred name
/// for the foreign server:</p>
/// <example>
///  do ##class(bdb.sql.InferSchema).CreateForeignTables("/tmp/data-dump/*.csv", { "verbose": 1, "targetSchema": "MySchema", "serverName": "MySchema.FServer" })
/// </example>
ClassMethod CreateForeignTables(path As %String, qualifiers As %String = "") As %Status [ SqlName = CreateForeignSchema, SqlProc ]
{
    set sc = $$$OK
    try {
        if $SYSTEM.Version.GetMajor()<2023 {
            set sc = $$$ERROR($$$GeneralError, "Foreign Tables are not supported on this release: "_$SYSTEM.Version.GetNumber()_" (requires 2023.1)")
            quit
        }

        set qualifiers = $s(qualifiers="":{}, '$isobject(qualifiers):##class(%DynamicObject).%FromJSON(qualifiers), 1:qualifiers)
        do ..FlattenQualifiers(.qf, qualifiers)
        set verbose = +$g(qf("verbose"))
        set targetSchema = $g(qf("targetschema"))
        set serverName = $g(qf("serverName"), $s(targetSchema="":"SQLUser",1:targetSchema)_".FServer")
        set info = {}  // not sure if we'll use this

        // scan path
        set pathSeparator = $s($$$isWINDOWS:"\",1:"/"),
            files = 0
        if ##class(%File).Exists(path) && '##class(%File).DirectoryExists(path) {
            do Log("INFO","Found a single file '"_path_"'")
            set files($i(files)) = path,
                queryPath = $piece(path,pathSeparator,1,*-1)
        } else {
            if ##class(%File).DirectoryExists(path) {
                set wildcard = "", queryPath = path
            } else {
                set wildcard = $piece(path, pathSeparator,*),
                    queryPath = $piece(path,pathSeparator,1,*-1)
            }
            set rs = ##class(%SQL.Statement).%ExecDirect(,"CALL %Library.File_FileSet(?, ?,, ?)", queryPath, wildcard, 0)
            while rs.%Next() {
                set f = rs.%Get("Name")
                if ##class(%File).DirectoryExists(f) {
                    do Log("INFO","Skipping directory '"_f_"'")
                    continue
                }
                do Log("INFO","Found file '"_f_"'")
                set files($i(files)) = f
            }
        }
        if 'files {
            do Log("WARNING","No files found at '"_path_"', exiting")
            quit
        }

        // create foreign server
        set rs = ##class(%SQL.Statement).%ExecDirect(,"SELECT COUNT(*) FROM INFORMATION_SCHEMA.FOREIGN_SERVERS WHERE SERVER_SCHEMA = ? AND SERVER_NAME = ?", $s($l(serverName,".")>1:$p(serverName,".",1), 1:"SQLUser"), $p(serverName,".",*))
        if (rs.%Next() && rs.%GetData(1)) {
            do Log("INFO", "Foreign Server "_serverName_" already exists, reusing...")
        } else {
            set ddl = "CREATE FOREIGN SERVER "_serverName_" FOREIGN DATA WRAPPER CSV "_$c(13,10,9,9)_" HOST '"_queryPath_"'"
            do Log("INFO","Creating Foreign Server: "_$c(13,10,9)_ddl)

            set rs = ##class(%SQL.Statement).%ExecDirect(,ddl)
            if rs.%SQLCODE {
                
                if ($SYSTEM.Version.GetMajor()>2023) || ($SYSTEM.Version.GetMinor()=3) {
                    do Log("ERROR","Error creating Foreign Server: "_rs.%Message)
                    quit
                } else {
                    // catalog query doesn't exist yet prior to 2023.3, so try proceeding on earlier versions
                    do Log("WARNING", "Error creating Foreign Server, assuming it exists")
                }

            } else {
                do Log("INFO", "Foreign Server "_serverName_" created successfully")
            }
        }

        do Log()
        do Log(,"Scanning "_files_" files...")

        set totalTables = 0
        for i = 1:1:files {
            kill scanInfo
            do Log(,"Scanning file structure for '"_files(i)_"'")
            set sc = ..ScanFile(.scanInfo, files(i), qualifiers)
            set files(i,"info") = scanInfo
            if $$$ISERR(sc) {
                do Log("ERROR", "Error scanning file structure: "_$SYSTEM.Status.GetOneErrorText(sc))
                continue
            }

            set tableName = $tr($piece($piece(files(i), pathSeparator, *), ".", 1, *-1),"- .","___")
            set:targetSchema'="" tableName = targetSchema_"."_tableName
            set files(i,"tableName") = tableName

            if $SYSTEM.SQL.Schema.TableExists(tableName) {
                do Log(,"Table "_tableName_" already exists, skipping")
                continue
            }

            set ddl = "CREATE FOREIGN TABLE "_tableName_" ("_..InferColumnListInternal(scanInfo)_") "_$c(13,10,9,9)
                        _" SERVER "_serverName_$c(13,10,9,9)
                        _" FILE '"_$piece(files(i), pathSeparator, *)_"' "_$c(13,10,9,9)
                        _" USING "_files(i,"info").qualifiers.%ToJSON()
            do Log(,"Creating target table: "_$c(13,10,9)_ddl)
            
            set rs = ##class(%SQL.Statement).%ExecDirect(,ddl)
            if rs.%SQLCODE {
                do Log("ERROR","Error creating table: "_rs.%Message)
                kill files(i,"tableName")
            } else {
                set totalTables = totalTables+1
            }

            do Log()
        }
        set sc = $$$OK
        do:totalTables>1 Log(,"Created "_totalTables_" foreign tables")

    } catch (ex) {
        set sc = ex.AsStatus()
        do Log("ERROR","Unexpected error occured: "_$system.Status.GetErrorText(sc))
        set logged=1
    }
    do:$$$ISERR(sc)&&'$g(logged) Log("ERROR","Error creating foreign schema: "_$system.Status.GetOneErrorText(sc))
    do Log()
    quit sc

Log(level="INFO", message="")
    if verbose && ($g(message)="") {
        write !
    } else {
        write:verbose !,$zdt($h)," - ",level,": ",message
        // TODO: write to %SQL_Diag
        if $isobject($g(info)) && (level'="INFO") && (level'="DEBUG") {
            set:(info.errors="") info.errors = []
            do info.errors.%Push({ "level": (level), "message": (message) })
        }
    }
    quit
}

}
