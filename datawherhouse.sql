if exists(select * from sys.sysdatabases where name ='datawherhouse')
drop database datawherhouse 
go
 create database datawherhouse
 go 
 use datawherhouse
 
 ---
CREATE SCHEMA staging 

CREATE SCHEMA edw;
------
CREATE OR ALTER PROCEDURE staging.usp_refresh_staging
AS
BEGIN
    SET NOCOUNT ON;

    IF OBJECT_ID('staging.stg_product', 'U') IS NULL
    CREATE TABLE staging.stg_product (
        product_id int,
        product_name nvarchar(100),
        category_name nvarchar(50),
        subcategory_name nvarchar(50),
        color nvarchar(15),
        standard_cost decimal(18,2),
        modified_date datetime
    );

    IF OBJECT_ID('staging.stg_customer', 'U') IS NULL
    CREATE TABLE staging.stg_customer (
        customer_id int,
        customer_name nvarchar(150),
        city nvarchar(50),
        modified_date datetime
    );

    IF OBJECT_ID('staging.stg_territory', 'U') IS NULL
    CREATE TABLE staging.stg_territory (
        territory_id int,
        territory_name nvarchar(50),
        country_code nvarchar(3),
        territory_group nvarchar(50),
        modified_date datetime
    );

    IF OBJECT_ID('staging.stg_sales', 'U') IS NULL
    CREATE TABLE staging.stg_sales (
        sales_order_number nvarchar(25),
        product_id int,
        customer_id int,
        territory_id int,
        order_date datetime,
        quantity int,
        unit_price decimal(18,2),
        modified_date datetime
    );

    TRUNCATE TABLE staging.stg_product;

    INSERT INTO staging.stg_product
    SELECT p.productid, p.name, pc.name, ps.name, p.color, p.standardcost, p.modifieddate
    FROM AdventureWorks2025.production.product p
    LEFT JOIN AdventureWorks2025.production.productsubcategory ps
        ON p.productsubcategoryid = ps.productsubcategoryid
    LEFT JOIN AdventureWorks2025.production.productcategory pc
        ON ps.productcategoryid = pc.productcategoryid;

    TRUNCATE TABLE staging.stg_customer;

    INSERT INTO staging.stg_customer
    SELECT c.customerid,
           ISNULL(p.firstname + ' ' + p.lastname, s.name),
           ad.city,
           c.modifieddate
    FROM AdventureWorks2025.sales.customer c
    LEFT JOIN AdventureWorks2025.person.person p
        ON c.personid = p.businessentityid
    LEFT JOIN AdventureWorks2025.sales.store s
        ON c.storeid = s.businessentityid
    LEFT JOIN AdventureWorks2025.person.businessentityaddress bea
        ON (p.businessentityid = bea.businessentityid OR s.businessentityid = bea.businessentityid)
    LEFT JOIN AdventureWorks2025.person.address ad
        ON bea.addressid = ad.addressid;

    TRUNCATE TABLE staging.stg_territory;

    INSERT INTO staging.stg_territory
    SELECT territoryid, name, countryregioncode, [group], modifieddate
    FROM AdventureWorks2025.sales.salesterritory;

    TRUNCATE TABLE staging.stg_sales;

    INSERT INTO staging.stg_sales
    SELECT h.salesordernumber,
           d.productid,
           h.customerid,
           h.territoryid,
           h.orderdate,
           d.orderqty,
           d.unitprice,
           h.modifieddate
    FROM AdventureWorks2025.sales.salesorderheader h
    JOIN AdventureWorks2025.sales.salesorderdetail d
        ON h.salesorderid = d.salesorderid;

END

------------------------------ 

if object_id('edw.dim_product', 'u') is null
create table edw.dim_product (
    product_key int identity(1,1) primary key, 
    product_id int,                            
    product_name nvarchar(100),
    category_name nvarchar(50),
    subcategory_name nvarchar(50),
    color nvarchar(15),
    standard_cost decimal(18,2),
    start_date datetime default getdate(),                       
    end_date datetime,                         
    is_current bit default 1                   
);
--  dimension: customer
if object_id('edw.dim_customer', 'u') is null
create table edw.dim_customer (
    customer_key int identity(1,1) primary key, 
    customer_id int,                            
    customer_name nvarchar(150),
    city nvarchar(50),
    start_date datetime default getdate(),
    end_date datetime,
    is_current bit default 1
);

--  dimension: territory
if object_id('edw.dim_territory', 'u') is null
create table edw.dim_territory (
    territory_key int identity(1,1) primary key, 
    territory_id int,                             
    territory_name nvarchar(50),
    country_code nvarchar(3),
    territory_group nvarchar(50),
     start_date datetime default getdate(),
    end_date datetime,
    is_current bit default 1
);

drop table edw .dim_territory

-- 4. fact: sales
if object_id('edw.fact_sales', 'u') is null
create table edw.fact_sales (
    sales_key int identity(1,1) primary key,    
    sales_order_number nvarchar(25),
    product_key int,                      
    customer_key int,                          
    territory_key int,                          
    date_key int,                              
    quantity int,
    unit_price decimal(18,2),
    total_revenue as (quantity * unit_price),   
    modified_date datetime
);
CREATE TABLE dim_date
(
    date_key INT PRIMARY KEY,
    full_date DATETIME,
    [day] INT,
    day_name VARCHAR(50),
    month_nom INT,
    month_name VARCHAR(50),
    [quarter] INT,
    [year] INT
);
GO

DECLARE @start_date DATE = '2020-01-01';
DECLARE @end_date DATE = '2030-01-01';

WHILE @start_date <= @end_date
BEGIN

    INSERT INTO dim_date
    (
        date_key,
        full_date,
        [day],
        [day_name],
        month_nom,
        month_name,
        [quarter],
        [year]
    )
    VALUES
    (
        CONVERT(INT, FORMAT(@start_date, 'yyMMdd')),
        @start_date,
        DATEPART(DW, @start_date),
        DATENAME(DW, @start_date),
        DATEPART(MM, @start_date),
        DATENAME(MM, @start_date),
        DATEPART(QQ, @start_date),
        DATEPART(YY, @start_date)
    );

    SET @start_date = DATEADD(DAY, 1, @start_date);

END


alter schema edw transfer dbo.dim_date
go

select * from edw.dim_customer

select * from edw.dim_product

select * from edw.dim_territory



