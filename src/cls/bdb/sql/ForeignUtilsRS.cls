/// Temporary workaround -- will be obviated through a 2024.1 product enhancement
/// No need to look into this class much further!
Class bdb.sql.ForeignUtilsRS Extends %XDBC.Gateway.JDBC.ResultSet [ Hidden ]
{

/// DO NOT USE DIRECTLY -- For compatibility with %SQL.IResultSet only
Property %Metadata As %Library.String(MAXLEN = "") [ Internal, MultiDimensional ];

/// For %ProcedureContext compatibility only
Property %PrivateTables As %ArrayOfObjects [ Internal ];

Method %DispatchGetProperty(pProperty As %Library.String(MAXLEN=255)) [ Internal ]
{
	set tPROPERTY = $$$ucase(pProperty)
	if (tPROPERTY = "SQLCODE") || (tPROPERTY = "%SQLCODE") { quit i%%SQLCODE }
	elseif (tPROPERTY = "%ROWID") { quit i%%ROWID }
	elseif (tPROPERTY = "%ROWCOUNT") { quit i%%ROWCOUNT }
	else { $$$ThrowPropertyDoesNotExistError(pProperty) }
	quit ""
}

Method %DispatchMethod(pMethod As %String, Args...)
{
	set tMETHOD = $$$ucase(pMethod)
	if (tMETHOD = "%GETMETADATA") {
        merge md = ..%Metadata
        quit ##class(%SQL.StatementMetadata).%New(1, .md)
    }
	$$$ThrowMethodDoesNotExistError(pMethod)
}

Method %Next(Output sc as %Status) As %Boolean
{
    set sc = $$$OK
    quit ##super()
}

/// Helper method to ensure this class is used instead of %XDBC.Gateway.JDBC.ResultSet when 
/// executing a prepared statement
ClassMethod ExecuteQuery(statement As %XDBC.Gateway.JDBC.PreparedStatement) As %XDBC.Gateway.ResultSet
{
    new %objlasterror
    if $data(void) {
        throw ##class(%Exception.SQL).CreateFromSQLCODE(-400, "Cannot pass an SQL statement to PreparedStatement.executeQuery")
    }
    set externalResult = statement.connection.jdbcConnection.executeQuery(statement.statement)
    set result = ..%New(statement.connection, externalResult)
    if (result = $$$NULLOREF) {
        if $$$ISERR($get(%objlasterror,$$$OK)) {
            throw ##class(%Exception.StatusException).CreateFromStatus(%objlasterror)
        } else {
            throw ##class(%Exception.SQL).CreateFromSQLCODE(-400,"Unknown error encountered while executing external JDBC Query")
        }
    } elseif result.%SQLCODE < 0 {
        throw ##class(%Exception.SQL).CreateFromSQLCODE(result.%SQLCODE, result.%Message)
    }
    return result
}

/// Override constructor to build additional metadata representation
Method %OnNew(connection As %XDBC.Gateway.JDBC.Connection, externalResult As %ObjectHandle) As %Status [ Internal ]
{
    set sc = ##super(connection, externalResult)
    quit:$$$ISERR(sc)

    try {
        // populate internal metadata representation
        set extMD = ..%externalResult.getMetaData()
        set ptr=0, m=0, 
            x = $listnext(extMD,ptr,count), 
            ..%Metadata(m) = $lb(count),
            ..%ResultColumnCount = count
        while $listnext(extMD, ptr, catalog) {
            set x = $listnext(extMD, ptr, schema),
                x = $listnext(extMD, ptr, table),
                x = $listnext(extMD, ptr, col),
                x = $listnext(extMD, ptr, label),
                x = $listnext(extMD, ptr, type),
                x = $listnext(extMD, ptr, precision),
                x = $listnext(extMD, ptr, scale),
                x = $listnext(extMD, ptr, typeName)
            set ..%Metadata(m) = ..%Metadata(m)_$lb(col, type, precision, scale, 1, label, table, schema, catalog, $c(0,0,0,0,0,0,0,0,0,0,0,0))
            set:$l(..%Metadata(m))>3200 m=m+1, ..%Metadata(m)=""
        }
    } catch exception {
        set ..%SQLCODE = exception.AsSQLCODE()
        set ..%Message = exception.AsSQLMessage()
    }
    return $$$OK
}

///  Fetch and send a series of rows for the ODBC/JDBC server. For internal use only.
Method %SendODBC() As %Library.Integer [ Internal ]
{
	// DP-427293 - basic implementation
	for {
		if ..%Next() {
			set SQLCODE=0
				#; Don't need a %protocol check here because there is no way for the values to be <UNDEFINED>, which would snd an 01/null instead of an 0201/null.
				#; Old logic that uses $zobjexport(...,7) would have had the same issue (or maybe gotten an <UNDEFINED> error at runtime.
			quit:$zobjexport(..GetRow(),60)
		}
		else {
			set SQLCODE=100
			if $d(sc)#2,$$$ISERR(sc) { set SQLCODE=-400,%msg=$$GetErrorText^%apiOBJ(sc) }
			quit
		}
	}
	QUIT SQLCODE
}

}
