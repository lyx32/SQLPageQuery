
/**
	这是一个几乎没有任何限制及额外操作的通用分页存储过程	
	使用方式：假设传入SQL查询有N个结果集，我会将最后一个查询结果作为要分页的结果进行处理并返回N+1个结果集。
			我会按照原有sql顺序返回结果集，并再第N个结果集（最终我认为要分页的结果集）前插入一个分页信息结果集（所以是返回N+1个结果集）。
			如果结果只有一个结果集，也是同理
	注意事项：	1.如果你传入的@sql参数存在多个结果集，那么每个sql需要用英文分号;进行分割。
				2.传入的sql语句分号（;）具有特殊作用，所以sql语句中的''，/ *** /等。不能出现分号（;）否则会导致sql执行异常（特别是要执行分页的sql）
				3.不允许出现--注释。
				

	2025-09-02	1.第四版,也是最终版优化（以前是使用into临时表处理的，有很多问题处理起来很麻烦，现在将sql语句的order by 截取出来处理）。
	2025-10-22	1.第五版优化。优化思路：将要分页的数据写入临时表。然后再临时表中按照结果集顺序添加一个自增列并作为最终排序字段。如果查询的结果集中已存在自增列，那么则转为截取order语句，来排序
*/
create procedure [dbo].[PageQuery]       
	@page   int=1,				--要显示的页码   
	@size   int=20,				--每页的大小   
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
  

  
set @sql= replace(@sql,'<','[lt]')
set @sql= replace(@sql,'>','[rt]')
set @sql= replace(@sql,'&','[@]')


  
create table #sql( idx int not null,sql nvarchar(4000) not null )



