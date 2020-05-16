if object_id(N'dbo.RunUnitTests') is not null
	drop procedure dbo.RunUnitTests

set ansi_nulls on
go
set quoted_identifier on
go
/**	Run UnitTests based on input xml
 *	Example input xml:
 *
 *	<unittests>
 *		<test name="name of test">
 *			<prefix dev="dbo." ut="#" />
 *			<mock>
 *				<mytable mycol="testvalue" />
 *			</mock>
 *			<act>exec MyStoredProc</act>
 *			<returns>
 *				<returncol type="varchar(10)" />
 *			</returns>
 *			<assert expected=" = 'testvalue'">
 *				select returncol from #utreturns
 *			</assert>
 *		</test>
 *	</unittests>
 *
 *	The above snippet mocks existing table dbo.mytable
 *	with 1 row of data. This row contains "testvalue"
 *	it for its [mycol]- column.
 *	Then it runs exec MyStoredProc and expects a
 *	resultset of 1 column with type varchar(10).
 *	Finally it looks at (select returncol from #utreturns)
 *	and assert that it = 'testvalue'.
 */
create procedure RunUnitTests(@unittests xml)
as begin
	set nocount on
	
	declare @DROP_TABLE_SNIP nvarchar(255) = '
if object_id(''tempdb.._TABLENAME_'') is not null
	drop table _TABLENAME_
'
	declare @CREATE_TABLE_SNIP nvarchar(255) = '
select top 0 *
into _UT_TABLENAME_
from _DEV_TABLENAME_
'
	declare @INSERT_SNIP nvarchar(255) = '
insert into _TABLENAME_(_TABLECOLUMNS_)
values
	_VALUES_
'
	declare @CREATE_RETURN_SNIP nvarchar(255) = '
if object_id(''tempdb..#utreturns'') is not null
	drop table #utreturns

create table #utreturns (
	_TABLECOLUMNS_
)
'
	declare @INSERT_RETURN_SNIP nvarchar(255) =
'insert into #utreturns(_TABLECOLUMNS_)
	'
	declare @ACT_SNIP nvarchar(255) = '
declare @error varchar(1000)
begin try
	_EXEC_ACT_
end try
begin catch
	set @error = error_message()
end catch
'
	declare @INSERT_RESULT_SNIP nvarchar(511) = '
insert into #testresults(name, test, expected, actual, pass, testxml, fullquery)
select
	''_TEST_NAME_'',
	''_EXAMEN_ESC_'',
	''_EXPECTED_ESC_'',
	isnull(@error, cast((_EXAMEN_) as varchar(255))),
	isnull(case 
		when @error is not null then 0
		when (_EXAMEN_) _EXPECTED_ then 1
	end, 0),
	@testxml,
	@sqltotal
