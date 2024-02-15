/// Use or operation of this code is subject to acceptance of the license available in the code repository for this code.
Class Sample.Customer Extends %SerialObject
{

Property Name As %String(TRUNCATE = 1);

Property MailingAddresses As list Of Address(JAVATYPE = "java.util.List");

Property Addresses As array Of Address(JAVATYPE = "java.util.Map");

Property MyAddress As Address;

Property Status As %String(TRUNCATE = 1);

Property TS As %TimeStamp;

/// This callback method is invoked by the <METHOD>%New</METHOD> method to 
/// provide notification that a new instance of an object is being created.
/// 
/// <P>If this method returns an error then the object will not be created.
Method %OnNew(initvalue As %CacheString) As %Status [ Private ]
{
	do ..SetDefault()
	quit $$$OK
}

Method SetDefault()
{
	do ..MailingAddresses.Clear()
	do ..Addresses.Clear()
	
	set l = $listbuild("One Memorial Dr.","Cambridge","MA","02142")
	set l1 = $listbuild(l,"Sample.Address")
	set a = ##class(Sample.Address).%Open(l1)
	do ..MailingAddresses.Insert(a)
	
	set l = $listbuild("768 Beacon St.","Brookline","MA","02446")
	set l1 = $listbuild(l,"Sample.Address")
	set a = ##class(Sample.Address).%Open(l1)
	do ..MailingAddresses.Insert(a)
	
	set l = $listbuild("825 Third Ave.","New York","NY","10022")
	set l1 = $listbuild(l,"Sample.Address")
	set a = ##class(Sample.Address).%Open(l1)
	do ..Addresses.SetAt(a, "Residence")
	
	set l = $listbuild("7722 Main St.","Detroit","MI","48224")
	set l1 = $listbuild(l,"Sample.Address")
	set a = ##class(Sample.Address).%Open(l1)
	do ..Addresses.SetAt(a, "Business")
	
	set l = $listbuild("25 Glen Ave","Newton","MA","02459")
	set l1 = $listbuild(l,"Sample.Address")
	set a = ##class(Sample.Address).%Open(l1)
	
	set ..MyAddress = a
	set ..Name = "Joe Doe, Jr."
	set ..Status = "Prospect"
}

}

