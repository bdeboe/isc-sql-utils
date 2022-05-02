/// Utilities for exporting a snapshot of the Statement Index. 
/// Methods to try:
/// <ol>
/// <li><method>Snapshot</method></li>
/// <li><method>ExportSnapshot</method></li>
/// </ol>
Class bdb.sql.StatementUtils
{

/// Builds a new schema named <var>targetSchema</var> with a copy of the current Statement Index,
/// optionally filtered to those statements touching at least one relation in <var>statementSchema</var>.
/// 
ClassMethod Snapshot(targetSchema As %String = "SISnapshot", statementSchema As %String = "", dropFirst As %Boolean = 1, extended As %Boolean = 1, verbose As %Boolean = 1) As %Status
{
    set sc = $$$OK
    try {
        if dropFirst {
            write:verbose !,"Dropping existing schema:",!
            for table = "STATEMENTS", "STATEMENT_RELATIONS", "STATEMENT_LOCATIONS", "STATEMENT_DAILY_STATS", "STATEMENT_HOURLY_STATS", "TABLES", "COLUMNS", "INDEXES", "TABLE_CONSTRAINTS", "VIEWS", "VIEW_COLUMN_USAGE", "VIEW_TABLE_USAGE" {
                continue:'$system.SQL.Schema.TableExists(targetSchema_"."_table)
                do RunDDL("DROP TABLE "_targetSchema_"."_table)
            }
            write:verbose !
        }
        
        write:verbose !,"Creating new schema:",!

        set sql = "CREATE TABLE "_targetSchema_".STATEMENTS "_$c(13,10)_"   AS SELECT * FROM INFORMATION_SCHEMA.STATEMENTS"
        if (statementSchema'="") {
            set sql = sql_$c(13,10)_"   WHERE "
            for i = 1:1:$l(statementSchema,",") {
                set:i'=1 sql = sql_$c(13,10)_"      OR "
                set sql = sql_"Hash IN (SELECT Statement FROM INFORMATION_SCHEMA.STATEMENT_RELATIONS WHERE Relation %STARTSWITH '"_$zstrip($p(statementSchema,",",i),"<>WC")_".')"
            }
        }
        quit:'$$RunDDL(sql)

        quit:'$$RunDDL("CREATE UNIQUE INDEX IdxHash ON "_targetSchema_".STATEMENTS(Hash)")

        for table = "STATEMENT_RELATIONS", "STATEMENT_LOCATIONS", "STATEMENT_DAILY_STATS", "STATEMENT_HOURLY_STATS" {

            continue:'$system.SQL.Schema.TableExists("INFORMATION_SCHEMA."_table)

            set sql = "CREATE TABLE "_targetSchema_"."_table_" AS SELECT * FROM INFORMATION_SCHEMA."_table
            set sql = sql_$c(13,10)_"   WHERE "_$case(table,"STATEMENT_HOURLY_STATS":"Day->Statement", :"Statement")_" IN (SELECT Hash FROM "_targetSchema_".STATEMENTS)"
            quit:'$$RunDDL(sql)

        }

        quit:'$$RunDDL("CREATE INDEX IdxStatement ON "_targetSchema_".STATEMENT_RELATIONS(Statement)")
        quit:'$$RunDDL("CREATE INDEX IdxRelation ON "_targetSchema_".STATEMENT_RELATIONS(Relation)")
        
        quit:'$$RunDDL("CREATE INDEX IdxStatement ON "_targetSchema_".STATEMENT_LOCATIONS(Statement)")

        quit:'$$RunDDL("CREATE INDEX IdxStatement ON "_targetSchema_".STATEMENT_DAILY_STATS(Statement)")
        
        // add in full schema information
        if (extended) {

            set sql = "CREATE TABLE "_targetSchema_".TABLES AS SELECT * FROM INFORMATION_SCHEMA.TABLES"
            set sql = sql_$c(13,10)_"   WHERE UPPER(TABLE_SCHEMA || '.' || TABLE_NAME) IN (SELECT DISTINCT UPPER(Relation) FROM "_targetSchema_".STATEMENT_RELATIONS)"
            quit:'$$RunDDL(sql)
            
            quit:'$$RunDDL("CREATE UNIQUE INDEX IdxName ON "_targetSchema_".TABLES(TABLE_SCHEMA, TABLE_NAME)")
                
            for table = "COLUMNS", "TABLE_CONSTRAINTS", "INDEXES" {

                set sql = "CREATE TABLE "_targetSchema_"."_table_" AS SELECT * FROM INFORMATION_SCHEMA."_table
                set sql = sql_$c(13,10)_"   WHERE SchemaExact || '.' || TableExact IN (SELECT SchemaExact || '.' || TableExact FROM "_targetSchema_".TABLES)"
                quit:'$$RunDDL(sql)
               
            }
            
            quit:'$$RunDDL("CREATE UNIQUE INDEX IdxName ON "_targetSchema_".COLUMNS(TABLE_SCHEMA, TABLE_NAME, COLUMN_NAME)")
            quit:'$$RunDDL("CREATE INDEX IdxName ON "_targetSchema_".INDEXES(TABLE_SCHEMA, TABLE_NAME, INDEX_NAME)")
            quit:'$$RunDDL("CREATE INDEX IdxName ON "_targetSchema_".TABLE_CONSTRAINTS(TABLE_SCHEMA, TABLE_NAME, CONSTRAINT_NAME)")

            set sql = "CREATE TABLE "_targetSchema_".VIEWS AS SELECT * FROM INFORMATION_SCHEMA.VIEWS"
            set sql = sql_$c(13,10)_"   WHERE UPPER(TABLE_SCHEMA || '.' || TABLE_NAME) IN (SELECT DISTINCT UPPER(Relation) FROM "_targetSchema_".STATEMENT_RELATIONS)"
            quit:'$$RunDDL(sql)

            quit:'$$RunDDL("CREATE UNIQUE INDEX IdxName ON "_targetSchema_".VIEWS(TABLE_SCHEMA, TABLE_NAME)")
                
            for table = "VIEW_COLUMN_USAGE", "VIEW_TABLE_USAGE" {

                set sql = "CREATE TABLE "_targetSchema_"."_table_" AS SELECT * FROM INFORMATION_SCHEMA."_table
                set sql = sql_$c(13,10)_"   WHERE SchemaExact || '.' || ViewExact IN (SELECT SchemaExact || '.' || ViewExact FROM "_targetSchema_".VIEWS)"
                quit:'$$RunDDL(sql)

            }
            quit:$$$ISERR(sc)
            
            quit:'$$RunDDL("CREATE UNIQUE INDEX IdxName ON "_targetSchema_".VIEW_COLUMN_USAGE(VIEW_SCHEMA, VIEW_NAME, COLUMN_NAME)")
            quit:'$$RunDDL("CREATE INDEX IdxName ON "_targetSchema_".VIEW_TABLE_USAGE(VIEW_SCHEMA, VIEW_NAME)")

        }
        quit:$$$ISERR(sc)

        // now add more good stuff
        quit:'$$RunDDL("ALTER TABLE "_targetSchema_".STATEMENTS MODIFY Plan VARCHAR(999999)")
        set sc = ..MakePlansReadable(targetSchema_".STATEMENTS")
        quit:$$$ISERR(sc)

        quit:'$$RunDDL("ALTER TABLE "_targetSchema_".STATEMENTS ADD UserStatement VARCHAR(999999) COMPUTECODE { set {*} = ##class(bdb.sql.StatementUtils).GetUserStatement({Statement}) } CALCULATED")
        quit:'$$RunDDL("ALTER TABLE "_targetSchema_".STATEMENTS ADD UserStatementHash VARCHAR(32) COMPUTECODE { set {*} = $zcrc({UserStatement},7) } CALCULATED")
        quit:'$$RunDDL("CREATE INDEX IdxUserStatementHash ON "_targetSchema_".STATEMENTS(UserStatementHash)")

    } catch (ex) {
        set sc = ex.AsStatus()
    }
    quit sc

RunDDL(sql)
    write:verbose !,"Executing DDL:",!,sql,!
    set rs = ##class(%SQL.Statement).%ExecDirect(,sql)
    if rs.%SQLCODE<0 {
        write:verbose !,rs.%Message,!
        set sc = $$$ERROR($$$GeneralError, rs.%Message)
        quit 0
    }
    quit 1
}

/// Exports a Statement Index snapshot created through <method>Snapshot</method> to a file
/// <var>file</var>
ClassMethod ExportSnapshot(file As %String, schema As %String = "SISnapshot", includeTables As %Boolean = 1, includeCQs As %Boolean = 0) As %Status
{
    set sc = $$$OK
    try {
        set stmt = ##class(%SQL.Statement).%New()
        set sc = stmt.%Prepare("CALL %ExtentMgr.GlobalsUsed(?)")
        quit:$$$ISERR(sc)

        for table = "STATEMENTS", "STATEMENT_RELATIONS", "STATEMENT_LOCATIONS", "STATEMENT_DAILY_STATS", "STATEMENT_HOURLY_STATS", "TABLES", "COLUMNS", "INDEXES", "TABLE_CONSTRAINTS", "VIEWS", "VIEW_COLUMN_USAGE", "VIEW_TABLE_USAGE" {
            continue:'$system.SQL.Schema.TableExists(schema_"."_table, .metadata)
            set classname = $lg(metadata,3)
            do AddClass(classname)
        }

        if includeTables {
            set rs = ##class(%SQL.Statement).%ExecDirect(,"SELECT DISTINCT Relation FROM "_schema_".STATEMENT_RELATIONS")
            while rs.%Next() {
                set table = rs.%GetData(1)
                continue:'$system.SQL.Schema.TableExists(table, .metadata)
                set classname = $lg(metadata,3)
                if $$$defClassKeyGet(classname,$$$cCLASSdeployed) {
                    write !,"Skipping deployed class: ",classname," (table: ",table,")"
                    continue
                }
                if $e(classname)="%" {
                    write !,"Skipping system class: ",classname," (table: ",table,")"
                    continue
                }
                set export(classname_".CLS")=""
            }
        }

        if includeCQs {
            set rs = ##class(%SQL.Statement).%ExecDirect(,"SELECT RuntimeLocation FROM "_schema_".STATEMENT_LOCATIONS")
            while rs.%Next() {
                set routine = rs.%GetData(1)
                continue:'$d(^ROUTINE(routine)) // not sure when this happens, but better safe than sorry
                set export(routine_".INT")=""
            }
        }

        set sc = $SYSTEM.OBJ.Export(.export, file, "/recursive /display /exportselectivity")

    } catch (ex) {
        set sc = ex.AsStatus()
    }
    quit sc

AddClass(classname)
    set export(classname_".CLS") = ""
    set xrs = stmt.%Execute(classname_".cls")
    while xrs.%Next() {
        // This may export more than we want, but there's no handy way to import only 
        // the GlobalReference subtree
        set export(xrs.%Get("GlobalName")_".GBL") = ""
    }
}

ClassMethod AddTableUsageStats(schema = "SISnapshot", verbose As %Boolean = 1) As %Status
{
    set sc = $$$OK
    try {
        set hasROWCOUNT = $s($system.Version.GetMajor()>=2022:1, $p($system.Version.GetNumber(),".",1,2)="2021.2":1, 1:0)

        set exists = $system.SQL.Schema.TableExists(schema_".TABLE_DAILY_USAGE_STATS")
        set sql = "SELECT Relation as TABLE_NAME, Type as TYPE, Day as DAY, SUM(d.StatCount) as TOTAL_COUNT"_$s(hasROWCOUNT:", SUM(d.StatRowCount) AS TOTAL_ROW_COUNT ",1:" ")_
                    "FROM (SELECT Hash, $PIECE(Statement,' ', CASE WHEN SUBSTR(Statement, 1, 4)=' DEC' THEN 6 ELSE 2 END) AS Type FROM INFORMATION_SCHEMA.STATEMENTS) AS s "_
                    "    JOIN INFORMATION_SCHEMA.STATEMENT_RELATIONS r ON s.Hash = r.Statement "_
                    "    JOIN INFORMATION_SCHEMA.STATEMENT_DAILY_STATS d ON s.Hash = d.Statement "_
                    " GROUP BY Relation, Type, Day"

        if 'exists {

            quit:'$$RunDDL("CREATE TABLE "_schema_".TABLE_DAILY_USAGE_STATS AS "_sql)
            quit:'$$RunDDL("CREATE UNIQUE INDEX UK ON "_schema_".TABLE_DAILY_USAGE_STATS(TABLE_NAME, TYPE, DAY)")

        } else {
            
            quit:'$$RunDDL("INSERT OR UPDATE INTO "_schema_".TABLE_DAILY_USAGE_STATS "_sql)

        }

    } catch (ex) {
        set sc = ex.AsStatus()
    }
    quit sc

RunDDL(sql)
    write:verbose !,"Executing DDL:",!,sql,!
    set rs = ##class(%SQL.Statement).%ExecDirect(,sql)
    if rs.%SQLCODE<0 {
        write:verbose !,rs.%Message,!
        set sc = $$$ERROR($$$GeneralError, rs.%Message)
        quit 0
    }
    quit 1
}

