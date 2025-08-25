
/**
	初衷：使用游标的方式进行分页虽然简单，但是不能在语句中使用临时表。
	执行原理：将你传入的sql语句进行拆分，然后将sql语句中最后一个结果集作为需要分页的结果写入临时表再进行分页查询
	返回结果：假设传入SQL语句中有N个查询结果集，那么第N和结果集，就会返回N+1个结果集。第N个结果集为分页信息，第N+1个结果集为进行分页的数据
	现有问题：
				1.@orderby参数可以为空，为空的话会写入一个名为N_7777的自增列，作为排序列。但是如果分页结果集中存在自增列，那么就会和N_7777冲突。这种情况下@orderby就需要传如明确值
				2.@orderby不为空的情况下。@orderby参数不能存在xxx.的前缀。因为最终我会写入到临时表，临时表不存在xxx.的情况
				3.如果你的SQL语句需要返回多个结果集，那么每个语句中间需要用;分割
				4.不支持太长的sql

	2025-08-25 	1.第三版优化。处理oderby不能为空得情况
*/
create procedure [dbo].[PageQuery]       
	@page   int=1,				--要显示的页码   
	@size   int=20,				--每页的大小   
	@orderby nvarchar(300),		-- 排序字段，可以为空。如不为空则不能包含order by ，以及xxx. 
	@sql   nvarchar(4000)		--要执行的sql语句   
as   

if(1 = charindex('(',ltrim(@sql))) begin
	THROW 777777,'执行sql不能用（）包裹',1
end

if( len(@sql) > 4000) begin
	THROW 777777,'sql太长了，弄短点！',1
end

  
declare @execTime varchar(30)=SYSDATETIME()
declare @itemTime varchar(30)
  
declare @tableName varchar(100) = '#'+left(convert(varchar(99),newId()),8)



set @sql= replace(@sql,'<','[lt]')
set @sql= replace(@sql,'>','[rt]')
set @sql= replace(@sql,'&','[@]')

  
create table #sql( idx int not null,sql nvarchar(2000) not null )


SELECT IDENTITY(int,1,1) as idx ,convert(nvarchar(2000),B.val) as sql into #sql2
FROM (
	(SELECT [value] = CONVERT(XML, '<v>' + REPLACE(@sql, ';', '</v><v>') + '</v>') ) A 
OUTER APPLY
    (SELECT val = N.v.value('.', 'varchar(2000)') FROM A.[value].nodes('/v') N(v) ) B
)

insert into #sql
select idx,sql from #sql2 order by idx
	  

delete #sql where len(ltrim(rtrim(sql)))=0
declare @sqlCount int
select @sqlCount=count(*) from #sql

declare @sql_item varchar(2000)
declare @idx int
 
select top 1 @sql_item=sql,@idx=idx from #sql order by idx desc


declare @fromStartIndex int =0
declare @whereStartIndex int =0
declare @temp_sql varchar(2000)=@sql_item
declare @lc int=-999
declare @rc int=-998
declare @temp varchar(2000)
declare @k_l int = charindex('(',@temp_sql)
declare @k_f int = charindex('from',@temp_sql)
declare @k_r int = charindex(')',@temp_sql)
declare @k_w int = charindex('where',@temp_sql)



set @itemTime=SYSDATETIME()

if( @k_f > @k_l and @k_l > 0 ) begin	
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
	 
	set @fromStartIndex = charindex('from' ,@temp_sql)-1 + len(@sql_item) - len(@temp_sql);
 end else begin
	set @fromStartIndex = charindex('from' ,@temp_sql)-1;
 end
 
set @temp_sql = @sql_item
set @k_l = charindex('(',@temp_sql)
set @k_r = charindex(')',@temp_sql)
set @k_w = charindex('where',@temp_sql)
set @lc=-999
set @rc=-998
 if( @k_w > @k_l and @k_l > 0 ) begin	 
	set @k_l = charindex('(',@temp_sql)
	set @k_w = charindex('where',@temp_sql)
	set @k_r = charindex(')',@temp_sql)


	while(( @lc<>@rc or @k_l < @k_w or @k_r < @k_w) and (@k_l>0 or @k_r>0)) begin
		if(@lc=-999) begin set @lc=0 end
		if(@rc=-998) begin set @rc=0 end
		set @temp = substring( @temp_sql,0,@k_r+1)
		set @lc = @lc+(SELECT count(*)-1 FROM ( (SELECT [value] = CONVERT(XML, '<v>' + REPLACE(@temp, '(', '</v><v>') + '</v>') ) A  OUTER APPLY (SELECT val = N.v.value('.', 'varchar(1000)') FROM A.[value].nodes('/v') N(v) ) B ))
		set @rc = @rc+(SELECT count(*)-1 FROM ( (SELECT [value] = CONVERT(XML, '<v>' + REPLACE(@temp, ')', '</v><v>') + '</v>') ) A  OUTER APPLY (SELECT val = N.v.value('.', 'varchar(1000)') FROM A.[value].nodes('/v') N(v) ) B ))
		
		set @temp_sql= substring( @temp_sql,@k_r+1,  4000)	
		set @k_l = charindex('(',@temp_sql)
		set @k_w = charindex('where',@temp_sql)
		set @k_r = charindex(')',@temp_sql)
	 end
	 
	set @whereStartIndex = charindex('where' ,@temp_sql)-1 + len(@sql_item) - len(@temp_sql);
 end else begin
	set @whereStartIndex = charindex('where' ,@temp_sql)-1;
 end

 
