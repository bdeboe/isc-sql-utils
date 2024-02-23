/// Utilities to increase your reach when working with <a href="https://docs.intersystems.com/irislatest/csp/docbook/DocBook.UI.Page.cls?KEY=GSQL_tables#GSQL_tables_foreign">Foreign
/// Tables</a>.
Class bdb.sql.ForeignUtils
{

/// Use this stored procedure to issue a query on a remote database that's registered as a Foreign Server:
/// <example language="SQL">
///   CALL bdb_sql.ForeignQuery('MySQLServer', 'SELECT abc, xyz FROM dbo.tab1')
/// </example>
/// Currently, only JDBC sources are supported.
ClassMethod ForeignQuery(serverName As %String, query As %String(MAXLEN=32000)) As %Status [ ReturnResultsets, SqlName = ForeignQuery, SqlProc ]
{
    #dim %sqlcontext As %ProcedureContext
    if '$isobject($Get(%sqlcontext)) { set %sqlcontext = ##class(%ProcedureContext).%New() } 
    set sc = $$$OK

    try {
        if $SYSTEM.Version.GetMajor() < 2023 {
            set sc = $$$ERROR($$$GeneralError, "Foreign Tables are not supported on versions earlier than 2023.1")
            quit
        }

        set is20233 = (($SYSTEM.Version.GetMajor()*10)+$SYSTEM.Version.GetMinor())>=20233

        if $ISOBJECT(serverName) {
            if 'serverName.%IsA("%DynamicObject") {
                set sc = $$$ERROR($$$GeneralError, "Unsupported server name format: '"_serverName_"'")
                quit
            }
            set requestObject = serverName
        } else {
            // serverName is a Foreign Server name, find class name
            if ('is20233) {
                // if the query doesn't exist, try optimistically looking for the class
                if '$f(serverName,".") {
                    set className = "User."_serverName, 
                        serverName = "SQLUser."_serverName
                } else {
                    set packageName = $tr($piece(serverName,".",1),"_","."), 
                        className = $s($$$UPPER(packageName)="SQLUSER":"User", 1:packageName)_"."_$piece(serverName,".",2)
                }
                if '##class(%Dictionary.ClassDefinition).%ExistsId(className) {
                    set sc = $$$ERROR($$$GeneralError, "Foreign Server '"_serverName_"' not found")
                    quit
                }
                set serverClassName = className
            } else {
                set:'$f(serverName,".") serverName = "SQLUser."_serverName
                set rs = ##class(%SQL.Statement).%ExecDirect(,"SELECT CLASSNAME, FOREIGN_DATA_WRAPPER FROM INFORMATION_SCHEMA.FOREIGN_SERVERS WHERE SERVER_SCHEMA = ? AND SERVER_NAME = ?", $piece(serverName,".",1), $piece(serverName,".",2))
                if 'rs.%Next() {
                    set sc = $$$ERROR($$$GeneralError, "Foreign Server '"_serverName_"' not found")
                    quit
                } elseif (rs.%GetData(2)'="%SQL.FDW.XDBC") {
                    set sc = $$$ERROR($$$GeneralError, "This feature is only supported for XDBC-based Foreign Servers")
                    quit
                }
                set serverClassName = rs.%GetData(1)
            }
            set requestObject = ##class(%SQL.FDW.XDBC).%New().GetRequestObject(serverClassName, "")
        }

        // only supports JDBC for now
        set connection = ##class(%XDBC.Gateway.Connection).GetConnection(requestObject) 
        set params = 1, params(params) = query
        if ($$$LOWER(requestObject.type) = "jdbc") {
            set:is20233 params = 3, 
                        params(2) = $PARAMETER("%XDBC.Gateway.JDBC.Connection", "TYPESCROLLINSENSITIVE"), 
                        params(3) = $PARAMETER("%XDBC.Gateway.JDBC.Connection", "CONCURREADONLY")
        }
		set statement = connection.PrepareStatement(params...)
        
        if ($SYSTEM.Version.GetMajor() < 2024) {
            // use workaround prior to 2024.1
    		set result = ##class(ForeignUtilsRS).ExecuteQuery(statement)
        } else {
            set result = statement.ExecuteQuery()
        }
        
        do result.SetFetchSize(1000)
        do %sqlcontext.AddResultSet(result)

    } catch (ex) {
        if (ex.%IsA("%Net.Remote.Exception")) {
            set sc = $$$ERROR($$$GeneralError, ex.Data)
        } else {
            set sc = ex.AsStatus()
        }
    }
    if $$$ISERR(sc) {
        set sqlcode=$system.Status.StatusToSQLCODE(sc,.msg)
        set %sqlcontext.%SQLCODE = sqlcode, %sqlcontext.%Message = msg
    }
    quit sc
}

}
