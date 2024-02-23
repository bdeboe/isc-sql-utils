/// <p>Utility class that will automatically generate an UPDATE/DELETE trigger for logging
/// any field changes to <class>bdb.logme.Log</class>. By default, all the table's fields
/// will be logged, except those whose name starts with a % sign. This behaviour can be 
/// overridden using the <parameter>LOGME</parameter> boolean flag at the class and
/// property level.</p>
/// <p>This is meant as a fine-grained convenience utility and should not be used as a
/// replacement for the fully-secured <a target="_new" href="https://docs.intersystems.com/iris20212/csp/docbook/DocBook.UI.Page.cls?KEY=AAUDIT">
/// IRIS Auditing feature</a>.</p>
Class bdb.logme.Trigger [ Abstract, NoExtent, PropertyClass = bdb.logme.PropertyClass ]
{

/// class-level default logging behaviour, which can be overruled through the
/// LOGME property parameter.
/// Note: properties whose name starts with a % sign are off by default, regardless of 
/// the class-level setting.
Parameter LOGME As BOOLEAN = 1;

Trigger LogMe [ CodeMode = objectgenerator, Event = UPDATE/DELETE, Foreach = row/object ]
{
    set default = $g(%parameter("LOGME"))

    do %code.WriteLine("    set log = ##class(bdb.logme.Log).%New(), log.TableName = "_$$$QUOTE(%compiledclass.SqlSchemaName_"."_%compiledclass.SqlTableName)_", log.Operation = %oper")

    #dim prop as %Dictionary.CompiledProperty
    for i = 1:1:%compiledclass.Properties.Count() {
        set prop = %compiledclass.Properties.GetAt(i)
        if (prop.Parameters.GetAt("LOGME")=0) || ($e(prop.Name)="%") || 'default {
            continue
        }

        do %code.WriteLine("    if {"_prop.SqlFieldName_"*C} { do log.Changes.SetAt($s(%oper=""DELETE"":##class(bdb.logme.LogField).%New({"_prop.SqlFieldName_"*O}), 1:##class(bdb.logme.LogField).%New({"_prop.SqlFieldName_"*O}, {"_prop.SqlFieldName_"*N})), "_$$$QUOTE(prop.Name)_") }")
    }
    do %code.WriteLine("    do log.%Save()")

    quit $$$OK
}

}
