# IRIS SQL Utilities

Various recipes from my SQL cookbook for baking your finest storage, all the way from baguette to croissant and back.

## Adopting Extent Sets

We've been recommending the use of [extent sets](https://docs.intersystems.com/irislatest/csp/documatic/%25CSP.Documatic.cls?&LIBRARY=%25SYS&CLASSNAME=%25Library.Persistent#USEEXTENTSET) for many years now, but sadly cannot make this the default behaviour for newly created classes because of backwards compatibility issues it'd cause. 

If you want to modernize your storage with just a little more than a paint job, you can already adopt `USEEXTENTSET=1` and just wire your existing master and index map to their current global locations, so that all _new_ maps will get their proper global. Specifically, you could drop and recreate your indices so they all get their own global.

```ObjectScript
write ##class(SQL.StorageUtils).ConvertToUseExtentSets("My.Ancient.CustomerClass")
```

See the class method's argument list for more ways to weak what gets generated.

Notes:
* when trying to convert classes in a hierarchy, aim at the superclass defining the storage
* this class does not (yet) provide an option to perform the described drop-and-recreate-indices procedure
* a future version of this class may also move the data from that long-ish D global into a proper extent global


## Projecting from a different namespace

As a developer you may find yourself longing for that perfect test table or bulky test dataset in a different namespace. Use `CreateMappedTable()` to create a projection in the current namespace of a table in another one.

```ObjectScript
write ##class(SQL.StorageUtils).CreateMappedTable("ORIGINAL","My_Very.BestTable")
```

See the class method's argument list for more ways to tweak what gets generated.

Note that this method just creates a one-off projection and does not refresh it if the source table / storage changes.
