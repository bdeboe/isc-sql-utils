Include %occInclude

/// Use or operation of this code is subject to acceptance of the license available in the code repository for this code.
/// This class contains a method to generate data for Sample package
Class Sample.Utils 
{

/// Invoke this method to set up the data for these classes.
/// Create one company for every five people.
ClassMethod Generate(personCount As %Integer = 100)
{
    // Make sure we always have at least 1 person
    if (personCount < 1) {
        set personCount=1
        }
        
    // Never use %KillExtent() in a real application
    do ##class(Sample.Company).%KillExtent()
    do ##class(Sample.Person).%KillExtent()
    do ##class(Sample.Employee).%KillExtent()
    //do ##class(Sample.Vendor).%KillExtent() ; doesn't work with %Storage.SQL 
    
    set companyCount= personCount \ 5
    if (companyCount < 1) {
        set companyCount=1
        }

    do ##class(Sample.Company).Populate(companyCount)
	do ##class(Sample.Person).Populate(personCount)
	do ##class(Sample.Employee).Populate(personCount,,,,2)
	do ##class(Sample.Vendor).Populate(personCount)
	
	// Specify values for stream properties in Sample.Employee
	// do this for the first lucky 10 employees, for reasons of space
	
	set e1=personCount+1 ; ID of the first employee
	for i=e1:1:e1+9 {
		set employee=##class(Sample.Employee).%OpenId(i)
		set firstname=$PIECE(employee.Name,",",2)
		set firstname=$PIECE(firstname," ",1)
		set text=firstname_" used to work at "_##class(%PopulateUtils).Company()
		         _" as a(n) "_##class(%PopulateUtils).Title()
		         
		do employee.Notes.Write(text)
		
		// Add a stock picture (yes, all these employees look alike)
		do employee.Picture.Write($G(^EmployeePictures))
		
		do employee.%Save()
		}
}

}