DECLARE @ErrorMessage NVARCHAR(4000);
DECLARE @ErrorSeverity INT;
DECLARE @ErrorState INT;

print 'from='+convert(varchar(20),@fromStartIndex)+'  where='+convert(varchar(20),@whereStartIndex)
if(@fromStartIndex >-1) begin
	if(@whereStartIndex = -1) begin
		set @whereStartIndex = len(@sql_item)
	end
	declare @rawSQLFrom nvarchar(3000)=substring( @sql_item,@fromStartIndex  ,4000)
	set @temp_sql = substring( @sql_item,0,@fromStartIndex )+' into '+@tableName+' '+substring( @sql_item,@fromStartIndex +1 ,@whereStartIndex - @fromStartIndex)+' where 1=2 ';
	if(len(substring( @sql_item,@whereStartIndex+6  ,4000))>0) begin
		set @temp_sql = @temp_sql+' and '+substring( @sql_item,@whereStartIndex+6  ,4000)
	end
	set @sql_item = substring( @sql_item,0,@fromStartIndex )+' into '+@tableName+' '+substring( @sql_item,@fromStartIndex  ,4000)

	if(ISNULL(@orderby,'')='') begin
		set @itemTime=SYSDATETIME()
		declare @nvarchar nvarchar(max)=replace(replace(replace(@temp_sql,'[lt]','<'),'[rt]','>'),'[@]','&') +N';select @primaryKeyName=a.name from tempdb.sys.columns a inner join tempdb.sys.objects b on a.[object_id]=b.[object_id] and b.type=''u'' where b.name LIKE '''+@tableName+'%'' and a.is_identity=''1'''		
		begin try
			exec sp_executesql @nvarchar,N'@primaryKeyName nvarchar(300) OUTPUT',@primaryKeyName=@orderby output
		end try
		begin catch    		
			SELECT @ErrorMessage = ERROR_MESSAGE(),@ErrorSeverity = ERROR_SEVERITY(),@ErrorState = ERROR_STATE();
			RAISERROR (@ErrorMessage,@ErrorSeverity, @ErrorState );
			return ;
		end catch

		if(len(@orderby)=0) begin 
			set @orderby='N_7777'  
			set @sql_item=@sql_item+';alter table '+@tableName+' add N_7777 int identity(1,1)';
		end
	end
	update #sql set sql=@sql_item where idx=@idx
	insert into #sql(idx,sql) values(@idx+1,'select '+convert(nvarchar(10) ,@page)+' as page,'+convert(nvarchar(10) ,@size)+' as size,CEILING(count(*)/convert(float,'+convert(nvarchar(10) ,@size)+')) as allPage,count(*) as allSize from '+@tableName)
	insert into #sql(idx,sql) values(@idx+2,'select * from '+@tableName+' order by '+@orderby+' offset '+convert(nvarchar(10) ,((@page - 1) * @size))+' row fetch next '+convert(nvarchar(10) ,@size)+' row only')
 end
 

 declare @nsql nvarchar(max)
 set @nsql=(SELECT  ';'+sql FROM #sql FOR XML PATH(''))
 set @nsql = replace(replace(replace(@nsql,'[lt]','<'),'[rt]','>'),'[@]','&')
 print @nsql

begin try
	exec sp_executesql  @nsql
end try
begin catch
	SELECT @ErrorMessage = ERROR_MESSAGE(),@ErrorSeverity = ERROR_SEVERITY(),@ErrorState = ERROR_STATE();
	RAISERROR (@ErrorMessage,@ErrorSeverity, @ErrorState );
	return ;
end catch

print '总用时：'+ convert(varchar(10), datediff( ms, @execTime,SYSDATETIME()))+'毫秒'