-- 不好判断;  暂时不判断
--insert into #sql values(0,@sql)
--if((select count(*) from #sql where sql like '%''%;%''%')>0) begin
--	THROW 777777,'不允许在字符串中出现分号（;）',1
--end
--if((select count(*) from #sql where sql like '%/*%;%*/%')>0) begin
--	THROW 777777,'不允许在注释中出现分号（;）',1
--end
--delete #sql

SELECT IDENTITY(int,1,1) as idx ,convert(nvarchar(4000),B.val) as sql into #sql_tmp
FROM (
	(SELECT [value] = CONVERT(XML, '<v>' + REPLACE(@sql, ';', '</v><v>') + '</v>') ) A 
OUTER APPLY
    (SELECT val = N.v.value('.', 'varchar(4000)') FROM A.[value].nodes('/v') N(v) ) B
)

insert into #sql
select idx,sql from #sql_tmp order by idx


delete #sql where len(ltrim(rtrim(sql)))=0


declare @sql_item varchar(4000)
declare @idx int
 
select top 1 @sql_item=lower(sql),@idx=idx from #sql order by idx desc

update #sql set idx=@idx+100 where idx=@idx
set @idx=@idx+100


create table #filter(id int identity(1,1) primary key not null,t varchar(4),s int,e int)


set @itemTime=SYSDATETIME()

declare @keyword_left int = charindex('/*',@sql_item)
declare @keyword int = 0
declare @keyword_right int = charindex('*/',@sql_item)
declare @isWhile varchar(1)='y'

  
while(@keyword_left>0) begin
	insert into #filter(t,s) values('注释',@keyword_left)
	set @keyword_left = charindex('/*',@sql_item,@keyword_left+2)
end
while(@keyword_right>0) begin
	update #filter set e=@keyword_right+2  where t='注释' and s=(select top 1 s from #filter where t='注释' and e is null order by s desc)
	set @keyword_right = charindex('*/',@sql_item,@keyword_right+2)
end

set @keyword_left= charindex('''',@sql_item)
while(@keyword_left>0) begin
	set @keyword_right = charindex('''',@sql_item,@keyword_left+1)+1;
	insert into #filter(t,s,e) values('字符',@keyword_left,@keyword_right)
	set @keyword_left = charindex('''',@sql_item,@keyword_right);
end

set @keyword_left= charindex('(',@sql_item)
if (@keyword_left > 0) begin
	declare @next_left int = 0
	declare @next_right int = 0
	insert into #filter(t,s) values('括号',@keyword_left)
	while(@isWhile='y') begin		
		set @next_left  = charindex('(',@sql_item,@keyword_left + 1)
		set @next_right  = charindex(')',@sql_item,@keyword_left + 1)
		if(@next_right = 0) begin
			set @isWhile='n';
		end else begin
			-- 处理正常括号结尾及处理（包裹的情况
			if( @next_left > @next_right or (@next_left = 0 and @next_right > @next_left) or @next_left < @next_right) begin
				if( subString(@sql_item,@keyword_left+1,@next_right-@keyword_left) like '%(%') begin	
					set @keyword_left = charindex('(',@sql_item,@keyword_left +1)
					insert into #filter(t,s) values('括号', charindex('(',@sql_item,@keyword_left ))
				end else begin
					update #filter set e=@next_right+1 where t='括号' and s=(select top 1 s from #filter where t='括号' and e is null order by s desc)
					set @keyword_left =@next_right
				end
			end  
		end
	end
end



declare @i int =1;
declare @count int = (select count(*) from #filter)
declare @id int =0;
declare @s int=0
declare @e int=0

set @keyword = charindex('--',@sql_item);  
while(@keyword>0) begin 
	select @id=count(*) from #filter where @keyword>=s and @keyword<e and t in ('字符','注释')  
	if(@id>0 and @keyword>0) begin
		set @keyword = charindex('--',@sql_item,@keyword+2);	
	end else begin 
		THROW 777777,'不允许出现注释（--）',1
		return ;
	end
end



declare @fromStartIndex int =0
set @keyword  = charindex('from',@sql_item)
set @isWhile='y'
while(@isWhile = 'y') begin
	select @id=count(*) from #filter where @keyword>=s and @keyword<e

	if(@id>0 and @keyword>0) begin
		set @keyword = charindex('from',@sql_item,@keyword+2);
	end else begin
		set @isWhile='n';
	end
end
set @fromStartIndex = @keyword-1;


set @keyword = charindex('order by',@sql_item);
while(@keyword > 0) begin
	select @id=id,@s=s,@e=e from #filter where @keyword>=s and @keyword<e
	if((select count(*) from #filter where @keyword>=s and @keyword<e)=0) begin
		set @id=0
	end
	if(@e>0 and @s>0 and @id>0) begin
		set @keyword = charindex('order by',@sql_item,@e+1);	
		delete #filter where id=@id
	end else begin
		if(charindex('order by',@sql_item,@keyword+1)>0) begin
			set @keyword = charindex('order by',@sql_item,@keyword+1);
		end else begin
			break;
		end
	end
end	

declare @orderStartIndex int =0
if( @keyword > 0 ) begin
	set @orderStartIndex=@keyword
end

print 'sql解析：'+ convert(varchar(10), datediff( ms, @itemTime,SYSDATETIME()))+'毫秒'


declare @temp_sql varchar(4000) = @sql_item


select top 1 @sql_item=sql from #sql where idx=@idx


begin try	
	declare @tableName varchar(34)='#'+replace(NewId(),'-','')
	
	
	set @sql_item = SUBSTRING(@sql_item,0,@fromStartIndex)+',IDENTITY(int,1,1) as N_7777 into '+@tableName+' '+SUBSTRING(@sql_item,@fromStartIndex,len(@sql_item))

	insert into #sql(idx,sql) values(@idx+1,';declare @allSize int;set @allSize=@@ROWCOUNT')
	insert into #sql(idx,sql) values(@idx+2,';select '+convert(nvarchar(10) ,@page)+' as page,'+convert(nvarchar(10) ,@size)+' as size,CEILING(@allSize/convert(float,'+convert(nvarchar(10) ,@size)+')) as allPage,@allSize as allSize')
	insert into #sql(idx,sql) values(@idx+3,';select * from '+@tableName+' order by N_7777 offset '+convert(nvarchar(10) ,((@page - 1) * @size))+' row fetch next '+convert(nvarchar(10) ,@size)+' row only')
	
	update #sql set sql=@sql_item where idx=@idx
	declare @execSql nvarchar(max)
	 set @execSql=(SELECT  ';'+sql FROM #sql order by idx FOR XML PATH(''))
 
	set @execSql= replace(replace(replace(@execSql,'[lt]','<'),'[rt]','>'),'[@]','&')
	
	exec sp_executesql @execSql	
	print '使用临时表 总用时：'+ convert(varchar(10), datediff( ms, @execTime,SYSDATETIME()))+'毫秒'
	return ;
end try
begin catch
	print convert(varchar(20), ERROR_NUMBER()) +' >>> '+ convert(varchar(800),ERROR_MESSAGE());
	-- 临时表中存在自增列，额外再添加一个自增列
	set @keyword  = charindex('select',@temp_sql,0)
	set @keyword_left  = charindex('(',@temp_sql,0)
	set @keyword_right  = charindex(')',@temp_sql,0)
	declare @tmp varchar(50)
	declare @distinctIndex int=0
	declare @len int=0
	declare @raw_sql varchar(max)=@temp_sql
	while(@keyword>0 ) begin
		set @tmp = subString(@temp_sql,@keyword,50)
		if(@tmp not like '%top%' and (@keyword<@keyword_left or @keyword>@keyword_right) ) begin
			set @len=6;
			set @distinctIndex = charindex('distinct',@tmp,0);
			if(@distinctIndex>0) begin set @len = 7 end
			set @temp_sql = SUBSTRING(@temp_sql,0,@keyword)+ STUFF(@tmp, charindex('select',@tmp,0) + @distinctIndex+@len, 0, N' TOP 100 PERCENT ')+SUBSTRING(@temp_sql,@keyword+len(@tmp),99999)

		end 
		set @keyword = charindex('select',@temp_sql,@keyword_right+@keyword+6)
		set @keyword_left  = charindex('(',@temp_sql,@keyword_left+1)
		set @keyword_right  = charindex(')',@temp_sql,@keyword_right+1)
		if(0 = @keyword) begin break; end
	end
	
	delete #sql where idx > @idx
	insert into #sql(idx,sql) values(@idx-3,'select * into '+@tableName+' from ('+@temp_sql+') as T7777')
	insert into #sql(idx,sql) values(@idx-2,';declare @allSize int;set @allSize=@@ROWCOUNT')
	insert into #sql(idx,sql) values(@idx-1,';select '+convert(nvarchar(10) ,@page)+' as page,'+convert(nvarchar(10) ,@size)+' as size,CEILING(@allSize/convert(float,'+convert(nvarchar(10) ,@size)+')) as allPage,@allSize as allSize')
	if(@orderStartIndex >0) begin
		set @sql_item = @raw_sql+' offset '+convert(nvarchar(10) ,((@page - 1) * @size))+' row fetch next '+convert(nvarchar(10) ,@size)+' row only'
	end else begin
		set @sql_item = @raw_sql+' ORDER BY (SELECT 1) offset '+convert(nvarchar(10) ,((@page - 1) * @size))+' row fetch next '+convert(nvarchar(10) ,@size)+' row only'	
	end
end catch






update #sql set sql=@sql_item where idx=@idx


 declare @nsql nvarchar(max)
 set @nsql=(SELECT  ';'+sql FROM #sql order by idx FOR XML PATH(''))
 
set @nsql= replace(replace(replace(@nsql,'[lt]','<'),'[rt]','>'),'[@]','&')

print @nsql


begin try
	exec sp_executesql @nsql
end try
begin catch
	DECLARE @ErrorMessage NVARCHAR(4000);
	DECLARE @ErrorSeverity INT;
	DECLARE @ErrorState INT;
	SELECT @ErrorMessage = ERROR_MESSAGE(),@ErrorSeverity = ERROR_SEVERITY(),@ErrorState = ERROR_STATE();
	RAISERROR (@ErrorMessage,@ErrorSeverity, @ErrorState );
	return ;
end catch

print '使用普通查询 总用时：'+ convert(varchar(10), datediff( ms, @execTime,SYSDATETIME()))+'毫秒'

