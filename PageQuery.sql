
/**
	初衷：使用游标的方式进行分页虽然简单，但是不能在语句中使用临时表。
	执行原理：将你传入的sql语句进行拆分，然后将sql语句中最后一个结果集作为需要分页的结果写入临时表再进行分页查询
	返回结果：假设传入SQL语句中有N个查询结果集，那么第N和结果集，就会返回N+1个结果集。第N个结果集为分页信息，第N+1个结果集为进行分页的数据
	现有问题：
				1.@orderby参数可以为空，为空的话会写入一个名为N_7777的自增列，作为排序列。但是如果分页结果集中存在自增列，那么就会和N_7777冲突。这种情况下@orderby就需要传如明确值
				2.@orderby不为空的情况下。@orderby参数不能存在xxx.的前缀。因为最终我会写入到临时表，临时表不存在xxx.的情况
				3.如果你的SQL语句需要返回多个结果集，那么每个语句中间需要用;分割
				4.不支持太长的sql

*/
create procedure [dbo].[PageQuery]       
	@page   int=1,				--要显示的页码   
	@size   int=20,				--每页的大小   
	@orderby nvarchar(300),		-- 排序字段，可以为空。不包含order by 字符
	@sql   nvarchar(4000)		--要执行的sql语句   
	as   

	if(1 = charindex('(',ltrim(@sql))) begin
		THROW 777777,'执行sql不能用（）包裹',1
	end

	if( len(@sql) > 4000) begin
		THROW 777777,'sql太长了，弄短点！',1
	end

	create table #sql(
		idx int identity(1,1) primary key not null,sql nvarchar(2000) not null,
	)
	set @sql= replace(@sql,'<','[lt]')
	set @sql= replace(@sql,'>','[rt]')
	set @sql= replace(@sql,'&','[@]')
	
	insert into #sql 
	SELECT B.val FROM (
		(SELECT [value] = CONVERT(XML, '<v>' + REPLACE(@sql, ';', '</v><v>') + '</v>') ) A 
		OUTER APPLY
		(SELECT val = N.v.value('.', 'varchar(2000)') FROM A.[value].nodes('/v') N(v) ) B
	  )

	declare @sql_item varchar(2000)
	declare @idx int

	select top 1 @sql_item=sql,@idx=idx from #sql order by idx desc

	declare @startIndex int =0
	declare @temp_sql varchar(2000)=@sql_item
	declare @lc int=-999
	declare @rc int=-998
	declare @temp varchar(2000)
	declare @k_l int = charindex('(',@temp_sql)
	declare @k_f int = charindex('from',@temp_sql)
	declare @k_r int = charindex(')',@temp_sql)

	print SYSDATETIME()
	if(@k_f > @k_l and @k_l > 0 ) begin	
		while(( @lc<>@rc or @k_l < @k_f or @k_r < @k_f) and (@k_l>0 or @k_r>0)) begin
			if(@lc=-999) begin set @lc=0 end
			if(@rc=-998) begin set @rc=0 end

			set @temp = substring( @temp_sql,0,@k_r+1)
			set @lc = @lc+(SELECT count(*)-1 FROM ( (SELECT [value] = CONVERT(XML, '<v>' + REPLACE(@temp, '(', '</v><v>') + '</v>') ) A  OUTER APPLY (SELECT val = N.v.value('.', 'varchar(1000)') FROM A.[value].nodes('/v') N(v) ) B ))
			set @rc = @rc+(SELECT count(*)-1 FROM ( (SELECT [value] = CONVERT(XML, '<v>' + REPLACE(@temp, ')', '</v><v>') + '</v>') ) A  OUTER APPLY (SELECT val = N.v.value('.', 'varchar(1000)') FROM A.[value].nodes('/v') N(v) ) B ))
		
			set @temp_sql= substring( @temp_sql,@k_r+1,  4000)	
			set @k_l = charindex('(',@temp_sql)
			set @k_f = charindex('from',@temp_sql)
			set @k_r = charindex(')',@temp_sql)
		end
	 

	 

		set @startIndex = charindex('from' ,@temp_sql)-1 + len(@sql_item) - len(@temp_sql);
	end else begin
		set @startIndex = charindex('from' ,@temp_sql)-1;
	end


	if(@startIndex >-1) begin

		declare @tableName varchar(100) = '#'+left(convert(varchar(99),newId()),8)
		if(ISNULL(@orderby,'')='') begin		
			set @sql_item = substring( @sql_item,0,@startIndex  )+',IDENTITY(int,1,1) as N_7777 into '+@tableName+' '+substring( @sql_item,@startIndex ,4000)
			set @orderby='N_7777';
		end else begin
			set @sql_item = substring( @sql_item,0,@startIndex  )+' into '+@tableName+' '+substring( @sql_item,@startIndex  ,4000)
		end
		update #sql set sql=@sql_item where idx=@idx
		insert into #sql(sql) values('select * from '+@tableName+' order by '+@orderby+' offset '+convert(nvarchar(10) ,((@page - 1) * @size))+' row fetch next '+convert(nvarchar(10) ,@size)+' row only')
		insert into #sql(sql) values('select '+convert(nvarchar(10) ,@page)+' as page,'+convert(nvarchar(10) ,@size)+' as size,CEILING(count(*)/convert(float,'+convert(nvarchar(10) ,@size)+')) as allPage,count(*) as allSize from '+@tableName)
	end



	declare @nsql nvarchar(max)
	set @nsql=(SELECT  ';'+sql FROM #sql FOR XML PATH(''))
	set @nsql = replace(replace(replace(@nsql,'[lt]','<'),'[rt]','>'),'[@]','&')
	print @nsql

	exec sp_executesql  @nsql
