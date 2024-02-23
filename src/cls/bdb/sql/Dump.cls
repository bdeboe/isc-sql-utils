/// <p>This utility dumps table data to a CSV or SQL (INSERT) file format so it can be imported into
/// another database using <tt>LOAD DATA</tt> or DML import mechanisms.</p> 
/// <p>This is a <i>logical</i> export mechanism that uses regular SQL semantics only and does not make 
/// assumptions about the physical storage structure being the same on the target system. See the 
/// <method>TableSize</method> in <class>bdb.sql.StorageUtils</class> for an example of such an 
/// approach, which trades flexibility for performance.</p>
/// <h3>Usage</h3>
/// <example>
///  do ##class(bdb.sql.Dump).Dump("Aviation.Event", "/tmp/export.csv")
/// </example>
Class bdb.sql.Dump
{

/// SQL entry point for <method>Dump</method>
/// columns can be passed as a list or comma-separated string of "column[:header]" elements
ClassMethod DumpSQL(from As %String, file As %String, columns As %List = "", qualifiers As %String = "") As %Status [ Internal, SqlName = Dump, SqlProc ]
{
    set sc = $$$OK
    try {
        if columns'="" {
            set:'$listvalid(columns) columns = $listfromstring(columns)
            set ptr=0, array=0
            while $listnext(columns, ptr, col) {
                set val = $lb($zstrip($piece(col,":",1),"<>W"))
                set:$f(col,":") val = val _ $lb($zstrip($piece(col,":",2,*),"<>W"))
                set array = array+1,
                    array(array) = val
            }
        }

        set sc = ..Dump(from, file, .array, qualifiers)

    } catch (ex) {
        set sc = ex.AsStatus()
    }
    quit sc
}