/// Updates a snapshot's STATEMENTS table by populating the Plan column with EXPLAIN output
/// for those statements. This is a best-effort routine that should be run prior to exporting.
ClassMethod MakePlansReadable(statementTable As %String = "SISnapshot.STATEMENTS") As %Status [ Internal, Private ]
{
    kill errors
    set sc = $$$OK
    try {
        return:'$SYSTEM.SQL.Schema.TableExists(statementTable, .metadata) $$$ERROR($$$TableDoesNotExist, statementTable)

        // we need to fetch the IDs upfront as our plan-reading calls interfere
        // with regular SQL processing
        set rs = ##class(%SQL.Statement).%ExecDirect(,"SELECT %ID FROM "_statementTable)
        while rs.%Next() {
            set ids(rs.%GetData(1))=""
        }
        kill stmt

        set %defschema=$lb("SQLUser"),
            info=1

        set id = "", classname = $lg(metadata,3)
        for {
            set id = $order(ids(id))
            quit:id=""

            set stmt = $classmethod(classname,"%OpenId",id)

            kill plan
            set plan=""

            // As this might get a slightly newer plan than what is stored,
            // we'll quickly freez this before pulling up the plan
            do:'stmt.Frozen $SYSTEM.SQL.Statement.FreezeStatement(stmt.Hash)
            
            set sql=1, sql(1)=stmt.Statement
            set sc = $SYSTEM.SQL.Explain(.sql,{"quiet":1,"frozenPlan":1},,.plan)
            
            do:'stmt.Frozen $SYSTEM.SQL.Statement.UnfreezeStatement(stmt.Hash)
            
            // most errors are for cases when the schema evolved since this
            // statement first got registered
            if $$$ISERR(sc) {
                set str = ""
            } else {
                set str = ""
                for i = 1:1:plan {
                    set str = str_$c(13,10)_plan(i)
                }
                kill plan
            }

            set stmt.Plan = str
            set sc = stmt.%Save()
            quit:$$$ISERR(sc)
        }
    } catch (ex) {
        set sc = ex.AsStatus()
    }
    quit sc
}

