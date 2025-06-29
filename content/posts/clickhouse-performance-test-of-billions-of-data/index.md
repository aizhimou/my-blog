---
title: "Clickhouse 亿级数据性能测试"
date: "2021-03-15"
summary: "一个单表 6 亿数据量的性能测试，有做超大数据量分析技术选型需求的朋友可以参考。"
toc: true
readTime: true
autonumber: false
math: true
tags: ["database", "java"]
showTags: true
hideBackToTop: false
---

Clickhouse 在数据分析技术领域早已声名远扬，如果还不知道可以 [点这里](https://clickhouse.tech/docs/zh/) 了解下。

最近由于项目需求使用到了 clickhouse 做分析数据库，于是用测试环境做了一个单表 6 亿数据量的性能测试，记录一下测试结果，有做超大数据量分析技术选型需求的朋友可以参考下。

## 服务器信息

- CPU：Intel Xeon Gold 6240 @ 8x 2.594GHz
- 内存：32G
- 系统：CentOS 7.6
- Linux内核版本：3.10.0
- 磁盘类型：机械硬盘
- 文件系统：ext4

## Clickhouse 信息

- 部署方式：单机部署
- 版本：20.8.11.17

## 测试情况

> 测试数据和测试方法来自 clickshouse 官方的 [Star Schema Benchmark](https://clickhouse.tech/docs/en/getting-started/example-datasets/star-schema/)

按照官方指导造出了测试数据之后，先看一下数据量和空间占用情况。

### 数据量和空间占用

| 表名           | 列数 | 数据行数    | 原始大小   | 压缩大小   | 压缩率 |
| -------------- | ---- | ----------- | ---------- | ---------- | ------ |
| supplier       | 6    | 200,000     | 11.07 MiB  | 7.53 MiB   | 68     |
| customer       | 7    | 3,000,000   | 168.83 MiB | 114.72 MiB | 68     |
| part           | 8    | 1,400,000   | 34.29 MiB  | 24.08 MiB  | 70     |
| lineorder      | 16   | 600,037,902 | 24.03 GiB  | 16.67 GiB  | 69     |
| lineorder_flat | 37   | 688,552,212 | 111.38 GiB | 61.05 GiB  | 55     |

可以看到 clickhouse 的压缩率很高，压缩率都在 50 以上，基本可以达到 70 左右。数据体积的减小可以非常有效的减少磁盘空间占用、提高 I/O 性能，这对整体查询性能的提升非常有效。

supplier、customer、part、lineorder 为一个简单的「供应商-客户-订单-地区」的星型模型，lineorder_flat 为根据这个星型模型数据关系合并的大宽表，所有分析都直接在这张大宽表中执行，减少不必要的表关联，符合我们实际工作中的分析建表逻辑。

以下性能测试的所有分析 SQL 都在这张大宽表中运行，未进行表关联查询。

### 查询性能测试详情

#### Query 1.1

```sql
SELECT sum(LO_EXTENDEDPRICE * LO_DISCOUNT) AS revenue
FROM lineorder_flat
WHERE (toYear(LO_ORDERDATE) = 1993) AND ((LO_DISCOUNT >= 1) AND (LO_DISCOUNT <= 3)) AND (LO_QUANTITY < 25)

┌────────revenue─┐
│ 44652567249651 │
└────────────────┘

1 rows in set. Elapsed: 0.242 sec. Processed 91.01 million rows, 728.06 MB (375.91 million rows/s., 3.01 GB/s.)
```

**扫描行数：91,010,000** *大约9100万*

**耗时(秒)：0.242**

**查询列数：2**

**结果行数：1**

#### Query 1.2

```sql
SELECT sum(LO_EXTENDEDPRICE * LO_DISCOUNT) AS revenue
FROM lineorder_flat
WHERE (toYYYYMM(LO_ORDERDATE) = 199401) AND ((LO_DISCOUNT >= 4) AND (LO_DISCOUNT <= 6)) AND ((LO_QUANTITY >= 26) AND (LO_QUANTITY <= 35))

┌───────revenue─┐
│ 9624332170119 │
└───────────────┘

1 rows in set. Elapsed: 0.040 sec. Processed 7.75 million rows, 61.96 MB (191.44 million rows/s., 1.53 GB/s.)
```

**扫描行数：7,750,000** *775万*

**耗时(秒)：0.040**

**查询列数：2**

**返回行数：1**

#### Query 2.1

```sql
SELECT 
    sum(LO_REVENUE),
    toYear(LO_ORDERDATE) AS year,
    P_BRAND
FROM lineorder_flat
WHERE (P_CATEGORY = 'MFGR#12') AND (S_REGION = 'AMERICA')
GROUP BY 
    year,
    P_BRAND
ORDER BY 
    year ASC,
    P_BRAND ASC
    
┌─sum(LO_REVENUE)─┬─year─┬─P_BRAND───┐
│     64420005618 │ 1992 │ MFGR#121  │
│     63389346096 │ 1992 │ MFGR#1210 │
│     ........... │ .... │ ..........│
│     39679892915 │ 1998 │ MFGR#128  │
│     35300513083 │ 1998 │ MFGR#129  │
└─────────────────┴──────┴───────────┘

280 rows in set. Elapsed: 8.558 sec. Processed 600.04 million rows, 6.20 GB (70.11 million rows/s., 725.04 MB/s.)
```

**扫描行数：600,040,000** *大约6亿*

**耗时(秒)：8.558**

**查询列数：3**

**结果行数：280**

#### Query 2.2

```sql
SELECT 
    sum(LO_REVENUE),
    toYear(LO_ORDERDATE) AS year,
    P_BRAND
FROM lineorder_flat
WHERE ((P_BRAND >= 'MFGR#2221') AND (P_BRAND <= 'MFGR#2228')) AND (S_REGION = 'ASIA')
GROUP BY 
    year,
    P_BRAND
ORDER BY 
    year ASC,
    P_BRAND ASC

┌─sum(LO_REVENUE)─┬─year─┬─P_BRAND───┐
│     66450349438 │ 1992 │ MFGR#2221 │
│     65423264312 │ 1992 │ MFGR#2222 │
│     ........... │ .... │ ......... │
│     39907545239 │ 1998 │ MFGR#2227 │
│     40654201840 │ 1998 │ MFGR#2228 │
└─────────────────┴──────┴───────────┘

56 rows in set. Elapsed: 1.242 sec. Processed 600.04 million rows, 5.60 GB (482.97 million rows/s., 4.51 GB/s.) 
```

**扫描行数：600,040,000** *大约6亿*

**耗时(秒)：1.242**

**查询列数：3**

**结果行数：56**

#### Query 3.1

```sql
SELECT 
    C_NATION,
    S_NATION,
    toYear(LO_ORDERDATE) AS year,
    sum(LO_REVENUE) AS revenue
FROM lineorder_flat
WHERE (C_REGION = 'ASIA') AND (S_REGION = 'ASIA') AND (year >= 1992) AND (year <= 1997)
GROUP BY 
    C_NATION,
    S_NATION,
    year
ORDER BY 
    year ASC,
    revenue DESC

┌─C_NATION──┬─S_NATION──┬─year─┬──────revenue─┐
│ INDIA     │ INDIA     │ 1992 │ 537778456208 │
│ INDONESIA │ INDIA     │ 1992 │ 536684093041 │
│ .....     │ .......   │ .... │ ............ │
│ CHINA     │ CHINA     │ 1997 │ 525562838002 │
│ JAPAN     │ VIETNAM   │ 1997 │ 525495763677 │
└───────────┴───────────┴──────┴──────────────┘

150 rows in set. Elapsed: 3.533 sec. Processed 546.67 million rows, 5.48 GB (154.72 million rows/s., 1.55 GB/s.) 
```

**扫描行数：546,670,000** *大约5亿4千多万*

**耗时(秒)：3.533**

**查询列数：4**

**结果行数：150**

#### Query 3.2

```sql
SELECT 
    C_CITY,
    S_CITY,
    toYear(LO_ORDERDATE) AS year,
    sum(LO_REVENUE) AS revenue
FROM lineorder_flat
WHERE (C_NATION = 'UNITED STATES') AND (S_NATION = 'UNITED STATES') AND (year >= 1992) AND (year <= 1997)
GROUP BY 
    C_CITY,
    S_CITY,
    year
ORDER BY 
    year ASC,
    revenue DESC

┌─C_CITY─────┬─S_CITY─────┬─year─┬────revenue─┐
│ UNITED ST6 │ UNITED ST6 │ 1992 │ 5694246807 │
│ UNITED ST0 │ UNITED ST0 │ 1992 │ 5676049026 │
│ .......... │ .......... │ .... │ .......... │
│ UNITED ST9 │ UNITED ST9 │ 1997 │ 4836163349 │
│ UNITED ST9 │ UNITED ST5 │ 1997 │ 4769919410 │
└────────────┴────────────┴──────┴────────────┘

600 rows in set. Elapsed: 1.000 sec. Processed 546.67 million rows, 5.56 GB (546.59 million rows/s., 5.56 GB/s.)
```

**扫描行数：546,670,000** *大约5亿4千多万*

**耗时(秒)：1.00**

**查询列数：4**

**结果行数：600**

#### Query 4.1 

```sql
SELECT 
    toYear(LO_ORDERDATE) AS year,
    C_NATION,
    sum(LO_REVENUE - LO_SUPPLYCOST) AS profit
FROM lineorder_flat
WHERE (C_REGION = 'AMERICA') AND (S_REGION = 'AMERICA') AND ((P_MFGR = 'MFGR#1') OR (P_MFGR = 'MFGR#2'))
GROUP BY 
    year,
    C_NATION
ORDER BY 
    year ASC,
    C_NATION ASC

┌─year─┬─C_NATION──────┬────────profit─┐
│ 1992 │ ARGENTINA     │ 1041983042066 │
│ 1992 │ BRAZIL        │ 1031193572794 │
│ .... │ ......        │  ............ │
│ 1998 │ PERU          │  603980044827 │
│ 1998 │ UNITED STATES │  605069471323 │
└──────┴───────────────┴───────────────┘

35 rows in set. Elapsed: 5.066 sec. Processed 600.04 million rows, 8.41 GB (118.43 million rows/s., 1.66 GB/s.)  
```

**扫描行数：600,040,000** *大约6亿*

**耗时(秒)：5.066**

**查询列数：4**

**结果行数：35**

#### Query 4.2

```sql
SELECT 
    toYear(LO_ORDERDATE) AS year,
    S_NATION,
    P_CATEGORY,
    sum(LO_REVENUE - LO_SUPPLYCOST) AS profit
FROM lineorder_flat
WHERE (C_REGION = 'AMERICA') AND (S_REGION = 'AMERICA') AND ((year = 1997) OR (year = 1998)) AND ((P_MFGR = 'MFGR#1') OR (P_MFGR = 'MFGR#2'))
GROUP BY 
    year,
    S_NATION,
    P_CATEGORY
ORDER BY 
    year ASC,
    S_NATION ASC,
    P_CATEGORY ASC

┌─year─┬─S_NATION──────┬─P_CATEGORY─┬───────profit─┐
│ 1997 │ ARGENTINA     │ MFGR#11    │ 102369950215 │
│ 1997 │ ARGENTINA     │ MFGR#12    │ 103052774082 │
│ .... │ .........     │ .......    │ ............ │
│ 1998 │ UNITED STATES │ MFGR#24    │  60779388345 │
│ 1998 │ UNITED STATES │ MFGR#25    │  60042710566 │
└──────┴───────────────┴────────────┴──────────────┘

100 rows in set. Elapsed: 0.826 sec. Processed 144.42 million rows, 2.17 GB (174.78 million rows/s., 2.63 GB/s.)
```

**扫描行数：144,420,000** *大约1亿4千多万*

**耗时(秒)：0.826**

**查询列数：4**

**结果行数：100**

## 性能测试结果汇总

| 查询语句 | SQL简要说明                                  |    扫描行数 | 返回行数 | 查询列数 | 耗时(秒) |
| :------- | :------------------------------------------- | ----------: | -------: | -------: | -------: |
| Q1.1     | 乘积、汇总、4个条件、首次运行                |  91,010,000 |        1 |        2 |    0.242 |
| Q1.2     | Q1.1增加1个条件运行                          |   7,750,000 |        1 |        2 |    0.040 |
| Q2.1     | 汇总、函数、2列分组、2列排序、首次运行       | 600,040,000 |      280 |        3 |    8.558 |
| Q2.2     | Q2.1增加1个条件运行                          | 600,040,000 |       56 |        3 |    1.242 |
| Q3.1     | 汇总、函数、3列分组、2列排序、首次运行       | 546,670,000 |      150 |        4 |    3.533 |
| Q3.2     | Q3.1更换条件运行                             | 546,670,000 |      600 |        4 |        1 |
| Q4.1     | 相减、汇总、函数、2列分组、2列排序、首次运行 | 600,040,000 |       35 |        4 |    5.006 |
| Q4.2     | Q4.1增加2个条件运行                          | 144,420,000 |      100 |        4 |    0.826 |

在当前软硬件环境下，扫描 6 亿多行数据，常见的分析语句首次运行最慢在 8 秒左右能返回结果，相同的分析逻辑更换条件再次查询的时候效率有明显的提升，可以缩短到 1 秒左右，如果只是简单的列查询没有加减乘除、聚合等逻辑，扫描全表 6 亿多行数据首次查询基本可以在 2 秒内执行完成。

> 本文由本人原创。网络中有多处内容与本文相同的文章，皆为未授权盗用，请知悉。