/// <p>This method dumps the rows in table <var>from</var> to a file <var>file</var> in a format based
/// on the extension of <var>file</var>: if its extension is either 'sql', 'dml' or 'ddl', the table
/// data will be written as <tt>INSERT</tt> statements that can be executed right away. Any other extension will 
/// lead to the file being written as a comma-separated values file.</p>
/// <p>The <var>qualifiers</var> argument matches those available for the <tt>LOAD DATA</tt> command for specifying
/// settings such as the column separator and output character set.</p>
/// <p>The <var>columns</var> argument can be used to restrict or reorder the columns available in <var>from</var>
/// that need to be written to <var>file</var>:
/// <example>
///  columns( i ) = $lb( srcValue [ , header ] )
/// </example>
ClassMethod Dump(from As %String, file As %String, ByRef columns, qualifiers As %DynamicObject = "")
{
    set sc = $$$OK
    try {
        set qualifiers = $s(qualifiers="":{}, '$isobject(qualifiers):##class(%DynamicObject).%FromJSON(qualifiers), 1:qualifiers)
        set verbose = +qualifiers.verbose

        // we'll accept either of "into", "into.file" as aliases for "file" for the output file 
        // properties for parity with LOAD DATA. 
        if '$isobject(qualifiers.file) {
            if $isobject(qualifiers.into) {
                if $isobject(qualifiers.into.file) {
                    set qualifiers.file = qualifiers.into.file
                } else {
                    set qualifiers.file = qualifiers.into
                }
            } else {
                set qualifiers.file = {}
            }
        }

        // apply default values 
        // TODO: delegate to utility method?
        set iterator = qualifiers.file.%GetIterator()
        while iterator.%GetNext(.key, .value) {
            set qf($$$LOWER(key)) = value
        }
        set writeHeader = +$g(qf("header"),1)
        set charset = $case($g(qf("charset")), "UTF-8":"UTF8", :$g(qf("charset")))
        set colSep = $g(qf("columnseparator"),",")
        set escapeChar = $g(qf("escapechar"),"\")
        set fileType = $g(qf("type"))

        set extension = $$$LOWER($piece(file,".",*))
        set zip = (extension="gz")
        set:zip extension = $$$LOWER($piece(file,".",*-1))

        // if fileType not set, try to derive from file name
        set:(fileType="") fileType = $case(extension, "sql":"sql", "dml":"sql", "ddl":"sql", :"csv")
        if ((fileType'="csv") && (fileType'="sql")) {
            set sc = $$$ERROR($$$GeneralError, "Unsupported file type: "_fileType)
            quit
        }
        do Log("INFO","Preparing to write output file format: "_fileType)

        // interpret column list
        if $d(columns) {
            set i="",
                headerLine="",
                selectList=""
            for {
                set i = $o(columns(i),1,info)
                quit:i=""
                set:writeHeader headerLine = headerLine _ $s(headerLine="":"", 1:colSep) _ $s($lg(info,2)="":$lg(info,1),1:$lg(info,2))
                set selectList = selectList _ $s(selectList="":"", 1:", ") _ $lg(info,1)
            }
        } else {
            set selectList = "*",
                headerLine = ""
        }

        // build SQL statement
        set from = $zstrip(from,"<>WC"), 
            firstPiece = $$$UPPER($piece(from," ",1)),
            statement = ##class(%SQL.Statement).%New(),
            statement.%SelectMode = 1 // ODBC mode
        if (selectList="*") && ((firstPiece="SELECT")||(firstPiece="CALL")) {
            set sql = from
        } else {
            set sql = "SELECT "_selectList_" FROM "_from
        }
        do Log("INFO","Preparing statement: "_sql)
        set sc = statement.%Prepare(sql)
        quit:$$$ISERR(sc) 
        
        for i = 1:1:statement.%Metadata.columnCount {
            set colTypes(i) = statement.%Metadata.columns.GetAt(i).clientType
            set stringify(i) = $case(colTypes(i), 3:0, 5:0, 14:0, 16:0, 18:0, :1)
        }

        // if the user didn't supply a column list, we need to get it from the resultset
        if (headerLine="") && writeHeader {
            for i = 1:1:statement.%Metadata.columnCount {
                set headerLine = headerLine _ $s(i=1:"",1:colSep) _ statement.%Metadata.columns.GetAt(i).colName
            }
        }

        set rs = statement.%Execute()
        if (rs.%SQLCODE < 0) {
            set sc = $$$ERROR($$$GeneralError,"Error executing SQL statement: %SQLCODE "_rs.%SQLCODE_" - "_rs.%Message)
            quit
        }


        // establish output file
        do Log("INFO","Opening output file: "_file)
        set fileStream = $s(zip:##class(%Stream.FileCharacterGzip).%New(), 1:##class(%Stream.FileCharacter).%New())
        set sc = fileStream.LinkToFile(file)
        quit:$$$ISERR(sc)

        if writeHeader {
            set sc = $$WriteLine(headerLine)
            quit:$$$ISERR(sc)
        }
        
        while rs.%Next() {
            if fileType="csv" {
                set line = ""
                for i = 1:1:statement.%Metadata.columnCount {
                    set line = line_$s(i=1:"",1:colSep)_$$Escape(rs.%GetData(i))
                }
            } elseif (fileType="sql") {
                set line = "INSERT INTO "_from_$s(selectList="*":"", 1:" ("_selectList_")")_" VALUES ("
                for i = 1:1:statement.%Metadata.columnCount {
                    set line = line_$s(i=1:"",1:", ")_$$EscapeSQL(rs.%GetData(i),stringify(i))
                }
                set line = line_");"
            }
            set sc = $$WriteLine(line)
            quit:$$$ISERR(sc)
        }
        quit:$$$ISERR(sc)

        do Log("INFO","Finished writing to output file")
        set sc = fileStream.%Save()
        set fileStream=""
        quit:$$$ISERR(sc)

    } catch (ex) {
        set sc = ex.AsStatus()
        do Log("ERROR","Unexpected error occured: "_$system.Status.GetErrorText(sc))
        set logged=1
    }
    do:$$$ISERR(sc)&&'$g(logged) Log("ERROR","Error while writing to output file: "_$system.Status.GetOneErrorText(sc))
    
    // blind save in case this file is still open
    do:$isobject($g(fileStream)) fileStream.%Save()
    
    quit sc


WriteLine(line)
    if (charset="") {
        quit fileStream.WriteLine(line)
    } else {
        quit fileStream.WriteLine($zcvt(line,"O", charset))
    }

Escape(string)
    if $f(string,colSep) {
        set string = $replace(string,escapeChar,escapeChar_escapeChar)
        set string = """"_$replace(string,"""",escapeChar_"""")_""""
    }
    quit string

EscapeSQL(string,isString)
    quit $s(isString:"'"_$replace(string,"'","''")_"'", 1:string)

Log(level, message)
    write:verbose !,$zdt($h)," - ",level,": ",message
    // TODO: write to %SQL_Diag
}

}