'

	if object_id('tempdb..#testresults') is not null
		drop table #testresults

	create table #testresults (
		id int identity,
		name nvarchar(255),
		test nvarchar(255),
		expected nvarchar(255),
		actual nvarchar(255),
		pass bit,
		testxml xml,
		fullquery nvarchar(max)
	)

	declare @nl nchar(2) = char(13) + char(10)
	declare @testxml xml
	declare @name nvarchar(255)
	declare @utprefix nvarchar(255)
	declare @envprefix nvarchar(255)
	declare @sqlmock nvarchar(max)
	declare @sqlpre nvarchar(max)
	declare @sqlact nvarchar(max)
	declare @sqlassert nvarchar(max)
	declare @sqlpost nvarchar(max)
	declare @sqltotal nvarchar(max)

	declare TestCursor cursor local forward_only static read_only for
		select te.st.query('.')
		from @unittests.nodes('unittests/test')te(st)
	
		open TestCursor
		fetch next from TestCursor into @testxml
		while @@fetch_status = 0 begin

			set @name = @testxml.value('(test/@name)[1]', 'nvarchar(255)')
			set @utprefix = @testxml.value('(test/prefix/@ut)[1]', 'nvarchar(255)')
			set @envprefix = isnull(@testxml.value('(test/prefix/@dev)[1]', 'nvarchar(255)'), '')

			;with mockdata as (
				select
					tablename = mo.ck.value('local-name(.)', 'nvarchar(255)'),
					tablecolumns =
					(
						select ', ' +
							'[' + co.l.value('local-name(.)', 'nvarchar(255)') + ']'
						from mo.ck.nodes('./@*')co(l)
						order by co.l.value('local-name(.)', 'nvarchar(255)')
						for xml path(''), type
					)
					.value('fn:substring(., 3)', 'nvarchar(max)'),
					tablevalues =
					(
						select ', ' + 
							'''' + replace(co.l.value('.', 'nvarchar(max)'), '''', '''''') + ''''
						from mo.ck.nodes('./@*')co(l)
						order by co.l.value('local-name(.)', 'nvarchar(255)')
						for xml path(''), type
					)
					.value('fn:substring(., 3)', 'nvarchar(max)')
				from @testxml.nodes('test/mock/*')mo(ck)
			), returntable as (
				select 
					colname = ret.urns.value('local-name(.)', 'nvarchar(50)'),
					coltype = ret.urns.value('./@type', 'nvarchar(50)')
				from @testxml.nodes('test/returns/*')ret(urns)
			), assertions as (
				select
					examen   = ass.ert.value('.', 'nvarchar(255)'),
					expected = ass.ert.value('@expected', 'nvarchar(1000)')
				from @testxml.nodes('test/assert')ass(ert)
			)
			select
			@sqlpost =
				(
					select replace(@DROP_TABLE_SNIP, '_TABLENAME_', @utprefix + t.tablename)
					from mockdata t
					group by t.tablename
					for xml path(''), type
				)
				.value('.', 'nvarchar(max)'),
				
			@sqlmock = 
				(
					select replace(replace(@CREATE_TABLE_SNIP,
							'_UT_TABLENAME_',  @utprefix  + t.tablename),
							'_DEV_TABLENAME_', @envprefix + t.tablename) +
						(
							select replace(replace(replace(@INSERT_SNIP,
								'_TABLENAME_', @utprefix + c.tablename),
								'_TABLECOLUMNS_', c.tablecolumns),
								'_VALUES_', (
									select ',' + @nl +
										'	(' + d.tablevalues + ')'
									from mockdata d
									where d.tablename = c.tablename
									  and d.tablecolumns = c.tablecolumns
									for xml path(''), type
								)
								.value('fn:substring(., 5)', 'nvarchar(max)'))
							from mockdata c
							where c.tablename = t.tablename
							group by c.tablename, c.tablecolumns
							for xml path(''), type
						)
						.value('.', 'nvarchar(max)')
					from mockdata t
					group by t.tablename
					for xml path(''), type
				)
				.value('.', 'nvarchar(max)'),
				
			@sqlpre =
				case (select count(*) from returntable) when 0 then '' else
					replace(@CREATE_RETURN_SNIP, '_TABLECOLUMNS_', (
						select ',' + @nl +
							'	' + colname + ' ' + coltype
						from returntable
						for xml path(''), type
					)
					.value('fn:substring(., 4)', 'nvarchar(max)'))
				end,
				
			@sqlact = replace(@ACT_SNIP, '_EXEC_ACT_',
				case (select count(*) from returntable) when 0 then '' else
					replace(@INSERT_RETURN_SNIP, '_TABLECOLUMNS_', (
						select ',' + colname
						from returntable
						for xml path(''), type
					)
					.value('fn:substring(., 2)', 'nvarchar(max)'))
				end +
				trim(@testxml.value('(test/act)[1]', 'nvarchar(max)'))),
				
			@sqlassert =
				(
					select replace(replace(replace(replace(replace(@INSERT_RESULT_SNIP,
						'_TEST_NAME_',    replace(@name,    '''', '''''')),
						'_EXAMEN_ESC_',   replace(examen,   '''', '''''')),
						'_EXPECTED_ESC_', replace(expected, '''', '''''')),
						'_EXAMEN_', examen),
						'_EXPECTED_', expected)
					from assertions
					for xml path(''), type
				)
				.value('.', 'nvarchar(max)')

			set @sqltotal = isnull(@sqlpost + @sqlmock, '') + @sqlpre + @sqlact + @sqlassert + isnull(@sqlpost, '')

			exec sp_executesql @sqltotal,
				N'@testxml xml, @sqltotal nvarchar(max)', @testxml, @sqltotal

			fetch next from TestCursor into @testxml
		end
		close TestCursor
	deallocate TestCursor

	select *
	from #testresults
	order by id

	if object_id('tempdb..#testresults') is not null
		drop table #testresults
end
go