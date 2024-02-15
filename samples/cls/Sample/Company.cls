/// Use or operation of this code is subject to acceptance of the license available in the code repository for this code.
/// This sample persistent class represents a company.<br>
Class Sample.Company Extends (%Persistent, %Populate, %XML.Adaptor)
{

/// Define an index for <property>Name</property>.
Index NameIdx On Name [ Type = index ];

/// Define a unique index for <property>TaxID</property>.
Index TaxIDIdx On TaxID [ Type = index, Unique ];

/// The company's name.
Property Name As %String(MAXLEN = 80, POPSPEC = "Company()") [ Required ];

/// The company's mission statement.
Property Mission As %String(MAXLEN = 200, POPSPEC = "Mission()");

/// The unique Tax ID number for the company.
Property TaxID As %String [ Required ];

/// The last reported revenue for the company.
Property Revenue As %Integer;

/// The <class>Employee</class> objects associated with this <class>Company</class>.
Relationship Employees As Employee [ Cardinality = many, Inverse = Company ];

}