/// Dumb statement parser that strips options, hints and other mechanical stuff that might have
/// been added by layers of SQL processing. The end result is a "clean" version of your SQL 
/// statement that may make it easier to, for example, relate JDBC and DynamicSQL versions of the
/// same statement back to one another.
ClassMethod GetUserStatement(statement As %String) As %String [ SqlName = GetUserStatement, SqlProc ]
{
    set sc = $$$OK, out = ""
    try {

        set out = $zstrip($tr(statement,$c(13,10,9),"   "), "<>=W"),
            upper = $$$UPPER(out)

        if $piece(upper," ",1)="DECLARE" {
            set out = $piece(out," ",5,*), 
                upper = $piece(upper," ",5,*)
        }

        for keyword = "%NOCHECK", "%NOTRIGGER", "%NOINDEX", "%NOLOCK", "%NORUNTIME", "%NOFPLAN", "%PROFILE_ALL", "%PROFILE" {
            do CutAll(keyword)
        }

        do Cut("INTO :", " FROM ")

        do CutAll("/*#OPTIONS","*/",0)

    } catch (ex) {
        set sc = ex.AsStatus()
    }
    quit $s($$$ISERR(sc):$SYSTEM.Status.GetOneErrorText(sc), 1:out)

CutAll(strFrom, strEnd="", includeEnd=1)
    while $$Cut(strFrom, strEnd, includeEnd) {}
Cut(strFrom, strEnd="", includeEnd=1)
    set cutFrom = $find(upper,strFrom)
    quit:'cutFrom 0
    if strEnd="" {
        set cutEnd = cutFrom, 
            cutFrom = cutFrom-$l(strFrom)-2
    } else {
        set cutEnd = $find(upper,strEnd,cutFrom), 
            cutFrom = cutFrom-$l(strFrom)-2
        quit:'cutEnd 0
        set:includeEnd cutEnd = cutEnd-$l(strEnd)
    }
    set upper = $e(upper,1,cutFrom)_$e(upper,cutEnd,*),
        out = $e(out,1,cutFrom)_$e(out,cutEnd,*)
    quit 1
}

}
