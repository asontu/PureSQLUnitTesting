# Documentation

This is the full documentation, for a quick overview take a look at the [README](./README.md).

## Installation

To install, simply run the `DeployObjects.sql` and `RunUnitTests.sql` files on the SQL server instance where the UnitTests will be run.

## Prepare Stored Proc for testing

Either deploy your stored proc to a UnitTest-variant with `DeployObjects` or write the UnitTest-variant and deploy after it passes all tests.

## Write and run a UnitTest

UnitTests follow the basic **Arrange** -> **Act** -> **Assert** pattern. **Arranging** in this case means mocking tables (or views). As well, because stored procs ofter return result-sets, a little more time is spend on describing what that result-set looks like before moving on to **Assert** things about it.

The `RunUnitTests` proc accepts the following XML:

`exec RunUnitTests '<unittests>`
-	`<test name="Name of this test">`
	-	`<prefix `
		-	`dev="dbo."` _(optional)_  
			The prefix for tables of the development environment that need to be mocked
		-	`ut="#unittest_" />` **(mandatory)**  
			The prefix for the temporary tables that the UnitTest works on, should be the same as the (deployed) UnitTest-variant of the stored proc.
	-	`<mock>`_(optional)_  
		Contains a list of tables that should be mocked for the test. The tag-name is the table name (without any prefixes) and attributes with values are column-names with the mocked value. For multiple rows you simply repeat the tag:
		-	`<customer id="1" name="John Doe" />`
		-	`<customer id="2" name="Jane Doe" />`
		-	`<order id="1" customer_id="2" vat_percent="10" />`
		-	`<orderline id="1" order_id="1" description="staplers" qty="5" unit_price="2.20" subtotal="11" />`
		-	`<orderline id="2" order_id="1" description="marker (red)" qty="3" unit_price="1.20" subtotal="3.60" />`
	-	`</mock>`
	-	`<act>exec TotalsPerCustomer_UTST</act>` **(mandatory)**  
		A snippet of T-SQL that invokes the procedure being tested. This should invoke the UnitTest-variant of the stored proc.
	-	`<returns>` _(optional)_  
		If the proc that's being tested returns a result-set (of even just one value), use this section to describe the list of columns and their type that the proc returns. Like the `<mock>` section above, the tag-name itself is used, this time as a column name. The attribute `type=""` is expected and must contain the type of that column. These columns are added to a table called `#utreturns`, which can then be queried in the `<assert>` statements.
		-	`<customer_name type="nvarchar(255)" />`
		-	`<orders type="int" />`
		-	`<total_excl_vat type="decimal(5,2)" />`
		-	`<total_incl_vat type="decimal(5,2)" />`
	-	`</returns>`
	-	`<assert` **(mandatory)**  
		A T-SQL snippet that should return a single value to be tested against the condition of the `expected` attribute below.
		-	`expected=" = 2">`  
			The attribute can contain any valid T-SQL condition, like `" = 'expected value'"`, `" <> 'wrong value'"`, `" > 1"`, `" like '%this%'"`, `" between 0 and 10"`, etc.
		-	`select count(*) from #utreturns`
	-	`</assert>`
	-	`<assert expected=" = 14.60">select total_excl_vat from #utreturns where customer_name = ''Jane Doe''</assert>`  
		_(single quotes doubled here because we're inside a string)_
	-	`<assert expected=" = 16.06">select total_incl_vat from #utreturns where customer_name = ''Jane Doe''</assert>`
-	`</test>`

`</unittests>'`