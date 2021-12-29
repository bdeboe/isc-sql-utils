# IRIS SQL Utilities

Various recipes from my SQL cookbook for baking your finest storage, all the way from baguette to croissant and back. This is not an official InterSystems repository but rather a practical way to exchange experiments and sample code. Use at your own risk, or yell at me in the Issues section :-)

## Adopting Extent Sets

We've been recommending the use of [extent sets](https://docs.intersystems.com/irislatest/csp/documatic/%25CSP.Documatic.cls?&LIBRARY=%25SYS&CLASSNAME=%25Library.Persistent#USEEXTENTSET) for many years now, but sadly cannot make this the default behaviour for newly created classes because of backwards compatibility issues it'd cause. 

If you want to modernize your storage with just a little more than a paint job, you can already adopt `USEEXTENTSET=1` and just wire your existing master and index map to their current global locations, so that all _new_ maps will get their proper global. Specifically, you could drop and recreate your indices so they all get their own global.

```ObjectScript
write ##class(SQL.StorageUtils).ConvertToUseExtentSets("My.Ancient.CustomerClass")
```

See the class method's argument list for further options.


Notes:
* When trying to convert classes in a hierarchy, you should aim this method at the superclass defining the storage. It will return an error if you try it on a subclass first, but will convert any subclasses along if you use it on a superclass.
* This method performs a very simple check on non-bitmap indices to see if they still work after swapping the storage (for which it keeps a backup). It may not be watertight, so make sure to run your own regression / unit tests.
* This method does not (yet) provide an option to perform the described drop-and-recreate-indices procedure
* A future version of this method may also move the data from that long-ish D global into a proper extent global


## Projecting from a different namespace

As a developer you may find yourself longing for that perfect test table or bulky test dataset in a different namespace. Use `CreateMappedTable()` to create a projection in the current namespace of a table in another one.

```ObjectScript
write ##class(SQL.StorageUtils).CreateMappedTable("ORIGINAL","My_Very.BestTable")
```

See the class method's argument list for more ways to tweak what gets generated.

Note that this method just creates a one-off projection and does not refresh it if the source table / storage changes.
